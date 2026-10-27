const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const { defineSecret } = require('firebase-functions/params');
const nodemailer = require('nodemailer');
const { AccountCreationError, createEmployeeAccount } = require('./src/create_employee_account');
const { ReportError, renderReportPdf, getEmployeeReport, previewEmployeeReport, sendEmployeeReports } = require('./src/employee_reports');

const smtpPassword = defineSecret('SMTP_PASSWORD');

initializeApp();

exports.createEmployeeAccount = onCall(async (request) => {
  const auth = getAuth();
  const firestore = getFirestore();

  try {
    return await createEmployeeAccount(request, {
      readCallerProfile: async (uid) => {
        const document = await firestore.collection('users').doc(uid).get();
        return document.exists ? document.data() : null;
      },
      createAuthUser: (data) => auth.createUser(data),
      createProfile: (uid, data) => firestore.collection('users').doc(uid).create(data),
      deleteAuthUser: (uid) => auth.deleteUser(uid),
      disableAuthUser: (uid) => auth.updateUser(uid, { disabled: true }),
      deleteProfile: (uid) => firestore.collection('users').doc(uid).delete(),
      logError: (step, uid, error) => {
        // Never log the request payload or the initial password.
        logger.error('createEmployeeAccount failed', { step, uid, code: error?.code });
      },
    });
  } catch (error) {
    if (error instanceof AccountCreationError) {
      throw new HttpsError(error.code, error.message);
    }
    logger.error('createEmployeeAccount unexpected failure', { code: error?.code });
    throw new HttpsError('internal', 'Không thể tạo tài khoản. Vui lòng thử lại.');
  }
});

function reportServices({ withMail = false } = {}) {
  const firestore = getFirestore();
  let transporter;
  return {
    readCallerProfile: async (uid) => {
      const document = await firestore.collection('users').doc(uid).get();
      return document.exists ? document.data() : null;
    },
    listEmployees: async () => {
      const snapshot = await firestore.collection('users').where('role', '==', 'employee').get();
      return snapshot.docs.map((document) => ({ ...document.data(), uid: document.id }));
    },
    loadAttendance: async (startDate, endDate) => {
      const snapshot = await firestore.collection('attendance')
        .where('workDate', '>=', startDate).where('workDate', '<=', endDate).get();
      return snapshot.docs.map((document) => {
        const data = document.data();
        return {
          employeeId: data.employeeId,
          workDate: data.workDate,
          status: data.status,
          method: data.method,
          checkInAt: data.checkInAt?.toDate?.() || null,
          checkOutAt: data.checkOutAt?.toDate?.() || null,
        };
      });
    },
    renderPdf: renderReportPdf,
    sendMail: withMail ? async (message) => {
      const host = process.env.SMTP_HOST;
      const port = Number(process.env.SMTP_PORT);
      const user = process.env.SMTP_USER;
      const from = process.env.SMTP_FROM;
      const password = smtpPassword.value();
      if (!host || !Number.isInteger(port) || port < 1 || port > 65535 || !user || !from || !password) {
        throw new Error('SMTP is not configured');
      }
      transporter ??= nodemailer.createTransport({
        host, port, secure: port === 465, requireTLS: port !== 465,
        auth: { user, pass: password }, disableFileAccess: true, disableUrlAccess: true,
      });
      const info = await transporter.sendMail({ from, ...message });
      if (!info.accepted?.some((address) => address.toLowerCase() === message.to.toLowerCase())) {
        throw new Error('SMTP rejected recipient');
      }
    } : undefined,
    logSendError: (_employeeId, error) => logger.error('sendEmployeeReports failed', {
      code: error?.code,
    }),
  };
}

function reportFailure(error) {
  if (error instanceof ReportError) return new HttpsError(error.code, error.message);
  logger.error('employee reports unexpected failure', { code: error?.code });
  return new HttpsError('internal', 'Không thể xử lý báo cáo. Vui lòng thử lại.');
}

exports.previewEmployeeReport = onCall({ timeoutSeconds: 120, memory: '512MiB' }, async (request) => {
  try {
    return await previewEmployeeReport(request, reportServices());
  } catch (error) {
    throw reportFailure(error);
  }
});

exports.getEmployeeReport = onCall({ timeoutSeconds: 120, memory: '512MiB' }, async (request) => {
  try {
    return await getEmployeeReport(request, reportServices());
  } catch (error) {
    throw reportFailure(error);
  }
});

exports.sendEmployeeReports = onCall({ secrets: [smtpPassword], timeoutSeconds: 540, memory: '512MiB' }, async (request) => {
  try {
    return await sendEmployeeReports(request, reportServices({ withMail: true }));
  } catch (error) {
    throw reportFailure(error);
  }
});
