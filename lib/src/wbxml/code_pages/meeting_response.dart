/// Code Page 8: MeetingResponse namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.9
library;

import 'code_page.dart';

class MeetingResponseCodePage extends CodePage {
  static final MeetingResponseCodePage instance = MeetingResponseCodePage._();

  MeetingResponseCodePage._();

  @override
  int get pageIndex => 8;

  @override
  String get namespace => 'MeetingResponse';

  @override
  Map<int, String> get tokenToTag => const {
    0x05: 'CalendarId',
    0x06: 'CollectionId',
    0x07: 'MeetingResponse',
    0x08: 'RequestId',
    0x09: 'Request',
    0x0A: 'Result',
    0x0B: 'Status',
    0x0C: 'UserResponse',
    0x0E: 'InstanceId',
    0x10: 'ProposedStartTime',
    0x11: 'ProposedEndTime',
    0x12: 'SendResponse',
  };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
