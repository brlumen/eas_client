/// ComposeMail commands — SendMail plus the shared base for
/// SmartReply/SmartForward.
///
/// Protocol versions 14.0+ send a WBXML request with the MIME content as
/// opaque data; 2.5-12.1 send the raw MIME (`message/rfc822`) with the
/// source identified by URI parameters (MS-ASHTTP 2.2.1.1.1.2.5).
///
/// HTTP 200 with an empty body means success; a WBXML body carries a
/// failure `Status` (global codes, MS-ASCMD 2.2.2), e.g. 117 = reply not
/// allowed.
///
/// Reference: MS-ASCMD sections 2.2.1.17, 2.2.1.19, 2.2.1.20
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/eas_global_status.dart';
import '../models/wbxml_helpers.dart' show isoDateTime, protocolVersionValue;
import '../transport/eas_http_client.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'ComposeMail';

/// Base class for ComposeMail commands (SendMail, SmartReply, SmartForward).
abstract class ComposeMailCommand extends EasCommand<void> {
  /// Unique client-generated ID (1-40 characters) to prevent duplicate
  /// sends (status 118).
  final String clientId;

  /// MIME content of the message (headers + body); `null` only for a
  /// SmartForward of a meeting with Forwardees/Body.
  final String? mimeContent;

  /// Whether to save the message in Sent Items.
  final bool saveInSentItems;

  /// IRM template to protect the message with
  /// (`RightsManagement:TemplateID`, EAS 14.1+).
  final String? templateId;

  /// Account to send from (`AccountId`, EAS 14.1+), as returned by
  /// Settings UserInformation.
  final String? accountId;

  ComposeMailCommand({
    required this.clientId,
    required String this.mimeContent,
    this.saveInSentItems = true,
    this.templateId,
    this.accountId,
  }) {
    checkLength(clientId, 40, 'clientId');
    validateMimeHeaders(mimeContent!);
  }

  /// Constructor for requests without MIME content.
  ComposeMailCommand.withoutMime({required this.clientId, this.accountId})
    : mimeContent = null,
      saveInSentItems = false,
      templateId = null {
    checkLength(clientId, 40, 'clientId');
  }

  /// Validates MIME headers do not contain bare CR or LF (header injection).
  ///
  /// Checks only the header section (before the first \r\n\r\n separator).
  /// Bare \r or \n within a header line indicates injection attempt.
  static void validateMimeHeaders(String mime) {
    final headerEnd = mime.indexOf('\r\n\r\n');
    final headers = headerEnd >= 0 ? mime.substring(0, headerEnd) : mime;
    for (final line in headers.split('\r\n')) {
      if (line.contains('\r') || line.contains('\n')) {
        throw ArgumentError.value(
          '(content hidden)',
          'mimeContent',
          'MIME headers contain bare CR or LF — possible header injection',
        );
      }
    }
  }

  /// Whether [protocolVersion] uses the raw MIME request (2.5-12.1).
  static bool usesRawMime(String protocolVersion) =>
      protocolVersionValue(protocolVersion) < 140;

  /// Elements placed after `ClientId` (e.g. `Source`).
  List<WbxmlElement> buildSourceElements() => const [];

  /// Elements placed between `SaveInSentItems` and `Mime`.
  List<WbxmlElement> buildPreMimeElements() => const [];

  /// Elements placed after `TemplateID`.
  List<WbxmlElement> buildTrailingElements() => const [];

  /// URI parameters identifying the source item in raw MIME mode.
  Map<String, String> buildMimeParameters() => const {};

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, commandName, [
      xText(_ns, 'ClientId', clientId),
      ...buildSourceElements(),
      if (accountId != null) xText(_ns, 'AccountId', accountId!),
      if (saveInSentItems) xEl(_ns, 'SaveInSentItems'),
      ...buildPreMimeElements(),
      if (mimeContent != null)
        xOpaque(_ns, 'Mime', Uint8List.fromList(utf8.encode(mimeContent!))),
      if (templateId != null)
        xText('RightsManagement', 'TemplateID', templateId!),
      ...buildTrailingElements(),
    ]),
  );

  @override
  Uint8List? encodeRequest(String protocolVersion) {
    if (!usesRawMime(protocolVersion)) {
      return super.encodeRequest(protocolVersion);
    }
    final mime = mimeContent;
    if (mime == null) {
      throw UnsupportedError(
        '$commandName without MIME requires protocol version 16.0+',
      );
    }
    return Uint8List.fromList(utf8.encode(mime));
  }

  @override
  String requestContentType(String protocolVersion) =>
      usesRawMime(protocolVersion)
      ? easMimeContentType
      : super.requestContentType(protocolVersion);

  @override
  Map<String, String> requestParameters(String protocolVersion) =>
      usesRawMime(protocolVersion) ? buildMimeParameters() : const {};

  @override
  bool saveInSentParameter(String protocolVersion) =>
      usesRawMime(protocolVersion) && saveInSentItems;

  /// Empty body on HTTP 200 = success.
  @override
  void parseEmptyResponse() {}

  /// A body means failure; global codes (>= 101) are thrown by
  /// [checkGlobalStatus] before this is called.
  @override
  void parseResponse(WbxmlDocument response) {
    final code = xStatus(response.root, _ns);
    if (code == 0 || code == 1) return;
    throw EasCommandException(
      command: commandName,
      statusCode: 200,
      easStatus: code,
      message:
          EasGlobalStatus.fromCode(code)?.description ??
          'Unknown $commandName error ($code)',
    );
  }
}

class SendMailCommand extends ComposeMailCommand {
  SendMailCommand({
    required super.clientId,
    required super.mimeContent,
    super.saveInSentItems,
    super.templateId,
    super.accountId,
  });

  @override
  String get commandName => 'SendMail';

  /// See [ComposeMailCommand.validateMimeHeaders].
  static void validateMimeHeaders(String mime) =>
      ComposeMailCommand.validateMimeHeaders(mime);
}

/// Identifies the source message of SmartReply/SmartForward: either
/// [collectionId] + [serverId] (optionally with [instanceId] for an
/// occurrence of a recurring meeting) or [longId] (a Search result).
mixin SmartMailSource on ComposeMailCommand {
  String? get serverId;
  String? get collectionId;
  String? get longId;
  DateTime? get instanceId;

  void validateSource() {
    final byId = serverId != null && collectionId != null;
    final partialId = (serverId != null) != (collectionId != null);
    if (partialId || byId == (longId != null)) {
      throw ArgumentError('Specify either serverId + collectionId, or longId');
    }
    if (byId) {
      checkLength(collectionId!, 64, 'collectionId');
      checkLength(serverId!, 64, 'serverId');
    } else {
      checkLength(longId!, 256, 'longId');
    }
  }

  @override
  List<WbxmlElement> buildSourceElements() => [
    xEl(_ns, 'Source', [
      if (longId != null)
        xText(_ns, 'LongId', longId!)
      else ...[
        xText(_ns, 'FolderId', collectionId!),
        xText(_ns, 'ItemId', serverId!),
      ],
      if (instanceId != null)
        xText(_ns, 'InstanceId', isoDateTime(instanceId!)),
    ]),
  ];

  @override
  Map<String, String> buildMimeParameters() => {
    'LongId': ?longId,
    'CollectionId': ?collectionId,
    'ItemId': ?serverId,
    if (instanceId != null) 'Occurrence': isoDateTime(instanceId!),
  };
}

/// Base class for SmartReply/SmartForward: identifies the source message
/// and lets the server append the original content.
abstract class SmartMailCommand extends ComposeMailCommand
    with SmartMailSource {
  @override
  final String? serverId;
  @override
  final String? collectionId;
  @override
  final String? longId;
  @override
  final DateTime? instanceId;

  /// If true, the server does not append the original message; the client
  /// supplies the full MIME content (`ReplaceMime`).
  final bool replaceMime;

  SmartMailCommand({
    required super.clientId,
    required super.mimeContent,
    this.serverId,
    this.collectionId,
    this.longId,
    this.instanceId,
    this.replaceMime = false,
    super.saveInSentItems,
    super.templateId,
    super.accountId,
  }) {
    validateSource();
  }

  SmartMailCommand.withoutMime({
    required super.clientId,
    this.serverId,
    this.collectionId,
    this.longId,
    this.instanceId,
    super.accountId,
  }) : replaceMime = false,
       super.withoutMime() {
    validateSource();
  }

  @override
  List<WbxmlElement> buildPreMimeElements() => [
    if (replaceMime) xEl(_ns, 'ReplaceMime'),
  ];
}
