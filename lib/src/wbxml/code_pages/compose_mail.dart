/// Code Page 21: ComposeMail namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.22
library;

import 'code_page.dart';

class ComposeMailCodePage extends CodePage {
  static final ComposeMailCodePage instance = ComposeMailCodePage._();

  ComposeMailCodePage._();

  @override
  int get pageIndex => 21;

  @override
  String get namespace => 'ComposeMail';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'SendMail',
        0x06: 'SmartForward',
        0x07: 'SmartReply',
        0x08: 'SaveInSentItems',
        0x09: 'ReplaceMime',
        0x0B: 'Source',
        0x0C: 'FolderId',
        0x0D: 'ItemId',
        0x0E: 'LongId',
        0x0F: 'InstanceId',
        0x10: 'Mime',
        0x11: 'ClientId',
        0x12: 'Status',
        0x13: 'AccountId',
        0x15: 'Forwardees',
        0x16: 'Forwardee',
        0x17: 'ForwardeeName',
        0x18: 'ForwardeeEmail',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
