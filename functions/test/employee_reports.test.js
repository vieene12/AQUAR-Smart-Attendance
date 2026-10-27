const test = require('node:test');
const assert = require('node:assert/strict');
const { periodFromInput, buildSummary, renderReportPdf, getEmployeeReport, previewEmployeeReport, sendEmployeeReports } = require('../src/employee_reports');

const employee = { uid: 'e1', role: 'employee', status: 'active', fullName: 'Nguyễn Văn A', email: 'a@example.com',
  employeeCode: 'NV001', position: 'Kỹ thuật viên', shiftStart: '08:00', shiftEnd: '17:00', hourlyRate: 60000 };
const attendance = { employeeId: 'e1', workDate: '2026-10-26', status: 'completed', method: 'biometric',
  checkInAt: new Date('2026-10-26T01:05:00Z'), checkOutAt: new Date('2026-10-26T10:00:00Z') };

function services(overrides = {}) {
  const sent = [];
  return {
    sent,
    readCallerProfile: async () => ({ role: 'admin', status: 'active' }),
    listEmployees: async () => [employee],
    loadAttendance: async () => [attendance],
    renderPdf: async () => Buffer.from('%PDF-test'),
    sendMail: async (message) => { sent.push(message); },
    ...overrides,
  };
}

const request = { auth: { uid: 'admin' }, data: { periodKind: 'month', anchorDate: '2026-10-26' } };

test('kỳ báo cáo chuẩn theo lịch Việt Nam', () => {
  assert.deepEqual(periodFromInput(request.data), { kind: 'month', startDate: '2026-10-01', endDate: '2026-10-31' });
  assert.deepEqual(periodFromInput({ periodKind: 'week', anchorDate: '2026-10-26' }),
    { kind: 'week', startDate: '2026-10-26', endDate: '2026-11-01' });
});

test('giờ công và tiền lương dùng dữ liệu thật, trừ nghỉ trưa', () => {
  const summary = buildSummary(employee, [attendance], periodFromInput(request.data));
  assert.equal(summary.late, 1);
  assert.equal(summary.early, 0);
  assert.equal(summary.totalMinutes, 475);
  assert.equal(summary.totalSalary, 475000);
  assert.equal(summary.checkIns, 1);
  assert.equal(summary.checkOuts, 1);
  const mobileNfc = buildSummary(employee, [{ ...attendance, method: 'nfc_mobile' }], periodFromInput(request.data));
  assert.equal(mobileNfc.totalSalary, 475000);
});

test('ngày có bản ghi trùng không được cộng lương hai lần', () => {
  const summary = buildSummary(employee, [attendance, { ...attendance, method: 'nfc' }],
    periodFromInput(request.data));
  assert.equal(summary.workDays, 1);
  assert.equal(summary.shifts, 2);
  assert.equal(summary.payableDays, 0);
  assert.equal(summary.totalSalary, 0);
  assert.ok(summary.days.every((day) => day.duplicateDate));
});

test('PDF tổng hợp có dữ liệu và tên file riêng', async () => {
  const report = await previewEmployeeReport({ ...request, data: { ...request.data, employeeId: 'e1' } },
    services({ renderPdf: renderReportPdf }));
  assert.match(report.fileName, /^BaoCaoTongHop_NV001_/);
  assert.ok(Buffer.from(report.pdfBase64, 'base64').subarray(0, 5).equals(Buffer.from('%PDF-')));
});

test('chi tiết lương trả số liệu thật và giữ trạng thái chưa check-out', async () => {
  const working = { ...attendance, status: 'working', checkOutAt: null };
  const report = await getEmployeeReport({ ...request, data: { ...request.data, employeeId: 'e1' } },
    services({ loadAttendance: async () => [working] }));
  assert.equal(report.hourlyRate, 60000);
  assert.equal(report.totalMinutes, 0);
  assert.equal(report.totalSalary, 0);
  assert.equal(report.days[0].checkOut, 'Chưa check-out');
  assert.equal(report.days[0].paidMinutes, null);
});

test('người không đăng nhập, nhân viên và quản lý khác bị chặn ở backend', async () => {
  await assert.rejects(sendEmployeeReports({ data: { ...request.data, employeeIds: ['e1'] } }, services()), { code: 'unauthenticated' });
  await assert.rejects(sendEmployeeReports({ ...request, data: { ...request.data, employeeIds: ['e1'] } },
    services({ readCallerProfile: async () => ({ role: 'employee', status: 'active' }) })), { code: 'permission-denied' });
  await assert.rejects(sendEmployeeReports({ ...request, auth: { uid: 'm2' }, data: { ...request.data, employeeIds: ['e1'] } },
    services({ readCallerProfile: async () => ({ role: 'manager', status: 'active' }),
      listEmployees: async () => [{ ...employee, managerUid: 'm1' }] })), { code: 'permission-denied' });
  await assert.rejects(previewEmployeeReport({ ...request, auth: { uid: 'm2' },
    data: { ...request.data, employeeId: 'e1' } },
  services({ readCallerProfile: async () => ({ role: 'manager', status: 'active' }),
    listEmployees: async () => [{ ...employee, managerUid: 'm1' }] })), { code: 'permission-denied' });
  await assert.rejects(getEmployeeReport({ ...request, auth: { uid: 'm2' },
    data: { ...request.data, employeeId: 'e1' } },
  services({ readCallerProfile: async () => ({ role: 'manager', status: 'active' }),
    listEmployees: async () => [{ ...employee, managerUid: 'm1' }] })), { code: 'permission-denied' });
  await assert.rejects(sendEmployeeReports({ ...request, data: { ...request.data, employeeIds: ['e1'] } },
    services({ listEmployees: async () => [{ ...employee, status: 'locked' }] })), { code: 'permission-denied' });
});

test('gửi riêng từng nhân viên và tiếp tục khi một người lỗi', async () => {
  const second = { ...employee, uid: 'e2', fullName: 'Trần Văn B', email: 'b@example.com' };
  const third = { ...employee, uid: 'e3', fullName: 'Lê Văn C', email: '' };
  const fake = services({ listEmployees: async () => [employee, second, third],
    loadAttendance: async () => [attendance, { ...attendance, employeeId: 'e2' }, { ...attendance, employeeId: 'e3' }],
    sendMail: async (message) => { fake.sent.push(message); if (message.to === 'b@example.com') throw new Error('SMTP'); } });
  const result = await sendEmployeeReports({ ...request, data: { ...request.data, employeeIds: ['e1', 'e2', 'e3'] } }, fake);
  assert.equal(result.successCount, 1);
  assert.equal(result.failureCount, 2);
  assert.deepEqual(fake.sent.map((mail) => mail.to), ['a@example.com', 'b@example.com']);
  assert.ok(fake.sent.every((mail) => !mail.cc && !mail.bcc && mail.attachments.length === 1));
  assert.equal(result.results[2].message, 'Nhân viên chưa đăng ký email.');
});

test('email sai, thiếu chấm công và thiếu đơn giá trả kết quả riêng', async () => {
  const invalidEmail = { ...employee, uid: 'e2', email: 'not-an-email' };
  const noAttendance = { ...employee, uid: 'e3', email: 'third@example.com' };
  const noRate = { ...employee, uid: 'e4', email: 'fourth@example.com', hourlyRate: undefined };
  const fake = services({ listEmployees: async () => [invalidEmail, noAttendance, noRate],
    loadAttendance: async () => [{ ...attendance, employeeId: 'e2' }, { ...attendance, employeeId: 'e4' }] });
  const result = await sendEmployeeReports({ ...request, data: { ...request.data, employeeIds: ['e2', 'e3', 'e4'] } }, fake);
  assert.deepEqual(result.results.map((item) => item.message), [
    'Email nhân viên không hợp lệ.',
    'Không có dữ liệu chấm công trong kỳ đã chọn.',
    'Chưa cấu hình lương theo giờ.',
  ]);
  assert.deepEqual(fake.sent, []);
});
