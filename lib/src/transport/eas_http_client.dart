/// HTTP transport for EAS protocol.
///
/// Handles POST requests to Microsoft-Server-ActiveSync endpoint
/// with proper headers, base64 command parameters, and policy key management.
library;

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'eas_credentials.dart';

/// Response from an EAS command.
class EasResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List body;

  const EasResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// Whether the response indicates success.
  bool get isSuccess => statusCode == 200;

  /// Whether the server requires provisioning (HTTP 449).
  bool get requiresProvisioning => statusCode == 449;
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

  /// Default timeout for regular commands (Sync, FolderSync, Provision, etc.).
  final Duration commandTimeout;

  /// Extra buffer added to HeartbeatInterval for Ping timeout.
  final Duration pingTimeoutBuffer;

  /// Maximum allowed response body size in bytes (default 25 MB).
  /// Protects against OOM from malicious/compromised servers.
  final int maxResponseSize;

  /// Regex for DeviceId per MS-ASHTTP 2.2.1.1.1.2.3: 1-32 alphanumeric.
  static final _deviceIdPattern = RegExp(r'^[a-zA-Z0-9]{1,32}$');

  /// Regex for DeviceType per MS-ASHTTP 2.2.1.1.1.2.4: 1+ VCHAR (0x21-0x7E).
  static final _deviceTypePattern = RegExp(r'^[\x21-\x7e]+$');

  /// Regex for valid hostname (no path, query, fragment, whitespace).
  static final _hostnamePattern = RegExp(r'^[^\s/?#]+$');

  EasHttpClient({
    required this.server,
    required this.credentials,
    this.protocolVersion = '16.1',
    this.policyKey,
    required this.deviceId,
    this.deviceType = 'FlutterEAS',
    this.commandTimeout = const Duration(seconds: 120),
    this.pingTimeoutBuffer = const Duration(seconds: 120),
    this.maxResponseSize = 25 * 1024 * 1024,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client() {
    if (commandTimeout <= Duration.zero) {
      throw ArgumentError.value(
        commandTimeout, 'commandTimeout', 'Must be > 0',
      );
    }
    if (pingTimeoutBuffer <= Duration.zero) {
      throw ArgumentError.value(
        pingTimeoutBuffer, 'pingTimeoutBuffer', 'Must be > 0',
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
    if (server.isEmpty || !_hostnamePattern.hasMatch(server)) {
      throw ArgumentError.value(
        server,
        'server',
        'Must be a valid hostname without path, query, or fragment',
      );
    }
  }

  /// Send an EAS command with optional WBXML body.
  ///
  /// [timeout] overrides [commandTimeout] for this request (e.g., for Ping).
  ///
  /// Throws [EasResponseTooLargeException] if the response exceeds
  /// [maxResponseSize].
  Future<EasResponse> sendCommand(
    String command,
    Uint8List? wbxmlBody, {
    Duration? timeout,
  }) async {
    final uri = _buildUri(command);

    var headers = <String, String>{
      'Content-Type': 'application/vnd.ms-sync.wbxml',
      'MS-ASProtocolVersion': protocolVersion,
      'User-Agent': 'FlutterEAS/1.0',
    };

    if (policyKey != null) {
      headers['X-MS-PolicyKey'] = policyKey!;
    }

    headers = credentials.applyToHeaders(headers);

    // Retry once on connection-closed errors (stale keep-alive).
    http.StreamedResponse? streamedResponse;
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = http.Request('POST', uri);
      request.headers.addAll(headers);
      if (wbxmlBody != null) {
        request.bodyBytes = wbxmlBody;
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

    // Check Content-Length header early
    final contentLength = streamedResponse!.contentLength;
    if (contentLength != null && contentLength > maxResponseSize) {
      // Drain stream to avoid resource leaks
      await streamedResponse.stream.drain<void>();
      throw EasResponseTooLargeException(contentLength, maxResponseSize);
    }

    // Read body with size enforcement
    final body = await _readBodyWithLimit(
      streamedResponse.stream,
      maxResponseSize,
    );

    return EasResponse(
      statusCode: streamedResponse.statusCode,
      headers: streamedResponse.headers,
      body: body,
    );
  }

  /// Send HTTP OPTIONS request to discover server capabilities.
  Future<EasResponse> sendOptions() async {
    final uri = Uri.https(server, '/Microsoft-Server-ActiveSync');

    var headers = <String, String>{
      'User-Agent': 'FlutterEAS/1.0',
    };
    headers = credentials.applyToHeaders(headers);

    final request = http.Request('OPTIONS', uri);
    request.headers.addAll(headers);

    final streamedResponse = await _httpClient
        .send(request)
        .timeout(commandTimeout);

    final body = await _readBodyWithLimit(
      streamedResponse.stream,
      maxResponseSize,
    );

    return EasResponse(
      statusCode: streamedResponse.statusCode,
      headers: streamedResponse.headers,
      body: body,
    );
  }

  /// Send a raw MIME command (SendMail, SmartReply, SmartForward).
  ///
  /// Per MS-ASCMD, these commands support sending raw MIME with
  /// `Content-Type: message/rfc822` and extra query parameters
  /// instead of WBXML wrapping.
  Future<EasResponse> sendMimeCommand(
    String command,
    Uint8List mimeBody, {
    required String clientId,
    bool saveInSentItems = true,
  }) async {
    final uri = Uri.https(
      server,
      '/Microsoft-Server-ActiveSync',
      {
        'Cmd': command,
        'User': _extractUsername(),
        'DeviceId': deviceId,
        'DeviceType': deviceType,
        'ClientId': clientId,
        if (saveInSentItems) 'SaveInSent': 'T',
      },
    );

    var headers = <String, String>{
      'Content-Type': 'message/rfc822',
      'MS-ASProtocolVersion': protocolVersion,
      'User-Agent': 'FlutterEAS/1.0',
    };

    if (policyKey != null) {
      headers['X-MS-PolicyKey'] = policyKey!;
    }

    headers = credentials.applyToHeaders(headers);

    final request = http.Request('POST', uri);
    request.headers.addAll(headers);
    request.bodyBytes = mimeBody;

    final streamedResponse = await _httpClient
        .send(request)
        .timeout(commandTimeout);

    final body = await _readBodyWithLimit(
      streamedResponse.stream,
      maxResponseSize,
    );

    return EasResponse(
      statusCode: streamedResponse.statusCode,
      headers: streamedResponse.headers,
      body: body,
    );
  }

  /// Build the request URI with plain-text query parameters
  /// per MS-ASHTTP section 2.2.1.1.1.2.
  Uri _buildUri(String command) {
    return Uri.https(
      server,
      '/Microsoft-Server-ActiveSync',
      {
        'Cmd': command,
        'User': _extractUsername(),
        'DeviceId': deviceId,
        'DeviceType': deviceType,
      },
    );
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
