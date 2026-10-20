const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');
const { AccountCreationError, createEmployeeAccount } = require('./src/create_employee_account');

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
