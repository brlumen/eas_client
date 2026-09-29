/// Base class for EAS commands.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../models/eas_global_status.dart';
import '../models/eas_policy.dart';
import '../transport/eas_http_client.dart';
import '../wbxml/wbxml_codec.dart';
import '../wbxml/wbxml_document.dart';

/// Exception thrown when an EAS command fails.
class EasCommandException implements Exception {
  final String command;
  final int? statusCode;
  final int? easStatus;
  final String message;

  EasCommandException({
    required this.command,
    this.statusCode,
    this.easStatus,
    required this.message,
  });

  /// Global status (MS-ASCMD 2.2.2) for [easStatus], if it is one.
  EasGlobalStatus? get globalStatus =>
      easStatus == null ? null : EasGlobalStatus.fromCode(easStatus!);

  /// Whether the client must re-run Provision and retry:
  /// HTTP 449 or global status 142/143/144.
  bool get requiresProvisioning =>
      statusCode == 449 || (globalStatus?.requiresProvisioning ?? false);

  @override
  String toString() =>
      'EasCommandException($command): $message '
      '(HTTP: $statusCode, EAS status: $easStatus)';
}

/// Thrown when the server requests a remote wipe of the device.
///
/// Raised on global status 140 (RemoteWipeRequested), in which case
/// [type] is `null` and the client should run Provision to obtain the
/// wipe directive, or by Provision itself with the concrete [type].
///
/// The library never wipes anything: the consumer performs the wipe and
/// then acknowledges it via `EasClient.acknowledgeRemoteWipe`.
class EasRemoteWipeException implements Exception {
  final String command;

  /// Wipe directive from Provision; `null` for global status 140.
  final RemoteWipeType? type;

  EasRemoteWipeException({required this.command, this.type});

  @override
  String toString() =>
      'EasRemoteWipeException($command): '
      'Server requests remote wipe${type == null ? '' : ' (${type!.name})'}';
}

/// Thrown on HTTP 401 (Unauthorized) — credentials invalid or expired.
///
/// For OAuth: the access token likely needs refresh.
/// For Basic Auth: username/password are wrong.
class EasAuthException implements Exception {
  final String command;

  EasAuthException({required this.command});

  @override
  String toString() =>
      'EasAuthException($command): '
      'Authentication failed (HTTP 401)';
}

/// Thrown on HTTP 403 (Forbidden) — authenticated but not authorized.
///
/// Common causes: EAS disabled for the user, mailbox not provisioned,
/// or tenant policy blocks the device.
class EasForbiddenException implements Exception {
  final String command;

  EasForbiddenException({required this.command});

  @override
  String toString() =>
      'EasForbiddenException($command): '
      'Access denied (HTTP 403)';
}

/// Thrown when the server accepts a Provision acknowledgement with a
/// non-success [ackStatus] but returns no final PolicyKey: it does not
/// allow devices that don't apply its policies (Exchange
/// `AllowNonProvisionableDevices = false`). Re-provision with
/// [PolicyAckStatus.success] once the policies are applied.
class EasPolicyNotAcceptedException implements Exception {
  final PolicyAckStatus ackStatus;

  EasPolicyNotAcceptedException({required this.ackStatus});

  @override
  String toString() =>
      'EasPolicyNotAcceptedException(Provision): server requires applied '
      'policies (ack ${ackStatus.code} rejected)';
}

/// Thrown on HTTP 451 — server requests redirect to a new URL.
///
/// Per MS-ASCMD 2.2.4, the client MUST re-issue the request to
/// the URL specified in the X-MS-Location header.
///
/// The [redirectUrl] is validated: HTTPS-only, valid hostname.
class EasRedirectException implements Exception {
  final String command;

  /// New server URL from X-MS-Location header (HTTPS, validated).
  final String redirectUrl;

  /// Extracted hostname from [redirectUrl].
  final String newServer;

  EasRedirectException({
    required this.command,
    required this.redirectUrl,
    required this.newServer,
  });

  @override
  String toString() =>
      'EasRedirectException($command): '
      'Server requests redirect (HTTP 451)';
}

/// Thrown on HTTP 503 (Service Unavailable) — server busy or the client
/// is throttled (MS-ASHTTP 3.1.5.2.3).
///
/// Retry after [retryAfter] (from `Retry-After`) or, if absent, after a
/// few seconds with exponential back-off.
class EasServiceUnavailableException implements Exception {
  final String command;

  /// Delay requested by the server's `Retry-After` header.
  final Duration? retryAfter;

  /// `X-MS-ASThrottle` value, if any.
  final String? throttle;

  EasServiceUnavailableException({
    required this.command,
    this.retryAfter,
    this.throttle,
  });

  @override
  String toString() {
    final retry = retryAfter == null
        ? ''
        : ', retry after ${retryAfter!.inSeconds}s';
    return 'EasServiceUnavailableException($command): HTTP 503$retry';
  }
}

/// Thrown on HTTP 456 (account blocked) or 457 (password expired)
/// (MS-ASHTTP 3.1.5.2.4). The client should stop sending requests.
class EasAccountException implements Exception {
  final String command;

  /// 456 = blocked, 457 = password expired.
  final int statusCode;

  /// Password reset site (`X-MS-Credential-Service-Url`, HTTPS only).
  final Uri? credentialServiceUrl;

  EasAccountException({
    required this.command,
    required this.statusCode,
    this.credentialServiceUrl,
  });

  /// Whether the account is blocked (HTTP 456).
  bool get isBlocked => statusCode == 456;

  /// Whether the password has expired (HTTP 457).
  bool get isPasswordExpired => statusCode == 457;

  @override
  String toString() =>
      'EasAccountException($command): '
      '${isBlocked ? 'Account blocked' : 'Password expired'} '
      '(HTTP $statusCode)';
}

/// Base class for all EAS commands.
abstract class EasCommand<T> {
  final WbxmlEncoder _encoder = WbxmlEncoder();
  final WbxmlDecoder _decoder = WbxmlDecoder();

  /// Command name (e.g., 'FolderSync', 'Sync', 'Provision').
  String get commandName;

  /// Build the WBXML request document.
  WbxmlDocument buildRequest();

  /// Build the request for a specific protocol version. Override when the
  /// request format depends on the version; defaults to [buildRequest].
  WbxmlDocument buildRequestFor(String protocolVersion) => buildRequest();

  /// Encode the HTTP request body; `null` sends no body.
  Uint8List? encodeRequest(String protocolVersion) =>
      _encoder.encode(buildRequestFor(protocolVersion));

  /// Parse the WBXML response into a typed result.
  T parseResponse(WbxmlDocument response);

  /// Result for a successful response with an empty body. Throws by
  /// default; override for commands where it means success.
  T parseEmptyResponse() => throw EasCommandException(
    command: commandName,
    statusCode: 200,
    message: 'Empty response body',
  );

  /// Extra HTTP request headers for this command (none by default).
  Map<String, String>? get extraHeaders => null;

  /// Command-specific URI parameters (MS-ASHTTP 2.2.1.1.1.2.5).
  Map<String, String> requestParameters(String protocolVersion) => const {};

  /// `Content-Type` of the request body.
  String requestContentType(String protocolVersion) => easWbxmlContentType;

  /// Request a multipart response (`MS-ASAcceptMultiPart` header or the
  /// base64 `Options` flag).
  bool get acceptMultiPart => false;

  /// `SaveInSent` URI parameter / base64 `Options` flag.
  bool saveInSentParameter(String protocolVersion) => false;

  /// Parse a successful, non-empty HTTP response. Override for non-WBXML
  /// bodies (e.g. multipart ItemOperations responses).
  T parseHttpResponse(EasResponse response) {
    final doc = _decoder.decode(response.body);
    checkGlobalStatus(doc);
    return parseResponse(doc);
  }

  /// Throw on a global status (>= 101, MS-ASCMD 2.2.2) in the root
  /// element's direct `Status` child. Command-specific codes (< 101) are
  /// left to [parseResponse].
  ///
  /// - 140 → [EasRemoteWipeException]
  /// - 142/143/144 → [EasCommandException] with
  ///   [EasCommandException.requiresProvisioning] (same signal as HTTP 449)
  /// - others → [EasCommandException] with [EasCommandException.easStatus]
  @visibleForTesting
  void checkGlobalStatus(WbxmlDocument response) {
    final root = response.root;
    final code = int.tryParse(root.childText(root.namespace, 'Status') ?? '');
    if (code == null || code < EasGlobalStatus.minCode) return;

    final status = EasGlobalStatus.fromCode(code);
    if (status == EasGlobalStatus.remoteWipeRequested) {
      throw EasRemoteWipeException(command: commandName);
    }
    throw EasCommandException(
      command: commandName,
      statusCode: 200,
      easStatus: code,
      message: status == null
          ? 'Unknown global status'
          : status.requiresProvisioning
          ? 'Server requires provisioning (${status.description}). '
                'Run Provision command first.'
          : status.description,
    );
  }

  /// Map a non-success HTTP [response] to an exception (MS-ASHTTP
  /// 3.1.5.2, MS-ASCMD 2.2.4).
  @visibleForTesting
  Exception httpError(EasResponse response) {
    switch (response.statusCode) {
      case 449:
        return EasCommandException(
          command: commandName,
          statusCode: 449,
          message:
              'Server requires provisioning. '
              'Run Provision command first.',
        );
      case 401:
        return EasAuthException(command: commandName);
      case 403:
        return EasForbiddenException(command: commandName);
      case 451:
        final uri = Uri.tryParse(response.headers['x-ms-location'] ?? '');
        if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) {
          return EasRedirectException(
            command: commandName,
            redirectUrl: uri.toString(),
            newServer: uri.host,
          );
        }
        return EasCommandException(
          command: commandName,
          statusCode: 451,
          message:
              'Server requests redirect but X-MS-Location '
              'header is missing or invalid',
        );
      case 503:
        return EasServiceUnavailableException(
          command: commandName,
          retryAfter: response.retryAfter,
          throttle: response.throttle,
        );
      case 456:
      case 457:
        return EasAccountException(
          command: commandName,
          statusCode: response.statusCode,
          credentialServiceUrl: response.credentialServiceUrl,
        );
    }
    return EasCommandException(
      command: commandName,
      statusCode: response.statusCode,
      message: switch (response.statusCode) {
        400 => 'Bad request (HTTP 400)',
        404 => 'Not found (HTTP 404)',
        500 => 'Internal server error (HTTP 500)',
        501 => 'Not implemented (HTTP 501)',
        502 => 'Proxy error (HTTP 502)',
        507 => 'Mailbox full (HTTP 507)',
        final code => 'HTTP error $code',
      },
    );
  }

  /// Execute this command against the server.
  ///
  /// [timeout] overrides the default [EasHttpClient.commandTimeout].
  Future<T> execute(EasHttpClient client, {Duration? timeout}) async {
    final version = client.protocolVersion;
    final response = await client.sendCommand(
      commandName,
      encodeRequest(version),
      timeout: timeout,
      extraHeaders: extraHeaders,
      parameters: requestParameters(version),
      contentType: requestContentType(version),
      saveInSent: saveInSentParameter(version),
      acceptMultiPart: acceptMultiPart,
    );

    if (!response.isSuccess) throw httpError(response);
    if (response.body.isEmpty) return parseEmptyResponse();
    return parseHttpResponse(response);
  }
}
