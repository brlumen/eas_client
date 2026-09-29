/// EAS attachment model (MS-ASAIRS 2.2.2.7 Attachment, MS-ASEMAIL 2.5
/// `email:Attachment`).
library;

import 'dart:typed_data';

import '../wbxml/wbxml_document.dart';
import 'wbxml_helpers.dart';

class EasAttachment {
  /// Display name of the attachment.
  final String displayName;

  /// File reference for downloading via ItemOperations
  /// (`email:AttName` for EAS 2.5).
  final String fileReference;

  /// Attachment method (1=normal, 5=embedded message, 6=OLE).
  final int method;

  /// Estimated size in bytes (`EstimatedDataSize`, `email:AttSize` in 2.5).
  final int? estimatedSize;

  /// Content ID (for inline attachments).
  final String? contentId;

  /// Content location (URI of an inline attachment).
  final String? contentLocation;

  /// Whether this is an inline attachment.
  final bool isInline;

  /// Content type (MIME type).
  final String? contentType;

  /// Client ID of an attachment added by the client (EAS 16.x responses).
  final String? clientId;

  /// Voice-mail attachment duration in seconds (`email2:UmAttDuration`).
  final int? umAttDuration;

  /// Voice-mail attachment order (`email2:UmAttOrder`).
  final int? umAttOrder;

  /// Attachment OID (`email:Att0id`, EAS 2.5).
  final String? attOid;

  const EasAttachment({
    required this.displayName,
    required this.fileReference,
    this.method = 1,
    this.estimatedSize,
    this.contentId,
    this.contentLocation,
    this.isInline = false,
    this.contentType,
    this.clientId,
    this.umAttDuration,
    this.umAttOrder,
    this.attOid,
  });

  /// Parse an `airsyncbase:Attachment` element.
  factory EasAttachment.fromElement(WbxmlElement att) => EasAttachment(
    displayName: att.str('AirSyncBase', 'DisplayName') ?? '',
    fileReference: att.str('AirSyncBase', 'FileReference') ?? '',
    method: att.integer('AirSyncBase', 'Method') ?? 1,
    estimatedSize: att.integer('AirSyncBase', 'EstimatedDataSize'),
    contentId: att.str('AirSyncBase', 'ContentId'),
    contentLocation: att.str('AirSyncBase', 'ContentLocation'),
    isInline: att.boolean('AirSyncBase', 'IsInline') ?? false,
    contentType: att.str('AirSyncBase', 'ContentType'),
    clientId: att.str('AirSyncBase', 'ClientId'),
    umAttDuration: att.integer('Email2', 'UmAttDuration'),
    umAttOrder: att.integer('Email2', 'UmAttOrder'),
  );

  /// Parse an EAS 2.5 `email:Attachment` element.
  factory EasAttachment.fromLegacyElement(WbxmlElement att) => EasAttachment(
    displayName:
        att.str('Email', 'DisplayName') ?? att.str('Email', 'AttName') ?? '',
    fileReference: att.str('Email', 'AttName') ?? '',
    method: att.integer('Email', 'AttMethod') ?? 1,
    estimatedSize: att.integer('Email', 'AttSize'),
    attOid: att.str('Email', 'Att0id'),
  );

  /// Attachments of [parent] (`airsyncbase:Attachments`, falling back to
  /// EAS 2.5 `email:Attachments`).
  static List<EasAttachment> listOf(WbxmlElement parent) {
    final base = parent.findChild('AirSyncBase', 'Attachments');
    if (base != null) {
      return base
          .findChildren('AirSyncBase', 'Attachment')
          .map(EasAttachment.fromElement)
          .toList();
    }
    return parent
            .findChild('Email', 'Attachments')
            ?.findChildren('Email', 'Attachment')
            .map(EasAttachment.fromLegacyElement)
            .toList() ??
        const [];
  }

  @override
  String toString() => 'EasAttachment($displayName, ref: $fileReference)';
}

/// Attachment to add via Sync (MS-ASAIRS 16.0 `Add`) — email drafts and
/// calendar items/exceptions.
class EasAttachmentAdd {
  /// Client-assigned ID; the server maps it to a FileReference in the
  /// Sync response.
  final String clientId;

  /// Display (file) name.
  final String displayName;

  /// Raw attachment bytes, sent as WBXML opaque data (MS-ASAIRS
  /// 2.2.2.15: byte array, MS-ASDTYPE 2.7.1).
  final Uint8List content;

  /// Attachment method (1=normal, 5=embedded message, 6=OLE).
  final int method;

  /// Content type (MIME type).
  final String? contentType;

  /// Content ID (for inline attachments).
  final String? contentId;

  /// Content location (for inline attachments).
  final String? contentLocation;

  /// Whether this is an inline attachment.
  final bool isInline;

  const EasAttachmentAdd({
    required this.clientId,
    required this.displayName,
    required this.content,
    this.method = 1,
    this.contentType,
    this.contentId,
    this.contentLocation,
    this.isInline = false,
  });

  @override
  String toString() => 'EasAttachmentAdd($clientId, ${content.length} bytes)';
}
