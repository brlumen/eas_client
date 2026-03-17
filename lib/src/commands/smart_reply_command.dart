/// SmartReply command — reply to an email with original message included.
///
/// HTTP 200 with empty body = success.
/// HTTP 200 with WBXML body = error (contains ComposeMail:Status).
///
/// Reference: MS-ASCMD section 2.2.1.19
library;

import 'dart:convert';
import 'dart:typed_data';

import '../transport/eas_http_client.dart';
import '../wbxml/wbxml_codec.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'send_mail_command.dart';

/// Reply to an email on the server, including the original message body.
///
/// The server appends the original message body to [mimeContent].
class SmartReplyCommand {
  final WbxmlEncoder _encoder = WbxmlEncoder();
  final WbxmlDecoder _decoder = WbxmlDecoder();

  /// Unique client-generated ID to prevent duplicate sends.
  final String clientId;

  /// ServerId of the email being replied to.
  final String serverId;

  /// CollectionId (folder) of the email being replied to.
  final String collectionId;

  /// MIME content of the reply (headers + body, without the original).
  final String mimeContent;

  /// Whether to save the reply in Sent Items.
  final bool saveInSentItems;

  SmartReplyCommand({
    required this.clientId,
    required this.serverId,
    required this.collectionId,
    required this.mimeContent,
    this.saveInSentItems = true,
  }) {
    SendMailCommand.validateMimeHeaders(mimeContent);
  }

  Future<void> execute(EasHttpClient client) async {
    final mimeBytes = Uint8List.fromList(utf8.encode(mimeContent));

    final doc = WbxmlDocument(
      root: WbxmlElement(
        namespace: 'ComposeMail',
        tag: 'SmartReply',
        codePageIndex: 21,
        children: [
          WbxmlElement.withText(
            namespace: 'ComposeMail',
            tag: 'ClientId',
            text: clientId,
            codePageIndex: 21,
          ),
          if (saveInSentItems)
            WbxmlElement(
              namespace: 'ComposeMail',
              tag: 'SaveInSentItems',
              codePageIndex: 21,
            ),
          WbxmlElement(
            namespace: 'ComposeMail',
            tag: 'Source',
            codePageIndex: 21,
            children: [
              WbxmlElement.withText(
                namespace: 'ComposeMail',
                tag: 'FolderId',
                text: collectionId,
                codePageIndex: 21,
              ),
              WbxmlElement.withText(
                namespace: 'ComposeMail',
                tag: 'ItemId',
                text: serverId,
                codePageIndex: 21,
              ),
            ],
          ),
          WbxmlElement(
            namespace: 'ComposeMail',
            tag: 'Mime',
            codePageIndex: 21,
            opaque: mimeBytes,
          ),
        ],
      ),
    );

    final bytes = _encoder.encode(doc);
    final response = await client.sendCommand('SmartReply', bytes);

    if (response.statusCode != 200) {
      throw EasCommandException(
        command: 'SmartReply',
        statusCode: response.statusCode,
        message: 'SmartReply failed with HTTP ${response.statusCode}',
      );
    }

    if (response.body.isEmpty) return;

    final respDoc = _decoder.decode(response.body);
    final statusText = respDoc.root.childText('ComposeMail', 'Status');
    final statusCode = int.tryParse(statusText ?? '') ?? 0;
    if (statusCode != 1) {
      throw EasCommandException(
        command: 'SmartReply',
        easStatus: statusCode,
        message: 'SmartReply error (status $statusCode)',
      );
    }
  }
}
