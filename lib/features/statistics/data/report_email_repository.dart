import 'package:smart_attendance/features/statistics/data/report_email_api_client.dart';

class ReportEmailUncertainException implements Exception {
  const ReportEmailUncertainException(this.cause);

  final ReportEmailApiException cause;
}

abstract interface class ReportEmailRepositoryContract {
  Future<ReportEmailAccepted> sendReport({
    required String employeeUid,
    required String periodKind,
    required String anchorDate,
  });
}

class ReportEmailRepository implements ReportEmailRepositoryContract {
  ReportEmailRepository({
    ReportEmailApiClient? apiClient,
    ReportIdempotencyKeyGenerator? keyGenerator,
  }) : _apiClient = apiClient ?? ReportEmailApiClient(),
       _keyGenerator = keyGenerator ?? SecureUuidV4Generator();

  final ReportEmailApiClient _apiClient;
  final ReportIdempotencyKeyGenerator _keyGenerator;
  final Map<String, _ReportAttempt> _attempts = {};

  @override
  Future<ReportEmailAccepted> sendReport({
    required String employeeUid,
    required String periodKind,
    required String anchorDate,
  }) {
    final scope = '$employeeUid\u0000$periodKind\u0000$anchorDate';
    final existing = _attempts[scope];
    if (existing != null) {
      if (existing.accepted != null) {
        return Future.value(existing.accepted);
      }
      if (existing.uncertain != null) {
        return Future.error(ReportEmailUncertainException(existing.uncertain!));
      }
      return existing.pending!;
    }

    final attempt = _ReportAttempt(_keyGenerator.generate());
    _attempts[scope] = attempt;
    final pending = _send(
      scope: scope,
      attempt: attempt,
      employeeUid: employeeUid,
      periodKind: periodKind,
      anchorDate: anchorDate,
    );
    attempt.pending = pending;
    return pending;
  }

  Future<ReportEmailAccepted> _send({
    required String scope,
    required _ReportAttempt attempt,
    required String employeeUid,
    required String periodKind,
    required String anchorDate,
  }) async {
    try {
      final accepted = await _apiClient.send(
        employeeUid: employeeUid,
        periodKind: periodKind,
        anchorDate: anchorDate,
        idempotencyKey: attempt.idempotencyKey,
      );
      attempt
        ..accepted = accepted
        ..pending = null;
      return accepted;
    } on ReportEmailApiException catch (error) {
      attempt.pending = null;
      if (error.outcomeMayBeUnknown) {
        attempt.uncertain = error;
        throw ReportEmailUncertainException(error);
      }
      _attempts.remove(scope);
      rethrow;
    }
  }
}

class _ReportAttempt {
  _ReportAttempt(this.idempotencyKey);

  final String idempotencyKey;
  Future<ReportEmailAccepted>? pending;
  ReportEmailAccepted? accepted;
  ReportEmailApiException? uncertain;
}
