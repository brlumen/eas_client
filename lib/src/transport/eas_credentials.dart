/// EAS authentication credentials.
library;

import 'dart:convert';

/// Base class for EAS credentials.
sealed class EasCredentials {
  const EasCredentials();

  /// Apply credentials to HTTP headers.
  Map<String, String> applyToHeaders(Map<String, String> headers);
}

/// Basic authentication (username:password base64).
class BasicCredentials extends EasCredentials {
  final String username;
  final String password;

  const BasicCredentials({
    required this.username,
    required this.password,
  });

  @override
  Map<String, String> applyToHeaders(Map<String, String> headers) {
    final encoded = base64Encode(utf8.encode('$username:$password'));
    return {...headers, 'Authorization': 'Basic $encoded'};
  }
}

/// OAuth2 Bearer token authentication.
class OAuthCredentials extends EasCredentials {
  final String accessToken;

  OAuthCredentials({required this.accessToken}) {
    if (accessToken.isEmpty) {
      throw ArgumentError.value(
        accessToken, 'accessToken', 'Must not be empty',
      );
    }
  }

  @override
  Map<String, String> applyToHeaders(Map<String, String> headers) {
    return {...headers, 'Authorization': 'Bearer $accessToken'};
  }
}
