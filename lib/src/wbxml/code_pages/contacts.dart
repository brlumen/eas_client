/// Code Page 1: Contacts namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.2
library;

import 'code_page.dart';

class ContactsCodePage extends CodePage {
  static final ContactsCodePage instance = ContactsCodePage._();

  ContactsCodePage._();

  @override
  int get pageIndex => 1;

  @override
  String get namespace => 'Contacts';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Anniversary',
        0x06: 'AssistantName',
        0x07: 'AssistantPhoneNumber',
        0x08: 'Birthday',
        0x09: 'Body',
        0x0A: 'BodySize',
        0x0B: 'BodyTruncated',
        0x0C: 'Business2PhoneNumber',
        0x0D: 'BusinessAddressCity',
        0x0E: 'BusinessAddressCountry',
        0x0F: 'BusinessAddressPostalCode',
        0x10: 'BusinessAddressState',
        0x11: 'BusinessAddressStreet',
        0x12: 'BusinessFaxNumber',
        0x13: 'BusinessPhoneNumber',
        0x14: 'CarPhoneNumber',
        0x15: 'Categories',
        0x16: 'Category',
        0x17: 'Children',
        0x18: 'Child',
        0x19: 'CompanyName',
        0x1A: 'Department',
        0x1B: 'Email1Address',
        0x1C: 'Email2Address',
        0x1D: 'Email3Address',
        0x1E: 'FileAs',
        0x1F: 'FirstName',
        0x20: 'Home2PhoneNumber',
        0x21: 'HomeAddressCity',
        0x22: 'HomeAddressCountry',
        0x23: 'HomeAddressPostalCode',
        0x24: 'HomeAddressState',
        0x25: 'HomeAddressStreet',
        0x26: 'HomeFaxNumber',
        0x27: 'HomePhoneNumber',
        0x28: 'JobTitle',
        0x29: 'LastName',
        0x2A: 'MiddleName',
        0x2B: 'MobilePhoneNumber',
        0x2C: 'OfficeLocation',
        0x2D: 'OtherAddressCity',
        0x2E: 'OtherAddressCountry',
        0x2F: 'OtherAddressPostalCode',
        0x30: 'OtherAddressState',
        0x31: 'OtherAddressStreet',
        0x32: 'PagerNumber',
        0x33: 'RadioPhoneNumber',
        0x34: 'Spouse',
        0x35: 'Suffix',
        0x36: 'Title',
        0x37: 'WebPage',
        0x38: 'YomiCompanyName',
        0x39: 'YomiFirstName',
        0x3A: 'YomiLastName',
        0x3C: 'Picture',
        0x3D: 'Alias',
        0x3E: 'WeightedRank',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
