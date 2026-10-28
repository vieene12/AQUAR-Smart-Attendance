class ApiConfiguration {
  const ApiConfiguration._();

  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  static Uri requireBaseUri([String? override]) {
    final value = (override ?? baseUrl).trim();
    final uri = Uri.tryParse(value);
    if (value.isEmpty ||
        uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ApiConfigurationException();
    }
    return uri;
  }
}

class ApiConfigurationException implements Exception {
  const ApiConfigurationException();
}
