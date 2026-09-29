/// Serializes EasNote to WBXML ApplicationData for Sync Add/Change.
///
/// Reference: MS-ASNOTE 2.2.2 (Subject, MessageClass, LastModifiedDate,
/// Categories, airsyncbase:Body).
library;

import '../models/eas_body.dart';
import '../models/eas_note.dart';
import '../models/wbxml_helpers.dart';
import '../wbxml/wbxml_document.dart';

/// Serializer for note items (Sync Add/Change).
class NoteSerializer {
  const NoteSerializer._();

  /// Serialize note for Sync Add/Change ApplicationData.
  static WbxmlElement serialize(EasNote note) {
    const n = 'Notes';
    final c = <WbxmlElement>[]
      ..addText(n, 'Subject', note.subject)
      ..addText(n, 'MessageClass', note.messageClass)
      ..addDate(n, 'LastModifiedDate', note.lastModifiedDate)
      ..addList(n, 'Categories', 'Category', note.categories);
    if (note.body case final body?) {
      c.add(EasBody.toElement(body, type: note.bodyDetails?.type ?? 1));
    }
    return applicationData(c);
  }
}
