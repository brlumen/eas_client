/// Autodiscover — automatic EAS server discovery by email address.
///
/// Implements the Autodiscover protocol (MS-OXDISCO) to find the
/// ActiveSync endpoint URL from just an email address.
///
/// Discovery order (per MS-OXDISCO):
/// 1. POST https://domain/autodiscover/autodiscover.xml
/// 2. POST https://autodiscover.domain/autodiscover/autodiscover.xml
/// 3. POST https://autodiscover-s.outlook.com/autodiscover/autodiscover.xml (Office 365)
///
/// Supports HTTP 301/302/307/308 redirects (HTTPS-only, max 10 per MS-OXDISCO).
/// Supports XML body redirects: `<Action><Redirect>` (new URL) and
/// `redirectAddr` (restart discovery with new email).
///
/// DNS SRV (_autodiscover._tcp.domain) is not implemented — requires DNS library.
library;

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:xml/xml.dart' as xml;

import 'eas_credentials.dart';

/// Result of Autodiscover.
class AutodiscoverResult {
  /// ActiveSync server hostname (e.g., 'mail.example.com').
  final String server;

  /// Full ActiveSync URL.
  final String url;

  /// Display name from server response.
  final String? displayName;

  const AutodiscoverResult({
    required this.server,
    required this.url,
    this.displayName,
  });

  @override
  String toString() => 'AutodiscoverResult(server: $server, url: $url)';
}

/// Exception thrown when Autodiscover fails.
class AutodiscoverException implements Exception {
  final String message;
  final List<String> triedUrls;

  /// Per-URL errors encountered during discovery.
  final Map<String, String> errors;

  /// Email address that was being discovered (not included in [toString]).
  final String? email;

  AutodiscoverException(
    this.message, {
    this.triedUrls = const [],
    this.errors = const {},
    this.email,
  });

  @override
  String toString() => 'AutodiscoverException: $message';
}

/// Discovers EAS server settings from an email address.
class Autodiscover {
  final http.Client _httpClient;
  final Duration _timeout;

  /// Max HTTP redirects per URL attempt (per MS-OXDISCO).
  static const _maxHttpRedirects = 10;

  /// Max XML-level redirectAddr restarts to prevent loops.
  static const _maxEmailRedirects = 5;

  Autodiscover({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 30),
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout;

  /// Discover EAS server for the given email address.
  Future<AutodiscoverResult> discover({
    required String email,
    required EasCredentials credentials,
  }) async {
    return _discoverWithRedirects(
      email: email,
      credentials: credentials,
      depth: 0,
    );
  }

  Future<AutodiscoverResult> _discoverWithRedirects({
    required String email,
    required EasCredentials credentials,
    required int depth,
  }) async {
    if (depth > _maxEmailRedirects) {
      throw AutodiscoverException(
        'Too many redirectAddr redirects',
        email: email,
      );
    }

    if (!email.contains('@')) {
      throw AutodiscoverException('Invalid email format: missing @');
    }
    final domain = email.split('@').last;
    if (domain.isEmpty) {
      throw AutodiscoverException('Invalid email format: empty domain');
    }
    final triedUrls = <String>[];
    final errors = <String, String>{};
    final requestBody = _buildRequest(email);

    final urls = [
      'https://$domain/autodiscover/autodiscover.xml',
      'https://autodiscover.$domain/autodiscover/autodiscover.xml',
      'https://autodiscover-s.outlook.com/autodiscover/autodiscover.xml',
    ];

    for (final url in urls) {
      triedUrls.add(url);
      final (response, error) =
          await _tryAutodiscover(url, requestBody, credentials);
      if (error != null) errors[url] = error;
      if (response == null) continue;

      final parsed = parseResponse(response);
      if (parsed != null) return parsed;

      // Check for XML-level redirects
      final redirect = _parseRedirect(response);
      if (redirect != null) {
        if (redirect.isUrl) {
          // <Action><Redirect>URL</Redirect> — POST to new URL
          final (redirectBody, redirectError) =
              await _tryAutodiscover(redirect.value, requestBody, credentials);
          if (redirectError != null) errors[redirect.value] = redirectError;
          if (redirectBody != null) {
            final parsed = parseResponse(redirectBody);
            if (parsed != null) return parsed;
          }
        } else {
          // redirectAddr — restart discovery with new email
          return _discoverWithRedirects(
            email: redirect.value,
            credentials: credentials,
            depth: depth + 1,
          );
        }
      }
    }

    throw AutodiscoverException(
      'Could not discover EAS settings',
      triedUrls: triedUrls,
      errors: errors,
      email: email,
    );
  }

  /// Attempts POST to [url], following HTTP redirects (HTTPS-only).
  /// Returns (responseBody, error) — body is non-null on success,
  /// error is non-null on failure.
  Future<(String?, String?)> _tryAutodiscover(
    String url,
    String requestBody,
    EasCredentials credentials,
  ) async {
    try {
      var headers = <String, String>{
        'Content-Type': 'text/xml',
      };
      headers = credentials.applyToHeaders(headers);

      var currentUri = Uri.parse(url);

      for (var i = 0; i <= _maxHttpRedirects; i++) {
        final response = await _httpClient
            .post(
              currentUri,
              headers: headers,
              body: requestBody,
            )
            .timeout(_timeout);

        if (response.statusCode == 200) {
          return (response.body, null);
        }

        // Follow HTTP redirects (HTTPS-only per MS-OXDISCO)
        if (response.statusCode == 301 ||
            response.statusCode == 302 ||
            response.statusCode == 307 ||
            response.statusCode == 308) {
          final location = response.headers['location'];
          if (location == null) {
            return (null, 'HTTP ${response.statusCode} without Location header');
          }

          final redirectUri = currentUri.resolve(location);
          if (redirectUri.scheme != 'https') {
            return (null, 'Redirect to non-HTTPS: $redirectUri');
          }
          currentUri = redirectUri;
          continue;
        }

        return (null, 'HTTP ${response.statusCode}');
      }
      return (null, 'Too many redirects (>$_maxHttpRedirects)');
    } catch (e) {
      return (null, e.toString());
    }
  }

  /// Parses XML body for redirect instructions.
  /// Returns redirect URL or email, or null if no redirect found.
  _AutodiscoverRedirect? _parseRedirect(String body) {
    final xml.XmlDocument doc;
    try {
      doc = xml.XmlDocument.parse(body);
    } catch (_) {
      return null;
    }

    // MobileSync: <Action><Redirect>https://...</Redirect></Action>
    for (final action in doc.findAllElements('Action')) {
      for (final redirect in action.findElements('Redirect')) {
        final value = redirect.innerText.trim();
        if (value.isEmpty) continue;
        if (value.startsWith('https://')) {
          return _AutodiscoverRedirect(value, isUrl: true);
        }
      }

      // POX/MobileSync: <Action>redirectAddr</Action> + <RedirectAddr>
      if (action.innerText.trim() == 'redirectAddr') {
        for (final addr in doc.findAllElements('RedirectAddr')) {
          final value = addr.innerText.trim();
          if (value.contains('@')) {
            return _AutodiscoverRedirect(value, isUrl: false);
          }
        }
      }
    }

    return null;
  }

  String _buildRequest(String email) {
    final safeEmail = _escapeXml(email);
    return '''<?xml version="1.0" encoding="utf-8"?>
<Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/mobilesync/requestschema/2006">
  <Request>
    <EMailAddress>$safeEmail</EMailAddress>
    <AcceptableResponseSchema>http://schemas.microsoft.com/exchange/autodiscover/mobilesync/responseschema/2006</AcceptableResponseSchema>
  </Request>
</Autodiscover>''';
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  @visibleForTesting
  static String escapeXmlForTest(String input) => _escapeXml(input);

  /// Regex for valid hostname (no path, query, fragment, whitespace).
  static final _hostnamePattern = RegExp(r'^[^\s/?#]+$');

  @visibleForTesting
  AutodiscoverResult? parseResponse(String body) {
    final xml.XmlDocument doc;
    try {
      doc = xml.XmlDocument.parse(body);
    } catch (_) {
      return null;
    }

    // Look for <Url> containing Microsoft-Server-ActiveSync (HTTPS only)
    for (final urlElement in doc.findAllElements('Url')) {
      final urlText = urlElement.innerText.trim();
      if (urlText.startsWith('https://') &&
          urlText.contains('Microsoft-Server-ActiveSync')) {
        final uri = Uri.tryParse(urlText);
        if (uri == null || uri.host.isEmpty) continue;

        // Extract display name if present
        String? displayName;
        for (final nameEl in doc.findAllElements('DisplayName')) {
          final text = nameEl.innerText.trim();
          if (text.isNotEmpty) {
            displayName = text;
            break;
          }
        }

        return AutodiscoverResult(
          server: uri.host,
          url: urlText,
          displayName: displayName,
        );
      }
    }

    // Fallback: <Server> element — validate hostname
    for (final serverElement in doc.findAllElements('Server')) {
      final server = serverElement.innerText.trim();
      if (server.isNotEmpty && _hostnamePattern.hasMatch(server)) {
        return AutodiscoverResult(
          server: server,
          url: 'https://$server/Microsoft-Server-ActiveSync',
        );
      }
    }

    return null;
  }

  void dispose() {
    _httpClient.close();
  }
}

/// Internal redirect parsed from Autodiscover XML response.
class _AutodiscoverRedirect {
  final String value;
  final bool isUrl;

  const _AutodiscoverRedirect(this.value, {required this.isUrl});
}
