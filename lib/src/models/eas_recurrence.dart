/// EAS recurrence model (shared by Calendar, Tasks and meeting requests).
///
/// Reference: MS-ASCAL 2.2.2.37, MS-ASTASK 2.2.2.18, MS-ASEMAIL 2.2.2.59
library;

import '../wbxml/wbxml_document.dart';
import 'wbxml_helpers.dart';

/// Recurrence pattern for calendar events, tasks and meeting requests.
class EasRecurrence {
  /// Recurrence type:
  /// - 0 = daily
  /// - 1 = weekly
  /// - 2 = monthly (Nth day)
  /// - 3 = monthly (specific day of week in Nth week)
  /// - 5 = yearly (Nth day of month)
  /// - 6 = yearly (specific day of week in Nth week of month)
  final int type;

  /// End date of recurrence (UTC). Null = no end.
  final DateTime? until;

  /// Number of occurrences. Null = unlimited (or until [until]).
  final int? occurrences;

  /// Interval between recurrences (e.g., every 2 weeks).
  final int interval;

  /// Day of week bitmask (1=Sun, 2=Mon, 4=Tue, 8=Wed, 16=Thu, 32=Fri, 64=Sat).
  final int? dayOfWeek;

  /// Day of the month (1-31).
  final int? dayOfMonth;

  /// Week of the month (1-5, where 5 = last).
  final int? weekOfMonth;

  /// Month of the year (1-12).
  final int? monthOfYear;

  /// Calendar type (MS-ASCAL 2.2.2.10): 0=default, 1=Gregorian, etc.
  final int? calendarType;

  /// Whether the month is a leap month (used with non-Gregorian calendars).
  final bool? isLeapMonth;

  /// First day of the week (0=Sun, 1=Mon, ..., 6=Sat).
  final int? firstDayOfWeek;

  /// Start of the recurrence (Tasks only, `tasks:Start`).
  final DateTime? start;

  /// Whether the task regenerates after completion (Tasks only).
  final bool? regenerate;

  /// Whether the task recurrence has a dead occurrence (Tasks only).
  final bool? deadOccur;

  const EasRecurrence({
    required this.type,
    this.until,
    this.occurrences,
    this.interval = 1,
    this.dayOfWeek,
    this.dayOfMonth,
    this.weekOfMonth,
    this.monthOfYear,
    this.calendarType,
    this.isLeapMonth,
    this.firstDayOfWeek,
    this.start,
    this.regenerate,
    this.deadOccur,
  });

  /// Parse a `Recurrence` element whose children are in namespace [ns]
  /// (`Calendar`, `Tasks` or `Email`). For `Email` (meeting requests)
  /// CalendarType/IsLeapMonth/FirstDayOfWeek are in `Email2`.
  factory EasRecurrence.fromElement(WbxmlElement el, String ns) {
    final ext = ns == 'Email' ? 'Email2' : ns;
    return EasRecurrence(
      type: el.integer(ns, 'Type') ?? 0,
      until: el.date(ns, 'Until'),
      occurrences: el.integer(ns, 'Occurrences'),
      interval: el.integer(ns, 'Interval') ?? 1,
      dayOfWeek: el.integer(ns, 'DayOfWeek'),
      dayOfMonth: el.integer(ns, 'DayOfMonth'),
      weekOfMonth: el.integer(ns, 'WeekOfMonth'),
      monthOfYear: el.integer(ns, 'MonthOfYear'),
      calendarType: el.integer(ext, 'CalendarType'),
      isLeapMonth: el.boolean(ext, 'IsLeapMonth'),
      firstDayOfWeek: el.integer(ext, 'FirstDayOfWeek'),
      start: ns == 'Tasks' ? el.date(ns, 'Start') : null,
      regenerate: ns == 'Tasks' ? el.boolean(ns, 'Regenerate') : null,
      deadOccur: ns == 'Tasks' ? el.boolean(ns, 'DeadOccur') : null,
    );
  }

  @override
  String toString() => 'EasRecurrence(type: $type, interval: $interval)';
}
