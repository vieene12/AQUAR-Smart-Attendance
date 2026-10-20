# Cloud Function tạo tài khoản

`createEmployeeAccount` là Callable Function Node.js 22. Function dùng Admin SDK để tạo Firebase Authentication user rồi tạo `users/{uid}`. Chỉ người gọi có hồ sơ Firestore `role: admin` và `status: active` mới được phép gọi. Mật khẩu ban đầu chỉ được gửi tới Firebase Authentication, không lưu trong Firestore hoặc log.

## Trước khi triển khai

1. Xác nhận Firebase project `smart-attendance-32d6b` đã dùng gói Blaze. Cloud Functions cần Blaze để triển khai; hãy tự thực hiện nâng cấp và thiết lập cảnh báo ngân sách trong Firebase Console nếu cần. Không có thao tác nâng cấp tự động trong mã nguồn.
2. Xác nhận Authentication đã bật phương thức Email/Password, Cloud Firestore đã hoạt động và hồ sơ Admin hiện tại trong `users/{uid}` có `role: admin`, `status: active`.
3. Đăng nhập Firebase CLI bằng tài khoản có quyền deploy vào project. Không đặt service-account key trong repository.

## Kiểm tra và deploy thủ công

Chạy từ thư mục `functions`:

```powershell
npm.cmd install
npm.cmd test
npm.cmd run check
```

Chạy từ thư mục gốc `smart_attendance`:

```powershell
firebase.cmd login
firebase.cmd deploy --only functions:createEmployeeAccount --project smart-attendance-32d6b
```

Giữ `firestore.rules` hiện tại: client không được `create`, `update` hay `delete` trong `users`. Admin SDK chạy phía server không dùng Security Rules của client; quyền Admin được kiểm tra riêng trong function. Sau deploy, chạy `flutter pub get` rồi build/chạy lại ứng dụng Android để có plugin `cloud_functions`.

Khi thử nghiệm, hãy dùng tài khoản Admin thật đã được cấp quyền. Nếu request bị timeout hoặc kết quả không rõ, kiểm tra danh sách tài khoản và Firebase Console trước khi thử lại để tránh tạo trùng. Nếu rollback thất bại, xem log function theo UID để xử lý thủ công.
