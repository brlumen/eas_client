/// EAS email model.
library;

import 'eas_attachment.dart';

/// Email importance level.
enum EmailImportance {
  low(0),
  normal(1),
  high(2);

  final int value;
  const EmailImportance(this.value);

  static EmailImportance fromValue(int value) {
    return EmailImportance.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EmailImportance.normal,
    );
  }
}

class EasEmail {
  /// Server-assigned ID.
  final String serverId;

  /// Subject line.
  final String subject;

  /// From address.
  final String from;

  /// To recipients.
  final String to;

  /// CC recipients.
  final String? cc;

  /// BCC recipients.
  final String? bcc;

  /// Display name in To field.
  final String? displayTo;

  /// Date received.
  final DateTime? dateReceived;

  /// Read status.
  final bool read;

  /// Importance level.
  final EmailImportance importance;

  /// Message class (e.g., 'IPM.Note').
  final String? messageClass;

  /// Body content.
  final String? body;

  /// Body type (1=plain, 2=HTML, 3=RTF, 4=MIME).
  final int bodyType;

  /// Whether body is truncated.
  final bool bodyTruncated;

  /// Estimated body size.
  final int? estimatedBodySize;

  /// Thread topic.
  final String? threadTopic;

  /// Reply-to address.
  final String? replyTo;

  /// Attachments.
  final List<EasAttachment> attachments;

  /// Conversation ID.
  final String? conversationId;

  /// Flag status (0=cleared, 1=complete, 2=active).
  final int flagStatus;

  /// Whether this is a draft.
  final bool isDraft;

  /// Content class (e.g., 'urn:content-classes:message').
  final String? contentClass;

  /// Internet code page ID.
  final int? internetCPID;

  /// Categories.
  final List<String> categories;

  /// Last verb executed (1=ReplyToSender, 2=ReplyToAll, 3=Forward).
  final int? lastVerbExecuted;

  /// Time of last verb execution.
  final DateTime? lastVerbExecutionTime;

  /// Whether email was received as BCC.
  final bool? receivedAsBcc;

  /// Sensitivity: 0=normal, 1=personal, 2=private, 3=confidential.
  final int? sensitivity;

  const EasEmail({
    required this.serverId,
    this.subject = '',
    this.from = '',
    this.to = '',
    this.cc,
    this.bcc,
    this.displayTo,
    this.dateReceived,
    this.read = false,
    this.importance = EmailImportance.normal,
    this.messageClass,
    this.body,
    this.bodyType = 1,
    this.bodyTruncated = false,
    this.estimatedBodySize,
    this.threadTopic,
    this.replyTo,
    this.attachments = const [],
    this.conversationId,
    this.flagStatus = 0,
    this.isDraft = false,
    this.contentClass,
    this.internetCPID,
    this.categories = const [],
    this.lastVerbExecuted,
    this.lastVerbExecutionTime,
    this.receivedAsBcc,
    this.sensitivity,
  });

  @override
  String toString() =>
      'EasEmail($serverId, subject: $subject, from: $from)';
}
