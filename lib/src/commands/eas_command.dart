/// Base class for EAS commands.
library;

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

  @override
  String toString() =>
      'EasCommandException($command): $message '
      '(HTTP: $statusCode, EAS status: $easStatus)';
}

/// Thrown on HTTP 401 (Unauthorized) — credentials invalid or expired.
///
/// For OAuth: the access token likely needs refresh.
/// For Basic Auth: username/password are wrong.
class EasAuthException implements Exception {
  final String command;

  EasAuthException({required this.command});

  @override
  String toString() => 'EasAuthException($command): '
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
  String toString() => 'EasForbiddenException($command): '
      'Access denied (HTTP 403)';
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
  String toString() => 'EasRedirectException($command): '
      'Server requests redirect (HTTP 451)';
}

/// Base class for all EAS commands.
abstract class EasCommand<T> {
  final WbxmlEncoder _encoder = WbxmlEncoder();
  final WbxmlDecoder _decoder = WbxmlDecoder();

  /// Command name (e.g., 'FolderSync', 'Sync', 'Provision').
  String get commandName;

  /// Build the WBXML request document.
  WbxmlDocument buildRequest();

  /// Parse the WBXML response into a typed result.
  T parseResponse(WbxmlDocument response);

  /// Execute this command against the server.
  ///
  /// [timeout] overrides the default [EasHttpClient.commandTimeout].
  Future<T> execute(EasHttpClient client, {Duration? timeout}) async {
    final requestDoc = buildRequest();
    final requestBytes = _encoder.encode(requestDoc);

    final response = await client.sendCommand(
      commandName,
      requestBytes,
      timeout: timeout,
    );

    if (response.requiresProvisioning) {
      throw EasCommandException(
        command: commandName,
        statusCode: 449,
        message: 'Server requires provisioning. '
            'Run Provision command first.',
      );
    }

    // HTTP 401 — credentials invalid or expired (MS-ASCMD)
    if (response.statusCode == 401) {
      throw EasAuthException(command: commandName);
    }

    // HTTP 403 — authenticated but not authorized (MS-ASCMD)
    if (response.statusCode == 403) {
      throw EasForbiddenException(command: commandName);
    }

    // HTTP 451 — redirect to new server (MS-ASCMD 2.2.4)
    if (response.statusCode == 451) {
      final location = response.headers['x-ms-location'];
      if (location != null) {
        final uri = Uri.tryParse(location);
        if (uri != null &&
            uri.scheme == 'https' &&
            uri.host.isNotEmpty) {
          throw EasRedirectException(
            command: commandName,
            redirectUrl: location,
            newServer: uri.host,
          );
        }
      }
      throw EasCommandException(
        command: commandName,
        statusCode: 451,
        message: 'Server requests redirect but X-MS-Location '
            'header is missing or invalid',
      );
    }

    if (!response.isSuccess) {
      throw EasCommandException(
        command: commandName,
        statusCode: response.statusCode,
        message: 'HTTP error ${response.statusCode}',
      );
    }

    if (response.body.isEmpty) {
      throw EasCommandException(
        command: commandName,
        statusCode: response.statusCode,
        message: 'Empty response body',
      );
    }

    final responseDoc = _decoder.decode(response.body);
    return parseResponse(responseDoc);
  }
}
