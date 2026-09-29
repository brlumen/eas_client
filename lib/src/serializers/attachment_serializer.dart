/// Serializes AirSyncBase `Attachments` Add/Delete (MS-ASAIRS 2.2.2.8,
/// EAS 16.0+): used by email drafts and calendar items/exceptions.
library;

import '../models/eas_attachment.dart';
import '../models/wbxml_helpers.dart';
import '../wbxml/wbxml_document.dart';

/// Serializer for attachment Add/Delete operations.
class AttachmentSerializer {
  const AttachmentSerializer._();

  /// `airsyncbase:Attachments` with [add] and [delete] (FileReferences),
  /// or `null` if both are empty.
  ///
  /// `Content` is written as WBXML opaque data: MS-ASAIRS 2.2.2.15 defines
  /// it as a byte array, which MS-ASDTYPE 2.7.1 requires to be transmitted
  /// as opaque data (not base64 text).
  static WbxmlElement? serialize({
    List<EasAttachmentAdd> add = const [],
    List<String> delete = const [],
  }) {
    if (add.isEmpty && delete.isEmpty) return null;
    return containerEl('AirSyncBase', 'Attachments', [
      for (final a in add)
        containerEl(
          'AirSyncBase',
          'Add',
          <WbxmlElement>[
              textEl('AirSyncBase', 'ClientId', a.clientId),
              opaqueEl('AirSyncBase', 'Content', a.content),
              textEl('AirSyncBase', 'Method', '${a.method}'),
              textEl('AirSyncBase', 'DisplayName', a.displayName),
            ]
            ..addText('AirSyncBase', 'ContentType', a.contentType)
            ..addText('AirSyncBase', 'ContentId', a.contentId)
            ..addText('AirSyncBase', 'ContentLocation', a.contentLocation)
            ..addText('AirSyncBase', 'IsInline', a.isInline ? true : null),
        ),
      for (final ref in delete)
        containerEl('AirSyncBase', 'Delete', [
          textEl('AirSyncBase', 'FileReference', ref),
        ]),
    ]);
  }
}
