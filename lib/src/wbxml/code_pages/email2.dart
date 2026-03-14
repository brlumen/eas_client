/// Code Page 22: Email2 namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.23
library;

import 'code_page.dart';

class Email2CodePage extends CodePage {
  static final Email2CodePage instance = Email2CodePage._();

  Email2CodePage._();

  @override
  int get pageIndex => 22;

  @override
  String get namespace => 'Email2';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'UmCallerID',
        0x06: 'UmUserNotes',
        0x07: 'UmAttDuration',
        0x08: 'UmAttOrder',
        0x09: 'ConversationId',
        0x0A: 'ConversationIndex',
        0x0B: 'LastVerbExecuted',
        0x0C: 'LastVerbExecutionTime',
        0x0D: 'ReceivedAsBcc',
        0x0E: 'Sender',
        0x0F: 'CalendarType',
        0x10: 'IsLeapMonth',
        0x11: 'AccountId',
        0x12: 'FirstDayOfWeek',
        0x13: 'MeetingMessageType',
        0x15: 'IsDraft',
        0x16: 'Bcc',
        0x17: 'Send',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
