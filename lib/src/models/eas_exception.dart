/// EAS calendar exception model (modified/deleted instances of recurring events).
///
/// Reference: MS-ASCAL section 2.2.2.19
library;

import 'eas_calendar_event.dart';

/// An exception to a recurring calendar event.
///
/// Represents either a deleted occurrence or a modified occurrence
/// of a recurring event.
class EasCalendarException {
  /// Original start time of this occurrence (UTC).
  final DateTime exceptionStartTime;

  /// Whether this occurrence is deleted (true) or modified (false).
  final bool deleted;

  /// Modified subject (null = same as parent).
  final String? subject;

  /// Modified start time (null = same as parent).
  final DateTime? startTime;

  /// Modified end time (null = same as parent).
  final DateTime? endTime;

  /// Modified location (null = same as parent).
  final String? location;

  /// Modified body (null = same as parent).
  final String? body;

  /// Modified all-day flag (null = same as parent).
  final bool? allDayEvent;

  /// Modified busy status (null = same as parent).
  final int? busyStatus;

  /// Modified sensitivity (null = same as parent).
  final int? sensitivity;

  /// Modified reminder (null = same as parent).
  final int? reminder;

  /// Modified attendees (null = same as parent).
  final List<EasAttendee>? attendees;

  /// Modified categories (null = same as parent).
  final List<String>? categories;

  const EasCalendarException({
    required this.exceptionStartTime,
    this.deleted = false,
    this.subject,
    this.startTime,
    this.endTime,
    this.location,
    this.body,
    this.allDayEvent,
    this.busyStatus,
    this.sensitivity,
    this.reminder,
    this.attendees,
    this.categories,
  });

  @override
  String toString() =>
      'EasCalendarException(${deleted ? "deleted" : "modified"}, $exceptionStartTime)';
}
