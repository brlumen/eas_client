/// SmartReply command — reply to an email with original message included.
///
/// HTTP 200 with empty body = success.
/// HTTP 200 with WBXML body = error (contains ComposeMail:Status; 117 =
/// the server does not allow a reply to the message).
///
/// Reference: MS-ASCMD section 2.2.1.20
library;

import 'send_mail_command.dart';

/// Reply to an email on the server, including the original message body.
///
/// The server appends the original message body to [mimeContent] unless
/// [replaceMime] is set.
class SmartReplyCommand extends SmartMailCommand {
  SmartReplyCommand({
    required super.clientId,
    super.serverId,
    super.collectionId,
    super.longId,
    super.instanceId,
    required super.mimeContent,
    super.saveInSentItems,
    super.replaceMime,
    super.templateId,
    super.accountId,
  });

  @override
  String get commandName => 'SmartReply';
}
