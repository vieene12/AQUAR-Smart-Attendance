# Cloud Function tạo tài khoản

## Gửi báo cáo chấm công và bảng lương

`getEmployeeReport`, `previewEmployeeReport` và `sendEmployeeReports` là Callable Functions. Flutter chỉ gửi UID nhân viên và kỳ báo cáo. Backend đọc lại hồ sơ, email, chấm công và đơn giá giờ trực tiếp từ Firestore; kiểm tra Firebase Auth, vai trò, trạng thái `active` và `managerUid` trước khi tạo một PDF tổng hợp hai phần. `getEmployeeReport` trả số liệu để hiển thị hai tab Chấm công và Bảng lương. Khi chọn nhiều người, ứng dụng tạo ZIP chứa PDF riêng của từng người rồi mở hộp thoại lưu file Android; không mở từng trang PDF. Mỗi nhân viên nhận một email riêng, không dùng CC/BCC. Function gửi tối đa 50 người mỗi lượt; ứng dụng chia danh sách lớn thành nhiều lượt và tổng hợp kết quả từng người. Hồ sơ cũ chưa có `managerUid` vẫn được xem bởi Quản lý cho tới khi Admin phân công.

Tiền lương chỉ tính từ `users/{uid}.hourlyRate` và bản ghi `attendance` hoàn tất, theo quy tắc giờ công hiện có (trừ giờ nghỉ 12:00–13:00 theo giờ Việt Nam). Database hiện chưa có lương cơ bản, tăng ca, thưởng, phụ cấp hay khoản trừ, nên PDF không tạo các khoản tiền đó. Nhân viên thiếu đơn giá giờ sẽ không được gửi bảng lương.

### Cấu hình SMTP

1. Sao chép `functions/.env.example` thành `functions/.env` và điền `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_FROM` của dịch vụ email thật. `SMTP_FROM` phải là địa chỉ/người gửi được SMTP cho phép. Không commit `.env`.
2. Lưu mật khẩu SMTP bằng Firebase Secret Manager, **không đặt trong `.env` hoặc source**:

   ```powershell
   firebase.cmd functions:secrets:set SMTP_PASSWORD --project smart-attendance-32d6b
   ```

3. Sau khi kiểm tra bằng `npm test` và `npm run check`, triển khai các function mới:

   ```powershell
   firebase.cmd deploy --only functions:getEmployeeReport,functions:previewEmployeeReport,functions:sendEmployeeReports --project smart-attendance-32d6b
   ```

Cloud Functions cần project Firebase gói Blaze và tài khoản CLI có quyền deploy. Chưa có cấu hình SMTP thật trong repository, nên test tự động chỉ dùng dịch vụ gửi giả; không gửi email thật. Khi gửi thành công, backend chỉ xác nhận SMTP đã nhận lệnh gửi, không chứng minh thư đã vào hộp thư người nhận.

### Kiểm thử sau khi cấu hình

- Đăng nhập Admin, mở **Gửi email**, chọn kỳ và một nhân viên có email, dữ liệu chấm công, đơn giá giờ; xem trước PDF, in rồi gửi. Kiểm tra một email với một PDF tổng hợp.
- Chọn nhiều nhân viên, gồm một người thiếu email; kiểm tra từng kết quả thành công/thất bại và không có CC/BCC.
- Chọn tất cả; kiểm tra số lượng kết quả bằng số nhân viên được chọn.
- Đăng nhập Quản lý; nhân viên đã gán cho quản lý khác không xuất hiện và backend từ chối UID đó nếu gọi trực tiếp.

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
