import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/statistics/data/report_dispatch_repository.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';

class ExportRepository extends FirebaseReportDispatchRepository {
  @override
  Future<ReportPdf> preview({
    required String employeeUid,
    required AttendancePeriodKind kind,
    required DateTime date,
  }) async {
    if (employeeUid == 'bad') throw StateError('Không có dữ liệu');
    return ReportPdf(
      fileName: '$employeeUid.pdf',
      bytes: Uint8List.fromList('%PDF-$employeeUid'.codeUnits),
    );
  }
}

void main() {
  test('xuất nhiều nhân viên thành một ZIP, PDF riêng và tiếp tục khi một người lỗi', () async {
    final progress = <int>[];
    final result = await ExportRepository().export(
      recipients: const [
        ReportRecipient(uid: 'a', name: 'Nguyễn Văn A', code: 'NV001'),
        ReportRecipient(uid: 'bad', name: 'Lỗi', code: 'NV002'),
        ReportRecipient(uid: 'b', name: 'Trần Văn B', code: 'NV003'),
      ],
      kind: AttendancePeriodKind.month,
      date: DateTime(2026, 10, 26),
      onProgress: (done, _) => progress.add(done),
    );
    expect(progress, [1, 2, 3]);
    expect(result.failures.map((item) => item.uid), ['bad']);
    expect(result.fileName, 'BaoCao_2026-10-01_2026-10-31.zip');
    final zip = ZipDecoder().decodeBytes(result.bytes!);
    expect(zip.files.length, 2);
    expect(zip.files.map((file) => file.name), contains('nv001_nguyen_van_a_a.pdf'));
    expect(zip.files.map((file) => file.name), contains('nv003_tran_van_b_b.pdf'));
    expect(zip.files.every((file) => String.fromCharCodes(file.content as List<int>).startsWith('%PDF-')), isTrue);
  });
}
