/// Code Page 2: Email namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.3
library;

import 'code_page.dart';

class EmailCodePage extends CodePage {
  static final EmailCodePage instance = EmailCodePage._();

  EmailCodePage._();

  @override
  int get pageIndex => 2;

  @override
  String get namespace => 'Email';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Attachment',
        0x06: 'Attachments',
        0x07: 'AttName',
        0x08: 'AttSize',
        0x09: 'Att0id',
        0x0A: 'AttMethod',
        0x0C: 'Body',
        0x0D: 'BodySize',
        0x0E: 'BodyTruncated',
        0x0F: 'DateReceived',
        0x10: 'DisplayName',
        0x11: 'DisplayTo',
        0x12: 'Importance',
        0x13: 'MessageClass',
        0x14: 'Subject',
        0x15: 'Read',
        0x16: 'To',
        0x17: 'Cc',
        0x18: 'From',
        0x19: 'ReplyTo',
        0x1A: 'AllDayEvent',
        0x1B: 'Categories',
        0x1C: 'Category',
        0x1D: 'DtStamp',
        0x1E: 'EndTime',
        0x1F: 'InstanceType',
        0x20: 'BusyStatus',
        0x21: 'Location',
        0x22: 'MeetingRequest',
        0x23: 'Organizer',
        0x24: 'RecurrenceId',
        0x25: 'Reminder',
        0x26: 'ResponseRequested',
        0x27: 'Recurrences',
        0x28: 'Recurrence',
        0x29: 'Type',
        0x2A: 'Until',
        0x2B: 'Occurrences',
        0x2C: 'Interval',
        0x2D: 'DayOfWeek',
        0x2E: 'DayOfMonth',
        0x2F: 'WeekOfMonth',
        0x30: 'MonthOfYear',
        0x31: 'StartTime',
        0x32: 'Sensitivity',
        0x33: 'TimeZone',
        0x34: 'GlobalObjId',
        0x35: 'ThreadTopic',
        0x36: 'MIMEData',
        0x37: 'MIMETruncated',
        0x38: 'MIMESize',
        0x39: 'InternetCPID',
        0x3A: 'Flag',
        0x3B: 'Status',
        0x3C: 'ContentClass',
        0x3D: 'FlagType',
        0x3E: 'CompleteTime',
        0x3F: 'DisallowNewTimeProposal',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
