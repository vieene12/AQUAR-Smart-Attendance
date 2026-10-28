'use strict';

const fs = require('node:fs');
const path = require('node:path');
require('firebase/compat/firestore');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails: firebaseAssertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  runTransaction,
  serverTimestamp,
  setDoc,
  Timestamp,
  writeBatch,
} = require('firebase/firestore');

const projectId = 'demo-employee-nfc-rules';
const rules = fs.readFileSync(
  path.resolve(__dirname, '../../firestore.rules'),
  'utf8',
).replace(/^\uFEFF/, '');
const workDate = new Date(Date.now() + 7 * 60 * 60 * 1000)
  .toISOString()
  .slice(0, 10);
const evaluationLimitFailures = [];

async function assertFails(operation) {
  const failure = await firebaseAssertFails(operation);
  const message = String(failure?.message ?? failure);
  if (message.includes('maximum of 1000 expressions')) {
    evaluationLimitFailures.push(message);
  }
  return failure;
}

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {rules},
  });
  try {
    async function seed() {
      await testEnv.clearFirestore();
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        for (const [employeeId, cardUid] of [
          ['employee-a', '04AABBCCDD'],
          ['employee-b', '0411223344'],
        ]) {
          await setDoc(doc(db, 'users', employeeId), {
            role: 'employee',
            status: 'active',
          });
          await setDoc(doc(db, 'nfc_cards', cardUid), {
            employeeUid: employeeId,
            createdAt: serverTimestamp(),
          });
          await setDoc(doc(db, 'nfc_employee_cards', employeeId), {
            cardUid,
            updatedAt: serverTimestamp(),
          });
        }
        await setDoc(doc(db, 'users', 'admin'), {
          role: 'admin',
          status: 'active',
        });
        await setDoc(doc(db, 'users', 'manager'), {
          role: 'manager',
          status: 'active',
        });
        await setDoc(doc(db, 'users', 'locked-manager'), {
          role: 'manager',
          status: 'locked',
        });
      });
    }

    function attendance(db) {
      return doc(db, 'attendance', `employee-a_${workDate}`);
    }

    function checkIn(db, employeeId, cardUid, method = 'nfc_mobile') {
      return runTransaction(db, async (tx) => {
        const target = attendance(db);
        await tx.get(doc(db, 'users', employeeId));
        await tx.get(doc(db, 'nfc_employee_cards', employeeId));
        await tx.get(doc(db, 'nfc_cards', cardUid));
        await tx.get(target);
        tx.set(target, {
          employeeId,
          workDate,
          checkInAt: serverTimestamp(),
          method,
          status: 'working',
          nfcCardUid: cardUid,
        });
      });
    }

    async function seedCompletedNfcMobile(attendanceId, before) {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await setDoc(
          doc(context.firestore(), 'attendance', attendanceId),
          before,
        );
      });
    }

    function adjustNfcMobile(
      db,
      operatorUid,
      attendanceId,
      before,
      newCheckIn,
      revision,
      auditOverrides = {},
    ) {
      const batch = writeBatch(db);
      const manualTime = serverTimestamp();
      const after = {
        ...before,
        checkInAt: newCheckIn,
        manualRevision: revision,
        lastManualAt: manualTime,
        lastManualBy: operatorUid,
      };
      batch.set(doc(db, 'attendance', attendanceId), after);
      batch.set(doc(db, 'attendance_audit', `${attendanceId}_${revision}`), {
        attendanceId,
        employeeUid: before.employeeId,
        operatorUid,
        reason: 'Dieu chinh gio vao NFC mobile',
        action: 'adjust',
        revision,
        before,
        after,
        createdAt: manualTime,
        ...auditOverrides,
      });
      return batch.commit();
    }

    await seed();
    const employeeA = testEnv.authenticatedContext('employee-a').firestore();
    await assertSucceeds(getDoc(attendance(employeeA)));
    await assertFails(getDoc(doc(
      employeeA,
      'attendance',
      `employee-b_${workDate}`,
    )));
    await assertSucceeds(checkIn(employeeA, 'employee-a', '04AABBCCDD'));
    const saved = await assertSucceeds(getDoc(attendance(employeeA)));
    if (saved.data().employeeId !== 'employee-a' ||
        saved.data().method !== 'nfc_mobile') {
      throw new Error('Check-in NFC đã ghi sai employeeId hoặc method.');
    }
    console.log('ALLOW: Employee A check-in bằng thẻ A.');

    await assertSucceeds(runTransaction(employeeA, async (tx) => {
      const target = attendance(employeeA);
      await tx.get(doc(employeeA, 'users', 'employee-a'));
      await tx.get(doc(employeeA, 'nfc_employee_cards', 'employee-a'));
      await tx.get(doc(employeeA, 'nfc_cards', '04AABBCCDD'));
      await tx.get(target);
      tx.update(target, {
        status: 'completed',
        checkOutAt: serverTimestamp(),
        checkOutCardUid: '04AABBCCDD',
      });
    }));
    console.log('ALLOW: Employee A check-out bằng thẻ A.');

    await seed();
    await assertFails(checkIn(employeeA, 'employee-a', '0411223344'));
    console.log('DENY: Employee A dùng thẻ B.');

    await seed();
    await assertFails(checkIn(employeeA, 'employee-a', '04FFEEDDCC'));
    console.log('DENY: thẻ chưa đăng ký.');

    await seed();
    const guest = testEnv.unauthenticatedContext().firestore();
    await assertFails(checkIn(guest, 'employee-a', '04AABBCCDD'));
    console.log('DENY: chưa đăng nhập.');

    await seed();
    await assertSucceeds(runTransaction(employeeA, async (tx) => {
      const target = attendance(employeeA);
      await tx.get(doc(employeeA, 'users', 'employee-a'));
      await tx.get(target);
      tx.set(target, {
        employeeId: 'employee-a',
        workDate,
        checkInAt: serverTimestamp(),
        method: 'biometric',
        status: 'working',
      });
    }));
    await assertSucceeds(runTransaction(employeeA, async (tx) => {
      const target = attendance(employeeA);
      await tx.get(doc(employeeA, 'users', 'employee-a'));
      await tx.get(target);
      tx.update(target, {
        status: 'completed',
        checkOutAt: serverTimestamp(),
      });
    }));
    console.log('ALLOW: biometric check-in/check-out vẫn hoạt động.');

    await seed();
    const admin = testEnv.authenticatedContext('admin').firestore();
    await assertSucceeds(runTransaction(admin, async (tx) => {
      const target = attendance(admin);
      await tx.get(doc(admin, 'users', 'admin'));
      await tx.get(doc(admin, 'users', 'employee-a'));
      await tx.get(doc(admin, 'nfc_cards', '04AABBCCDD'));
      await tx.get(doc(admin, 'nfc_employee_cards', 'employee-a'));
      await tx.get(target);
      tx.set(target, {
        employeeId: 'employee-a',
        workDate,
        checkInAt: serverTimestamp(),
        method: 'nfc',
        status: 'working',
        nfcCardUid: '04AABBCCDD',
        operatorUid: 'admin',
        recordedAt: serverTimestamp(),
      });
    }));
    console.log('ALLOW: Admin NFC kiosk vẫn tạo attendance.');

    await seed();
    const attendanceId = `employee-a_${workDate}`;
    const originalCheckIn = Timestamp.fromDate(
      new Date(`${workDate}T02:00:00.000Z`),
    );
    const adjustedCheckIn = Timestamp.fromDate(
      new Date(`${workDate}T02:15:00.000Z`),
    );
    const originalCheckOut = Timestamp.fromDate(
      new Date(`${workDate}T10:00:00.000Z`),
    );
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'attendance', attendanceId), {
        employeeId: 'employee-a',
        workDate,
        checkInAt: originalCheckIn,
        checkOutAt: originalCheckOut,
        method: 'nfc_mobile',
        status: 'completed',
        nfcCardUid: '04AABBCCDD',
        checkOutCardUid: '04AABBCCDD',
      });
    });
    await assertSucceeds(runTransaction(admin, async (tx) => {
      const target = doc(admin, 'attendance', attendanceId);
      const audit = doc(admin, 'attendance_audit', `${attendanceId}_1`);
      const beforeSnapshot = await tx.get(target);
      await tx.get(audit);
      const before = beforeSnapshot.data();
      const manualTime = serverTimestamp();
      const after = {
        ...before,
        checkInAt: adjustedCheckIn,
        manualRevision: 1,
        lastManualAt: manualTime,
        lastManualBy: 'admin',
      };
      tx.set(target, after);
      tx.set(audit, {
        attendanceId,
        employeeUid: 'employee-a',
        operatorUid: 'admin',
        reason: 'Điều chỉnh giờ vào NFC mobile',
        action: 'adjust',
        revision: 1,
        before,
        after,
        createdAt: manualTime,
      });
    }));
    const adjusted = await assertSucceeds(
      getDoc(doc(admin, 'attendance', attendanceId)),
    );
    if (adjusted.data().method !== 'nfc_mobile' ||
        adjusted.data().manualRevision !== 1 ||
        !adjusted.data().checkInAt.isEqual(adjustedCheckIn)) {
      throw new Error('Điều chỉnh thủ công đã làm sai bản ghi NFC mobile.');
    }
    console.log('ALLOW: Admin điều chỉnh thủ công attendance NFC mobile.');
    const firstAudit = await assertSucceeds(getDoc(
      doc(admin, 'attendance_audit', `${attendanceId}_1`),
    ));
    if (!firstAudit.exists() ||
        firstAudit.data().revision !== 1 ||
        firstAudit.data().operatorUid !== 'admin' ||
        firstAudit.data().before.method !== 'nfc_mobile' ||
        firstAudit.data().after.nfcCardUid !== '04AABBCCDD' ||
        firstAudit.data().after.checkOutCardUid !== '04AABBCCDD') {
      throw new Error('Audit revision 1 khong luu dung metadata NFC mobile.');
    }

    const secondAdjustedCheckIn = Timestamp.fromDate(
      new Date(`${workDate}T02:30:00.000Z`),
    );
    await assertSucceeds(adjustNfcMobile(
      admin,
      'admin',
      attendanceId,
      adjusted.data(),
      secondAdjustedCheckIn,
      2,
    ));
    const secondAudit = await assertSucceeds(getDoc(
      doc(admin, 'attendance_audit', `${attendanceId}_2`),
    ));
    if (secondAudit.data().revision !== 2 ||
        secondAudit.data().before.manualRevision !== 1 ||
        !secondAudit.data().after.checkInAt.isEqual(secondAdjustedCheckIn) ||
        secondAudit.data().after.method !== 'nfc_mobile') {
      throw new Error('Audit revision 2 khong lien ket dung revision truoc.');
    }
    console.log('ALLOW: Admin audit, revision, and NFC metadata are preserved.');

    const baseAttendance = {
      employeeId: 'employee-a',
      workDate,
      checkInAt: originalCheckIn,
      checkOutAt: originalCheckOut,
      method: 'nfc_mobile',
      status: 'completed',
      nfcCardUid: '04AABBCCDD',
      checkOutCardUid: '04AABBCCDD',
    };
    await seed();
    await seedCompletedNfcMobile(attendanceId, baseAttendance);
    const manager = testEnv.authenticatedContext('manager').firestore();
    await assertSucceeds(adjustNfcMobile(
      manager,
      'manager',
      attendanceId,
      baseAttendance,
      adjustedCheckIn,
      1,
    ));
    console.log('ALLOW: Manager manual adjustment for NFC mobile.');

    await seed();
    await seedCompletedNfcMobile(attendanceId, baseAttendance);
    const lockedManager = testEnv
      .authenticatedContext('locked-manager')
      .firestore();
    await assertFails(adjustNfcMobile(
      employeeA,
      'employee-a',
      attendanceId,
      baseAttendance,
      adjustedCheckIn,
      1,
    ));
    await assertFails(adjustNfcMobile(
      lockedManager,
      'locked-manager',
      attendanceId,
      baseAttendance,
      adjustedCheckIn,
      1,
    ));
    await assertFails(adjustNfcMobile(
      guest,
      'guest',
      attendanceId,
      baseAttendance,
      adjustedCheckIn,
      1,
    ));
    console.log('DENY: wrong role, locked manager, and unauthenticated adjustment.');

    await assertFails(adjustNfcMobile(
      admin,
      'admin',
      attendanceId,
      baseAttendance,
      adjustedCheckIn,
      1,
      {operatorUid: 'manager'},
    ));
    await assertFails(adjustNfcMobile(
      admin,
      'admin',
      attendanceId,
      baseAttendance,
      adjustedCheckIn,
      1,
      {revision: 2},
    ));
    console.log('DENY: tampered audit operator and revision metadata.');

    await seed();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'users', 'employee-a'), {
        role: 'employee',
        status: 'locked',
      });
    });
    await assertFails(checkIn(employeeA, 'employee-a', '04AABBCCDD'));
    console.log('DENY: locked employee NFC mobile check-in.');

    await seed();
    await seedCompletedNfcMobile(attendanceId, baseAttendance);
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), 'users', 'employee-a'), {
        role: 'employee',
        status: 'locked',
      });
    });
    await assertFails(adjustNfcMobile(
      manager,
      'manager',
      attendanceId,
      baseAttendance,
      adjustedCheckIn,
      1,
    ));
    console.log('DENY: manual adjustment for locked employee.');

    if (evaluationLimitFailures.length > 0) {
      throw new Error(
        `${evaluationLimitFailures.length} negative Rules assertions exceeded ` +
        'the 1000-expression evaluation limit; authorization was not verified.',
      );
    }
  } finally {
    await testEnv.cleanup();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
