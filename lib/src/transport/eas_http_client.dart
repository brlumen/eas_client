/// HTTP transport for EAS protocol.
///
/// Handles POST requests to Microsoft-Server-ActiveSync endpoint
/// with proper headers, base64 command parameters, and policy key management.
///
/// Reference: MS-ASHTTP
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'eas_credentials.dart';

/// Content type of a WBXML request/response body.
const easWbxmlContentType = 'application/vnd.ms-sync.wbxml';

/// Content type of a raw MIME request body (SendMail/SmartReply/
/// SmartForward with protocol versions 2.5-12.1).
const easMimeContentType = 'message/rfc822';

/// Response from an EAS command.
class EasResponse {
  final int statusCode;

  /// Response headers (lower-case names).
  final Map<String, String> headers;
  final Uint8List body;

  const EasResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// Whether the response indicates success (2xx, MS-ASHTTP 3.1.5.1).
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Whether the server requires provisioning (HTTP 449).
  bool get requiresProvisioning => statusCode == 449;

  String? _header(String name) {
    final v = headers[name]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  static List<String>? _list(String? value) => value
      ?.split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  /// `Content-Type` header.
  String? get contentType => _header('content-type');

  /// `MS-Server-ActiveSync` — server implementation version.
  String? get serverVersion => _header('ms-server-activesync');

  /// `X-MS-RP` — the client MUST discard local data and resynchronize;
  /// the value lists the protocol versions the server supports
  /// (MS-ASHTTP 2.2.2.1.2.9).
  List<String>? get resyncVersions => _list(_header('x-ms-rp'));

  /// `MS-ASProtocolCommands` — commands supported by the server.
  List<String>? get protocolCommands => _list(_header('ms-asprotocolcommands'));

  /// `MS-ASProtocolVersions` — protocol versions supported by the server.
  List<String>? get protocolVersions => _list(_header('ms-asprotocolversions'));

  /// `X-MS-Credentials-Expire` — days until the password expires
  /// (0 = less than 24 hours).
  int? get credentialsExpireDays =>
      int.tryParse(_header('x-ms-credentials-expire') ?? '');

  /// `X-MS-Credential-Service-Url` — password reset site (HTTPS only;
  /// other schemes are ignored).
  Uri? get credentialServiceUrl {
    final uri = Uri.tryParse(_header('x-ms-credential-service-url') ?? '');
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? uri
        : null;
  }

  /// `X-MS-ASThrottle` — throttling condition.
  String? get throttle => _header('x-ms-asthrottle');

  /// `Retry-After` (delta-seconds or HTTP-date), used with HTTP 503.
  Duration? get retryAfter {
    final value = _header('retry-after');
    if (value == null) return null;
    final seconds = int.tryParse(value);
    if (seconds != null) return seconds < 0 ? null : Duration(seconds: seconds);
    final date = _parseHttpDate(value);
    if (date == null) return null;
    final diff = date.difference(DateTime.now().toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  static const _months = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  /// Parse an RFC 7231 IMF-fixdate (`Sun, 06 Nov 1994 08:49:37 GMT`).
  static DateTime? _parseHttpDate(String value) {
    final m = RegExp(
      r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(value);
    if (m == null) return null;
    final month = _months.indexOf(m.group(2)!.toLowerCase()) + 1;
    if (month == 0) return null;
    int g(int i) => int.parse(m.group(i)!);
    return DateTime.utc(g(3), month, g(1), g(4), g(5), g(6));
  }
}

/// Server-side signals carried by response headers (MS-ASHTTP 2.2.2.1.2).
///
/// Emitted on [EasHttpClient.notices] whenever a response contains at
/// least one of these headers.
class EasServerNotice {
  /// Command that received the response.
  final String command;

  /// `X-MS-RP`: when non-null the client MUST reinitialize its
  /// synchronization state (MS-ASHTTP 3.1.5.1) — except after a
  /// FolderSync with SyncKey 0.
  final List<String>? resyncVersions;

  /// `MS-ASProtocolCommands` returned in a POST response: the server
  /// requires the client to reinitialize its synchronization state.
  final List<String>? protocolCommands;

  /// `MS-ASProtocolVersions` returned in a POST response.
  final List<String>? protocolVersions;

  /// `X-MS-Credentials-Expire`: days until the password expires.
  final int? credentialsExpireDays;

  /// `X-MS-Credential-Service-Url` (HTTPS only).
  final Uri? credentialServiceUrl;

  /// `X-MS-ASThrottle`.
  final String? throttle;

  const EasServerNotice({
    required this.command,
    this.resyncVersions,
    this.protocolCommands,
    this.protocolVersions,
    this.credentialsExpireDays,
    this.credentialServiceUrl,
    this.throttle,
  });

  /// Whether the client must reinitialize its synchronization state.
  bool get requiresResync =>
      resyncVersions != null ||
      protocolCommands != null ||
      protocolVersions != null;

  /// Build from [response]; `null` if it carries no notice header.
  static EasServerNotice? fromResponse(String command, EasResponse response) {
    final notice = EasServerNotice(
      command: command,
      resyncVersions: response.resyncVersions,
      protocolCommands: response.protocolCommands,
      protocolVersions: response.protocolVersions,
      credentialsExpireDays: response.credentialsExpireDays,
      credentialServiceUrl: response.credentialServiceUrl,
      throttle: response.throttle,
    );
    final empty =
        !notice.requiresResync &&
        notice.credentialsExpireDays == null &&
        notice.credentialServiceUrl == null &&
        notice.throttle == null;
    return empty ? null : notice;
  }

  @override
  String toString() => 'EasServerNotice($command, resync: $requiresResync)';
}

/// HTTP client for EAS protocol communication.
class EasHttpClient {
  final String server;
  final EasCredentials credentials;
  final http.Client _httpClient;

  /// EAS protocol version (e.g., '16.1').
  String protocolVersion;

  /// Policy key from Provision command. Required for most commands.
  ///
  /// Set internally by [ProvisionCommand]. Consumers should not
  /// modify this directly — use [ProvisionCommand.execute] instead.
  String? policyKey;

  /// Device ID (unique identifier for this device).
  final String deviceId;

  /// Device type (e.g., 'FlutterEAS').
  final String deviceType;

  /// `User-Agent` header (MS-ASHTTP 2.2.1.1.2.7). Should not change
  /// between requests.
  final String userAgent;

  /// `Accept-Language` header: locale for Search/Find queries
  /// (MS-ASHTTP 2.2.1.1.2.1). Not sent when `null`.
  String? acceptLanguage;

  /// Default timeout for regular commands (Sync, FolderSync, Provision, etc.).
  final Duration commandTimeout;

  /// Extra buffer added to HeartbeatInterval for Ping timeout.
  final Duration pingTimeoutBuffer;

  /// Maximum allowed response body size in bytes (default 25 MB).
  /// Protects against OOM from malicious/compromised servers.
  final int maxResponseSize;

  /// Encode command query parameters as a base64 byte sequence
  /// (MS-ASHTTP 2.2.1.1.1.1) instead of plain text. Default `false`.
  ///
  /// Ignored (plain text is used) for protocol versions 2.5 and 12.0,
  /// which do not support it, and when a parameter does not fit.
  final bool useBase64QueryString;

  /// Server version from the last `MS-Server-ActiveSync` header.
  String? serverVersion;

  final _notices = StreamController<EasServerNotice>.broadcast();

  /// Cookies set by the server (`Set-Cookie` → `Cookie`, MS-ASHTTP
  /// 2.2.1.1.2.4). Kept in memory only.
  final Map<String, String> _cookies = {};

  static const _maxCookies = 32;
  static const _maxCookieLength = 4096;

  /// Command codes for the base64 query (MS-ASHTTP 2.2.1.1.1.1.2).
  static const _commandCodes = <String, int>{
    'Sync': 0,
    'SendMail': 1,
    'SmartForward': 2,
    'SmartReply': 3,
    'GetAttachment': 4,
    'FolderSync': 9,
    'FolderCreate': 10,
    'FolderDelete': 11,
    'FolderUpdate': 12,
    'MoveItems': 13,
    'GetItemEstimate': 14,
    'MeetingResponse': 15,
    'Search': 16,
    'Settings': 17,
    'Ping': 18,
    'ItemOperations': 19,
    'Provision': 20,
    'ResolveRecipients': 21,
    'ValidateCert': 22,
    'Find': 23,
  };

  /// Command parameter tags (MS-ASHTTP 2.2.1.1.1.1.3).
  static const _paramTags = <String, int>{
    'AttachmentName': 0,
    'CollectionId': 1,
    'ItemId': 3,
    'LongId': 4,
    'Occurrence': 6,
  };

  /// Locale for the base64 query: en-US (MS-LCID 0x0409).
  static const _base64Locale = 0x0409;

  /// Command parameter tag `Options` (MS-ASHTTP 2.2.1.1.1.1.3).
  static const _optionsParamTag = 7;

  /// Command parameter tag `User` (MS-ASHTTP 2.2.1.1.1.1.3).
  static const _userParamTag = 8;

  /// `Options` flags (MS-ASHTTP 2.2.1.1.1.1.3).
  static const _optSaveInSent = 0x01;
  static const _optAcceptMultiPart = 0x02;

  /// Max length of a length-prefixed field in the base64 query.
  static const _maxFieldLength = 255;

  /// Regex for DeviceId per MS-ASHTTP 2.2.1.1.1.2.3: 1-32 alphanumeric.
  static final _deviceIdPattern = RegExp(r'^[a-zA-Z0-9]{1,32}$');

  /// Regex for DeviceType per MS-ASHTTP 2.2.1.1.1.2.4: 1+ VCHAR (0x21-0x7E).
  static final _deviceTypePattern = RegExp(r'^[\x21-\x7e]+$');

  /// Header value: printable ASCII and space (no CR/LF injection).
  static final _headerValuePattern = RegExp(r'^[\x20-\x7e]+$');

  /// Regex for valid hostname (no path, query, fragment, whitespace).
  static final _hostnamePattern = RegExp(r'^[^\s/?#]+$');

  EasHttpClient({
    required this.server,
    required this.credentials,
    this.protocolVersion = '16.1',
    this.policyKey,
    required this.deviceId,
    this.deviceType = 'FlutterEAS',
    this.userAgent = 'FlutterEAS/1.0',
    this.acceptLanguage,
    this.commandTimeout = const Duration(seconds: 120),
    this.pingTimeoutBuffer = const Duration(seconds: 120),
    this.maxResponseSize = 25 * 1024 * 1024,
    this.useBase64QueryString = false,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client() {
    if (commandTimeout <= Duration.zero) {
      throw ArgumentError.value(
        commandTimeout,
        'commandTimeout',
        'Must be > 0',
      );
    }
    if (pingTimeoutBuffer <= Duration.zero) {
      throw ArgumentError.value(
        pingTimeoutBuffer,
        'pingTimeoutBuffer',
        'Must be > 0',
      );
    }
    if (!_deviceIdPattern.hasMatch(deviceId)) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'Must be 1-32 alphanumeric characters (MS-ASHTTP 2.2.1.1.1.2.3)',
      );
    }
    if (!_deviceTypePattern.hasMatch(deviceType)) {
      throw ArgumentError.value(
        deviceType,
        'deviceType',
        'Must be printable ASCII (MS-ASHTTP 2.2.1.1.1.2.4)',
      );
    }
    if (!_headerValuePattern.hasMatch(userAgent)) {
      throw ArgumentError.value(
        userAgent,
        'userAgent',
        'Must be printable ASCII without CR/LF',
      );
    }
    if (useBase64QueryString && deviceType.length > _maxFieldLength) {
      throw ArgumentError.value(
        deviceType,
        'deviceType',
        'Must be at most $_maxFieldLength characters for base64 query '
            '(MS-ASHTTP 2.2.1.1.1.1)',
      );
    }
    if (server.isEmpty || !_hostnamePattern.hasMatch(server)) {
      throw ArgumentError.value(
        server,
        'server',
        'Must be a valid hostname without path, query, or fragment',
      );
    }
  }

  /// Server notices (resync required, password expiry, throttling)
  /// extracted from response headers.
  Stream<EasServerNotice> get notices => _notices.stream;

  /// Send an EAS command with optional request body.
  ///
  /// [timeout] overrides [commandTimeout] for this request (e.g., for Ping).
  ///
  /// [parameters] are command-specific URI parameters (MS-ASHTTP
  /// 2.2.1.1.1.2.5): AttachmentName, CollectionId, ItemId, LongId,
  /// Occurrence. [saveInSent] and [acceptMultiPart] map to the
  /// `SaveInSent` parameter / `MS-ASAcceptMultiPart` header, or to the
  /// `Options` flags of a base64 query.
  ///
  /// [extraHeaders] are added first, so they can never override protocol,
  /// policy or credential headers.
  ///
  /// Throws [EasResponseTooLargeException] if the response exceeds
  /// [maxResponseSize].
  Future<EasResponse> sendCommand(
    String command,
    Uint8List? body, {
    Duration? timeout,
    Map<String, String>? extraHeaders,
    Map<String, String> parameters = const {},
    String contentType = easWbxmlContentType,
    bool saveInSent = false,
    bool acceptMultiPart = false,
  }) async {
    for (final name in parameters.keys) {
      if (!_paramTags.containsKey(name)) {
        throw ArgumentError.value(name, 'parameters', 'Unknown parameter');
      }
    }
    final base64Query = _base64QueryOrNull(
      command,
      parameters,
      saveInSent: saveInSent,
      acceptMultiPart: acceptMultiPart,
    );
    final uri = base64Query != null
        ? Uri(
            scheme: 'https',
            host: server,
            path: '/Microsoft-Server-ActiveSync',
            query: base64Query,
          )
        : Uri.https(server, '/Microsoft-Server-ActiveSync', {
            'Cmd': command,
            'User': _extractUsername(),
            'DeviceId': deviceId,
            'DeviceType': deviceType,
            ...parameters,
            if (saveInSent) 'SaveInSent': 'T',
          });

    // Base64 query carries version, policy key and options itself
    // (MS-ASHTTP 2.2.1.1.2.5, 2.2.1.1.2.6, 2.2.1.1.2.8).
    final base64 = base64Query != null;
    final encodedKey = base64 && _numericPolicyKey != null;
    final headers = credentials.applyToHeaders({
      ...?extraHeaders,
      ..._commonHeaders(),
      'Content-Type': contentType,
      if (!base64) 'MS-ASProtocolVersion': protocolVersion,
      if (policyKey != null && !encodedKey) 'X-MS-PolicyKey': policyKey!,
      if (acceptMultiPart && !base64) 'MS-ASAcceptMultiPart': 'T',
    });

    // Retry once on connection-closed errors (stale keep-alive).
    http.StreamedResponse? streamedResponse;
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = http.Request('POST', uri);
      request.headers.addAll(headers);
      if (body != null) {
        request.bodyBytes = body;
      }
      // Disable keep-alive on retry to force a fresh connection.
      if (attempt > 0) {
        request.persistentConnection = false;
      }

      try {
        streamedResponse = await _httpClient
            .send(request)
            .timeout(timeout ?? commandTimeout);
        break;
      } on http.ClientException catch (e) {
        if (attempt == 0 && e.message.contains('Connection closed')) {
          continue;
        }
        rethrow;
      }
    }

    final response = await _readResponse(streamedResponse!);
    final notice = EasServerNotice.fromResponse(command, response);
    if (notice != null) _notices.add(notice);
    return response;
  }

  /// Send HTTP OPTIONS request to discover server capabilities.
  Future<EasResponse> sendOptions() async {
    final uri = Uri.https(server, '/Microsoft-Server-ActiveSync');
    final request = http.Request('OPTIONS', uri);
    request.headers.addAll(credentials.applyToHeaders(_commonHeaders()));

    final streamedResponse = await _httpClient
        .send(request)
        .timeout(commandTimeout);
    return _readResponse(streamedResponse);
  }

  /// Send a raw MIME command (SendMail, SmartReply, SmartForward) as used
  /// with protocol versions 2.5, 12.0 and 12.1 (`Content-Type:
  /// message/rfc822`, source identified by URI [parameters]).
  Future<EasResponse> sendMimeCommand(
    String command,
    Uint8List mimeBody, {
    Map<String, String> parameters = const {},
    bool saveInSentItems = true,
  }) => sendCommand(
    command,
    mimeBody,
    parameters: parameters,
    contentType: easMimeContentType,
    saveInSent: saveInSentItems,
  );

  Map<String, String> _commonHeaders() => {
    'User-Agent': userAgent,
    if (acceptLanguage != null && _headerValuePattern.hasMatch(acceptLanguage!))
      'Accept-Language': acceptLanguage!,
    if (_cookies.isNotEmpty)
      'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
  };

  Future<EasResponse> _readResponse(http.StreamedResponse streamed) async {
    // Check Content-Length header early
    final contentLength = streamed.contentLength;
    if (contentLength != null && contentLength > maxResponseSize) {
      // Drain stream to avoid resource leaks
      await streamed.stream.drain<void>();
      throw EasResponseTooLargeException(contentLength, maxResponseSize);
    }

    final body = await _readBodyWithLimit(streamed.stream, maxResponseSize);
    final headers = {
      for (final e in streamed.headers.entries) e.key.toLowerCase(): e.value,
    };
    _storeCookies(headers['set-cookie']);
    final response = EasResponse(
      statusCode: streamed.statusCode,
      headers: headers,
      body: body,
    );
    serverVersion = response.serverVersion ?? serverVersion;
    return response;
  }

  /// Store `name=value` pairs of (possibly comma-joined) `Set-Cookie`
  /// headers. Attributes are ignored; `Max-Age=0` or an empty value
  /// removes the cookie. Count and size are bounded.
  void _storeCookies(String? header) {
    if (header == null) return;
    for (final cookie in header.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
      final parts = cookie.split(';');
      final pair = parts.first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0 || pair.length > _maxCookieLength) continue;
      final name = pair.substring(0, eq).trim();
      final value = pair.substring(eq + 1).trim();
      if (!_headerValuePattern.hasMatch(pair) || name.contains(' ')) continue;
      final expired = parts
          .skip(1)
          .any(
            (a) => a.trim().toLowerCase().replaceAll(' ', '') == 'max-age=0',
          );
      if (value.isEmpty || expired) {
        _cookies.remove(name);
      } else if (_cookies.containsKey(name) || _cookies.length < _maxCookies) {
        _cookies[name] = value;
      }
    }
  }

  /// Names of the cookies currently held (values are not exposed).
  @visibleForTesting
  Iterable<String> get cookieNames => _cookies.keys;

  /// Base64 query is not supported by protocol versions 2.5 and 12.0.
  bool get _supportsBase64Query =>
      protocolVersion != '2.5' && protocolVersion != '12.0';

  int? get _numericPolicyKey {
    final key = int.tryParse(policyKey ?? '');
    return key != null && key >= 0 && key <= 0xffffffff ? key : null;
  }

  String? _base64QueryOrNull(
    String command,
    Map<String, String> parameters, {
    required bool saveInSent,
    required bool acceptMultiPart,
  }) {
    if (!useBase64QueryString ||
        !_supportsBase64Query ||
        !_commandCodes.containsKey(command) ||
        parameters.values.any((v) => utf8.encode(v).length > _maxFieldLength)) {
      return null;
    }
    return buildBase64Query(
      command,
      parameters: parameters,
      saveInSent: saveInSent,
      acceptMultiPart: acceptMultiPart,
    );
  }

  /// Encode the base64 query value (MS-ASHTTP 2.2.1.1.1.1) for [command].
  ///
  /// Layout: protocol version (1 byte, e.g. 161), command code (1),
  /// locale (2, little-endian), DeviceId length + bytes, policy key
  /// length (0|4) + uint32 little-endian, DeviceType length + bytes,
  /// then encoded parameters (tag, length, value): command [parameters],
  /// `Options` flags and `User`.
  ///
  /// A non-numeric policy key is omitted from the byte sequence (it is
  /// then sent in the `X-MS-PolicyKey` header). A `User` value longer
  /// than 255 bytes is omitted (it is only used for server logging).
  @visibleForTesting
  String buildBase64Query(
    String command, {
    Map<String, String> parameters = const {},
    bool saveInSent = false,
    bool acceptMultiPart = false,
  }) {
    final code = _commandCodes[command];
    if (code == null) {
      throw ArgumentError.value(
        command,
        'command',
        'No base64 command code (MS-ASHTTP 2.2.1.1.1.1.2)',
      );
    }
    final version = int.tryParse(protocolVersion.replaceAll('.', ''));
    if (version == null || version < 0 || version > 0xff) {
      throw StateError('Unsupported protocol version for base64 query');
    }

    final bytes = BytesBuilder()
      ..addByte(version)
      ..addByte(code)
      ..addByte(_base64Locale & 0xff)
      ..addByte(_base64Locale >> 8);

    // DeviceId/DeviceType are validated ASCII in the constructor.
    _addField(bytes, ascii.encode(deviceId));

    final key = _numericPolicyKey;
    if (key != null) {
      bytes
        ..addByte(4)
        ..add(
          (ByteData(4)..setUint32(0, key, Endian.little)).buffer.asUint8List(),
        );
    } else {
      bytes.addByte(0);
    }

    _addField(bytes, ascii.encode(deviceType));

    for (final e in parameters.entries) {
      final tag = _paramTags[e.key];
      final value = utf8.encode(e.value);
      if (tag == null || value.length > _maxFieldLength) {
        throw ArgumentError.value(e.key, 'parameters', 'Cannot be encoded');
      }
      bytes.addByte(tag);
      _addField(bytes, value);
    }

    final options =
        (saveInSent ? _optSaveInSent : 0) |
        (acceptMultiPart ? _optAcceptMultiPart : 0);
    if (options != 0) {
      bytes
        ..addByte(_optionsParamTag)
        ..addByte(1)
        ..addByte(options);
    }

    final user = utf8.encode(_extractUsername());
    if (user.isNotEmpty && user.length <= _maxFieldLength) {
      bytes.addByte(_userParamTag);
      _addField(bytes, user);
    }

    return base64.encode(bytes.toBytes());
  }

  static void _addField(BytesBuilder bytes, List<int> value) {
    bytes
      ..addByte(value.length)
      ..add(value);
  }

  String _extractUsername() {
    if (credentials is BasicCredentials) {
      return (credentials as BasicCredentials).username;
    }
    return '';
  }

  /// Read streamed body enforcing [limit] bytes.
  static Future<Uint8List> _readBodyWithLimit(
    http.ByteStream stream,
    int limit,
  ) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in stream) {
      total += chunk.length;
      if (total > limit) {
        throw EasResponseTooLargeException(total, limit);
      }
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  /// Dispose of the HTTP client.
  void dispose() {
    _httpClient.close();
    _notices.close();
  }
}

/// Thrown when server response exceeds [EasHttpClient.maxResponseSize].
class EasResponseTooLargeException implements Exception {
  final int actualSize;
  final int maxSize;

  EasResponseTooLargeException(this.actualSize, this.maxSize);

  @override
  String toString() =>
      'EasResponseTooLargeException: response size ($actualSize) '
      'exceeds limit ($maxSize)';
}
