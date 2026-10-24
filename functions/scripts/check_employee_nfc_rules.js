const fs = require('node:fs');
const path = require('node:path');
require('firebase/compat/firestore');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  runTransaction,
  serverTimestamp,
  setDoc,
} = require('firebase/firestore');

const projectId = 'demo-employee-nfc-rules';
const rules = fs.readFileSync(
  path.resolve(__dirname, '../../firestore.rules'),
  'utf8',
);
const workDate = new Date(Date.now() + 7 * 60 * 60 * 1000)
  .toISOString()
  .slice(0, 10);

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
  } finally {
    await testEnv.cleanup();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
