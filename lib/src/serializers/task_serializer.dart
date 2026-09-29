/// Serializes EasTask to WBXML ApplicationData for Sync Add/Change.
///
/// Reference: MS-ASTASK 2.2.2; writable elements per MS-ASCMD 6.45.
library;

import '../models/eas_body.dart';
import '../models/eas_recurrence.dart';
import '../models/eas_task.dart';
import '../models/wbxml_helpers.dart';
import '../wbxml/wbxml_document.dart';

/// Serializer for task items (Sync Add/Change).
class TaskSerializer {
  const TaskSerializer._();

  static const _ns = 'Tasks';

  /// Serialize task for Sync Add/Change ApplicationData.
  ///
  /// OrdinalDate/SubOrdinalDate are server-maintained and not sent.
  static WbxmlElement serialize(
    EasTask task, {
    String protocolVersion = '16.1',
  }) {
    final v = protocolVersionValue(protocolVersion);
    final c = <WbxmlElement>[];
    if (task.body case final body?) {
      if (v < 120) {
        c.addText(_ns, 'Body', body);
      } else {
        c.add(EasBody.toElement(body, type: task.bodyDetails?.type ?? 1));
      }
    }
    c
      ..addText(_ns, 'Subject', task.subject)
      ..addText(_ns, 'Importance', task.importance)
      ..addDate(_ns, 'UtcStartDate', task.utcStartDate ?? task.startDate)
      ..addDate(_ns, 'StartDate', task.startDate, wallClock: true)
      ..addDate(_ns, 'UtcDueDate', task.utcDueDate ?? task.dueDate)
      ..addDate(_ns, 'DueDate', task.dueDate, wallClock: true)
      ..addList(_ns, 'Categories', 'Category', task.categories);
    if (task.recurrence case final rec?) {
      c.add(serializeRecurrence(rec, protocolVersion: protocolVersion));
    }
    c
      ..addText(_ns, 'Complete', task.complete)
      ..addDate(_ns, 'DateCompleted', task.dateCompleted)
      ..addText(_ns, 'Sensitivity', task.sensitivity)
      ..addDate(_ns, 'ReminderTime', task.reminderTime)
      ..addText(_ns, 'ReminderSet', task.reminderSet);
    return applicationData(c);
  }

  /// Serialize a `Tasks:Recurrence` element (all children in the Tasks
  /// namespace, MS-ASTASK 2.2.2.18).
  static WbxmlElement serializeRecurrence(
    EasRecurrence rec, {
    String protocolVersion = '16.1',
  }) {
    final v = protocolVersionValue(protocolVersion);
    final c = <WbxmlElement>[]
      ..addText(_ns, 'Type', rec.type)
      ..addDate(_ns, 'Start', rec.start)
      ..addDate(_ns, 'Until', rec.until)
      ..addText(_ns, 'Occurrences', rec.occurrences)
      ..addText(_ns, 'Interval', rec.interval)
      ..addText(_ns, 'DayOfWeek', rec.dayOfWeek)
      ..addText(_ns, 'DayOfMonth', rec.dayOfMonth)
      ..addText(_ns, 'WeekOfMonth', rec.weekOfMonth)
      ..addText(_ns, 'MonthOfYear', rec.monthOfYear)
      ..addText(_ns, 'Regenerate', rec.regenerate)
      ..addText(_ns, 'DeadOccur', rec.deadOccur);
    if (v >= 140) {
      c
        ..addText(_ns, 'CalendarType', rec.calendarType)
        ..addText(_ns, 'IsLeapMonth', rec.isLeapMonth);
    }
    if (v >= 141) c.addText(_ns, 'FirstDayOfWeek', rec.firstDayOfWeek);
    return containerEl(_ns, 'Recurrence', c);
  }
}
