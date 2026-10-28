import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_attendance/core/network/api_configuration.dart';
import 'package:smart_attendance/features/admin/accounts/domain/account_record.dart';

enum AccountApiFailure {
  configuration,
  invalidRequest,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  unavailable,
  network,
  invalidResponse,
}

enum AccountApiOperation { list, create, update, changeStatus }

class AccountApiException implements Exception {
  const AccountApiException(this.failure, {this.statusCode});

  final AccountApiFailure failure;
  final int? statusCode;

  String messageFor(AccountApiOperation operation) {
    return switch (failure) {
      AccountApiFailure.configuration =>
        'Chưa cấu hình địa chỉ Backend API. Vui lòng kiểm tra API_BASE_URL.',
      AccountApiFailure.invalidRequest => switch (operation) {
        AccountApiOperation.create =>
          'Thông tin tài khoản không hợp lệ. Vui lòng kiểm tra lại.',
        AccountApiOperation.update =>
          'Thông tin cập nhật không hợp lệ. Vui lòng kiểm tra lại.',
        AccountApiOperation.changeStatus =>
          'Trạng thái tài khoản không hợp lệ.',
        AccountApiOperation.list => 'Yêu cầu tải danh sách không hợp lệ.',
      },
      AccountApiFailure.unauthorized =>
        'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
      AccountApiFailure.forbidden => switch (operation) {
        AccountApiOperation.list =>
          'Bạn không có quyền xem danh sách tài khoản.',
        AccountApiOperation.create => 'Bạn không có quyền tạo tài khoản.',
        AccountApiOperation.update =>
          'Bạn không có quyền cập nhật tài khoản này.',
        AccountApiOperation.changeStatus =>
          'Bạn không có quyền đổi trạng thái tài khoản này.',
      },
      AccountApiFailure.notFound => 'Tài khoản không còn tồn tại.',
      AccountApiFailure.conflict => switch (operation) {
        AccountApiOperation.create =>
          'Email đã được sử dụng hoặc tài khoản đã tồn tại.',
        _ => 'Dữ liệu Authentication và hồ sơ tài khoản không đồng nhất. Vui lòng kiểm tra lại.',
      },
      AccountApiFailure.unavailable =>
        'Backend hoặc Firebase tạm thời không khả dụng. Vui lòng thử lại.',
      AccountApiFailure.network =>
        'Không thể kết nối Backend API. Vui lòng kiểm tra mạng và thử lại.',
      AccountApiFailure.invalidResponse =>
        'Backend trả về dữ liệu không hợp lệ. Vui lòng thử lại.',
    };
  }
}

abstract interface class FirebaseIdTokenProvider {
  Future<String> getIdToken();
}

class CurrentFirebaseIdTokenProvider implements FirebaseIdTokenProvider {
  CurrentFirebaseIdTokenProvider({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Future<String> getIdToken() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AccountApiException(AccountApiFailure.unauthorized);
    }

    try {
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) {
        throw const AccountApiException(AccountApiFailure.unauthorized);
      }
      return token;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'network-request-failed') {
        throw const AccountApiException(AccountApiFailure.network);
      }
      throw const AccountApiException(AccountApiFailure.unauthorized);
    }
  }
}

class AccountHttpResponse {
  const AccountHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

abstract interface class AccountHttpTransport {
  Future<AccountHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  });
}

class IoAccountHttpTransport implements AccountHttpTransport {
  const IoAccountHttpTransport({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  @override
  Future<AccountHttpResponse> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      headers.forEach(request.headers.set);
      if (body != null) request.add(utf8.encode(body));
      final response = await request.close().timeout(timeout);
      final responseBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(timeout);
      return AccountHttpResponse(
        statusCode: response.statusCode,
        body: responseBody,
      );
    } on SocketException {
      throw const AccountApiException(AccountApiFailure.network);
    } on TimeoutException {
      throw const AccountApiException(AccountApiFailure.network);
    } on HttpException {
      throw const AccountApiException(AccountApiFailure.network);
    } finally {
      client.close(force: true);
    }
  }
}

class AccountPage {
  const AccountPage({required this.items, required this.nextPageToken});

  final List<AccountRecord> items;
  final String? nextPageToken;
}

class AccountApiClient {
  AccountApiClient({
    FirebaseIdTokenProvider? tokenProvider,
    AccountHttpTransport? transport,
    this.baseUrl,
  }) : _tokenProvider = tokenProvider ?? CurrentFirebaseIdTokenProvider(),
       _transport = transport ?? const IoAccountHttpTransport();

  final FirebaseIdTokenProvider _tokenProvider;
  final AccountHttpTransport _transport;
  final String? baseUrl;

  Future<AccountPage> getAccounts({
    int pageSize = 100,
    String? pageToken,
  }) async {
    final query = <String, String>{'pageSize': pageSize.toString()};
    if (pageToken != null) query['pageToken'] = pageToken;
    final json = await _send(
      method: 'GET',
      path: '/api/accounts',
      queryParameters: query,
      expectedStatus: 200,
    );
    if (json is! Map<String, dynamic> || json['items'] is! List) {
      throw const AccountApiException(AccountApiFailure.invalidResponse);
    }

    try {
      final items = (json['items'] as List<Object?>)
          .map((item) {
            if (item is! Map<String, dynamic>) throw const FormatException();
            return AccountRecord.fromApi(item);
          })
          .toList(growable: false);
      final nextPageToken = json['nextPageToken'];
      if (nextPageToken != null && nextPageToken is! String) {
        throw const FormatException();
      }
      return AccountPage(items: items, nextPageToken: nextPageToken as String?);
    } on FormatException {
      throw const AccountApiException(AccountApiFailure.invalidResponse);
    }
  }

  Future<AccountRecord> createAccount({
    required String fullName,
    required String email,
    required String password,
    required String role,
    required int hourlyRate,
  }) async {
    final json = await _send(
      method: 'POST',
      path: '/api/accounts',
      expectedStatus: 201,
      body: {
        'fullName': fullName,
        'email': email,
        'password': password,
        'role': role,
        'hourlyRate': hourlyRate,
      },
    );
    return _accountFromResponse(json);
  }

  Future<AccountRecord> updateAccount({
    required String uid,
    required String fullName,
    required int hourlyRate,
  }) async {
    final json = await _send(
      method: 'PUT',
      path: '/api/accounts/${Uri.encodeComponent(uid)}',
      expectedStatus: 200,
      body: {'fullName': fullName, 'hourlyRate': hourlyRate},
    );
    return _accountFromResponse(json);
  }

  Future<AccountRecord> changeStatus({
    required String uid,
    required String status,
  }) async {
    final json = await _send(
      method: 'PATCH',
      path: '/api/accounts/${Uri.encodeComponent(uid)}/status',
      expectedStatus: 200,
      body: {'status': status},
    );
    return _accountFromResponse(json);
  }

  Future<Object?> _send({
    required String method,
    required String path,
    required int expectedStatus,
    Map<String, String>? queryParameters,
    Map<String, Object>? body,
  }) async {
    final uri = _uri(path, queryParameters);
    final token = await _tokenProvider.getIdToken();
    final response = await _transport.send(
      method: method,
      uri: uri,
      headers: {
        HttpHeaders.authorizationHeader: 'Bearer $token',
        HttpHeaders.acceptHeader: ContentType.json.mimeType,
        if (body != null)
          HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
      },
      body: body == null ? null : jsonEncode(body),
    );
    if (response.statusCode != expectedStatus) {
      throw AccountApiException(
        _failureForStatus(response.statusCode),
        statusCode: response.statusCode,
      );
    }
    if (response.body.isEmpty) {
      throw const AccountApiException(AccountApiFailure.invalidResponse);
    }
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const AccountApiException(AccountApiFailure.invalidResponse);
    }
  }

  Uri _uri(String path, Map<String, String>? queryParameters) {
    late final Uri baseUri;
    try {
      baseUri = ApiConfiguration.requireBaseUri(baseUrl);
    } on ApiConfigurationException {
      throw const AccountApiException(AccountApiFailure.configuration);
    }
    final root = baseUri.toString().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$root$path').replace(queryParameters: queryParameters);
  }

  static AccountRecord _accountFromResponse(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const AccountApiException(AccountApiFailure.invalidResponse);
    }
    try {
      return AccountRecord.fromApi(json);
    } on FormatException {
      throw const AccountApiException(AccountApiFailure.invalidResponse);
    }
  }

  static AccountApiFailure _failureForStatus(int statusCode) =>
      switch (statusCode) {
        400 => AccountApiFailure.invalidRequest,
        401 => AccountApiFailure.unauthorized,
        403 => AccountApiFailure.forbidden,
        404 => AccountApiFailure.notFound,
        409 => AccountApiFailure.conflict,
        503 => AccountApiFailure.unavailable,
        _ => AccountApiFailure.invalidResponse,
      };
}
