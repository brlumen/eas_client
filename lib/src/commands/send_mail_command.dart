/// SendMail command — sends email via EAS.
///
/// The MIME content is sent as opaque data within a WBXML wrapper.
///
/// Reference: MS-ASCMD section 2.2.1.17
library;

import 'dart:convert';
import 'dart:typed_data';

import '../transport/eas_http_client.dart';
import '../wbxml/wbxml_codec.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

class SendMailCommand {
  final WbxmlEncoder _encoder = WbxmlEncoder();
  final String clientId;
  final String mimeContent;
  final bool saveInSentItems;

  /// Create a SendMail command.
  ///
  /// [clientId] — unique ID for this message (to prevent duplicates).
  /// [mimeContent] — full MIME content of the email.
  /// [saveInSentItems] — whether to save a copy in Sent Items.
  SendMailCommand({
    required this.clientId,
    required this.mimeContent,
    this.saveInSentItems = true,
  });

  Future<void> execute(EasHttpClient client) async {
    final mimeBytes = Uint8List.fromList(utf8.encode(mimeContent));

    final doc = WbxmlDocument(
      root: WbxmlElement(
        namespace: 'ComposeMail',
        tag: 'SendMail',
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
            tag: 'Mime',
            codePageIndex: 21,
            opaque: mimeBytes,
          ),
        ],
      ),
    );

    final bytes = _encoder.encode(doc);
    final response = await client.sendCommand('SendMail', bytes);

    if (response.statusCode != 200) {
      throw EasCommandException(
        command: 'SendMail',
        statusCode: response.statusCode,
        message: 'SendMail failed with HTTP ${response.statusCode}',
      );
    }

    // SendMail returns empty body on success
  }
}
