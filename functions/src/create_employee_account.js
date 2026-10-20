class AccountCreationError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'AccountCreationError';
    this.code = code;
  }
}

function validateAccountData(data) {
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    throw new AccountCreationError('invalid-argument', 'Dữ liệu tài khoản không hợp lệ.');
  }

  const fullName = typeof data.fullName === 'string' ? data.fullName.trim() : '';
  const email = typeof data.email === 'string' ? data.email.trim().toLowerCase() : '';
  const password = data.password;
  const role = data.role;
  const hourlyRate = data.hourlyRate;

  if (!fullName || fullName.length > 100) {
    throw new AccountCreationError('invalid-argument', 'Họ tên không hợp lệ.');
  }
  if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new AccountCreationError('invalid-argument', 'Email không hợp lệ.');
  }
  if (typeof password !== 'string' || !password.trim() || password.length < 6) {
    throw new AccountCreationError('invalid-argument', 'Mật khẩu phải có ít nhất 6 ký tự.');
  }
  if (role !== 'manager' && role !== 'employee') {
    throw new AccountCreationError('invalid-argument', 'Vai trò không hợp lệ.');
  }
  if (!Number.isSafeInteger(hourlyRate) || hourlyRate < 0) {
    throw new AccountCreationError('invalid-argument', 'Lương theo giờ phải là số nguyên không âm.');
  }

  return { fullName, email, password, role, hourlyRate };
}

async function createEmployeeAccount(request, services) {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new AccountCreationError('unauthenticated', 'Vui lòng đăng nhập lại.');
  }

  let callerProfile;
  try {
    callerProfile = await services.readCallerProfile(callerUid);
  } catch (error) {
    services.logError?.('read-caller-profile', callerUid, error);
    throw new AccountCreationError('unavailable', 'Không thể xác minh quyền Admin. Vui lòng thử lại.');
  }
  if (callerProfile?.role !== 'admin' || callerProfile.status !== 'active') {
    throw new AccountCreationError('permission-denied', 'Bạn không có quyền thêm tài khoản.');
  }

  const input = validateAccountData(request.data);
  let createdUser;
  try {
    createdUser = await services.createAuthUser({
      email: input.email,
      password: input.password,
      displayName: input.fullName,
    });
  } catch (error) {
    if (error.code === 'auth/email-already-exists') {
      throw new AccountCreationError('already-exists', 'Email đã được sử dụng.');
    }
    if (error.code === 'auth/invalid-email' || error.code === 'auth/invalid-password') {
      throw new AccountCreationError('invalid-argument', 'Email hoặc mật khẩu không hợp lệ.');
    }
    services.logError?.('create-auth-user', callerUid, error);
    throw new AccountCreationError('internal', 'Không thể tạo tài khoản. Vui lòng thử lại.');
  }

  try {
    await services.createProfile(createdUser.uid, {
      fullName: input.fullName,
      email: input.email,
      role: input.role,
      status: 'active',
      hourlyRate: input.hourlyRate,
    });
  } catch (error) {
    services.logError?.('create-profile', createdUser.uid, error);
    let rollbackFailed = false;

    try {
      await services.deleteAuthUser(createdUser.uid);
    } catch (deleteError) {
      rollbackFailed = true;
      services.logError?.('delete-auth-user', createdUser.uid, deleteError);
      try {
        await services.disableAuthUser(createdUser.uid);
      } catch (disableError) {
        services.logError?.('disable-auth-user', createdUser.uid, disableError);
      }
    }

    // A timeout can happen after a write commits. Do not delete a pre-existing document.
    const profileAlreadyExisted = error.code === 6 || error.code === 'already-exists';
    if (!profileAlreadyExisted) {
      try {
        await services.deleteProfile(createdUser.uid);
      } catch (deleteError) {
        rollbackFailed = true;
        services.logError?.('delete-profile', createdUser.uid, deleteError);
      }
    }

    if (rollbackFailed) {
      throw new AccountCreationError(
        'failed-precondition',
        'Không thể hoàn tác đầy đủ. Vui lòng liên hệ quản trị viên trước khi thử lại.',
      );
    }
    throw new AccountCreationError(
      'internal',
      'Không thể lưu hồ sơ. Tài khoản vừa tạo đã được hoàn tác.',
    );
  }

  return { uid: createdUser.uid };
}

module.exports = { AccountCreationError, createEmployeeAccount, validateAccountData };
