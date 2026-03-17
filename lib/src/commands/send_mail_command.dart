/// SendMail command — sends email via EAS.
///
/// For protocol versions 14.0+, the MIME content is sent as opaque data
/// within a WBXML wrapper. For older versions (2.5, 12.0, 12.1),
/// raw MIME with Content-Type: message/rfc822 is used.
///
/// Per MS-ASCMD 2.2.1.17: HTTP 200 with empty body = success.
/// HTTP 200 with WBXML body = error (contains Status element).
///
/// Reference: MS-ASCMD section 2.2.1.17
library;

import 'dart:convert';
import 'dart:typed_data';

import '../transport/eas_http_client.dart';
import '../wbxml/wbxml_codec.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Common EAS status codes relevant to SendMail (MS-ASCMD 2.2.2).
enum SendMailStatus {
  success(1, 'Success'),
  invalidContent(101, 'Invalid content (wrong Content-Type or body)'),
  invalidWbxml(102, 'Invalid WBXML'),
  invalidXml(103, 'Invalid XML'),
  invalidMime(107, 'Invalid MIME'),
  serverError(110, 'Server error'),
  serverErrorRetryLater(111, 'Server error — retry later'),
  mailboxQuotaExceeded(113, 'Mailbox quota exceeded'),
  mailboxServerOffline(114, 'Mailbox server offline'),
  sendQuotaExceeded(115, 'Send quota exceeded'),
  recipientUnresolved(116, 'Recipient could not be resolved'),
  messagePreviouslySent(118, 'Message previously sent (duplicate ClientId)'),
  messageHasNoRecipient(119, 'Message has no recipient'),
  mailSubmissionFailed(120, 'Mail submission failed'),
  invalidRecipients(183, 'Invalid recipients (bad SMTP format)');

  final int code;
  final String description;

  const SendMailStatus(this.code, this.description);

  static SendMailStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

class SendMailCommand {
  final WbxmlEncoder _encoder = WbxmlEncoder();
  final WbxmlDecoder _decoder = WbxmlDecoder();
  final String clientId;
  final String mimeContent;
  final bool saveInSentItems;

  SendMailCommand({
    required this.clientId,
    required this.mimeContent,
    this.saveInSentItems = true,
  }) {
    validateMimeHeaders(mimeContent);
  }

  /// Validates MIME headers do not contain bare CR or LF (header injection).
  ///
  /// Checks only the header section (before the first \r\n\r\n separator).
  /// Bare \r or \n within a header line indicates injection attempt.
  static void validateMimeHeaders(String mime) {
    // Find end of headers
    final headerEnd = mime.indexOf('\r\n\r\n');
    final headers = headerEnd >= 0 ? mime.substring(0, headerEnd) : mime;

    // Split by proper CRLF and check each line
    final lines = headers.split('\r\n');
    for (final line in lines) {
      if (line.contains('\r') || line.contains('\n')) {
        throw ArgumentError.value(
          '(content hidden)',
          'mimeContent',
          'MIME headers contain bare CR or LF — possible header injection',
        );
      }
    }
  }

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

    // Empty body on HTTP 200 = success
    if (response.body.isEmpty) return;

    // Non-empty body = WBXML error response with Status
    final respDoc = _decoder.decode(response.body);
    final statusText = respDoc.root.childText('ComposeMail', 'Status');
    final statusCode = int.tryParse(statusText ?? '') ?? 0;

    if (statusCode != SendMailStatus.success.code) {
      final status = SendMailStatus.fromCode(statusCode);
      throw EasCommandException(
        command: 'SendMail',
        easStatus: statusCode,
        message: status?.description ?? 'Unknown SendMail error ($statusCode)',
      );
    }
  }
}
