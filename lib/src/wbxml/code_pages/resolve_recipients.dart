/// Code Page 10: ResolveRecipients namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.11
library;

import 'code_page.dart';

class ResolveRecipientsCodePage extends CodePage {
  static final ResolveRecipientsCodePage instance =
      ResolveRecipientsCodePage._();

  ResolveRecipientsCodePage._();

  @override
  int get pageIndex => 10;

  @override
  String get namespace => 'ResolveRecipients';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'ResolveRecipients',
        0x06: 'Response',
        0x07: 'Status',
        0x08: 'Type',
        0x09: 'Recipient',
        0x0A: 'DisplayName',
        0x0B: 'EmailAddress',
        0x0C: 'Certificates',
        0x0D: 'Certificate',
        0x0E: 'MiniCertificate',
        0x0F: 'Options',
        0x10: 'To',
        0x11: 'CertificateRetrieval',
        0x12: 'RecipientCount',
        0x13: 'MaxCertificates',
        0x14: 'MaxAmbiguousRecipients',
        0x15: 'CertificateCount',
        0x16: 'Availability',
        0x17: 'StartTime',
        0x18: 'EndTime',
        0x19: 'MergedFreeBusy',
        0x1A: 'Picture',
        0x1B: 'MaxSize',
        0x1C: 'Data',
        0x1D: 'MaxPictures',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
