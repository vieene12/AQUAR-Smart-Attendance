# Cấu hình Firebase cho Android

Ứng dụng dùng Firebase Authentication (Email/Password) và Cloud Firestore. Android `applicationId` hiện là `com.example.smart_attendance` trong `android/app/build.gradle.kts`; dùng đúng giá trị này khi đăng ký ứng dụng Firebase. Nếu muốn định danh khác, đổi có chủ đích **trước** khi đăng ký.

## Cấu hình production

1. Dùng Firebase project **đã có** trong [Firebase Console](https://console.firebase.google.com/) và ghi lại Project ID. Trên Windows, cài [Firebase CLI](https://firebase.google.com/docs/cli) bằng `npm.cmd install -g firebase-tools` (hoặc dùng bản standalone), rồi chạy `firebase.cmd login` trong terminal có trình duyệt (`firebase login` nếu dùng bản standalone). Cài FlutterFire CLI bằng `dart pub global activate flutterfire_cli`.
2. Tại thư mục `smart_attendance`, chạy `flutterfire configure --project=<FIREBASE_PROJECT_ID> --platforms=android`. CLI chỉ chọn Android, ghép ứng dụng có `applicationId` tương ứng hoặc đăng ký ứng dụng Android trong project đó. CLI tạo `lib/firebase_options.dart` và mặc định tạo `android/app/google-services.json` với cấu hình thật. Kiểm tra cả hai tệp sau khi lệnh hoàn tất; nếu JSON không được tạo, tải bản của đúng Android app từ Firebase Console.
3. Project đã khai báo Google Services Gradle plugin. `main.dart` gọi `FirebaseBootstrap.initialize()` trước `runApp`; khi không bật Emulator, bootstrap dùng `DefaultFirebaseOptions.currentPlatform` từ `firebase_options.dart`. Android cũng dùng `google-services.json` thật cho Google Services plugin. Không tạo hoặc sửa tay các giá trị production.
4. Trong Firebase Console, bật **Authentication → Sign-in method → Email/Password**. Tạo tài khoản thật trong Authentication. Tạo cơ sở dữ liệu Cloud Firestore và thiết lập Security Rules phù hợp.
5. Với mỗi tài khoản, tạo document `users/{uid}`; `{uid}` là Firebase Authentication UID. Dùng `status: "active"` hoặc `"locked"`, `role: "admin"`, `"manager"` hoặc `"employee"`, và `name` là tên hiển thị. Thiếu document, thiếu trạng thái/vai trò hoặc giá trị không hợp lệ đều bị từ chối. Nếu thiếu `name`, app thử dùng `fullName`, tên Firebase Auth rồi email.
6. Chạy `flutter pub get`, `flutter analyze`, rồi `flutter run` trên thiết bị Android.

`firestore.rules` cho phép người dùng đọc hồ sơ của mình. Luồng F02 quản lý tài khoản lấy Firebase ID Token của Admin và gọi ASP.NET Core REST API; Flutter không tự tạo tài khoản bằng secondary Firebase Auth app và không fallback ghi Firestore trực tiếp khi API lỗi. Backend chỉ cho Admin active tạo/cập nhật/khóa Employee hoặc Manager; Admin khác chỉ được xem.

`firebase.json` trỏ đến rules production. **Rules trong repo chưa tự động có hiệu lực trên Firebase**. Không deploy rules hoặc backend khi chưa được nhóm phê duyệt. Tài khoản Admin đầu tiên vẫn phải được cấp qua Firebase Console/Admin SDK đáng tin cậy; ứng dụng không cho tạo Admin hoặc đổi vai trò.

Hồ sơ được đọc từ Firestore server ngay sau khi Authentication thành công; ứng dụng đăng xuất nếu không thể xác nhận trạng thái. Kiểm tra trong client không thay thế Security Rules cho các dữ liệu được bảo vệ. Hai tệp cấu hình thật được bỏ qua bởi `.gitignore` và cần chia sẻ qua quy trình riêng của nhóm.

## Firebase Emulator trên điện thoại Android thật

Chế độ này chỉ bật có chủ đích trong debug và chỉ dùng project demo `demo-smart-attendance`. Điện thoại phải cho phép USB debugging. Thiết lập port forwarding trước khi chạy ứng dụng:

```powershell
$adb = 'C:\Users\Thanh Vy\AppData\Local\Android\sdk\platform-tools\adb.exe'
& $adb reverse tcp:8080 tcp:8080
& $adb reverse tcp:9099 tcp:9099
& $adb reverse tcp:8081 tcp:8081
```

Khởi động Auth và Firestore Emulator bằng cấu hình dành riêng cho điện thoại:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-22'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
firebase emulators:start --config firebase.device-emulator.json `
  --only auth,firestore --project demo-smart-attendance
```

Khởi động backend trong PowerShell khác:

```powershell
$env:ASPNETCORE_ENVIRONMENT = 'Development'
$env:ASPNETCORE_URLS = 'http://127.0.0.1:8080'
$env:Firebase__ProjectId = 'demo-smart-attendance'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099'
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8081'
dotnet run --project backend/src/SmartAttendance.Api --no-launch-profile
```

Sau khi tạo Admin thử nghiệm trong Auth Emulator và `users/{uid}`, chạy debug app:

```powershell
flutter run -d R7AY311Y11L --flavor emutest -t lib/main_emutest.dart `
  --dart-define=USE_FIREBASE_EMULATORS=true `
  --dart-define=FIREBASE_EMULATOR_PROJECT_ID=demo-smart-attendance `
  --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1 `
  --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

Ứng dụng fail-fast trước `runApp` nếu bật Emulator ngoài debug build, project không phải `demo-smart-attendance`, hoặc host điện thoại không phải `127.0.0.1`. HTTP cleartext của Android debug chỉ được phép cho loopback qua `android/app/src/debug/res/xml/network_security_config.xml`. Release manifest không cho phép cleartext.

Flavor `emutest` có application ID `com.example.smart_attendance.emutest`, nhãn
`Smart Attendance Emulator` và được cài song song với ứng dụng production. Task
Google Services bị tắt riêng cho flavor này nên `android/app/google-services.json`
production không được xử lý. Entrypoint `lib/main_emutest.dart` bắt buộc Emulator;
Gradle từ chối build nếu flavor này dùng nhầm `lib/main.dart`.

Không build `emutest` release/profile. Bản kiểm thử chỉ hỗ trợ debug với bốn
`dart-define` ở trên. Flavor `production` giữ nguyên application ID
`com.example.smart_attendance` và dùng cấu hình Firebase production hiện có.
