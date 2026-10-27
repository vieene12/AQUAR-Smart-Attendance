# Aquar Smart Attendance

## Gửi báo cáo và bảng lương qua email

Admin dùng mục **Gửi email**; Quản lý cũng có mục này cho nhân viên trong phạm vi phụ trách. Chọn tuần/tháng/quý/năm, một hoặc nhiều nhân viên, **Chọn tất cả**. Thanh thao tác cố định cho phép gửi email hoặc xuất file ngay trên màn hình danh sách. Chọn một người để mở hai tab **Chấm công** và **Bảng lương**, xem trước/in/lưu PDF hoặc gửi email. Chọn nhiều người để lưu một ZIP chứa PDF riêng của từng người; thao tác hàng loạt không mở từng trang báo cáo. Kết quả gửi và lỗi xuất hiển thị riêng từng người. Nút email trong **Báo cáo thống kê** dẫn tới cùng màn hình gửi mới. Xem [hướng dẫn Cloud Functions](functions/README.md) để cấu hình SMTP và triển khai backend trước khi gửi email thật.

## Nhân viên phụ trách và lịch sử

Admin mở **Quản lý nhân viên → Chỉnh sửa tài khoản** để nhập mã nhân viên (`employeeCode`), chức vụ (`position`), giờ bắt đầu/kết thúc ca (`shiftStart`, `shiftEnd`, định dạng `HH:mm`) và gán quản lý (`managerUid`) cho hồ sơ nhân viên trong `users/{uid}`. Hồ sơ cũ chưa có các trường này sẽ hiển thị “Chưa cập nhật”. Quản lý thấy nhân viên được gán cho mình và nhân viên chưa được phân công; nhân viên đã gán cho quản lý khác không hiển thị. Admin nên phân công các hồ sơ cũ để giới hạn danh sách đúng theo người phụ trách. Không dùng dữ liệu giả hoặc giờ ca mặc định.

Mục **Nhân viên phụ trách** của quản lý đọc bản ghi `attendance` của ngày Việt Nam hiện tại, chỉ hiển thị trạng thái `working` chưa có `checkOutAt`. Mục **Lịch sử** của quản lý/admin đọc check-in/check-out thật theo hôm nay, tuần này hoặc tháng này; nhân viên tiếp tục chỉ xem lịch sử của chính mình. Nhấn **Làm mới** để lấy trạng thái mới từ Firestore. Sau khi cập nhật [firestore.rules](firestore.rules), cần triển khai Rules lên Firebase project thật trước khi lưu các trường hồ sơ mới.

Ứng dụng Android chấm công nhân viên bằng Flutter. Hiện có màn hình khởi động, đăng nhập email/mật khẩu bằng Firebase Authentication, kiểm tra hồ sơ Cloud Firestore và điều hướng theo vai trò. Employee có thể Check-in và Check-out vào Firestore sau xác thực sinh trắc học. Chưa có tính lương hoặc báo cáo.

## Yêu cầu

- Flutter 3.47.4 hoặc bản tương thích; Dart 3.13 trở lên.
- Android SDK, Java và thiết bị Android hoặc emulator đã sẵn sàng.

## Chạy ứng dụng

Trước khi chạy, hoàn tất [cấu hình Firebase cho Android](lib/core/firebase/README.md) bằng FlutterFire CLI và Firebase Console.

```powershell
cd smart_attendance
flutter pub get
flutter devices
flutter run -d <device-id>
```

Kiểm tra mã:

```powershell
flutter analyze
flutter test
```

## Cấu trúc

```text
lib/
  app/                         Cấu hình MaterialApp và định tuyến sau này
  core/
    firebase/                  Hướng dẫn cấu hình Firebase Android
    theme/                     Chủ đề Material 3 dùng chung
  features/
    auth/data/                 Xác thực và kiểm tra hồ sơ Firestore
    auth/domain/               Hồ sơ và vai trò người dùng
    auth/presentation/         Đăng nhập và kiểm tra phiên
    attendance/data/           Check-in, Check-out Firestore và xác thực sinh trắc học
    attendance/presentation/   Giao diện chấm công Employee
    home/presentation/         Ba trang chủ theo vai trò
    splash/presentation/       Màn hình khởi động
  main.dart                    Điểm khởi chạy
test/                           Kiểm thử giao diện và luồng chấm công
android/                        Project Android chuẩn của Flutter
```

Mỗi tính năng tương lai nên có thư mục riêng trong `features/` (ví dụ `auth`, `attendance`, `reports`, `payroll`) và chỉ thêm các lớp `data`, `domain`, `presentation` khi thật sự cần. Giữ logic chung trong `core/`.

## Dữ liệu đăng nhập

Mỗi Firebase Authentication UID cần một document `users/{uid}` trong Firestore với `status: "active"` hoặc `status: "locked"`, `role: "admin" | "manager" | "employee"` và `name` để hiển thị. Ứng dụng kiểm tra lại hồ sơ từ server khi mở app và khi quay từ nền lên; nếu không xác minh được thì không mở trang chủ. Xem hướng dẫn Firebase để triển khai Security Rules và dữ liệu thật.

## Check-in Employee

Một ngày làm việc được tính theo giờ Việt Nam (UTC+07:00). Bản ghi nằm tại `attendance/{uid}_{YYYY-MM-DD}` với đúng năm trường: `employeeId`, `workDate`, `checkInAt` (server timestamp), `method: "biometric"`, `status: "working"`. Transaction kiểm tra hồ sơ `users/{uid}` còn `active` và chưa có bản ghi trước khi tạo. Ứng dụng đọc lại bản ghi từ server mới hiển thị giờ vào; nếu không xác nhận được kết quả thì yêu cầu tải lại trạng thái.

## Check-out Employee

Employee `active` đã Check-in hôm nay có thể xác thực sinh trắc học để Check-out. Transaction đọc hồ sơ và bản ghi hiện có, sau đó chỉ cập nhật `checkOutAt` bằng server timestamp và `status: "completed"`. Rules chỉ cho chủ bản ghi chuyển `working` sang `completed` một lần, giữ nguyên các trường Check-in và yêu cầu giờ ra không trước giờ vào. Ứng dụng đọc lại bản ghi từ Firestore server rồi mới hiện giờ ra và tổng thời lượng từ hai timestamp đã lưu. Nếu không xác nhận được kết quả ghi, tải lại trạng thái trước khi thử tiếp. MVP này chỉ Check-out bản ghi của ngày Việt Nam hiện tại; ca làm qua nửa đêm cần thiết kế riêng.

## Lịch sử chấm công Employee

Từ trang chủ Employee, mở **Lịch sử chấm công** để xem các bản ghi của UID đang đăng nhập. Danh sách đọc từ Firestore server, sắp xếp `workDate` mới nhất trước và lọc tất cả, theo tháng hoặc khoảng ngày (bao gồm hai đầu khoảng). Bản ghi `working` chỉ hiển thị giờ vào; tổng thời lượng chỉ tính khi đã có `checkOutAt` từ server. Rules chỉ cho Employee `active` truy vấn bản ghi có `employeeId` bằng UID của mình. Truy vấn dùng composite index `attendance`: `employeeId` tăng dần, `workDate` giảm dần, khai báo trong [firestore.indexes.json](firestore.indexes.json). Nếu Firestore báo thiếu index, triển khai index bên dưới hoặc tạo theo liên kết trong thông báo lỗi Firestore.

## NFC bước 08.1

Màn hình Chấm công có lựa chọn **Sinh trắc học / Thẻ NFC**. Ứng dụng dùng `nfc_manager` để kiểm tra thiết bị Android có NFC và NFC đã bật chưa; kiểm tra lại khi quay về ứng dụng hoặc nhấn **Kiểm tra lại NFC**. Thiết bị không hỗ trợ sẽ không chọn được Thẻ NFC. Nếu NFC đang tắt, mở **Cài đặt Android**, tìm **NFC**, bật lên rồi quay lại. Khi chọn Thẻ NFC, hai nút Check-in/Check-out bị khóa vì bước này chưa đọc thẻ, liên kết thẻ hoặc ghi chấm công bằng NFC. Chọn Sinh trắc học để dùng luồng hiện có.

Kiểm thử trên Android thật: thử một thiết bị không có NFC, một thiết bị có NFC đang tắt, rồi bật NFC trong Cài đặt và quay lại ứng dụng. Xác nhận trạng thái được cập nhật, lựa chọn NFC có thể chọn khi thiết bị hỗ trợ, hai nút chấm công bị khóa khi chọn NFC và hoạt động sinh trắc học như cũ sau khi chọn lại.

## Dịch vụ GPS chuẩn bị giới hạn vị trí

`LocationService` trong `lib/features/attendance/data/location_service.dart` kiểm tra GPS và quyền vị trí, chỉ yêu cầu quyền khi `getCurrentLocation()` được gọi, rồi lấy **một** vị trí hiện tại với độ chính xác tính bằng mét. Nơi gọi phải truyền `maxAccuracyMeters`; dịch vụ trả lỗi phân loại khi GPS tắt, quyền bị từ chối hoặc từ chối vĩnh viễn, hết thời gian chờ, sai số vượt ngưỡng hoặc không thể lấy vị trí. Android chỉ khai báo quyền vị trí gần đúng và chính xác, không khai báo quyền nền.

## Admin cấu hình vị trí chấm công (bước 07.7)

Admin mở **Vị trí chấm công** từ trang chủ để đọc và sửa document `company_settings/attendance_location`. Cấu hình gồm `name`, `latitude`, `longitude`, `radiusMeters` và `maxAccuracyMeters`; tọa độ phải nằm trong giới hạn hợp lệ, bán kính và sai số GPS phải lớn hơn 0. Nút **Lấy vị trí hiện tại** chỉ xin quyền GPS khi nhấn và cần nhập độ chính xác GPS tối đa trước; tọa độ lấy được chỉ điền vào form, Admin vẫn phải nhấn **Lưu cấu hình**. Ứng dụng đọc lại cấu hình từ Firestore server sau khi ghi trước khi báo lưu thành công. Rules cho Admin `active` tạo/sửa; Admin, Manager và Employee `active` được đọc; không cho liệt kê hoặc xóa.

## Kiểm tra phạm vi trước chấm công (bước 07.8)

Khi Employee nhấn Check-in hoặc Check-out bằng sinh trắc học, ứng dụng đọc cấu hình vị trí từ Firestore server, lấy một vị trí hiện tại bằng `LocationService`, kiểm tra sai số không vượt `maxAccuracyMeters` và tính khoảng cách bằng `Geolocator.distanceBetween`. Chỉ khi khoảng cách không vượt `radiusMeters` mới mở prompt sinh trắc học. Thiếu cấu hình, lỗi mạng/quyền, GPS tắt, từ chối vị trí, timeout, sai số lớn hoặc ngoài phạm vi đều dừng trước xác thực và trước ghi attendance. Hai nút bị khóa trong suốt thao tác. Tọa độ GPS không được ghi vào attendance hay lưu thành lịch sử.

Kiểm thử Android: đặt vị trí thử nghiệm và bán kính trên tài khoản Admin, dùng Employee thử Check-in và Check-out trong/ngoài phạm vi; tắt GPS, từ chối quyền, đặt sai số tối đa thấp và xóa cấu hình trên dự án thử nghiệm để xác nhận thông báo và không có bản ghi mới. Kiểm tra prompt sinh trắc học chỉ xuất hiện khi vượt qua kiểm tra vị trí.

**Giới hạn bảo mật GPS:** Kiểm tra khoảng cách diễn ra trên client. Một client bị sửa hoặc vị trí giả lập có thể bỏ qua bước này và gọi Firestore trực tiếp; Rules attendance hiện không kiểm chứng vị trí. Nếu phạm vi địa lý phải là ràng buộc bảo mật, cần xác minh phía server và biện pháp chống giả mạo phù hợp.

Sau khi rà soát [firestore.rules](firestore.rules), triển khai Rules bằng `firebase deploy --only firestore:rules --project <project-id>`. Kiểm thử trên Android bằng tài khoản Admin `active`: mở form, nhập dữ liệu sai để kiểm tra lỗi, lấy GPS khi quyền chưa cấp, lưu và mở lại để xác nhận dữ liệu thật. Thử tài khoản Manager/Employee để xác nhận không thể ghi trực tiếp vào document; thử tài khoản bị khóa để xác nhận không đọc được.

Trước khi thử chấm công thật, kiểm tra Rules trong [firestore.rules](firestore.rules), thử trên Firestore Emulator hoặc dự án thử nghiệm, rồi triển khai vào đúng Firebase project:

```powershell
firebase deploy --only firestore:rules --project <project-id>
firebase deploy --only firestore:indexes --project <project-id>
```

Lệnh deploy Rules thay thế Rules đang hoạt động trên project, gồm cả Rules cho `users`. Lệnh deploy indexes áp dụng cấu hình index trong repository; kiểm tra các index hiện có của project trước khi triển khai. Không triển khai vào production khi chưa rà soát cấu hình.

Kiểm thử trên Android có mạng, đã bật khóa màn hình và đăng ký vân tay hoặc khuôn mặt:

1. Đăng nhập bằng Employee `active`, vào Chấm công, nhấn Check-in và xác thực. Kiểm tra đúng một document của ngày Việt Nam trong Firestore, giờ vào xuất hiện từ server và trạng thái “Đang làm việc”.
2. Mở lại màn hình và thử Check-in lần nữa; không được tạo bản ghi thứ hai. Thử đồng thời trên hai thiết bị cùng tài khoản để kiểm tra transaction.
3. Hủy prompt, xác thực sai, tắt mạng, khóa hồ sơ hoặc dùng tài khoản khác; không được báo Check-in thành công. Với lỗi mạng sau lúc gửi, dùng “Tải lại” để xác nhận bản ghi thực.
4. Nhấn Check-out và xác thực. Kiểm tra cùng document có `checkOutAt`, `status: "completed"`, các trường cũ giữ nguyên; giờ ra và tổng thời lượng xuất hiện trong ứng dụng.
5. Thử Check-out khi chưa Check-in, sau khi đã Check-out, khi hủy prompt, tắt mạng hoặc khóa hồ sơ. Không trường hợp nào được báo thành công giả. Thử sửa `checkInAt`, `employeeId`, `workDate`, `method` hoặc đặt `checkOutAt` trước `checkInAt` qua client để xác nhận Rules từ chối.

**Giới hạn bảo mật:** Firestore Rules xác minh UID, vai trò, trạng thái hồ sơ, ngày, cấu trúc bản ghi và thời gian server, nhưng không thể chứng minh prompt sinh trắc học đã chạy. Trường `method` do client khai báo; một client tự sửa có thể gọi Firestore trực tiếp nếu vẫn đáp ứng Rules. Cần cơ chế xác minh phía server nếu sinh trắc học phải là bằng chứng bảo mật.
