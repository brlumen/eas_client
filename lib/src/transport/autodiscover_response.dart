/// Typed model of the Autodiscover (mobilesync) response.
///
/// Schema: MS-ASCMD 6.2 (AutodiscoverMobileSync.xsd) and 6.4
/// (AutodiscoverResponse.xsd). Element names are matched by local name so
/// both default-namespace and prefixed (`autodiscover:Response`) documents
/// are accepted.
library;

import 'package:xml/xml.dart' as xml;

/// Known Autodiscover `ErrorCode` values.
///
/// 600/601 — MS-ASCMD 2.2.3.64; 500/501/602/603 — MS-OXDSCLI 2.2.4.1.1.3.2.
abstract final class AutodiscoverErrorCode {
  /// The email address cannot be found.
  static const emailNotFound = 500;

  /// Bad address: the address has no configuration options.
  static const badAddress = 501;

  /// Invalid request: the XML request was improperly formatted.
  static const invalidRequest = 600;

  /// No provider for the requested `AcceptableResponseSchema`.
  static const schemaNotAvailable = 601;

  /// Bad address: configuration errors on the server.
  static const configurationError = 602;

  /// Internal server error.
  static const internalError = 603;

  /// Human-readable description of [code], or `null` if unknown.
  static String? describe(int code) => switch (code) {
    emailNotFound => 'Email address cannot be found',
    badAddress => 'Email address has no configuration options',
    invalidRequest => 'Invalid request',
    schemaNotAvailable => 'Requested response schema is not available',
    configurationError => 'Server configuration error for this address',
    internalError => 'Autodiscover server internal error',
    _ => null,
  };
}

/// `Error` element — either `Response/Error` (ErrorCode) or
/// `Response/Action/Error` (Status, MS-ASCMD 2.2.3.177.1).
class AutodiscoverError {
  /// `ErrorCode` (see [AutodiscoverErrorCode]).
  final int? errorCode;

  /// `Status` — 2 = protocol error (MS-ASCMD 2.2.3.177.1).
  final int? status;

  final String? message;
  final String? debugData;

  /// `Time` attribute (Response-level error only).
  final String? time;

  /// `Id` attribute (Response-level error only).
  final String? id;

  /// `true` for `Action/Error`, `false` for `Response/Error`.
  final bool isActionError;

  const AutodiscoverError({
    this.errorCode,
    this.status,
    this.message,
    this.debugData,
    this.time,
    this.id,
    this.isActionError = false,
  });

  /// Status value meaning "protocol error" (MS-ASCMD 2.2.3.177.1).
  static const statusProtocolError = 2;

  @override
  String toString() {
    final code = errorCode != null
        ? 'code $errorCode'
        : status != null
        ? 'status $status'
        : 'unknown';
    final desc = errorCode != null
        ? AutodiscoverErrorCode.describe(errorCode!)
        : null;
    return 'AutodiscoverError($code${desc != null ? ': $desc' : ''})';
  }
}

/// `Settings/Server` entry.
class AutodiscoverServer {
  /// Server type, e.g. [typeMobileSync] or [typeCertEnroll].
  final String? type;

  /// Server URL as sent by the server (not validated; see [secureUri]).
  final String? url;

  final String? name;

  /// `ServerData` — e.g. certificate template name for CertEnroll.
  final String? serverData;

  const AutodiscoverServer({this.type, this.url, this.name, this.serverData});

  static const typeMobileSync = 'MobileSync';
  static const typeCertEnroll = 'CertEnroll';

  bool get isMobileSync => type?.toLowerCase() == 'mobilesync';
  bool get isCertEnroll => type?.toLowerCase() == 'certenroll';

  /// [url] parsed, only if it is an absolute HTTPS URL with a host.
  Uri? get secureUri {
    final u = url;
    if (u == null) return null;
    final uri = Uri.tryParse(u);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }
}

/// Parsed Autodiscover response.
class AutodiscoverResponse {
  final String? culture;
  final String? displayName;
  final String? emailAddress;

  /// `Action/Redirect` — SMTP address to restart discovery with.
  final String? redirectEmail;

  /// `Action/Settings/Server` entries.
  final List<AutodiscoverServer> servers;

  /// `Response/Error` or `Action/Error`, if present.
  final AutodiscoverError? error;

  /// Hostnames from legacy `<Server>host</Server>` text elements.
  final List<String> legacyServerHosts;

  const AutodiscoverResponse({
    this.culture,
    this.displayName,
    this.emailAddress,
    this.redirectEmail,
    this.servers = const [],
    this.error,
    this.legacyServerHosts = const [],
  });

  /// First MobileSync server with a valid HTTPS URL.
  ///
  /// Servers without a `Type` are accepted only if their URL points to
  /// `Microsoft-Server-ActiveSync`.
  AutodiscoverServer? get mobileSync {
    for (final s in servers) {
      final uri = s.secureUri;
      if (uri == null) continue;
      if (s.isMobileSync ||
          (s.type == null && s.url!.contains('Microsoft-Server-ActiveSync'))) {
        return s;
      }
    }
    return null;
  }

  /// First CertEnroll server, if any.
  AutodiscoverServer? get certEnroll {
    for (final s in servers) {
      if (s.isCertEnroll) return s;
    }
    return null;
  }

  /// Parses [body]; returns `null` if it is not well-formed XML.
  static AutodiscoverResponse? tryParse(String body) {
    final xml.XmlDocument doc;
    try {
      doc = xml.XmlDocument.parse(body);
    } catch (_) {
      return null;
    }
    final response = _all(doc, 'Response').firstOrNull ?? doc.rootElement;

    final user = _child(response, 'User');
    final action = _child(response, 'Action');
    final settings = action == null ? null : _child(action, 'Settings');

    final servers = <AutodiscoverServer>[];
    final legacyHosts = <String>[];
    for (final s
        in (settings == null ? null : _children(settings, 'Server')) ??
            const <xml.XmlElement>[]) {
      servers.add(
        AutodiscoverServer(
          type: _text(s, 'Type'),
          url: _text(s, 'Url'),
          name: _text(s, 'Name'),
          serverData: _text(s, 'ServerData'),
        ),
      );
    }
    // Legacy/non-standard: <Server>hostname</Server> without children.
    for (final s in _all(doc, 'Server')) {
      if (s.childElements.isEmpty) {
        final t = s.innerText.trim();
        if (t.isNotEmpty) legacyHosts.add(t);
      }
    }

    // MS-ASCMD: Action/Redirect. Older/POX servers: RedirectAddr.
    var redirect = action == null ? null : _text(action, 'Redirect');
    redirect ??= action == null ? null : _text(action, 'RedirectAddr');
    if (redirect == null) {
      final addr = _all(doc, 'RedirectAddr');
      if (addr.isNotEmpty) redirect = _nonEmpty(addr.first.innerText);
    }

    final responseError = _child(response, 'Error');
    final actionError = action == null ? null : _child(action, 'Error');
    final errorEl = responseError ?? actionError;

    return AutodiscoverResponse(
      culture: _text(response, 'Culture'),
      displayName: user == null ? null : _text(user, 'DisplayName'),
      emailAddress: user == null ? null : _text(user, 'EMailAddress'),
      redirectEmail: redirect,
      servers: List.unmodifiable(servers),
      error: errorEl == null
          ? null
          : AutodiscoverError(
              errorCode: _int(_text(errorEl, 'ErrorCode')),
              status: _int(_text(errorEl, 'Status')),
              message: _text(errorEl, 'Message'),
              debugData: _text(errorEl, 'DebugData'),
              time: errorEl.getAttribute('Time'),
              id: errorEl.getAttribute('Id'),
              isActionError: responseError == null,
            ),
      legacyServerHosts: List.unmodifiable(legacyHosts),
    );
  }

  // Matching by local name in any namespace without the `namespace:` /
  // `namespaceUri:` parameter, which xml 6.x and 7.x name differently.
  static Iterable<xml.XmlElement> _all(xml.XmlNode node, String name) =>
      node.descendantElements.where((e) => e.name.local == name);

  static Iterable<xml.XmlElement> _children(
    xml.XmlElement parent,
    String name,
  ) => parent.childElements.where((e) => e.name.local == name);

  static xml.XmlElement? _child(xml.XmlElement parent, String name) =>
      _children(parent, name).firstOrNull;

  static String? _text(xml.XmlElement parent, String name) {
    final el = _child(parent, name);
    return el == null ? null : _nonEmpty(el.innerText);
  }

  static String? _nonEmpty(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  static int? _int(String? s) => s == null ? null : int.tryParse(s);
}
