/// Code Page 7: FolderHierarchy namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.8
library;

import 'code_page.dart';

class FolderHierarchyCodePage extends CodePage {
  static final FolderHierarchyCodePage instance =
      FolderHierarchyCodePage._();

  FolderHierarchyCodePage._();

  @override
  int get pageIndex => 7;

  @override
  String get namespace => 'FolderHierarchy';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Folders',
        0x06: 'Folder',
        0x07: 'DisplayName',
        0x08: 'ServerId',
        0x09: 'ParentId',
        0x0A: 'Type',
        0x0C: 'Status',
        0x0E: 'Changes',
        0x0F: 'Add',
        0x10: 'Delete',
        0x11: 'Update',
        0x12: 'SyncKey',
        0x13: 'FolderCreate',
        0x14: 'FolderDelete',
        0x15: 'FolderUpdate',
        0x16: 'FolderSync',
        0x17: 'Count',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
