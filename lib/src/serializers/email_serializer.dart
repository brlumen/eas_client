/// Serializes EasEmail to WBXML ApplicationData for Sync Add/Change.
///
/// Reference: MS-ASEMAIL 3.1.5.3, MS-ASCMD 6.45 (Sync request schema).
library;

import '../models/eas_attachment.dart';
import '../models/eas_body.dart';
import '../models/eas_email.dart';
import '../models/wbxml_helpers.dart';
import '../wbxml/wbxml_document.dart';
import 'attachment_serializer.dart';

/// Serializer for email items (Sync Add/Change).
///
/// Only serializes fields that are writable via Sync command.
/// Read-only server fields (serverId, DisplayTo, ThreadTopic, ...) are
/// skipped.
class EmailSerializer {
  const EmailSerializer._();

  /// Serialize an email for a generic Sync Add ApplicationData
  /// (e.g. importing a message).
  ///
  /// Emits To, From, Cc, Subject, ReplyTo, DateReceived, InternetCPID,
  /// Importance, Read, MessageClass, Flag, Categories and Body.
  static WbxmlElement serialize(EasEmail email) {
    final c = <WbxmlElement>[]
      ..addText('Email', 'To', email.to)
      ..addText('Email', 'From', email.from)
      ..addText('Email', 'Cc', email.cc)
      ..addText('Email', 'Subject', email.subject)
      ..addText('Email', 'ReplyTo', email.replyTo)
      ..addDate('Email', 'DateReceived', email.dateReceived)
      ..addText('Email', 'InternetCPID', email.internetCPID)
      ..addText('Email', 'Importance', email.importance.value)
      ..addText('Email', 'Read', email.read)
      ..addText('Email', 'MessageClass', email.messageClass);
    final flag = _flag(email);
    if (flag != null) c.add(flag);
    if (email.body case final body?) {
      c.add(EasBody.toElement(body, type: email.bodyType));
    }
    c.addList('Email', 'Categories', 'Category', email.categories);
    return applicationData(c);
  }

  /// Serialize an SMS message for Sync Add in the SMS/Inbox folder
  /// (EAS 14.0+, class `SMS`): To, From, DateReceived, Importance, Read
  /// and a plain-text Body.
  static WbxmlElement serializeSms(EasEmail sms) {
    final c = <WbxmlElement>[]
      ..addText('Email', 'To', sms.to)
      ..addText('Email', 'From', sms.from)
      ..addDate('Email', 'DateReceived', sms.dateReceived)
      ..addText('Email', 'Importance', sms.importance.value)
      ..addText('Email', 'Read', sms.read);
    if (sms.body case final body?) c.add(EasBody.toElement(body));
    return applicationData(c);
  }

  /// Serialize a Sync Change of an existing message: only Read, Flag
  /// and Categories are writable (MS-ASCMD 2.2.3.24). Omitted values are
  /// left unchanged on the server.
  static WbxmlElement serializeChange({
    bool? read,
    EasFlag? flag,
    List<String>? categories,
  }) {
    final c = <WbxmlElement>[]..addText('Email', 'Read', read);
    if (flag != null) c.add(flag.toElement());
    if (categories != null) {
      c.add(
        containerEl('Email', 'Categories', [
          for (final cat in categories) textEl('Email', 'Category', cat),
        ]),
      );
    }
    return applicationData(c);
  }

  /// Serialize a draft for Sync Add/Change in the Drafts folder
  /// (EAS 16.x, MS-ASEMAIL 16.0).
  ///
  /// Writable draft fields: To, Cc, Bcc, Subject, ReplyTo, Importance,
  /// Categories, Body, plus AirSyncBase Attachments [addAttachments] /
  /// [deleteAttachments] (FileReferences, MS-ASAIRS 16.0).
  ///
  /// To send the draft, set `send: true` on the [SyncChangeItem] /
  /// [SyncAddItem]: `email2:Send` is a sibling of ApplicationData
  /// (MS-ASCMD 2.2.3.24), not part of it.
  static WbxmlElement serializeDraft(
    EasEmail email, {
    List<EasAttachmentAdd> addAttachments = const [],
    List<String> deleteAttachments = const [],
  }) {
    final c = <WbxmlElement>[]
      ..addText('Email', 'To', email.to)
      ..addText('Email', 'Cc', email.cc)
      ..addText('Email2', 'Bcc', email.bcc)
      ..addText('Email', 'Subject', email.subject)
      ..addText('Email', 'ReplyTo', email.replyTo)
      ..addText('Email', 'Importance', email.importance.value)
      ..addList('Email', 'Categories', 'Category', email.categories);
    if (email.body case final body?) {
      c.add(EasBody.toElement(body, type: email.bodyType));
    }
    final attachments = AttachmentSerializer.serialize(
      add: addAttachments,
      delete: deleteAttachments,
    );
    if (attachments != null) c.add(attachments);
    return applicationData(c);
  }

  /// Serialize only the Read field (for mark read/unread).
  static WbxmlElement serializeReadFlag(bool read) =>
      serializeChange(read: read);

  /// Serialize only the Flag status.
  static WbxmlElement serializeFlag(int flagStatus) => applicationData([
    containerEl('Email', 'Flag', [textEl('Email', 'Status', '$flagStatus')]),
  ]);

  static WbxmlElement? _flag(EasEmail email) {
    if (email.flag case final flag?) return flag.toElement();
    if (email.flagStatus == 0) return null;
    return EasFlag(status: email.flagStatus).toElement();
  }
}
