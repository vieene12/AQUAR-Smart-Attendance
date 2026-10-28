import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:smart_attendance/core/network/api_configuration.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_api_client.dart';

enum ReportEmailApiFailure {
  configuration,
  invalidRequest,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  tooLarge,
  unprocessable,
  rateLimited,
  unavailable,
  network,
  invalidResponse,
}

class ReportEmailApiException implements Exception {
  const ReportEmailApiException(this.failure, {this.statusCode});

  final ReportEmailApiFailure failure;
  final int? statusCode;

  bool get outcomeMayBeUnknown =>
      failure == ReportEmailApiFailure.conflict ||
      failure == ReportEmailApiFailure.unavailable ||
      failure == ReportEmailApiFailure.network ||
      failure == ReportEmailApiFailure.invalidResponse;

  String get userMessage => switch (failure) {
    ReportEmailApiFailure.configuration =>
      'Chưa cấu hình địa chỉ Backend API. Vui lòng kiểm tra API_BASE_URL.',
    ReportEmailApiFailure.invalidRequest =>
      'Kỳ báo cáo hoặc ngày được chọn không hợp lệ.',
    ReportEmailApiFailure.unauthorized =>
      'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
    ReportEmailApiFailure.forbidden =>
      'Bạn không có quyền gửi báo cáo qua email.',
    ReportEmailApiFailure.notFound =>
      'Không tìm thấy nhân viên đang hoạt động để gửi báo cáo.',
    ReportEmailApiFailure.conflict =>
      'Yêu cầu đang được xử lý hoặc chưa xác định kết quả.',
    ReportEmailApiFailure.tooLarge =>
      'Báo cáo PDF vượt quá giới hạn dung lượng.',
    ReportEmailApiFailure.unprocessable =>
      'Email đăng ký hoặc dữ liệu báo cáo của nhân viên không hợp lệ.',
    ReportEmailApiFailure.rateLimited =>
      'Đã gửi quá nhiều yêu cầu. Vui lòng chờ trước khi thử lại.',
    ReportEmailApiFailure.unavailable =>
      'Dịch vụ gửi email tạm thời không khả dụng.',
    ReportEmailApiFailure.network => 'Không thể kết nối Backend API.',
    ReportEmailApiFailure.invalidResponse =>
      'Backend trả về dữ liệu không hợp lệ.',
  };
}

class ReportEmailAccepted {
  const ReportEmailAccepted({
    required this.requestId,
    required this.employeeUid,
    required this.periodKind,
    required this.startDate,
    required this.endDate,
    required this.maskedRecipient,
    required this.acceptedAtUtc,
  });

  final String requestId;
  final String employeeUid;
  final String periodKind;
  final String startDate;
  final String endDate;
  final String maskedRecipient;
  final DateTime acceptedAtUtc;

  factory ReportEmailAccepted.fromJson(Map<String, dynamic> json) {
    if (json['status'] != 'accepted' ||
        json['requestId'] is! String ||
        json['employeeUid'] is! String ||
        json['periodKind'] is! String ||
        json['startDate'] is! String ||
        json['endDate'] is! String ||
        json['maskedRecipient'] is! String ||
        json['acceptedAtUtc'] is! String) {
      throw const FormatException();
    }
    final acceptedAt = DateTime.tryParse(json['acceptedAtUtc'] as String);
    if (acceptedAt == null) throw const FormatException();
    return ReportEmailAccepted(
      requestId: json['requestId'] as String,
      employeeUid: json['employeeUid'] as String,
      periodKind: json['periodKind'] as String,
      startDate: json['startDate'] as String,
      endDate: json['endDate'] as String,
      maskedRecipient: json['maskedRecipient'] as String,
      acceptedAtUtc: acceptedAt,
    );
  }
}

class ReportEmailHttpResponse {
  const ReportEmailHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

abstract interface class ReportEmailHttpTransport {
  Future<ReportEmailHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  });
}

class IoReportEmailHttpTransport implements ReportEmailHttpTransport {
  const IoReportEmailHttpTransport({
    this.timeout = const Duration(seconds: 90),
    this.connectionTimeout = const Duration(seconds: 15),
  });

  final Duration timeout;
  final Duration connectionTimeout;

  @override
  Future<ReportEmailHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = connectionTimeout;
    try {
      return await (() async {
        final request = await client.postUrl(uri);
        headers.forEach(request.headers.set);
        request.add(utf8.encode(body));
        final response = await request.close();
        final responseBody = await utf8.decoder.bind(response).join();
        return ReportEmailHttpResponse(
          statusCode: response.statusCode,
          body: responseBody,
        );
      })().timeout(timeout);
    } on SocketException {
      throw const ReportEmailApiException(ReportEmailApiFailure.network);
    } on TimeoutException {
      throw const ReportEmailApiException(ReportEmailApiFailure.network);
    } on HttpException {
      throw const ReportEmailApiException(ReportEmailApiFailure.network);
    } finally {
      client.close(force: true);
    }
  }
}

abstract interface class ReportIdempotencyKeyGenerator {
  String generate();
}

class SecureUuidV4Generator implements ReportIdempotencyKeyGenerator {
  SecureUuidV4Generator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  @override
  String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

class ReportEmailApiClient {
  ReportEmailApiClient({
    FirebaseIdTokenProvider? tokenProvider,
    ReportEmailHttpTransport? transport,
    this.baseUrl,
  }) : _providedTokenProvider = tokenProvider,
       _transport = transport ?? const IoReportEmailHttpTransport();

  final FirebaseIdTokenProvider? _providedTokenProvider;
  final ReportEmailHttpTransport _transport;
  final String? baseUrl;
  late final FirebaseIdTokenProvider _tokenProvider =
      _providedTokenProvider ?? CurrentFirebaseIdTokenProvider();

  Future<ReportEmailAccepted> send({
    required String employeeUid,
    required String periodKind,
    required String anchorDate,
    required String idempotencyKey,
  }) async {
    final base = _baseUri();
    final root = base.toString().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      '$root/api/employees/${Uri.encodeComponent(employeeUid)}/attendance-reports/email',
    );
    late final String token;
    try {
      token = await _tokenProvider.getIdToken();
    } on AccountApiException catch (error) {
      throw ReportEmailApiException(
        error.failure == AccountApiFailure.network
            ? ReportEmailApiFailure.network
            : ReportEmailApiFailure.unauthorized,
      );
    }
    final response = await _transport.post(
      uri: uri,
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $token',
        HttpHeaders.acceptHeader: ContentType.json.mimeType,
        HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
        'Idempotency-Key': idempotencyKey,
      },
      body: jsonEncode({'periodKind': periodKind, 'anchorDate': anchorDate}),
    );
    if (response.statusCode != HttpStatus.accepted) {
      throw ReportEmailApiException(
        _failureForStatus(response.statusCode),
        statusCode: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return ReportEmailAccepted.fromJson(decoded);
    } on FormatException {
      throw const ReportEmailApiException(
        ReportEmailApiFailure.invalidResponse,
      );
    }
  }

  Uri _baseUri() {
    try {
      return ApiConfiguration.requireBaseUri(baseUrl);
    } on ApiConfigurationException {
      throw const ReportEmailApiException(ReportEmailApiFailure.configuration);
    }
  }

  static ReportEmailApiFailure _failureForStatus(int statusCode) =>
      switch (statusCode) {
        400 => ReportEmailApiFailure.invalidRequest,
        401 => ReportEmailApiFailure.unauthorized,
        403 => ReportEmailApiFailure.forbidden,
        404 => ReportEmailApiFailure.notFound,
        409 => ReportEmailApiFailure.conflict,
        413 => ReportEmailApiFailure.tooLarge,
        422 => ReportEmailApiFailure.unprocessable,
        429 => ReportEmailApiFailure.rateLimited,
        503 => ReportEmailApiFailure.unavailable,
        _ => ReportEmailApiFailure.invalidResponse,
      };
}
