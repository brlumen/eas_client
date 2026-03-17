/// Code Page 23: Notes namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.23
library;

import 'code_page.dart';

class NotesCodePage extends CodePage {
  static final NotesCodePage instance = NotesCodePage._();

  NotesCodePage._();

  @override
  int get pageIndex => 23;

  @override
  String get namespace => 'Notes';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Subject',
        0x06: 'MessageClass',
        0x07: 'LastModifiedDate',
        0x08: 'Categories',
        0x09: 'Category',
        0x0C: 'IsRead',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
