/// Code Page 4: Calendar namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.5
library;

import 'code_page.dart';

class CalendarCodePage extends CodePage {
  static final CalendarCodePage instance = CalendarCodePage._();

  CalendarCodePage._();

  @override
  int get pageIndex => 4;

  @override
  String get namespace => 'Calendar';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Timezone',
        0x06: 'AllDayEvent',
        0x07: 'Attendees',
        0x08: 'Attendee',
        0x09: 'Email',
        0x0A: 'Name',
        0x0B: 'Body',
        0x0C: 'BodyTruncated',
        0x0D: 'BusyStatus',
        0x0E: 'Categories',
        0x0F: 'Category',
        0x11: 'DtStamp',
        0x12: 'EndTime',
        0x13: 'Exception',
        0x14: 'Exceptions',
        0x15: 'Deleted',
        0x16: 'ExceptionStartTime',
        0x17: 'Location',
        0x18: 'MeetingStatus',
        0x19: 'OrganizerEmail',
        0x1A: 'OrganizerName',
        0x1B: 'Recurrence',
        0x1C: 'Type',
        0x1D: 'Until',
        0x1E: 'Occurrences',
        0x1F: 'Interval',
        0x20: 'DayOfWeek',
        0x21: 'DayOfMonth',
        0x22: 'WeekOfMonth',
        0x23: 'MonthOfYear',
        0x24: 'Reminder',
        0x25: 'Sensitivity',
        0x26: 'Subject',
        0x27: 'StartTime',
        0x28: 'UID',
        0x29: 'AttendeeStatus',
        0x2A: 'AttendeeType',
        0x33: 'DisallowNewTimeProposal',
        0x34: 'ResponseRequested',
        0x35: 'AppointmentReplyTime',
        0x36: 'ResponseType',
        0x37: 'CalendarType',
        0x38: 'IsLeapMonth',
        0x39: 'FirstDayOfWeek',
        0x3A: 'OnlineMeetingConfLink',
        0x3B: 'OnlineMeetingExternalLink',
        0x3C: 'ClientUid',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
