/// EAS task model (MS-ASTASK).
library;

import '../wbxml/wbxml_document.dart';
import 'eas_body.dart';
import 'eas_recurrence.dart';
import 'wbxml_helpers.dart';

/// EAS task (to-do item).
class EasTask {
  /// Server-assigned ID.
  final String serverId;

  /// Task subject.
  final String subject;

  /// Whether the task is complete.
  final bool complete;

  /// Due date (local time of the task, as sent by the server).
  final DateTime? dueDate;

  /// Due date in UTC (`UtcDueDate`).
  final DateTime? utcDueDate;

  /// Start date (local time of the task).
  final DateTime? startDate;

  /// Start date in UTC (`UtcStartDate`).
  final DateTime? utcStartDate;

  /// Date completed (UTC).
  final DateTime? dateCompleted;

  /// Importance: 0=low, 1=normal, 2=high.
  final int importance;

  /// Task body/notes.
  final String? body;

  /// Full `airsyncbase:Body`, if present.
  final EasBody? bodyDetails;

  /// Native body type on the server.
  final int? nativeBodyType;

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

  /// Ordinal date for task ordering (dateTime string).
  final String? ordinalDate;

  /// Sub-ordinal date for task ordering.
  final String? subOrdinalDate;

  /// Calendar type of the recurrence (0=default, 1=Gregorian, etc.).
  final int? calendarType;

  const EasTask({
    required this.serverId,
    this.subject = '',
    this.complete = false,
    this.dueDate,
    this.utcDueDate,
    this.startDate,
    this.utcStartDate,
    this.dateCompleted,
    this.importance = 1,
    this.body,
    this.bodyDetails,
    this.nativeBodyType,
    this.sensitivity = 0,
    this.reminderSet = false,
    this.reminderTime,
    this.categories = const [],
    this.recurrence,
    this.ordinalDate,
    this.subOrdinalDate,
    this.calendarType,
  });

  /// Parse a task from `ApplicationData` / `Properties`.
  factory EasTask.fromApplicationData(String serverId, WbxmlElement data) {
    const ns = 'Tasks';
    final bodyDetails = EasBody.anyOf(data, ns);
    final recurrenceEl = data.findChild(ns, 'Recurrence');
    final recurrence = recurrenceEl == null
        ? null
        : EasRecurrence.fromElement(recurrenceEl, ns);
    return EasTask(
      serverId: serverId,
      subject: data.str(ns, 'Subject') ?? '',
      complete: data.boolean(ns, 'Complete') ?? false,
      dueDate: data.date(ns, 'DueDate'),
      utcDueDate: data.date(ns, 'UtcDueDate'),
      startDate: data.date(ns, 'StartDate'),
      utcStartDate: data.date(ns, 'UtcStartDate'),
      dateCompleted: data.date(ns, 'DateCompleted'),
      importance: data.integer(ns, 'Importance') ?? 1,
      body: bodyDetails?.data,
      bodyDetails: bodyDetails,
      nativeBodyType: data.integer('AirSyncBase', 'NativeBodyType'),
      sensitivity: data.integer(ns, 'Sensitivity') ?? 0,
      reminderSet: data.boolean(ns, 'ReminderSet') ?? false,
      reminderTime: data.date(ns, 'ReminderTime'),
      categories: data.list(ns, 'Categories', 'Category') ?? const [],
      recurrence: recurrence,
      ordinalDate: data.str(ns, 'OrdinalDate'),
      subOrdinalDate: data.str(ns, 'SubOrdinalDate'),
      calendarType:
          data.integer(ns, 'CalendarType') ?? recurrence?.calendarType,
    );
  }

  @override
  String toString() => 'EasTask($serverId, complete: $complete)';
}
