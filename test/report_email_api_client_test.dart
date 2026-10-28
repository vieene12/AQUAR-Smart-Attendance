import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_api_client.dart';
import 'package:smart_attendance/features/statistics/data/report_email_api_client.dart';
import 'package:smart_attendance/features/statistics/data/report_email_repository.dart';

void main() {
  test('F04 dùng deadline tổng 90 giây và connect timeout 15 giây', () {
    const transport = IoReportEmailHttpTransport();

    expect(transport.timeout, const Duration(seconds: 90));
    expect(transport.connectionTimeout, const Duration(seconds: 15));
  });

  test('POST gửi Bearer, UUID và chỉ hai field body được phép', () async {
    final transport = _FakeTransport(_acceptedResponse());
    final client = ReportEmailApiClient(
      tokenProvider: _FakeTokenProvider(),
      transport: transport,
      baseUrl: 'https://api.example.test',
    );

    final result = await client.send(
      employeeUid: 'employee/one',
      periodKind: 'month',
      anchorDate: '2026-10-01',
      idempotencyKey: '11111111-1111-4111-8111-111111111111',
    );

    expect(result.maskedRecipient, 'e***@example.test');
    expect(transport.uri.pathSegments, [
      'api',
      'employees',
      'employee/one',
      'attendance-reports',
      'email',
    ]);
    expect(transport.headers['authorization'], 'Bearer firebase-id-token');
    expect(
      transport.headers['Idempotency-Key'],
      '11111111-1111-4111-8111-111111111111',
    );
    expect(jsonDecode(transport.body), {
      'periodKind': 'month',
      'anchorDate': '2026-10-01',
    });
    expect(transport.body, isNot(contains('email')));
    expect(transport.body, isNot(contains('pdf')));
    expect(transport.body, isNot(contains('role')));
  });

  test('UUID generator tạo UUID v4 đúng version và variant', () {
    final generator = SecureUuidV4Generator();
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );

    final values = List.generate(20, (_) => generator.generate());

    expect(values.toSet(), hasLength(values.length));
    expect(values, everyElement(matches(pattern)));
  });

  test('HTTP transport timeout không gọi dịch vụ bên ngoài', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final response =
          const IoReportEmailHttpTransport(
            timeout: Duration(milliseconds: 50),
          ).post(
            uri: Uri.parse('http://127.0.0.1:${server.port}/f04'),
            headers: {HttpHeaders.contentTypeHeader: ContentType.json.mimeType},
            body: '{}',
          );
      final request = await server.first;

      await expectLater(
        response,
        throwsA(
          isA<ReportEmailApiException>().having(
            (error) => error.failure,
            'failure',
            ReportEmailApiFailure.network,
          ),
        ),
      );
      await request.response.close();
    } finally {
      await server.close(force: true);
    }
  });

  test('API_BASE_URL thiếu bị chặn trước HTTP request', () async {
    final transport = _FakeTransport(_acceptedResponse());
    final client = ReportEmailApiClient(
      tokenProvider: _FakeTokenProvider(),
      transport: transport,
      baseUrl: '',
    );

    await expectLater(
      client.send(
        employeeUid: 'employee',
        periodKind: 'week',
        anchorDate: '2026-10-01',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
      ),
      throwsA(
        isA<ReportEmailApiException>().having(
          (error) => error.failure,
          'failure',
          ReportEmailApiFailure.configuration,
        ),
      ),
    );
    expect(transport.calls, 0);
  });

  test('ánh xạ đầy đủ status code F04', () async {
    const cases = {
      400: ReportEmailApiFailure.invalidRequest,
      401: ReportEmailApiFailure.unauthorized,
      403: ReportEmailApiFailure.forbidden,
      404: ReportEmailApiFailure.notFound,
      409: ReportEmailApiFailure.conflict,
      413: ReportEmailApiFailure.tooLarge,
      422: ReportEmailApiFailure.unprocessable,
      429: ReportEmailApiFailure.rateLimited,
      503: ReportEmailApiFailure.unavailable,
    };
    for (final entry in cases.entries) {
      final client = ReportEmailApiClient(
        tokenProvider: _FakeTokenProvider(),
        transport: _FakeTransport(
          ReportEmailHttpResponse(statusCode: entry.key, body: '{}'),
        ),
        baseUrl: 'https://api.example.test',
      );

      await expectLater(
        client.send(
          employeeUid: 'employee',
          periodKind: 'week',
          anchorDate: '2026-10-01',
          idempotencyKey: '11111111-1111-4111-8111-111111111111',
        ),
        throwsA(
          isA<ReportEmailApiException>().having(
            (error) => error.failure,
            'failure',
            entry.value,
          ),
        ),
      );
    }
  });

  test('lỗi Firebase token được ánh xạ thành 401 hoặc network', () async {
    for (final entry in const {
      AccountApiFailure.unauthorized: ReportEmailApiFailure.unauthorized,
      AccountApiFailure.network: ReportEmailApiFailure.network,
    }.entries) {
      final client = ReportEmailApiClient(
        tokenProvider: _FailingTokenProvider(entry.key),
        transport: _FakeTransport(_acceptedResponse()),
        baseUrl: 'https://api.example.test',
      );

      await expectLater(
        client.send(
          employeeUid: 'employee',
          periodKind: 'week',
          anchorDate: '2026-10-01',
          idempotencyKey: '11111111-1111-4111-8111-111111111111',
        ),
        throwsA(
          isA<ReportEmailApiException>().having(
            (error) => error.failure,
            'failure',
            entry.value,
          ),
        ),
      );
    }
  });

  test('repository gộp double tap thành một HTTP request', () async {
    final transport = _FakeTransport(_acceptedResponse())
      ..pending = Completer<ReportEmailHttpResponse>();
    final repository = ReportEmailRepository(
      apiClient: ReportEmailApiClient(
        tokenProvider: _FakeTokenProvider(),
        transport: transport,
        baseUrl: 'https://api.example.test',
      ),
      keyGenerator: _FixedKeyGenerator(),
    );

    final first = repository.sendReport(
      employeeUid: 'employee',
      periodKind: 'month',
      anchorDate: '2026-10-01',
    );
    final second = repository.sendReport(
      employeeUid: 'employee',
      periodKind: 'month',
      anchorDate: '2026-10-01',
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.calls, 1);
    transport.pending!.complete(_acceptedResponse());

    expect((await first).requestId, (await second).requestId);
    expect(transport.calls, 1);
  });

  for (final status in [409, 503]) {
    test('HTTP $status giữ nguyên key và không tự gửi lại', () async {
      final transport = _FakeTransport(
        ReportEmailHttpResponse(statusCode: status, body: '{}'),
      );
      final repository = ReportEmailRepository(
        apiClient: ReportEmailApiClient(
          tokenProvider: _FakeTokenProvider(),
          transport: transport,
          baseUrl: 'https://api.example.test',
        ),
        keyGenerator: _FixedKeyGenerator(),
      );

      Future<ReportEmailAccepted> send() => repository.sendReport(
        employeeUid: 'employee',
        periodKind: 'month',
        anchorDate: '2026-10-01',
      );
      await expectLater(send(), throwsA(isA<ReportEmailUncertainException>()));
      await expectLater(send(), throwsA(isA<ReportEmailUncertainException>()));

      expect(transport.calls, 1);
    });
  }

  test('timeout/network được coi là kết quả không rõ và không retry', () async {
    final transport = _FakeTransport(_acceptedResponse())
      ..failure = const ReportEmailApiException(ReportEmailApiFailure.network);
    final repository = ReportEmailRepository(
      apiClient: ReportEmailApiClient(
        tokenProvider: _FakeTokenProvider(),
        transport: transport,
        baseUrl: 'https://api.example.test',
      ),
      keyGenerator: _FixedKeyGenerator(),
    );

    Future<ReportEmailAccepted> send() => repository.sendReport(
      employeeUid: 'employee',
      periodKind: 'week',
      anchorDate: '2026-10-01',
    );
    await expectLater(send(), throwsA(isA<ReportEmailUncertainException>()));
    await expectLater(send(), throwsA(isA<ReportEmailUncertainException>()));

    expect(transport.calls, 1);
  });
}

ReportEmailHttpResponse _acceptedResponse() => ReportEmailHttpResponse(
  statusCode: 202,
  body: jsonEncode({
    'requestId': 'request-id',
    'status': 'accepted',
    'employeeUid': 'employee',
    'periodKind': 'month',
    'startDate': '2026-10-01',
    'endDate': '2026-10-31',
    'maskedRecipient': 'e***@example.test',
    'acceptedAtUtc': '2026-10-28T08:00:00Z',
  }),
);

class _FakeTokenProvider implements FirebaseIdTokenProvider {
  @override
  Future<String> getIdToken() async => 'firebase-id-token';
}

class _FailingTokenProvider implements FirebaseIdTokenProvider {
  const _FailingTokenProvider(this.failure);

  final AccountApiFailure failure;

  @override
  Future<String> getIdToken() => Future.error(AccountApiException(failure));
}

class _FixedKeyGenerator implements ReportIdempotencyKeyGenerator {
  @override
  String generate() => '11111111-1111-4111-8111-111111111111';
}

class _FakeTransport implements ReportEmailHttpTransport {
  _FakeTransport(this.response);

  final ReportEmailHttpResponse response;
  int calls = 0;
  late Uri uri;
  Map<String, String> headers = {};
  String body = '';
  Object? failure;
  Completer<ReportEmailHttpResponse>? pending;

  @override
  Future<ReportEmailHttpResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) async {
    calls++;
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    if (failure != null) throw failure!;
    return pending?.future ?? response;
  }
}
