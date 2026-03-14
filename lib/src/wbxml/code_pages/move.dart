/// Code Page 5: Move namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.6
library;

import 'code_page.dart';

class MoveCodePage extends CodePage {
  static final MoveCodePage instance = MoveCodePage._();

  MoveCodePage._();

  @override
  int get pageIndex => 5;

  @override
  String get namespace => 'Move';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'MoveItems',
        0x06: 'Move',
        0x07: 'SrcMsgId',
        0x08: 'SrcFldId',
        0x09: 'DstFldId',
        0x0A: 'Response',
        0x0B: 'Status',
        0x0C: 'DstMsgId',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
