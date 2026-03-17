/// Serializes EasTask to WBXML ApplicationData for Sync Add/Change.
library;

import '../models/eas_recurrence.dart';
import '../models/eas_task.dart';
import '../serializers/calendar_serializer.dart';
import '../wbxml/wbxml_document.dart';

/// Serializer for task items (Sync Add/Change).
class TaskSerializer {
  const TaskSerializer._();

  /// Serialize task for Sync Add/Change ApplicationData.
  static WbxmlElement serialize(EasTask task) {
    final children = <WbxmlElement>[];

    if (task.subject.isNotEmpty) {
      children.add(WbxmlElement.withText(
        namespace: 'Tasks',
        tag: 'Subject',
        text: task.subject,
        codePageIndex: 9,
      ));
    }

    children.add(WbxmlElement.withText(
      namespace: 'Tasks',
      tag: 'Importance',
      text: task.importance.toString(),
      codePageIndex: 9,
    ));

    children.add(WbxmlElement.withText(
      namespace: 'Tasks',
      tag: 'Complete',
      text: task.complete ? '1' : '0',
      codePageIndex: 9,
    ));

    if (task.startDate != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Tasks',
        tag: 'StartDate',
        text: task.startDate!.toUtc().toIso8601String(),
        codePageIndex: 9,
      ));
    }

    if (task.dueDate != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Tasks',
        tag: 'DueDate',
        text: task.dueDate!.toUtc().toIso8601String(),
        codePageIndex: 9,
      ));
    }

    if (task.dateCompleted != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Tasks',
        tag: 'DateCompleted',
        text: task.dateCompleted!.toUtc().toIso8601String(),
        codePageIndex: 9,
      ));
    }

    children.add(WbxmlElement.withText(
      namespace: 'Tasks',
      tag: 'Sensitivity',
      text: task.sensitivity.toString(),
      codePageIndex: 9,
    ));

    children.add(WbxmlElement.withText(
      namespace: 'Tasks',
      tag: 'ReminderSet',
      text: task.reminderSet ? '1' : '0',
      codePageIndex: 9,
    ));

    if (task.reminderTime != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Tasks',
        tag: 'ReminderTime',
        text: task.reminderTime!.toUtc().toIso8601String(),
        codePageIndex: 9,
      ));
    }

    // Recurrence (uses Calendar code page tags)
    if (task.recurrence != null) {
      children.add(_serializeTaskRecurrence(task.recurrence!));
    }

    // Categories
    if (task.categories.isNotEmpty) {
      children.add(WbxmlElement(
        namespace: 'Tasks',
        tag: 'Categories',
        codePageIndex: 9,
        children: task.categories
            .map((c) => WbxmlElement.withText(
                  namespace: 'Tasks',
                  tag: 'Category',
                  text: c,
                  codePageIndex: 9,
                ))
            .toList(),
      ));
    }

    // Body
    if (task.body != null) {
      children.add(WbxmlElement(
        namespace: 'AirSyncBase',
        tag: 'Body',
        codePageIndex: 17,
        children: [
          WbxmlElement.withText(
            namespace: 'AirSyncBase',
            tag: 'Type',
            text: '1',
            codePageIndex: 17,
          ),
          WbxmlElement.withText(
            namespace: 'AirSyncBase',
            tag: 'Data',
            text: task.body!,
            codePageIndex: 17,
          ),
        ],
      ));
    }

    return WbxmlElement(
      namespace: 'AirSync',
      tag: 'ApplicationData',
      codePageIndex: 0,
      children: children,
    );
  }

  /// Task recurrence uses Tasks code page for Recurrence container
  /// but Calendar code page for inner elements.
  static WbxmlElement _serializeTaskRecurrence(EasRecurrence rec) {
    // Reuse CalendarSerializer's recurrence but wrap in Tasks namespace
    final calRec = CalendarSerializer.serializeRecurrence(rec);
    return WbxmlElement(
      namespace: 'Tasks',
      tag: 'Recurrence',
      codePageIndex: 9,
      children: calRec.children,
    );
  }
}
