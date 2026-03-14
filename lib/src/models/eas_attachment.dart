/// EAS attachment model.
library;

class EasAttachment {
  /// Display name of the attachment.
  final String displayName;

  /// File reference for downloading via ItemOperations.
  final String fileReference;

  /// Attachment method (1=normal, 5=embedded, 6=OLE).
  final int method;

  /// Estimated size in bytes.
  final int? estimatedSize;

  /// Content ID (for inline attachments).
  final String? contentId;

  /// Whether this is an inline attachment.
  final bool isInline;

  /// Content type (MIME type).
  final String? contentType;

  const EasAttachment({
    required this.displayName,
    required this.fileReference,
    this.method = 1,
    this.estimatedSize,
    this.contentId,
    this.isInline = false,
    this.contentType,
  });

  @override
  String toString() => 'EasAttachment($displayName, ref: $fileReference)';
}
