/// Code Page 9: Tasks namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.10
library;

import 'code_page.dart';

class TasksCodePage extends CodePage {
  static final TasksCodePage instance = TasksCodePage._();

  TasksCodePage._();

  @override
  int get pageIndex => 9;

  @override
  String get namespace => 'Tasks';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Body',
        0x06: 'BodySize',
        0x07: 'BodyTruncated',
        0x08: 'Categories',
        0x09: 'Category',
        0x0A: 'Complete',
        0x0B: 'DateCompleted',
        0x0C: 'DueDate',
        0x0D: 'UtcDueDate',
        0x0E: 'Importance',
        0x0F: 'Recurrence',
        0x10: 'Type',
        0x11: 'Start',
        0x12: 'Until',
        0x13: 'Occurrences',
        0x14: 'Interval',
        0x15: 'DayOfMonth',
        0x16: 'DayOfWeek',
        0x17: 'WeekOfMonth',
        0x18: 'MonthOfYear',
        0x19: 'Regenerate',
        0x1A: 'DeadOccur',
        0x1B: 'ReminderSet',
        0x1C: 'ReminderTime',
        0x1D: 'Sensitivity',
        0x1E: 'StartDate',
        0x1F: 'UtcStartDate',
        0x20: 'Subject',
        0x22: 'OrdinalDate',
        0x23: 'SubOrdinalDate',
        0x24: 'CalendarType',
        0x25: 'IsLeapMonth',
        0x26: 'FirstDayOfWeek',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
