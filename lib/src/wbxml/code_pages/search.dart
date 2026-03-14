/// Code Page 15: Search namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.16
library;

import 'code_page.dart';

class SearchCodePage extends CodePage {
  static final SearchCodePage instance = SearchCodePage._();

  SearchCodePage._();

  @override
  int get pageIndex => 15;

  @override
  String get namespace => 'Search';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Search',
        0x07: 'Store',
        0x08: 'Name',
        0x09: 'Query',
        0x0A: 'Options',
        0x0B: 'Range',
        0x0C: 'Status',
        0x0D: 'Response',
        0x0E: 'Result',
        0x0F: 'Properties',
        0x10: 'Total',
        0x11: 'EqualTo',
        0x12: 'Value',
        0x13: 'And',
        0x14: 'Or',
        0x15: 'FreeText',
        0x17: 'DeepTraversal',
        0x18: 'LongId',
        0x19: 'RebuildResults',
        0x1A: 'LessThan',
        0x1B: 'GreaterThan',
        0x1E: 'UserName',
        0x1F: 'Password',
        0x20: 'ConversationId',
        0x21: 'Picture',
        0x22: 'MaxSize',
        0x23: 'MaxPictures',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
