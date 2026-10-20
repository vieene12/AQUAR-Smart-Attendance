# Hướng dẫn phát triển Smart Attendance

- Phạm vi hiện tại gồm đăng nhập Firebase Authentication, kiểm tra `users/{uid}` trong Firestore và ba trang chủ cơ bản theo vai trò. Chưa triển khai chấm công, lương hoặc báo cáo.
- Giữ mã Dart đơn giản, đặt tính năng trong `lib/features/<ten_tinh_nang>/`; dùng `lib/core/` cho thành phần dùng chung.
- Giao diện dùng Material 3, văn bản hướng đến người dùng bằng tiếng Việt; kiểm tra cả chế độ sáng và tối khi thay đổi giao diện.
- Chỉ thêm package khi tính năng được triển khai. Không tạo Firebase options, `google-services.json`, tài khoản hay dữ liệu giả; dùng cấu hình thật theo `lib/core/firebase/README.md`.
- Không tự ý thay đổi phiên bản Gradle, Kotlin, Android SDK hoặc định danh ứng dụng. Trao đổi với nhóm trước khi cần thay đổi những mục này.
- Không ghi thông tin nhạy cảm vào source, test, log hoặc tài liệu.
- Trước khi bàn giao thay đổi, chạy `flutter pub get`, `flutter analyze`, `flutter test` khi môi trường cho phép và ghi rõ nếu lệnh nào bị chặn.
