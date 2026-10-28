import 'package:smart_attendance/features/admin/accounts/data/account_api_client.dart';
import 'package:smart_attendance/features/admin/accounts/domain/account_record.dart';

abstract interface class AccountRepositoryContract {
  Future<List<AccountRecord>> getAccounts();

  Future<void> updateAccount({
    required String uid,
    required String fullName,
    required int hourlyRate,
  });

  Future<void> setAccountLocked({required String uid, required bool locked});
}

class AccountRepository implements AccountRepositoryContract {
  AccountRepository({AccountApiClient? apiClient})
    : _apiClient = apiClient ?? AccountApiClient();

  final AccountApiClient _apiClient;

  @override
  Future<List<AccountRecord>> getAccounts() async {
    final accounts = <String, AccountRecord>{};
    final observedTokens = <String>{};
    String? pageToken;
    do {
      final page = await _apiClient.getAccounts(
        pageSize: 100,
        pageToken: pageToken,
      );
      for (final account in page.items) {
        accounts[account.uid] = account;
      }
      pageToken = page.nextPageToken;
      if (pageToken != null && !observedTokens.add(pageToken)) {
        throw const AccountApiException(AccountApiFailure.invalidResponse);
      }
    } while (pageToken != null);
    return accounts.values.toList(growable: false);
  }

  @override
  Future<void> updateAccount({
    required String uid,
    required String fullName,
    required int hourlyRate,
  }) async {
    await _apiClient.updateAccount(
      uid: uid,
      fullName: fullName,
      hourlyRate: hourlyRate,
    );
  }

  @override
  Future<void> setAccountLocked({
    required String uid,
    required bool locked,
  }) async {
    await _apiClient.changeStatus(
      uid: uid,
      status: locked ? 'locked' : 'active',
    );
  }
}
