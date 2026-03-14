/// Code Page 16: GAL (Global Address List) namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.17
library;

import 'code_page.dart';

class GalCodePage extends CodePage {
  static final GalCodePage instance = GalCodePage._();

  GalCodePage._();

  @override
  int get pageIndex => 16;

  @override
  String get namespace => 'GAL';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'DisplayName',
        0x06: 'Phone',
        0x07: 'Office',
        0x08: 'Title',
        0x09: 'Company',
        0x0A: 'Alias',
        0x0B: 'FirstName',
        0x0C: 'LastName',
        0x0D: 'HomePhone',
        0x0E: 'MobilePhone',
        0x0F: 'EmailAddress',
        0x10: 'Picture',
        0x11: 'Status',
        0x12: 'Data',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
