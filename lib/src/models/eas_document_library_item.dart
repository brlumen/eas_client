/// Document class (Windows SharePoint Services / UNC document library).
///
/// Document class data is carried only by Search (Store=DocumentLibrary,
/// all elements in `search:Properties`) and ItemOperations Fetch (LinkId
/// only). It is not a Sync class. Supported in EAS 12.0+ (not 2.5).
///
/// Reference: MS-ASDOC sections 2.2.2, 3.2.5; MS-ASCMD 2.2.3.50
library;

import 'dart:convert';

import '../wbxml/wbxml_document.dart';

const _ns = 'DocumentLibrary';

/// Maximum LinkId size in bytes (`search:Value`, MS-ASCMD 2.2.3.196).
const int maxDocumentLinkIdBytes = 1024;

/// Validate a document library LinkId (MS-ASCMD 2.2.3.50: a URI).
///
/// Accepted forms: a UNC path (`\\server\share\path`) or an absolute
/// `http`/`https` URL (SharePoint). Rejected: other schemes (`file:`,
/// `ftp:`, …), URLs with embedded credentials (`user:pass@host`), Win32
/// device paths (`\\?\`, `\\.\`), `.`/`..` UNC segments, control
/// characters and values over [maxDocumentLinkIdBytes] bytes.
///
/// Throws [ArgumentError]; the message never contains the value itself.
void validateDocumentLinkId(String linkId, [String name = 'linkId']) {
  Never fail(String reason) => throw ArgumentError(reason, name);

  if (linkId.isEmpty) fail('Must not be empty');
  if (utf8.encode(linkId).length > maxDocumentLinkIdBytes) {
    fail('Must be at most $maxDocumentLinkIdBytes bytes');
  }
  if (linkId.codeUnits.any((c) => c < 0x20 || c == 0x7F)) {
    fail('Must not contain control characters');
  }

  if (linkId.startsWith(r'\\')) {
    final segments = linkId.substring(2).split(r'\');
    final host = segments.first;
    if (host.isEmpty || host == '?' || host == '.' || host.contains('/')) {
      fail('Invalid UNC server name');
    }
    for (var i = 1; i < segments.length; i++) {
      final s = segments[i];
      final last = i == segments.length - 1;
      if ((s.isEmpty && !last) || s == '.' || s == '..') {
        fail('Invalid UNC path segment');
      }
    }
    return;
  }

  final uri = Uri.tryParse(linkId);
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null || (scheme != 'http' && scheme != 'https')) {
    fail('Must be a UNC path or an http(s) URL');
  }
  if (uri.host.isEmpty) fail('URL must have a host');
  if (uri.userInfo.isNotEmpty) fail('URL must not contain credentials');
}

/// Document class item (document or folder) returned by a
/// DocumentLibrary Search (MS-ASDOC 2.2.2).
///
/// For a folder LinkId the first result is the folder itself, followed by
/// its contents (MS-ASCMD 2.2.3.155.3).
class EasDocumentLibraryItem {
  /// URI of the item (UNC path or URL); use with ItemOperations Fetch or
  /// another Search. Optional in the response per MS-ASCMD 2.2.3.50.
  final String? linkId;

  /// Name as displayed to the user.
  final String? displayName;

  /// `IsFolder`: the item is a folder.
  final bool isFolder;

  /// Creation time (UTC).
  final DateTime? creationDate;

  /// Last modification time of the item or its properties (UTC).
  final DateTime? lastModifiedDate;

  /// `IsHidden`: the item is hidden.
  final bool isHidden;

  /// Estimated size in bytes (documents only; may change before fetch).
  final int? contentLength;

  /// MIME type of the content, if known (documents only).
  final String? contentType;

  const EasDocumentLibraryItem({
    this.linkId,
    this.displayName,
    this.isFolder = false,
    this.creationDate,
    this.lastModifiedDate,
    this.isHidden = false,
    this.contentLength,
    this.contentType,
  });

  /// Parse from a `search:Properties` element.
  factory EasDocumentLibraryItem.fromWbxml(WbxmlElement props) {
    String? text(String tag) => props.childText(_ns, tag);
    DateTime? date(String tag) => DateTime.tryParse(text(tag) ?? '');

    return EasDocumentLibraryItem(
      linkId: text('LinkId'),
      displayName: text('DisplayName'),
      isFolder: text('IsFolder') == '1',
      creationDate: date('CreationDate'),
      lastModifiedDate: date('LastModifiedDate'),
      isHidden: text('IsHidden') == '1',
      contentLength: int.tryParse(text('ContentLength') ?? ''),
      contentType: text('ContentType'),
    );
  }

  @override
  String toString() =>
      'EasDocumentLibraryItem(${isFolder ? 'folder' : 'file'}, '
      '$contentLength bytes)';
}
