/// Autodiscover — automatic EAS server discovery by email address.
///
/// Implements the Autodiscover protocol (MS-OXDISCO) to find the
/// ActiveSync endpoint URL from just an email address.
///
/// Discovery order (HTTPS-only per MS-OXDISCO 4.1):
/// 1. https://domain/autodiscover/autodiscover.xml
/// 2. https://autodiscover.domain/autodiscover/autodiscover.xml
/// 3. https://autodiscover-s.outlook.com/autodiscover/autodiscover.xml (Office 365)
///
/// Note: HTTP redirect step (MS-OXDISCO step 3) is intentionally omitted.
/// MS-OXDISCO 4.1 warns that HTTP requests are vulnerable to MitM/DNS spoofing
/// and the client cannot verify the identity of the redirect target.
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

  /// Email address that was being discovered (not included in [toString]).
  final String? email;

  AutodiscoverException(this.message, {this.triedUrls = const [], this.email});

  @override
  String toString() => 'AutodiscoverException: $message';
}

/// Discovers EAS server settings from an email address.
class Autodiscover {
  final http.Client _httpClient;
  final Duration _timeout;

  Autodiscover({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 10),
  })  : _httpClient = httpClient ?? http.Client(),
        _timeout = timeout;

  /// Discover EAS server for the given email address.
  Future<AutodiscoverResult> discover({
    required String email,
    required EasCredentials credentials,
  }) async {
    if (!email.contains('@')) {
      throw AutodiscoverException('Invalid email format: missing @');
    }
    final domain = email.split('@').last;
    if (domain.isEmpty) {
      throw AutodiscoverException('Invalid email format: empty domain');
    }
    final triedUrls = <String>[];

    // Build Autodiscover request body
    final requestBody = _buildRequest(email);

    // Try each URL in order
    final urls = [
      'https://$domain/autodiscover/autodiscover.xml',
      'https://autodiscover.$domain/autodiscover/autodiscover.xml',
    ];

    for (final url in urls) {
      triedUrls.add(url);
      final result = await _tryAutodiscover(url, requestBody, credentials);
      if (result != null) return result;
    }

    // Try well-known Microsoft endpoint for Office 365
    const msUrl =
        'https://autodiscover-s.outlook.com/autodiscover/autodiscover.xml';
    triedUrls.add(msUrl);
    final msResult = await _tryAutodiscover(msUrl, requestBody, credentials);
    if (msResult != null) return msResult;

    throw AutodiscoverException(
      'Could not discover EAS settings',
      triedUrls: triedUrls,
      email: email,
    );
  }

  Future<AutodiscoverResult?> _tryAutodiscover(
    String url,
    String requestBody,
    EasCredentials credentials,
  ) async {
    try {
      var headers = <String, String>{
        'Content-Type': 'text/xml',
      };
      headers = credentials.applyToHeaders(headers);

      final response = await _httpClient
          .post(
            Uri.parse(url),
            headers: headers,
            body: requestBody,
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return parseResponse(response.body);
      }
    } catch (_) {
      // Connection failed, try next URL
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
