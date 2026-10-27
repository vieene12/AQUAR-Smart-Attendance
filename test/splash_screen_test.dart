import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/app/app.dart';

void main() {
  testWidgets('hiển thị tên và mô tả ứng dụng', (tester) async {
    await tester.pumpWidget(const SmartAttendanceApp());

    expect(find.text('Aquar Smart Attendance'), findsOneWidget);
    expect(
      find.text('Chấm công thông minh · Làm việc hiệu quả'),
      findsOneWidget,
    );
  });
}
