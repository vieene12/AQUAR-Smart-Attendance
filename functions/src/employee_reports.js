const path = require('node:path');
const PDFDocument = require('pdfkit');

class ReportError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const fontPath = path.join(__dirname, '..', 'assets', 'Roboto-Regular.ttf');
const emailPattern = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;
const validKinds = new Set(['week', 'month', 'quarter', 'year']);
const pad = (n) => String(n).padStart(2, '0');
const iso = (date) => `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;

function periodFromInput(data) {
  const kind = data?.periodKind;
  const anchor = data?.anchorDate;
  if (!validKinds.has(kind) || typeof anchor !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(anchor)) {
    throw new ReportError('invalid-argument', 'Kỳ báo cáo không hợp lệ.');
  }
  const date = new Date(`${anchor}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime()) || iso(date) !== anchor) {
    throw new ReportError('invalid-argument', 'Ngày báo cáo không hợp lệ.');
  }
  let start;
  let end;
  if (kind === 'week') {
    start = new Date(date);
    start.setUTCDate(start.getUTCDate() - ((start.getUTCDay() + 6) % 7));
    end = new Date(start);
    end.setUTCDate(end.getUTCDate() + 6);
  } else if (kind === 'month') {
    start = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
    end = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0));
  } else if (kind === 'quarter') {
    const firstMonth = Math.floor(date.getUTCMonth() / 3) * 3;
    start = new Date(Date.UTC(date.getUTCFullYear(), firstMonth, 1));
    end = new Date(Date.UTC(date.getUTCFullYear(), firstMonth + 3, 0));
  } else {
    start = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
    end = new Date(Date.UTC(date.getUTCFullYear(), 11, 31));
  }
  return { kind, startDate: iso(start), endDate: iso(end) };
}

function canAccessEmployee(caller, callerUid, employee) {
  if (caller.role === 'admin') return true;
  if (caller.role !== 'manager') return false;
  // Legacy profiles have no assignment; once assigned, only that manager can access them.
  return !employee.managerUid || employee.managerUid === callerUid;
}

function vietnamSeconds(date) {
  const shifted = new Date(date.getTime() + 7 * 3600000);
  return shifted.getUTCHours() * 3600 + shifted.getUTCMinutes() * 60 + shifted.getUTCSeconds();
}

function vietnamDate(date) {
  return iso(new Date(date.getTime() + 7 * 3600000));
}

function timeLabel(date) {
  if (!date) return 'Chưa check-out';
  const shifted = new Date(date.getTime() + 7 * 3600000);
  return `${pad(shifted.getUTCHours())}:${pad(shifted.getUTCMinutes())}`;
}

function minutesLabel(minutes) {
  if (minutes == null) return 'Chưa check-out';
  return `${Math.floor(minutes / 60)} giờ ${pad(minutes % 60)} phút`;
}

function validTime(value) {
  return typeof value === 'string' && /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value);
}

function buildSummary(employee, records, period) {
  const days = [];
  const recordsByDate = new Map();
  for (const record of records) {
    if (record.employeeId !== employee.uid || record.workDate < period.startDate || record.workDate > period.endDate) continue;
    recordsByDate.set(record.workDate, (recordsByDate.get(record.workDate) || 0) + 1);
  }
  let payableMilliseconds = 0;
  let payableDays = 0;
  let checkIns = 0;
  let checkOuts = 0;
  let late = 0;
  let early = 0;
  for (const record of records) {
    if (record.employeeId !== employee.uid || record.workDate < period.startDate || record.workDate > period.endDate) continue;
    const checkIn = record.checkInAt;
    const checkOut = record.checkOutAt;
    if (!(checkIn instanceof Date) || Number.isNaN(checkIn.getTime()) || vietnamDate(checkIn) !== record.workDate) continue;
    if (record.status !== 'working' && record.status !== 'completed') continue;
    if (record.status === 'working' && checkOut) continue;
    if (record.status === 'completed' && (!(checkOut instanceof Date) || checkOut <= checkIn)) continue;
    checkIns++;
    if (checkOut) checkOuts++;
    const shiftStart = employee.shiftStart;
    const shiftEnd = employee.shiftEnd;
    const isLate = validTime(shiftStart) && vietnamSeconds(checkIn) > (Number(shiftStart.slice(0, 2)) * 60 + Number(shiftStart.slice(3))) * 60;
    const isEarly = checkOut && validTime(shiftEnd) && vietnamSeconds(checkOut) < (Number(shiftEnd.slice(0, 2)) * 60 + Number(shiftEnd.slice(3))) * 60;
    if (isLate) late++;
    if (isEarly) early++;
    const actualMinutes = checkOut ? Math.floor((checkOut - checkIn) / 60000) : null;
    let paidMilliseconds = null;
    const duplicateDate = recordsByDate.get(record.workDate) > 1;
    if (checkOut && !duplicateDate && vietnamDate(checkOut) === record.workDate && ['biometric', 'nfc', 'nfc_mobile', 'manual'].includes(record.method)) {
      const lunchStart = new Date(`${record.workDate}T05:00:00.000Z`);
      const lunchEnd = new Date(`${record.workDate}T06:00:00.000Z`);
      const overlap = Math.max(0, Math.min(checkOut.getTime(), lunchEnd.getTime()) - Math.max(checkIn.getTime(), lunchStart.getTime()));
      paidMilliseconds = checkOut.getTime() - checkIn.getTime() - overlap;
      payableMilliseconds += paidMilliseconds;
      payableDays++;
    }
    days.push({ workDate: record.workDate, checkIn, checkOut, actualMinutes, paidMilliseconds,
      status: checkOut ? 'Đã hoàn thành ca' : 'Đang làm việc', isLate, isEarly, duplicateDate });
  }
  days.sort((a, b) => a.workDate.localeCompare(b.workDate));
  const totalMinutes = Math.floor(payableMilliseconds / 60000);
  const hourlyRate = Number.isSafeInteger(employee.hourlyRate) && employee.hourlyRate >= 0 ? employee.hourlyRate : null;
  const calculatedSalary = hourlyRate == null ? null :
    (BigInt(totalMinutes) * BigInt(hourlyRate) + 30n) / 60n;
  const totalSalary = calculatedSalary != null && calculatedSalary <= BigInt(Number.MAX_SAFE_INTEGER)
    ? Number(calculatedSalary) : null;
  return { employee, period, days, workDays: new Set(days.map((day) => day.workDate)).size,
    shifts: days.length, checkIns, checkOuts, late, early,
    payableDays, totalMinutes, hourlyRate, totalSalary };
}

function safeFilePart(value) {
  return String(value || '').replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 48) || 'NhanVien';
}

function reportFileName(summary) {
  return `BaoCaoTongHop_${safeFilePart(summary.employee.employeeCode || summary.employee.uid)}_${summary.period.startDate}_${summary.period.endDate}.pdf`;
}

async function renderReportPdf(summary) {
  const document = new PDFDocument({ size: 'A4', margin: 42, autoFirstPage: true });
  const chunks = [];
  const done = new Promise((resolve, reject) => {
    document.on('data', (chunk) => chunks.push(chunk));
    document.on('end', () => resolve(Buffer.concat(chunks)));
    document.on('error', reject);
  });
  document.registerFont('Roboto', fontPath).font('Roboto');
  const { employee, period } = summary;
  const heading = (text) => document.moveDown(0.5).fillColor('#0872b8').fontSize(16).text(text).fillColor('#152238').fontSize(10).moveDown(0.5);
  const line = (label, value) => document.text(`${label}: ${value}`);
  heading('BÁO CÁO CHẤM CÔNG');
  line('Họ tên', employee.fullName || employee.uid);
  line('Mã nhân viên', employee.employeeCode || 'Chưa cập nhật');
  line('Email', employee.email || 'Chưa đăng ký');
  line('Chức vụ', employee.position || 'Chưa cập nhật');
  line('Kỳ báo cáo', `${period.startDate} - ${period.endDate}`);
  document.moveDown();
  line('Số ngày có chấm công', summary.workDays);
  line('Tổng số ca', summary.shifts);
  line('Số lần check-in', summary.checkIns);
  line('Số lần check-out', summary.checkOuts);
  line('Đi trễ', summary.late);
  line('Về sớm', summary.early);
  line('Tổng thời gian làm việc hợp lệ', minutesLabel(summary.totalMinutes));
  heading('CHI TIẾT TỪNG NGÀY');
  for (const day of summary.days) {
    document.fontSize(9).text(`${day.workDate}  |  Ca: ${employee.shiftStart && employee.shiftEnd ? `${employee.shiftStart} - ${employee.shiftEnd}` : 'Chưa cập nhật'}`);
    const workMinutes = day.paidMilliseconds == null ? day.actualMinutes : Math.floor(day.paidMilliseconds / 60000);
    document.text(`Check-in: ${timeLabel(day.checkIn)}  |  Check-out: ${timeLabel(day.checkOut)}  |  Tổng giờ: ${minutesLabel(workMinutes)}`);
    document.text(`Trạng thái: ${day.status}${day.isLate ? ' · Đi trễ' : ''}${day.isEarly ? ' · Về sớm' : ''}${day.duplicateDate ? ' · Trùng ngày, không tính lương' : ''}`).moveDown(0.5);
  }
  document.addPage();
  heading('BẢNG LƯƠNG CÁ NHÂN');
  line('Họ tên', employee.fullName || employee.uid);
  line('Mã nhân viên', employee.employeeCode || 'Chưa cập nhật');
  line('Chức vụ', employee.position || 'Chưa cập nhật');
  line('Kỳ lương', `${period.startDate} - ${period.endDate}`);
  document.moveDown();
  line('Số ngày công hợp lệ', summary.payableDays);
  line('Tổng giờ công hợp lệ', minutesLabel(summary.totalMinutes));
  line('Đi trễ / về sớm', `${summary.late} / ${summary.early} lần (thời gian thiếu đã phản ánh trong giờ công)`);
  line('Đơn giá theo giờ', summary.hourlyRate == null ? 'Chưa cấu hình' : `${summary.hourlyRate.toLocaleString('vi-VN')} VNĐ`);
  line('Tổng lương theo giờ', summary.totalSalary == null ? 'Chưa tính được' : `${summary.totalSalary.toLocaleString('vi-VN')} VNĐ`);
  line('Thực nhận theo dữ liệu hiện có', summary.totalSalary == null ? 'Chưa tính được' : `${summary.totalSalary.toLocaleString('vi-VN')} VNĐ`);
  document.moveDown();
  document.fontSize(9).text('Lương tính theo số phút công hợp lệ và đơn giá giờ trong hồ sơ. Giờ nghỉ trưa 12:00–13:00 được loại trừ. Hệ thống chưa lưu lương cơ bản, tăng ca, thưởng, phụ cấp hoặc khoản trừ; các mục này không được cộng giả vào bảng lương.');
  document.end();
  return done;
}

async function loadContext(request, services) {
  const uid = request.auth?.uid;
  if (!uid) throw new ReportError('unauthenticated', 'Vui lòng đăng nhập.');
  const caller = await services.readCallerProfile(uid);
  if (!caller || caller.status !== 'active' || !['admin', 'manager'].includes(caller.role)) {
    throw new ReportError('permission-denied', 'Không có quyền gửi báo cáo.');
  }
  const period = periodFromInput(request.data);
  const employees = (await services.listEmployees()).filter((employee) => employee.role === 'employee' &&
    employee.status === 'active' && canAccessEmployee(caller, uid, employee));
  return { caller, uid, period, employees };
}

function validateIds(ids) {
  if (!Array.isArray(ids) || ids.length < 1 || ids.length > 50 || ids.some((id) => typeof id !== 'string' || id.length < 1 || id.length > 128) || new Set(ids).size !== ids.length) {
    throw new ReportError('invalid-argument', 'Chọn từ 1 đến 50 nhân viên khác nhau cho mỗi lượt gửi.');
  }
}

function employeeIssue(employee, summary) {
  if (!employee.email || !String(employee.email).trim()) return 'Nhân viên chưa đăng ký email.';
  const email = String(employee.email).trim();
  if (email.length > 254 || email.includes('..') || !emailPattern.test(email)) return 'Email nhân viên không hợp lệ.';
  if (summary.shifts === 0) return 'Không có dữ liệu chấm công trong kỳ đã chọn.';
  if (summary.hourlyRate == null) return 'Chưa cấu hình lương theo giờ.';
  if (summary.totalSalary == null) return 'Không thể tính lương vì số tiền vượt giới hạn.';
  return null;
}

async function previewEmployeeReport(request, services) {
  const context = await loadContext(request, services);
  const employeeId = request.data?.employeeId;
  const employee = context.employees.find((item) => item.uid === employeeId);
  if (!employee) throw new ReportError('permission-denied', 'Không có quyền xem báo cáo nhân viên này.');
  const records = await services.loadAttendance(context.period.startDate, context.period.endDate);
  const summary = buildSummary(employee, records, context.period);
  if (summary.shifts === 0) throw new ReportError('failed-precondition', 'Không có dữ liệu chấm công trong kỳ đã chọn.');
  const bytes = await services.renderPdf(summary);
  return { fileName: reportFileName(summary), pdfBase64: bytes.toString('base64') };
}

async function getEmployeeReport(request, services) {
  const context = await loadContext(request, services);
  const employee = context.employees.find((item) => item.uid === request.data?.employeeId);
  if (!employee) throw new ReportError('permission-denied', 'Không có quyền xem báo cáo nhân viên này.');
  const records = await services.loadAttendance(context.period.startDate, context.period.endDate);
  const summary = buildSummary(employee, records, context.period);
  return {
    employeeId: employee.uid,
    name: employee.fullName || employee.uid,
    employeeCode: employee.employeeCode || null,
    position: employee.position || null,
    email: employee.email || null,
    shift: employee.shiftStart && employee.shiftEnd ? `${employee.shiftStart} - ${employee.shiftEnd}` : null,
    startDate: context.period.startDate,
    endDate: context.period.endDate,
    workDays: summary.workDays,
    shifts: summary.shifts,
    payableDays: summary.payableDays,
    checkIns: summary.checkIns,
    checkOuts: summary.checkOuts,
    late: summary.late,
    early: summary.early,
    totalMinutes: summary.totalMinutes,
    hourlyRate: summary.hourlyRate,
    totalSalary: summary.totalSalary,
    days: summary.days.map((day) => ({
      workDate: day.workDate,
      checkIn: timeLabel(day.checkIn),
      checkOut: timeLabel(day.checkOut),
      paidMinutes: day.paidMilliseconds == null ? null : Math.floor(day.paidMilliseconds / 60000),
      status: day.status,
      late: day.isLate,
      early: day.isEarly,
      duplicateDate: day.duplicateDate,
    })),
  };
}

async function sendEmployeeReports(request, services) {
  const context = await loadContext(request, services);
  const ids = request.data?.employeeIds;
  validateIds(ids);
  const permitted = new Map(context.employees.map((employee) => [employee.uid, employee]));
  if (ids.some((id) => !permitted.has(id))) {
    throw new ReportError('permission-denied', 'Có nhân viên không thuộc phạm vi được phép.');
  }
  const records = await services.loadAttendance(context.period.startDate, context.period.endDate);
  const results = [];
  for (const id of ids) {
    const employee = permitted.get(id);
    const summary = buildSummary(employee, records, context.period);
    const issue = employeeIssue(employee, summary);
    if (issue) {
      results.push({ employeeId: id, name: employee.fullName || id, success: false, message: issue });
      continue;
    }
    try {
      const bytes = await services.renderPdf(summary);
      await services.sendMail({
        to: String(employee.email).trim(),
        subject: `Báo cáo chấm công và bảng lương ${context.period.startDate} - ${context.period.endDate}`,
        text: `Kính gửi ${employee.fullName || id},\n\nĐính kèm là báo cáo chấm công và bảng lương của bạn cho kỳ ${context.period.startDate} - ${context.period.endDate}.\n\nAquar Smart Attendance`,
        attachments: [{ filename: reportFileName(summary), content: bytes, contentType: 'application/pdf' }],
      });
      results.push({ employeeId: id, name: employee.fullName || id, success: true, message: 'Thành công' });
    } catch (error) {
      services.logSendError?.(id, error);
      results.push({ employeeId: id, name: employee.fullName || id, success: false,
        message: error?.message === 'SMTP is not configured' ? 'Máy chủ email chưa được cấu hình.' : 'Gửi email thất bại.' });
    }
  }
  return { successCount: results.filter((result) => result.success).length, failureCount: results.filter((result) => !result.success).length, results };
}

module.exports = { ReportError, periodFromInput, canAccessEmployee, buildSummary, renderReportPdf,
  getEmployeeReport, previewEmployeeReport, sendEmployeeReports };
