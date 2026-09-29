/// SmartForward command — forward an email with original message included.
///
/// HTTP 200 with empty body = success.
/// HTTP 200 with WBXML body = error (contains ComposeMail:Status).
///
/// Reference: MS-ASCMD section 2.2.1.19
library;

import '../models/eas_body.dart';
import '../wbxml/wbxml_document.dart';
import 'send_mail_command.dart';
import 'wbxml_builders.dart';

/// A recipient added via `Forwardees` (EAS 16.0+).
class Forwardee {
  final String email;
  final String? name;

  const Forwardee({required this.email, this.name});
}

/// Forward an email on the server, including the original message body.
///
/// The server appends the original message body to [mimeContent] unless
/// [replaceMime] is set.
class SmartForwardCommand extends SmartMailCommand {
  /// Additional recipients of a forwarded meeting (EAS 16.0+,
  /// [SmartForwardCommand.meeting] only).
  final List<Forwardee> forwardees;

  /// Free-form body added to a forwarded meeting (EAS 16.0+,
  /// [SmartForwardCommand.meeting] only).
  final String? body;

  /// Type of [body]: 1 = plain text, 2 = HTML.
  final int bodyType;

  SmartForwardCommand({
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
  }) : forwardees = const [],
       body = null,
       bodyType = 1;

  /// Forward a calendar item to [forwardees] with an optional [body]
  /// (EAS 16.0+). Per MS-ASCMD 2.2.3.169, `Mime`, `SaveInSentItems`,
  /// `ReplaceMime` and `TemplateID` MUST NOT be present in this form.
  SmartForwardCommand.meeting({
    required super.clientId,
    super.serverId,
    super.collectionId,
    super.longId,
    super.instanceId,
    super.accountId,
    this.forwardees = const [],
    this.body,
    this.bodyType = 1,
  }) : super.withoutMime() {
    if (forwardees.isEmpty && body == null) {
      throw ArgumentError('Specify forwardees and/or body');
    }
    for (final f in forwardees) {
      if (f.email.isEmpty) {
        throw ArgumentError.value(f.email, 'forwardees', 'Empty email');
      }
    }
  }

  @override
  String get commandName => 'SmartForward';

  @override
  List<WbxmlElement> buildTrailingElements() => [
    if (body != null) EasBody.toElement(body!, type: bodyType),
    if (forwardees.isNotEmpty)
      xEl('ComposeMail', 'Forwardees', [
        for (final f in forwardees)
          xEl('ComposeMail', 'Forwardee', [
            xText('ComposeMail', 'Email', f.email),
            if (f.name != null) xText('ComposeMail', 'Name', f.name!),
          ]),
      ]),
  ];
}
