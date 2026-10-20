# Cấu hình Firebase cho Android

Ứng dụng dùng Firebase Authentication (Email/Password) và Cloud Firestore. Không có cấu hình Firebase giả trong mã nguồn. Android `applicationId` hiện là `com.example.smart_attendance` trong `android/app/build.gradle.kts`; dùng đúng giá trị này khi đăng ký ứng dụng Firebase. Nếu muốn định danh khác, đổi có chủ đích **trước** khi đăng ký.

## Việc cần làm trên máy phát triển

1. Dùng Firebase project **đã có** trong [Firebase Console](https://console.firebase.google.com/) và ghi lại Project ID. Trên Windows, cài [Firebase CLI](https://firebase.google.com/docs/cli) bằng `npm.cmd install -g firebase-tools` (hoặc dùng bản standalone), rồi chạy `firebase.cmd login` trong terminal có trình duyệt (`firebase login` nếu dùng bản standalone). Cài FlutterFire CLI bằng `dart pub global activate flutterfire_cli`.
2. Tại thư mục `smart_attendance`, chạy `flutterfire configure --project=<FIREBASE_PROJECT_ID> --platforms=android`. CLI chỉ chọn Android, ghép ứng dụng có `applicationId` tương ứng hoặc đăng ký ứng dụng Android trong project đó. CLI tạo `lib/firebase_options.dart` và mặc định tạo `android/app/google-services.json` với cấu hình thật. Kiểm tra cả hai tệp sau khi lệnh hoàn tất; nếu JSON không được tạo, tải bản của đúng Android app từ Firebase Console.
3. Project đã khai báo Google Services Gradle plugin. `main.dart` khởi tạo Firebase một lần trước `runApp` bằng `DefaultFirebaseOptions.currentPlatform` từ `firebase_options.dart` do CLI tạo. Android cũng dùng `google-services.json` thật cho Google Services plugin. Không tạo hoặc sửa tay các giá trị cấu hình.
4. Trong Firebase Console, bật **Authentication → Sign-in method → Email/Password**. Tạo tài khoản thật trong Authentication. Tạo cơ sở dữ liệu Cloud Firestore và thiết lập Security Rules phù hợp.
5. Với mỗi tài khoản, tạo document `users/{uid}`; `{uid}` là Firebase Authentication UID. Dùng `status: "active"` hoặc `"locked"`, `role: "admin"`, `"manager"` hoặc `"employee"`, và `name` là tên hiển thị. Thiếu document, thiếu trạng thái/vai trò hoặc giá trị không hợp lệ đều bị từ chối. Nếu thiếu `name`, app thử dùng tên Firebase Auth rồi email.
6. Chạy `flutter pub get`, `flutter analyze`, rồi `flutter run` trên thiết bị Android.

`firestore.rules` cho phép người dùng đọc hồ sơ của mình, Admin đang hoạt động đọc danh sách và tạo hồ sơ mới với vai trò manager/employee. Client không được sửa hoặc xóa hồ sơ. Admin tạo tài khoản bằng Firebase Auth trên Secondary Firebase App, rồi ghi `users/{uid}` bằng phiên Admin trên app mặc định; cách này dùng được trên Spark và không đổi phiên Admin. Nếu ghi hồ sơ thất bại, ứng dụng cố gắng xóa tài khoản Auth vừa tạo; khi kết quả không rõ, hãy kiểm tra Authentication và Firestore trước khi thử lại.

`firebase.json` trỏ đến tệp rules này. **Rules trong repo chưa tự động có hiệu lực trên Firebase**. Trước khi triển khai, so sánh với rules hiện hành của project để không vô tình chặn dữ liệu khác; sau khi hợp nhất, triển khai bằng `firebase deploy --only firestore:rules --project=smart-attendance-32d6b` trong terminal đã đăng nhập. Tài khoản Admin đầu tiên vẫn phải được cấp qua Firebase Console/Admin SDK đáng tin cậy; ứng dụng không cho tạo Admin hoặc đổi vai trò.

Hồ sơ được đọc từ Firestore server ngay sau khi Authentication thành công; ứng dụng đăng xuất nếu không thể xác nhận trạng thái. Kiểm tra trong client không thay thế Security Rules cho các dữ liệu được bảo vệ. Hai tệp cấu hình thật được bỏ qua bởi `.gitignore` và cần chia sẻ qua quy trình riêng của nhóm.
