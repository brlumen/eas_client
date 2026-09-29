/// EAS note model (MS-ASNOTE, IPM.StickyNote).
library;

import '../wbxml/wbxml_document.dart';
import 'eas_body.dart';
import 'wbxml_helpers.dart';

/// EAS note.
class EasNote {
  /// Server-assigned ID.
  final String serverId;

  /// Note subject/title.
  final String subject;

  /// Note body.
  final String? body;

  /// Full `airsyncbase:Body`, if present.
  final EasBody? bodyDetails;

  /// Message class (`IPM.StickyNote` or a derived class).
  final String messageClass;

  /// Last modified date (UTC).
  final DateTime? lastModifiedDate;

  /// Whether the note is read (not defined by MS-ASNOTE; kept for
  /// servers that send `Notes:IsRead`).
  final bool isRead;

  /// Categories.
  final List<String> categories;

  const EasNote({
    required this.serverId,
    this.subject = '',
    this.body,
    this.bodyDetails,
    this.messageClass = 'IPM.StickyNote',
    this.lastModifiedDate,
    this.isRead = false,
    this.categories = const [],
  });

  /// Parse a note from `ApplicationData` / `Properties`.
  factory EasNote.fromApplicationData(String serverId, WbxmlElement data) {
    const ns = 'Notes';
    final bodyDetails = EasBody.of(data);
    return EasNote(
      serverId: serverId,
      subject: data.str(ns, 'Subject') ?? '',
      body: bodyDetails?.data,
      bodyDetails: bodyDetails,
      messageClass: data.str(ns, 'MessageClass') ?? 'IPM.StickyNote',
      lastModifiedDate: data.date(ns, 'LastModifiedDate'),
      isRead: data.boolean(ns, 'IsRead') ?? false,
      categories: data.list(ns, 'Categories', 'Category') ?? const [],
    );
  }

  @override
  String toString() => 'EasNote($serverId)';
}
