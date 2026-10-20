const test = require('node:test');
const assert = require('node:assert/strict');
const { createEmployeeAccount } = require('../src/create_employee_account');

const validData = {
  fullName: 'Nguyễn Văn A',
  email: 'employee@example.com',
  password: 'secret123',
  role: 'employee',
  hourlyRate: 50000,
};

function makeServices(overrides = {}) {
  const calls = [];
  const services = {
    readCallerProfile: async () => ({ role: 'admin', status: 'active' }),
    createAuthUser: async () => {
      calls.push('create-auth');
      return { uid: 'new-uid' };
    },
    createProfile: async () => calls.push('create-profile'),
    deleteAuthUser: async () => calls.push('delete-auth'),
    disableAuthUser: async () => calls.push('disable-auth'),
    deleteProfile: async () => calls.push('delete-profile'),
    ...overrides,
  };
  return { services, calls };
}

test('người chưa đăng nhập bị chặn trước khi đọc hồ sơ', async () => {
  const { services, calls } = makeServices();
  await assert.rejects(
    createEmployeeAccount({ data: validData }, services),
    { code: 'unauthenticated' },
  );
  assert.deepEqual(calls, []);
});

test('chỉ Admin active được tạo tài khoản', async () => {
  const { services, calls } = makeServices({
    readCallerProfile: async () => ({ role: 'manager', status: 'active' }),
  });
  await assert.rejects(
    createEmployeeAccount({ auth: { uid: 'caller' }, data: validData }, services),
    { code: 'permission-denied' },
  );
  assert.deepEqual(calls, []);

  services.readCallerProfile = async () => ({ role: 'admin', status: 'locked' });
  await assert.rejects(
    createEmployeeAccount({ auth: { uid: 'caller' }, data: validData }, services),
    { code: 'permission-denied' },
  );
});

test('không cho tạo role admin hoặc lương âm', async () => {
  const { services, calls } = makeServices();
  await assert.rejects(
    createEmployeeAccount(
      { auth: { uid: 'caller' }, data: { ...validData, role: 'admin' } },
      services,
    ),
    { code: 'invalid-argument' },
  );
  await assert.rejects(
    createEmployeeAccount(
      { auth: { uid: 'caller' }, data: { ...validData, hourlyRate: -1 } },
      services,
    ),
    { code: 'invalid-argument' },
  );
  assert.deepEqual(calls, []);
});

test('email trùng được báo lỗi và không ghi hồ sơ', async () => {
  const { services } = makeServices({
    createAuthUser: async () => {
      throw { code: 'auth/email-already-exists' };
    },
  });
  await assert.rejects(
    createEmployeeAccount({ auth: { uid: 'caller' }, data: validData }, services),
    { code: 'already-exists' },
  );
});

test('ghi hồ sơ đúng trường sau khi tạo Auth', async () => {
  let profile;
  const { services, calls } = makeServices({
    createProfile: async (uid, data) => {
      calls.push('create-profile');
      profile = { uid, ...data };
    },
  });
  const result = await createEmployeeAccount(
    { auth: { uid: 'caller' }, data: validData },
    services,
  );

  assert.deepEqual(result, { uid: 'new-uid' });
  assert.deepEqual(calls, ['create-auth', 'create-profile']);
  assert.deepEqual(profile, {
    uid: 'new-uid',
    fullName: validData.fullName,
    email: validData.email,
    role: 'employee',
    status: 'active',
    hourlyRate: 50000,
  });
});

test('ghi Firestore thất bại thì xóa Auth và hồ sơ có thể đã ghi', async () => {
  const { services, calls } = makeServices({
    createProfile: async () => {
      calls.push('create-profile');
      throw new Error('write failed');
    },
  });
  await assert.rejects(
    createEmployeeAccount({ auth: { uid: 'caller' }, data: validData }, services),
    { code: 'internal' },
  );
  assert.deepEqual(calls, ['create-auth', 'create-profile', 'delete-auth', 'delete-profile']);
});

test('không xóa hồ sơ đã tồn tại khi Firestore báo trùng UID', async () => {
  const { services, calls } = makeServices({
    createProfile: async () => {
      const error = new Error('already exists');
      error.code = 6;
      throw error;
    },
  });
  await assert.rejects(
    createEmployeeAccount({ auth: { uid: 'caller' }, data: validData }, services),
    { code: 'internal' },
  );
  assert.deepEqual(calls, ['create-auth', 'delete-auth']);
});

test('rollback Auth thất bại thì vô hiệu hóa và yêu cầu kiểm tra thủ công', async () => {
  const { services, calls } = makeServices({
    createProfile: async () => {
      throw new Error('write failed');
    },
    deleteAuthUser: async () => {
      throw new Error('delete failed');
    },
  });
  await assert.rejects(
    createEmployeeAccount({ auth: { uid: 'caller' }, data: validData }, services),
    { code: 'failed-precondition' },
  );
  assert.deepEqual(calls, ['create-auth', 'disable-auth', 'delete-profile']);
});
