/// Partial email change (Sync `Commands/Change`).
library;

import 'dart:typed_data';

import '../wbxml/wbxml_document.dart';
import 'eas_body.dart';
import 'eas_email.dart';
import 'wbxml_helpers.dart';

/// A server-to-client email change (Sync `Commands/Change`).
///
/// A Change carries only the properties that changed (MS-ASCMD
/// 2.2.3.24.2), so every field is nullable: `null` means "not present in
/// the response — keep the local value". Unlike [EasEmail] no defaults
/// are substituted.
class EasEmailChange {
  /// Server-assigned ID of the changed item.
  final String serverId;

  /// Item class when it differs from the collection class (e.g. `SMS`).
  final String? className;

  /// `email:Read`.
  final bool? read;

  /// `email:Flag`. An empty `Flag` element (flag cleared) yields a flag
  /// with status 0.
  final EasFlag? flag;

  /// `email:Categories`; an empty list means all categories were removed.
  final List<String>? categories;

  /// `email:Importance`.
  final EmailImportance? importance;

  /// `email2:LastVerbExecuted` (1=ReplyToSender, 2=ReplyToAll, 3=Forward).
  final int? lastVerbExecuted;

  /// `email2:LastVerbExecutionTime`.
  final DateTime? lastVerbExecutionTime;

  /// `email:Subject` (e.g. edited drafts).
  final String? subject;

  /// `email:MessageClass`.
  final String? messageClass;

  /// `email2:IsDraft`.
  final bool? isDraft;

  /// `email2:ConversationId` (opaque bytes base64-encoded).
  final String? conversationId;

  /// `email2:ConversationIndex`.
  final Uint8List? conversationIndex;

  /// `airsyncbase:Body`, if the server sent one.
  final EasBody? body;

  /// The raw `ApplicationData` element, for properties not mapped above.
  final WbxmlElement applicationData;

  const EasEmailChange({
    required this.serverId,
    required this.applicationData,
    this.className,
    this.read,
    this.flag,
    this.categories,
    this.importance,
    this.lastVerbExecuted,
    this.lastVerbExecutionTime,
    this.subject,
    this.messageClass,
    this.isDraft,
    this.conversationId,
    this.conversationIndex,
    this.body,
  });

  /// Parse from a Change's `ApplicationData`.
  factory EasEmailChange.fromApplicationData(
    String serverId,
    WbxmlElement data, {
    String? className,
  }) {
    final flagEl = data.findChild('Email', 'Flag');
    final categoriesEl = data.findChild('Email', 'Categories');
    final importance = data.integer('Email', 'Importance');
    return EasEmailChange(
      serverId: serverId,
      applicationData: data,
      className: className,
      read: data.boolean('Email', 'Read'),
      flag: flagEl == null ? null : EasFlag.fromElement(flagEl),
      categories: categoriesEl == null
          ? null
          : data.list('Email', 'Categories', 'Category'),
      importance: importance == null
          ? null
          : EmailImportance.fromValue(importance),
      lastVerbExecuted: data.integer('Email2', 'LastVerbExecuted'),
      lastVerbExecutionTime: data.date('Email2', 'LastVerbExecutionTime'),
      subject: data.str('Email', 'Subject'),
      messageClass: data.str('Email', 'MessageClass'),
      isDraft: data.boolean('Email2', 'IsDraft'),
      conversationId: data.idString('Email2', 'ConversationId'),
      conversationIndex: data.bytes('Email2', 'ConversationIndex'),
      body: EasBody.of(data),
    );
  }

  /// Flag status (0=cleared, 1=complete, 2=active), `null` if the flag
  /// did not change.
  int? get flagStatus => flag?.status;

  /// Whether this is an SMS change.
  bool get isSms => className == 'SMS';

  @override
  String toString() => 'EasEmailChange($serverId)';
}
