/// EAS recurrence model (shared by Calendar and Tasks).
///
/// Reference: MS-ASCAL section 2.2.2.42, MS-ASTASK section 2.2.2.15
library;

/// Recurrence pattern for calendar events and tasks.
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

  /// Calendar type (MS-ASCAL 2.2.2.6):
  /// 0=default, 1=Gregorian, etc.
  final int? calendarType;

  /// Whether the month is a leap month (used with non-Gregorian calendars).
  final bool? isLeapMonth;

  /// First day of the week (0=Sun, 1=Mon, ..., 6=Sat).
  final int? firstDayOfWeek;

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
  });

  @override
  String toString() => 'EasRecurrence(type: $type, interval: $interval)';
}
