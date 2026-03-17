/// Serializes EasNote to WBXML ApplicationData for Sync Add/Change.
library;

import '../models/eas_note.dart';
import '../wbxml/wbxml_document.dart';

/// Serializer for note items (Sync Add/Change).
class NoteSerializer {
  const NoteSerializer._();

  /// Serialize note for Sync Add/Change ApplicationData.
  static WbxmlElement serialize(EasNote note) {
    final children = <WbxmlElement>[];

    if (note.subject.isNotEmpty) {
      children.add(WbxmlElement.withText(
        namespace: 'Notes',
        tag: 'Subject',
        text: note.subject,
        codePageIndex: 23,
      ));
    }

    // MessageClass for notes: IPM.StickyNote
    children.add(WbxmlElement.withText(
      namespace: 'Notes',
      tag: 'MessageClass',
      text: 'IPM.StickyNote',
      codePageIndex: 23,
    ));

    // Categories
    if (note.categories.isNotEmpty) {
      children.add(WbxmlElement(
        namespace: 'Notes',
        tag: 'Categories',
        codePageIndex: 23,
        children: note.categories
            .map((c) => WbxmlElement.withText(
                  namespace: 'Notes',
                  tag: 'Category',
                  text: c,
                  codePageIndex: 23,
                ))
            .toList(),
      ));
    }

    // Body
    if (note.body != null) {
      children.add(WbxmlElement(
        namespace: 'AirSyncBase',
        tag: 'Body',
        codePageIndex: 17,
        children: [
          WbxmlElement.withText(
            namespace: 'AirSyncBase',
            tag: 'Type',
            text: '1',
            codePageIndex: 17,
          ),
          WbxmlElement.withText(
            namespace: 'AirSyncBase',
            tag: 'Data',
            text: note.body!,
            codePageIndex: 17,
          ),
        ],
      ));
    }

    return WbxmlElement(
      namespace: 'AirSync',
      tag: 'ApplicationData',
      codePageIndex: 0,
      children: children,
    );
  }
}
