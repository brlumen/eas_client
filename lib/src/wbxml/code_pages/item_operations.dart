/// Code Page 20: ItemOperations namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.21
library;

import 'code_page.dart';

class ItemOperationsCodePage extends CodePage {
  static final ItemOperationsCodePage instance =
      ItemOperationsCodePage._();

  ItemOperationsCodePage._();

  @override
  int get pageIndex => 20;

  @override
  String get namespace => 'ItemOperations';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'ItemOperations',
        0x06: 'Fetch',
        0x07: 'Store',
        0x08: 'Options',
        0x09: 'Range',
        0x0A: 'Total',
        0x0B: 'Properties',
        0x0C: 'Data',
        0x0D: 'Status',
        0x0E: 'Response',
        0x0F: 'Version',
        0x10: 'Schema',
        0x11: 'Part',
        0x12: 'EmptyFolderContents',
        0x13: 'DeleteSubFolders',
        0x14: 'UserName',
        0x15: 'Password',
        0x16: 'Move',
        0x17: 'DstFldId',
        0x18: 'ConversationId',
        0x19: 'MoveAlways',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
