/// EAS task model.
library;

import 'eas_recurrence.dart';

/// EAS task (to-do item).
class EasTask {
  /// Server-assigned ID.
  final String serverId;

  /// Task subject.
  final String subject;

  /// Whether the task is complete.
  final bool complete;

  /// Due date (UTC).
  final DateTime? dueDate;

  /// Start date (UTC).
  final DateTime? startDate;

  /// Date completed (UTC).
  final DateTime? dateCompleted;

  /// Importance: 0=low, 1=normal, 2=high.
  final int importance;

  /// Task body/notes.
  final String? body;

  /// Sensitivity: 0=normal, 1=personal, 2=private, 3=confidential.
  final int sensitivity;

  /// Whether a reminder is set.
  final bool reminderSet;

  /// Reminder date/time (UTC).
  final DateTime? reminderTime;

  /// Categories.
  final List<String> categories;

  /// Recurrence pattern (null = non-recurring).
  final EasRecurrence? recurrence;

  /// Ordinal date for task ordering.
  final String? ordinalDate;

  /// Sub-ordinal date for task ordering.
  final String? subOrdinalDate;

  /// Calendar type (0=default, 1=Gregorian, etc.).
  final int? calendarType;

  const EasTask({
    required this.serverId,
    this.subject = '',
    this.complete = false,
    this.dueDate,
    this.startDate,
    this.dateCompleted,
    this.importance = 1,
    this.body,
    this.sensitivity = 0,
    this.reminderSet = false,
    this.reminderTime,
    this.categories = const [],
    this.recurrence,
    this.ordinalDate,
    this.subOrdinalDate,
    this.calendarType,
  });

  @override
  String toString() =>
      'EasTask($serverId, subject: $subject, complete: $complete)';
}
