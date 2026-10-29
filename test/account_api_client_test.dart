import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_api_client.dart';
import 'package:smart_attendance/features/admin/accounts/data/account_repository.dart';

void main() {
  test(
    'GET gửi Firebase Bearer token và ánh xạ Admin legacy nullable',
    () async {
      final transport = _FakeTransport([
        _jsonResponse(200, {
          'items': [
            {
              'uid': 'admin-1',
              'fullName': 'Quản trị viên',
              'email': null,
              'role': 'admin',
              'status': 'active',
              'hourlyRate': null,
            },
          ],
          'nextPageToken': null,
        }),
      ]);
      final client = _client(transport);

      final page = await client.getAccounts(pageSize: 100);

      expect(page.items.single.role, 'admin');
      expect(page.items.single.hourlyRate, isNull);
      expect(transport.requests.single.method, 'GET');
      expect(
        transport.requests.single.headers['authorization'],
        'Bearer firebase-id-token',
      );
      expect(transport.requests.single.uri.queryParameters['pageSize'], '100');
    },
  );

  test('POST gửi đúng contract và không làm thay đổi token provider', () async {
    final tokenProvider = _FakeTokenProvider();
    final transport = _FakeTransport([
      _accountResponse(201, uid: 'employee-1'),
    ]);
    final client = AccountApiClient(
      tokenProvider: tokenProvider,
      transport: transport,
      baseUrl: 'https://api.example.test',
    );

    final created = await client.createAccount(
      fullName: 'Nguyễn A',
      email: 'a@example.com',
      password: 'secret123',
      role: 'employee',
      hourlyRate: 50000,
    );

    expect(created.uid, 'employee-1');
    expect(tokenProvider.calls, 1);
    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '/api/accounts');
    expect(jsonDecode(request.body!), {
      'fullName': 'Nguyễn A',
      'email': 'a@example.com',
      'password': 'secret123',
      'role': 'employee',
      'hourlyRate': 50000,
    });
  });

  test('PUT và PATCH dùng UID encode, không gửi role hoặc email', () async {
    final transport = _FakeTransport([
      _accountResponse(200, uid: 'uid/one'),
      _accountResponse(200, uid: 'uid/one', status: 'locked'),
    ]);
    final client = _client(transport);

    await client.updateAccount(
      uid: 'uid/one',
      fullName: 'Tên mới',
      hourlyRate: 60000,
    );
    await client.changeStatus(uid: 'uid/one', status: 'locked');

    expect(transport.requests[0].method, 'PUT');
    expect(jsonDecode(transport.requests[0].body!), {
      'fullName': 'Tên mới',
      'hourlyRate': 60000,
    });
    expect(transport.requests[1].method, 'PATCH');
    expect(jsonDecode(transport.requests[1].body!), {'status': 'locked'});
  });

  test('repository tải hết các trang và không bỏ sót role', () async {
    final transport = _FakeTransport([
      _jsonResponse(200, {
        'items': [
          _accountJson('admin-1', 'admin'),
          _accountJson('manager-1', 'manager'),
        ],
        'nextPageToken': 'page-2',
      }),
      _jsonResponse(200, {
        'items': [_accountJson('employee-1', 'employee')],
        'nextPageToken': null,
      }),
    ]);
    final repository = AccountRepository(apiClient: _client(transport));

    final accounts = await repository.getAccounts();

    expect(accounts.map((item) => item.role).toSet(), {
      'admin',
      'manager',
      'employee',
    });
    expect(transport.requests[1].uri.queryParameters['pageToken'], 'page-2');
  });

  test('HTTP transport sends Vietnamese JSON as UTF-8', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final responseFuture = const IoAccountHttpTransport().send(
        method: 'POST',
        uri: Uri.parse('http://127.0.0.1:${server.port}/api/accounts'),
        headers: {HttpHeaders.contentTypeHeader: ContentType.json.mimeType},
        body: jsonEncode({'fullName': 'Nhân viên E2E'}),
      );
      final request = await server.first;
      final bytes = await request.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      );
      final decodedBody = utf8.decode(bytes);
      request.response
        ..statusCode = HttpStatus.ok
        ..write('{}');
      await request.response.close();

      final response = await responseFuture;

      expect(response.statusCode, HttpStatus.ok);
      expect(jsonDecode(decodedBody), {'fullName': 'Nhân viên E2E'});
    } finally {
      await server.close(force: true);
    }
  });

  for (final entry in {
    400: AccountApiFailure.invalidRequest,
    401: AccountApiFailure.unauthorized,
    403: AccountApiFailure.forbidden,
    404: AccountApiFailure.notFound,
    409: AccountApiFailure.conflict,
    503: AccountApiFailure.unavailable,
  }.entries) {
    test('HTTP ${entry.key} được ánh xạ đúng', () async {
      final client = _client(
        _FakeTransport([const AccountHttpResponse(statusCode: 0, body: '')])
          ..responses[0] = AccountHttpResponse(
            statusCode: entry.key,
            body: '{}',
          ),
      );

      await expectLater(
        client.getAccounts(),
        throwsA(
          isA<AccountApiException>().having(
            (error) => error.failure,
            'failure',
            entry.value,
          ),
        ),
      );
    });
  }

  test('lỗi mạng không fallback sang Firebase trực tiếp', () async {
    final client = AccountApiClient(
      tokenProvider: _FakeTokenProvider(),
      transport: const _NetworkFailureTransport(),
      baseUrl: 'https://api.example.test',
    );

    await expectLater(
      client.getAccounts(),
      throwsA(
        isA<AccountApiException>().having(
          (error) => error.failure,
          'failure',
          AccountApiFailure.network,
        ),
      ),
    );
  });

  test('API_BASE_URL thiếu hoặc sai bị từ chối trước request', () async {
    final missing = AccountApiClient(
      tokenProvider: _FakeTokenProvider(),
      transport: _FakeTransport([]),
      baseUrl: '',
    );
    final invalid = AccountApiClient(
      tokenProvider: _FakeTokenProvider(),
      transport: _FakeTransport([]),
      baseUrl: 'localhost:8080',
    );
    final matcher = throwsA(
      isA<AccountApiException>().having(
        (error) => error.failure,
        'failure',
        AccountApiFailure.configuration,
      ),
    );
    await expectLater(missing.getAccounts(), matcher);
    await expectLater(invalid.getAccounts(), matcher);
  });
}

AccountApiClient _client(_FakeTransport transport) => AccountApiClient(
  tokenProvider: _FakeTokenProvider(),
  transport: transport,
  baseUrl: 'https://api.example.test',
);

AccountHttpResponse _jsonResponse(int statusCode, Object body) =>
    AccountHttpResponse(statusCode: statusCode, body: jsonEncode(body));

AccountHttpResponse _accountResponse(
  int statusCode, {
  required String uid,
  String status = 'active',
}) => _jsonResponse(statusCode, {
  'uid': uid,
  'fullName': 'Nguyễn A',
  'email': 'a@example.com',
  'role': 'employee',
  'status': status,
  'hourlyRate': 50000,
});

Map<String, Object?> _accountJson(String uid, String role) => {
  'uid': uid,
  'fullName': 'Tên $uid',
  'email': role == 'admin' ? null : '$uid@example.com',
  'role': role,
  'status': 'active',
  'hourlyRate': role == 'admin' ? null : 50000,
};

class _FakeTokenProvider implements FirebaseIdTokenProvider {
  int calls = 0;

  @override
  Future<String> getIdToken() async {
    calls++;
    return 'firebase-id-token';
  }
}

class _CapturedRequest {
  const _CapturedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    required this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

class _FakeTransport implements AccountHttpTransport {
  _FakeTransport(this.responses);

  final List<AccountHttpResponse> responses;
  final List<_CapturedRequest> requests = [];

  @override
  Future<AccountHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) async {
    requests.add(
      _CapturedRequest(
        method: method,
        uri: uri,
        headers: Map.of(headers),
        body: body,
      ),
    );
    return responses.removeAt(0);
  }
}

class _NetworkFailureTransport implements AccountHttpTransport {
  const _NetworkFailureTransport();

  @override
  Future<AccountHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) {
    throw const AccountApiException(AccountApiFailure.network);
  }
}
