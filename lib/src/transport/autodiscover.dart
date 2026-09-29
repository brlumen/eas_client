/// Autodiscover — automatic EAS server discovery by email address.
///
/// Implements the EAS Autodiscover command (MS-ASCMD 2.2.1.1) and server
/// location per MS-OXDISCO 3.1.5. Candidate order for each email address:
///
/// 1. POST `https://<domain>/autodiscover/autodiscover.xml`
/// 2. POST `https://autodiscover.<domain>/autodiscover/autodiscover.xml`
/// 3. *(opt-in, [Autodiscover.enableHttpRedirectStep])* unauthenticated GET
///    `http://autodiscover.<domain>/autodiscover/autodiscover.xml`; a 302
///    `Location` that is HTTPS and confirmed via
///    [Autodiscover.confirmRedirect] is then POSTed to.
/// 4. *(opt-in, [Autodiscover.srvResolver])* DNS SRV
///    `_autodiscover._tcp.<domain>`; each confirmed target is POSTed to at
///    `https://<target>[:port]/autodiscover/autodiscover.xml`.
/// 5. *(optional, [Autodiscover.useOffice365Fallback])*
///    `https://autodiscover-s.outlook.com/autodiscover/autodiscover.xml`.
///
/// Security:
/// * Credentials are sent only over HTTPS. The HTTP step is a bare GET
///   without credentials, body or cookies; only an HTTPS `Location` is used.
/// * Hosts from spoofable sources (steps 3 and 4) require explicit consumer
///   confirmation; without a [Autodiscover.confirmRedirect] callback they
///   are rejected.
/// * HTTP redirects (301/302/303/307/308, 451 `X-MS-Location`) on HTTPS
///   steps are followed only to HTTPS, max 10 per attempt, loops detected.
/// * `Action/Redirect` email redirects: max 10 in total, circular redirects
///   are skipped (moves to the next candidate).
/// * Response bodies are size-limited ([Autodiscover.maxResponseSize]).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'autodiscover_response.dart';
import 'dns_srv_resolver.dart';
import 'eas_credentials.dart';

/// Consumer callback confirming a server location obtained from an
/// unauthenticated source (HTTP redirect or DNS SRV). Return `true` to allow
/// sending credentials to [uri].
typedef AutodiscoverRedirectConfirmation = Future<bool> Function(Uri uri);

/// Result of Autodiscover.
class AutodiscoverResult {
  /// ActiveSync server hostname (e.g., 'mail.example.com').
  final String server;

  /// Full ActiveSync URL.
  final String url;

  /// Display name from server response.
  final String? displayName;

  /// User's SMTP address from `User/EMailAddress`.
  final String? emailAddress;

  /// `Culture` (e.g. `en:us`).
  final String? culture;

  /// All `Settings/Server` entries (MobileSync, CertEnroll, ...).
  final List<AutodiscoverServer> servers;

  const AutodiscoverResult({
    required this.server,
    required this.url,
    this.displayName,
    this.emailAddress,
    this.culture,
    this.servers = const [],
  });

  /// CertEnroll server entry, if provided.
  AutodiscoverServer? get certEnroll {
    for (final s in servers) {
      if (s.isCertEnroll) return s;
    }
    return null;
  }

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

  /// Opt-in: MS-OXDISCO HTTP GET redirect step (plain HTTP, no credentials).
  final bool enableHttpRedirectStep;

  /// Opt-in: DNS SRV step; `null` disables it.
  final DnsSrvResolver? srvResolver;

  /// Confirms hosts from steps 3/4. `null` = reject all.
  final AutodiscoverRedirectConfirmation? confirmRedirect;

  /// Whether to try the Office 365 endpoint as the last candidate.
  final bool useOffice365Fallback;

  /// Max response body size in bytes.
  final int maxResponseSize;

  final Random _random;

  /// Max HTTP redirects per URL attempt.
  static const maxHttpRedirects = 10;

  /// Max `Action/Redirect` email redirects in total.
  static const maxEmailRedirects = 10;

  /// Max SRV targets tried per domain.
  static const maxSrvTargets = 10;

  static const _redirectStatuses = {301, 302, 303, 307, 308};
  static const _office365Url =
      'https://autodiscover-s.outlook.com/autodiscover/autodiscover.xml';

  Autodiscover({
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 30),
    this.enableHttpRedirectStep = false,
    this.srvResolver,
    this.confirmRedirect,
    this.useOffice365Fallback = true,
    this.maxResponseSize = 1024 * 1024,
    Random? random,
  }) : _httpClient = httpClient ?? http.Client(),
       _timeout = timeout,
       _random = random ?? Random.secure();

  /// Discover EAS server for the given email address.
  Future<AutodiscoverResult> discover({
    required String email,
    required EasCredentials credentials,
  }) async {
    final triedUrls = <String>[];
    final errors = <String, String>{};
    final visitedEmails = <String>{};
    var current = email;

    for (var redirects = 0; ; redirects++) {
      final domain = _domainOf(current);
      visitedEmails.add(current.toLowerCase());
      final ctx = _Attempt(
        domain: domain,
        credentials: credentials,
        body: _buildRequest(current),
        triedUrls: triedUrls,
        errors: errors,
        visitedEmails: visitedEmails,
      );

      final outcome = await _discoverForEmail(ctx);
      switch (outcome) {
        case _Found(:final result):
          return result;
        case _RedirectEmail(:final email):
          if (redirects + 1 > maxEmailRedirects) {
            throw AutodiscoverException(
              'Too many Autodiscover redirects',
              triedUrls: triedUrls,
              errors: errors,
              email: email,
            );
          }
          current = email;
        case null:
          throw AutodiscoverException(
            'Could not discover EAS settings',
            triedUrls: triedUrls,
            errors: errors,
            email: current,
          );
      }
    }
  }

  /// Tries all candidates for one email address.
  Future<_Outcome?> _discoverForEmail(_Attempt ctx) async {
    for (final url in [
      'https://${ctx.domain}/autodiscover/autodiscover.xml',
      'https://autodiscover.${ctx.domain}/autodiscover/autodiscover.xml',
    ]) {
      final o = await _post(Uri.parse(url), ctx);
      if (o != null) return o;
    }

    if (enableHttpRedirectStep) {
      final target = await _httpRedirectStep(ctx);
      if (target != null && await _confirm(target, ctx)) {
        final o = await _post(target, ctx);
        if (o != null) return o;
      }
    }

    if (srvResolver != null) {
      for (final target in await _srvCandidates(ctx)) {
        if (!await _confirm(target, ctx)) continue;
        final o = await _post(target, ctx);
        if (o != null) return o;
      }
    }

    if (useOffice365Fallback) {
      return _post(Uri.parse(_office365Url), ctx);
    }
    return null;
  }

  /// Step 3: unauthenticated GET over HTTP; returns HTTPS redirect target.
  Future<Uri?> _httpRedirectStep(_Attempt ctx) async {
    final uri = Uri.parse(
      'http://autodiscover.${ctx.domain}/autodiscover/autodiscover.xml',
    );
    final key = 'GET $uri';
    ctx.triedUrls.add(key);
    try {
      // No credentials, no body: nothing sensitive leaves over plain HTTP.
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await _send(request);
      if (!_redirectStatuses.contains(response.statusCode)) {
        ctx.errors[key] = 'HTTP ${response.statusCode} (expected 302)';
        return null;
      }
      final location = response.headers['location'];
      final target = location == null ? null : Uri.tryParse(location.trim());
      if (target == null || !_isSecure(target)) {
        ctx.errors[key] = 'Redirect Location is missing or not HTTPS';
        return null;
      }
      return target;
    } catch (e) {
      ctx.errors[key] = _describe(e);
      return null;
    }
  }

  /// Step 4: SRV lookup → ordered HTTPS Autodiscover URIs.
  Future<List<Uri>> _srvCandidates(_Attempt ctx) async {
    final name = '_autodiscover._tcp.${ctx.domain}';
    final key = 'SRV $name';
    ctx.triedUrls.add(key);
    try {
      if (!DnsSrvCodec.isValidHostname(ctx.domain)) {
        ctx.errors[key] = 'Domain is not a valid DNS name';
        return const [];
      }
      final records = await srvResolver!.lookupSrv(name).timeout(_timeout);
      final ordered = DnsSrvCodec.order(records, _random)
          .where((r) => DnsSrvCodec.isValidHostname(r.target) && r.port > 0)
          .take(maxSrvTargets)
          .map(
            (r) => Uri(
              scheme: 'https',
              host: r.target,
              port: r.port == 443 ? null : r.port,
              path: '/autodiscover/autodiscover.xml',
            ),
          )
          .toList();
      if (ordered.isEmpty) ctx.errors[key] = 'No usable SRV records';
      return ordered;
    } catch (e) {
      ctx.errors[key] = _describe(e);
      return const [];
    }
  }

  Future<bool> _confirm(Uri uri, _Attempt ctx) async {
    final confirm = confirmRedirect;
    var ok = false;
    if (confirm != null) {
      try {
        ok = await confirm(uri);
      } catch (_) {
        ok = false;
      }
    }
    if (!ok) ctx.errors['$uri'] = 'Redirect not confirmed by consumer';
    return ok;
  }

  /// POSTs the Autodiscover request to [start] (HTTPS only), following
  /// HTTPS redirects, and interprets the response.
  Future<_Outcome?> _post(Uri start, _Attempt ctx) async {
    var uri = start;
    final visited = <String>{};
    try {
      for (var i = 0; i <= maxHttpRedirects; i++) {
        final key = uri.toString();
        ctx.triedUrls.add(key);
        if (!_isSecure(uri)) {
          ctx.errors[key] = 'Refusing non-HTTPS URL';
          return null;
        }
        if (!visited.add(key)) {
          ctx.errors[key] = 'Circular HTTP redirect';
          return null;
        }

        final request = http.Request('POST', uri)
          ..followRedirects = false
          ..headers.addAll(
            ctx.credentials.applyToHeaders({
              'Content-Type': 'text/xml; charset=utf-8',
            }),
          )
          ..bodyBytes = utf8.encode(ctx.body);
        final response = await _send(request);
        final status = response.statusCode;

        if (status == 200) {
          return _interpret(
            utf8.decode(response.bodyBytes, allowMalformed: true),
            key,
            ctx,
          );
        }

        final String? location;
        if (_redirectStatuses.contains(status)) {
          location = response.headers['location'];
        } else if (status == 451) {
          location =
              response.headers['x-ms-location'] ?? response.headers['location'];
        } else {
          ctx.errors[key] = 'HTTP $status';
          return null;
        }
        final next = location == null ? null : Uri.tryParse(location.trim());
        if (next == null) {
          ctx.errors[key] = 'HTTP $status without valid Location';
          return null;
        }
        final resolved = uri.resolveUri(next);
        if (!_isSecure(resolved)) {
          ctx.errors[key] = 'Redirect to non-HTTPS refused';
          return null;
        }
        uri = resolved;
      }
      ctx.errors[uri.toString()] = 'Too many redirects (>$maxHttpRedirects)';
      return null;
    } catch (e) {
      ctx.errors[uri.toString()] = _describe(e);
      return null;
    }
  }

  _Outcome? _interpret(String body, String key, _Attempt ctx) {
    final response = AutodiscoverResponse.tryParse(body);
    if (response == null) {
      ctx.errors[key] = 'Malformed Autodiscover XML';
      return null;
    }
    final redirect = response.redirectEmail;
    if (redirect != null) {
      if (!_isValidEmail(redirect)) {
        ctx.errors[key] = 'Invalid redirect address';
        return null;
      }
      if (ctx.visitedEmails.contains(redirect.toLowerCase())) {
        ctx.errors[key] = 'Circular email redirect';
        return null;
      }
      return _RedirectEmail(redirect);
    }
    final result = resultFrom(response);
    if (result != null) return _Found(result);
    ctx.errors[key] = response.error?.toString() ?? 'No MobileSync settings';
    return null;
  }

  /// Sends [request] with timeout and bounded body read.
  Future<http.Response> _send(http.BaseRequest request) async {
    return Future(() async {
      final streamed = await _httpClient.send(request);
      final declared = streamed.contentLength;
      if (declared != null && declared > maxResponseSize) {
        throw const _TooLarge();
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream) {
        builder.add(chunk);
        if (builder.length > maxResponseSize) throw const _TooLarge();
      }
      return http.Response.bytes(
        builder.takeBytes(),
        streamed.statusCode,
        headers: streamed.headers,
        request: request,
      );
    }).timeout(_timeout);
  }

  /// Builds an [AutodiscoverResult] from a parsed response, or `null` if it
  /// holds no usable (HTTPS) MobileSync endpoint.
  @visibleForTesting
  static AutodiscoverResult? resultFrom(AutodiscoverResponse response) {
    final mobileSync = response.mobileSync;
    if (mobileSync != null) {
      final uri = mobileSync.secureUri!;
      return AutodiscoverResult(
        server: uri.host,
        url: mobileSync.url!,
        displayName: response.displayName,
        emailAddress: response.emailAddress,
        culture: response.culture,
        servers: response.servers,
      );
    }
    // Legacy fallback: <Server>hostname</Server>.
    for (final host in response.legacyServerHosts) {
      if (_hostnamePattern.hasMatch(host)) {
        return AutodiscoverResult(
          server: host,
          url: 'https://$host/Microsoft-Server-ActiveSync',
          displayName: response.displayName,
          emailAddress: response.emailAddress,
          culture: response.culture,
        );
      }
    }
    return null;
  }

  static bool _isSecure(Uri uri) =>
      uri.scheme == 'https' && uri.host.isNotEmpty;

  /// Characters that must never appear in an email domain used in URLs.
  static final _badDomainChars = RegExp(r'[\s/?#@:\\\[\]%]');

  static String _domainOf(String email) {
    if (!email.contains('@')) {
      throw AutodiscoverException('Invalid email format: missing @');
    }
    final domain = email.split('@').last;
    if (domain.isEmpty) {
      throw AutodiscoverException('Invalid email format: empty domain');
    }
    if (_badDomainChars.hasMatch(domain) ||
        domain.split('.').any((l) => l.isEmpty)) {
      throw AutodiscoverException('Invalid email format: bad domain');
    }
    return domain;
  }

  static bool _isValidEmail(String email) {
    if (email.length > 320) return false;
    final parts = email.split('@');
    if (parts.length != 2 || parts[0].isEmpty) return false;
    try {
      _domainOf(email);
      return true;
    } on AutodiscoverException {
      return false;
    }
  }

  static String _describe(Object e) => switch (e) {
    _TooLarge() => 'Response exceeds size limit',
    _ => e.toString(),
  };

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
  static final _hostnamePattern = RegExp(r'^[^\s/?#@:\\]+$');

  /// Parses an Autodiscover response body into a result (HTTPS only).
  @visibleForTesting
  AutodiscoverResult? parseResponse(String body) {
    final response = AutodiscoverResponse.tryParse(body);
    return response == null ? null : resultFrom(response);
  }

  void dispose() {
    _httpClient.close();
  }
}

/// Per-email discovery context.
class _Attempt {
  final String domain;
  final EasCredentials credentials;
  final String body;
  final List<String> triedUrls;
  final Map<String, String> errors;
  final Set<String> visitedEmails;

  _Attempt({
    required this.domain,
    required this.credentials,
    required this.body,
    required this.triedUrls,
    required this.errors,
    required this.visitedEmails,
  });
}

sealed class _Outcome {
  const _Outcome();
}

final class _Found extends _Outcome {
  final AutodiscoverResult result;
  const _Found(this.result);
}

final class _RedirectEmail extends _Outcome {
  final String email;
  const _RedirectEmail(this.email);
}

class _TooLarge implements Exception {
  const _TooLarge();
}
