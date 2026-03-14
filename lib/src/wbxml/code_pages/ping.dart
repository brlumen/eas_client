/// Code Page 13: Ping namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.14
library;

import 'code_page.dart';

class PingCodePage extends CodePage {
  static final PingCodePage instance = PingCodePage._();

  PingCodePage._();

  @override
  int get pageIndex => 13;

  @override
  String get namespace => 'Ping';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Ping',
        0x07: 'Status',
        0x08: 'HeartbeatInterval',
        0x09: 'Folders',
        0x0A: 'Folder',
        0x0B: 'Id',
        0x0C: 'Class',
        0x0D: 'MaxFolders',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
