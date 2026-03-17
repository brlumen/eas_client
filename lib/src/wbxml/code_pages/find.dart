/// Code Page 25: Find namespace (EAS 16.1).
///
/// Reference: MS-ASWBXML section 2.2.2.25
library;

import 'code_page.dart';

class FindCodePage extends CodePage {
  static final FindCodePage instance = FindCodePage._();

  FindCodePage._();

  @override
  int get pageIndex => 25;

  @override
  String get namespace => 'Find';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Find',
        0x06: 'SearchId',
        0x07: 'ExecuteSearch',
        0x08: 'MailBoxSearchCriterion',
        0x09: 'Query',
        0x0A: 'Status',
        0x0B: 'FreeText',
        0x0C: 'Options',
        0x0D: 'Range',
        0x0E: 'DeepTraversal',
        0x11: 'Response',
        0x12: 'Result',
        0x13: 'Properties',
        0x14: 'Preview',
        0x15: 'HasAttachments',
        0x16: 'Total',
        0x17: 'DisplayCc',
        0x18: 'DisplayBcc',
        0x19: 'GALSearchCriterion',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
