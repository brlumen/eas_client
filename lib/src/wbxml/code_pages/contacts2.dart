/// Code Page 12: Contacts2 namespace.
///
/// Extended contact fields not present in the base Contacts code page.
///
/// Reference: MS-ASWBXML section 2.2.2.12
library;

import 'code_page.dart';

class Contacts2CodePage extends CodePage {
  static final Contacts2CodePage instance = Contacts2CodePage._();

  Contacts2CodePage._();

  @override
  int get pageIndex => 12;

  @override
  String get namespace => 'Contacts2';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'CustomerId',
        0x06: 'GovernmentId',
        0x07: 'IMAddress',
        0x08: 'IMAddress2',
        0x09: 'IMAddress3',
        0x0A: 'ManagerName',
        0x0B: 'CompanyMainPhone',
        0x0C: 'AccountName',
        0x0D: 'NickName',
        0x0E: 'MMS',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
