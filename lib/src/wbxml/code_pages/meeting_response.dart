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
        0x09: 'RequestId',
        0x0A: 'Request',
        0x0B: 'Result',
        0x0C: 'Status',
        0x0D: 'UserResponse',
        0x0F: 'InstanceId',
        0x11: 'ProposedStartTime',
        0x12: 'ProposedEndTime',
        0x13: 'SendResponse',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
