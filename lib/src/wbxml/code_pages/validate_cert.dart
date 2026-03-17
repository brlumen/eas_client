/// Code Page 11: ValidateCert namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.12
library;

import 'code_page.dart';

class ValidateCertCodePage extends CodePage {
  static final ValidateCertCodePage instance = ValidateCertCodePage._();

  ValidateCertCodePage._();

  @override
  int get pageIndex => 11;

  @override
  String get namespace => 'ValidateCert';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'ValidateCert',
        0x06: 'Certificates',
        0x07: 'Certificate',
        0x08: 'CertificateChain',
        0x09: 'CheckCRL',
        0x0A: 'Status',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
