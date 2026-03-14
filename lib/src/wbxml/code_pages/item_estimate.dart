/// Code Page 6: GetItemEstimate namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.7
library;

import 'code_page.dart';

class ItemEstimateCodePage extends CodePage {
  static final ItemEstimateCodePage instance = ItemEstimateCodePage._();

  ItemEstimateCodePage._();

  @override
  int get pageIndex => 6;

  @override
  String get namespace => 'GetItemEstimate';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'GetItemEstimate',
        0x07: 'Collections',
        0x08: 'Collection',
        0x09: 'Class',
        0x0A: 'CollectionId',
        0x0C: 'Estimate',
        0x0D: 'Response',
        0x0E: 'Status',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
