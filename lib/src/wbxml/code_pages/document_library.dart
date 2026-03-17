/// Code Page 19: DocumentLibrary namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.19
library;

import 'code_page.dart';

class DocumentLibraryCodePage extends CodePage {
  static final DocumentLibraryCodePage instance = DocumentLibraryCodePage._();

  DocumentLibraryCodePage._();

  @override
  int get pageIndex => 19;

  @override
  String get namespace => 'DocumentLibrary';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'LinkId',
        0x06: 'DisplayName',
        0x07: 'IsFolder',
        0x08: 'CreationDate',
        0x09: 'LastModifiedDate',
        0x0A: 'IsHidden',
        0x0B: 'ContentLength',
        0x0C: 'ContentType',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
