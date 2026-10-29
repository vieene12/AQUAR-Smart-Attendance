import 'package:smart_attendance/features/admin/accounts/data/account_api_client.dart';

abstract interface class AccountCreationRepositoryContract {
  Future<String> createAccount({
    required String fullName,
    required String email,
    required String password,
    required String role,
    required int hourlyRate,
  });
}

class AccountCreationRepository implements AccountCreationRepositoryContract {
  AccountCreationRepository({AccountApiClient? apiClient})
    : _apiClient = apiClient ?? AccountApiClient();

  final AccountApiClient _apiClient;

  @override
  Future<String> createAccount({
    required String fullName,
    required String email,
    required String password,
    required String role,
    required int hourlyRate,
  }) async {
    final account = await _apiClient.createAccount(
      fullName: fullName,
      email: email,
      password: password,
      role: role,
      hourlyRate: hourlyRate,
    );
    return account.uid;
  }
}
