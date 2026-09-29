/// Parser for `application/vnd.ms-sync.multipart` responses.
///
/// Layout (all integers are 32-bit little-endian signed):
/// `PartCount`, then `PartCount` pairs of `(Offset, Length)`, then the part
/// data. Offsets are relative to the start of the body. Part 0 is the WBXML
/// response; `ItemOperations:Part` elements reference the other parts by
/// index.
///
/// Reference: MS-ASCMD section 2.2.2.10.1 (MultiPartResponse)
library;

import 'dart:typed_data';

/// Content type of a multipart ItemOperations response.
const easMultipartContentType = 'application/vnd.ms-sync.multipart';

/// Thrown when a multipart body is malformed or exceeds size limits.
class EasMultipartException implements Exception {
  final String message;

  EasMultipartException(this.message);

  @override
  String toString() => 'EasMultipartException: $message';
}

/// A parsed multipart response. Parts are views over the original buffer.
class EasMultipartResponse {
  final List<Uint8List> parts;

  EasMultipartResponse._(this.parts);

  /// Whether [contentType] denotes a multipart response.
  static bool isMultipart(String? contentType) =>
      contentType != null &&
      contentType.toLowerCase().startsWith(easMultipartContentType);

  /// Parse [body], rejecting malformed input and parts above [maxPartSize].
  factory EasMultipartResponse.parse(
    Uint8List body, {
    int maxPartSize = 50 * 1024 * 1024,
  }) {
    if (body.length < 4) {
      throw EasMultipartException('Body too short for part count');
    }
    final view = ByteData.sublistView(body);
    final count = view.getInt32(0, Endian.little);
    // Each part needs an 8-byte descriptor; this also bounds [count].
    if (count < 1 || count > (body.length - 4) ~/ 8) {
      throw EasMultipartException('Invalid part count ($count)');
    }
    final dataStart = 4 + count * 8;
    final parts = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      final offset = view.getInt32(4 + i * 8, Endian.little);
      final length = view.getInt32(8 + i * 8, Endian.little);
      if (length < 0 || length > maxPartSize) {
        throw EasMultipartException('Invalid length ($length) of part $i');
      }
      if (offset < dataStart || offset > body.length - length) {
        throw EasMultipartException('Part $i is out of bounds');
      }
      parts.add(Uint8List.sublistView(body, offset, offset + length));
    }
    return EasMultipartResponse._(List.unmodifiable(parts));
  }

  /// Part referenced by an `ItemOperations:Part` index.
  ///
  /// Throws [EasMultipartException] if the index is not a valid data part
  /// (part 0 is the WBXML document itself).
  Uint8List partAt(String? index) {
    final i = int.tryParse(index ?? '');
    if (i == null || i < 1 || i >= parts.length) {
      throw EasMultipartException('Invalid part reference');
    }
    return parts[i];
  }
}
