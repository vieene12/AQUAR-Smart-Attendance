import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:smart_attendance/features/auth/domain/user_profile.dart';
import 'package:smart_attendance/features/statistics/domain/attendance_statistics_service.dart';

class ReportRecipient {
  const ReportRecipient({
    required this.uid,
    required this.name,
    this.code,
    this.email,
  });

  final String uid;
  final String name;
  final String? code;
  final String? email;
}

class ReportPdf {
  const ReportPdf({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

class ReportSendResult {
  const ReportSendResult({
    required this.uid,
    required this.name,
    required this.success,
    required this.message,
  });

  final String uid;
  final String name;
  final bool success;
  final String message;
}

class ReportEmployeeDetail {
  const ReportEmployeeDetail(this.data);
  final Map<String, dynamic> data;

  String get name => data['name'] as String? ?? '';
  String get code => data['employeeCode'] as String? ?? 'Chưa có mã';
  String get period => '${data['startDate']} – ${data['endDate']}';
  int get totalMinutes => data['totalMinutes'] as int? ?? 0;
  int? get hourlyRate => data['hourlyRate'] as int?;
  int? get totalSalary => data['totalSalary'] as int?;
  int get payableDays => data['payableDays'] as int? ?? 0;
  List<Map<String, dynamic>> get days => (data['days'] as List? ?? const [])
      .whereType<Map>()
      .map((day) => day.map((key, value) => MapEntry(key.toString(), value)))
      .toList();
}

class ReportExportResult {
  const ReportExportResult({
    required this.fileName,
    required this.bytes,
    required this.failures,
  });
  final String fileName;
  final Uint8List? bytes;
  final List<ReportSendResult> failures;
}

class ReportFileExporter {
  const ReportFileExporter();
  static const _channel = MethodChannel('smart_attendance/report_export');

  Future<bool> save(String fileName, Uint8List bytes) async =>
      await _channel.invokeMethod<bool>('saveFile', {
        'fileName': fileName,
        'bytes': bytes,
      }) ??
      false;
}

abstract class ReportDispatchRepository {
  Future<List<ReportRecipient>> listRecipients(UserProfile profile);
  Future<ReportEmployeeDetail> detail({
    required String employeeUid,
    required AttendancePeriodKind kind,
    required DateTime date,
  });
  Future<ReportPdf> preview({
    required String employeeUid,
    required AttendancePeriodKind kind,
    required DateTime date,
  });
  Future<List<ReportSendResult>> send({
    required List<ReportRecipient> recipients,
    required AttendancePeriodKind kind,
    required DateTime date,
    void Function(int done, int total)? onProgress,
  });
  Future<ReportExportResult> export({
    required List<ReportRecipient> recipients,
    required AttendancePeriodKind kind,
    required DateTime date,
    required void Function(int done, int total) onProgress,
  });
}

class FirebaseReportDispatchRepository implements ReportDispatchRepository {
  FirebaseReportDispatchRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _providedFirestore = firestore,
       _providedAuth = auth,
       _providedFunctions = functions;

  final FirebaseFirestore? _providedFirestore;
  final FirebaseAuth? _providedAuth;
  final FirebaseFunctions? _providedFunctions;
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;
  FirebaseFunctions get _functions =>
      _providedFunctions ?? FirebaseFunctions.instance;

  @override
  Future<List<ReportRecipient>> listRecipients(UserProfile profile) async {
    if (_auth.currentUser?.uid != profile.uid ||
        profile.role == UserRole.employee) {
      throw StateError('Không có quyền xem nhân viên.');
    }
    final caller = await _firestore
        .collection('users')
        .doc(profile.uid)
        .get(const GetOptions(source: Source.server));
    if (caller.data()?['status'] != 'active' ||
        caller.data()?['role'] != profile.role.name) {
      throw StateError('Không có quyền xem nhân viên.');
    }
    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'employee')
        .get(const GetOptions(source: Source.server));
    if (_auth.currentUser?.uid != profile.uid) {
      throw StateError('Phiên đăng nhập đã thay đổi.');
    }
    final recipients = <ReportRecipient>[];
    for (final document in snapshot.docs) {
      final data = document.data();
      if (data['status'] != 'active') continue;
      final managerUid = data['managerUid'];
      if (profile.role == UserRole.manager &&
          managerUid is String &&
          managerUid.isNotEmpty &&
          managerUid != profile.uid) {
        continue;
      }
      recipients.add(
        ReportRecipient(
          uid: document.id,
          name: _text(data['fullName']) ?? _text(data['name']) ?? document.id,
          code: _text(data['employeeCode']),
          email: _text(data['email']),
        ),
      );
    }
    recipients.sort((a, b) => a.name.compareTo(b.name));
    return recipients;
  }

  @override
  Future<ReportEmployeeDetail> detail({
    required String employeeUid,
    required AttendancePeriodKind kind,
    required DateTime date,
  }) async {
    final result = await _functions
        .httpsCallable('getEmployeeReport')
        .call<Map<Object?, Object?>>({
          'employeeId': employeeUid,
          'periodKind': kind.name,
          'anchorDate': _date(date),
        });
    return ReportEmployeeDetail(
      result.data.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  @override
  Future<ReportPdf> preview({
    required String employeeUid,
    required AttendancePeriodKind kind,
    required DateTime date,
  }) async {
    final result = await _functions
        .httpsCallable(
          'previewEmployeeReport',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 2)),
        )
        .call<Map<Object?, Object?>>({
          'employeeId': employeeUid,
          'periodKind': kind.name,
          'anchorDate': _date(date),
        });
    final data = result.data;
    final fileName = data['fileName'];
    final base64 = data['pdfBase64'];
    if (fileName is! String || base64 is! String) {
      throw const FormatException('PDF từ server không hợp lệ.');
    }
    return ReportPdf(fileName: fileName, bytes: base64Decode(base64));
  }

  @override
  Future<ReportExportResult> export({
    required List<ReportRecipient> recipients,
    required AttendancePeriodKind kind,
    required DateTime date,
    required void Function(int done, int total) onProgress,
  }) async {
    if (recipients.isEmpty) throw ArgumentError('Chưa chọn nhân viên.');
    final failures = <ReportSendResult>[];
    final archive = Archive();
    ReportPdf? singlePdf;
    for (var index = 0; index < recipients.length; index++) {
      final person = recipients[index];
      try {
        final pdf = await preview(
          employeeUid: person.uid,
          kind: kind,
          date: date,
        );
        singlePdf = pdf;
        final code = _safePart(person.code ?? person.uid);
        final name = _safePart(person.name);
        archive.addFile(
          ArchiveFile.bytes(
            '${code}_${name}_${_safePart(person.uid)}.pdf',
            pdf.bytes,
          ),
        );
      } catch (error) {
        failures.add(
          ReportSendResult(
            uid: person.uid,
            name: person.name,
            success: false,
            message:
                error is FirebaseFunctionsException &&
                    error.message?.isNotEmpty == true
                ? error.message!
                : 'Không tạo được PDF.',
          ),
        );
      }
      onProgress(index + 1, recipients.length);
    }
    if (archive.files.isEmpty) {
      return ReportExportResult(fileName: '', bytes: null, failures: failures);
    }
    if (recipients.length == 1 && singlePdf != null) {
      return ReportExportResult(
        fileName: singlePdf.fileName,
        bytes: singlePdf.bytes,
        failures: failures,
      );
    }
    final period = AttendanceStatisticsPeriod.containing(kind, date);
    final zipName = 'BaoCao_${period.startDate}_${period.endDate}.zip';
    return ReportExportResult(
      fileName: zipName,
      bytes: ZipEncoder().encodeBytes(archive),
      failures: failures,
    );
  }

  String _safePart(String value) {
    final cleaned = value.toLowerCase()
        .replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
        .replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e')
        .replaceAll(RegExp(r'[ìíịỉĩ]'), 'i')
        .replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
        .replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u')
        .replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y')
        .replaceAll('đ', 'd')
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.length > 50 ? cleaned.substring(0, 50) : cleaned;
  }

  @override
  Future<List<ReportSendResult>> send({
    required List<ReportRecipient> recipients,
    required AttendancePeriodKind kind,
    required DateTime date,
    void Function(int done, int total)? onProgress,
  }) async {
    final results = <ReportSendResult>[];
    for (var start = 0; start < recipients.length; start += 10) {
      final chunk = recipients.skip(start).take(10).toList();
      try {
        final response = await _functions
            .httpsCallable(
              'sendEmployeeReports',
              options: HttpsCallableOptions(
                timeout: const Duration(minutes: 9),
              ),
            )
            .call<Map<Object?, Object?>>({
              'employeeIds': chunk.map((recipient) => recipient.uid).toList(),
              'periodKind': kind.name,
              'anchorDate': _date(date),
            });
        final items = response.data['results'];
        if (items is! List) {
          throw const FormatException('Kết quả gửi không hợp lệ.');
        }
        final received = <String, ReportSendResult>{};
        for (final item in items) {
          if (item is! Map) continue;
          final uid = item['employeeId'];
          if (uid is! String) continue;
          received[uid] = ReportSendResult(
            uid: uid,
            name: item['name'] is String ? item['name'] as String : uid,
            success: item['success'] == true,
            message: item['message'] is String
                ? item['message'] as String
                : 'Không xác định được kết quả gửi.',
          );
        }
        for (final recipient in chunk) {
          results.add(
            received[recipient.uid] ??
                ReportSendResult(
                  uid: recipient.uid,
                  name: recipient.name,
                  success: false,
                  message: 'Không xác định được kết quả gửi.',
                ),
          );
        }
      } on FirebaseFunctionsException catch (error) {
        if (error.code == 'permission-denied' ||
            error.code == 'unauthenticated') {
          rethrow;
        }
        for (final recipient in chunk) {
          results.add(
            ReportSendResult(
              uid: recipient.uid,
              name: recipient.name,
              success: false,
              message: 'Không nhận được kết quả từ server. Kiểm tra hộp thư trước khi thử lại.',
            ),
          );
        }
      } catch (_) {
        for (final recipient in chunk) {
          results.add(
            ReportSendResult(
              uid: recipient.uid,
              name: recipient.name,
              success: false,
              message: 'Không nhận được kết quả từ server. Kiểm tra hộp thư trước khi thử lại.',
            ),
          );
        }
      }
      onProgress?.call(results.length, recipients.length);
    }
    return results;
  }

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
