/// Internal: parse a content-class item from a `Properties` element of
/// Search / Find / ItemOperations responses. Not exported.
library;

import '../models/eas_calendar_event.dart';
import '../models/eas_contact.dart';
import '../models/eas_email.dart';
import '../models/eas_note.dart';
import '../models/eas_task.dart';
import '../wbxml/wbxml_document.dart';

/// Typed item for [className] (`airsync:Class`): [EasEmail] (Email, SMS),
/// [EasCalendarEvent], [EasContact], [EasTask] or [EasNote]; `null` for
/// other classes or missing properties.
Object? parseContentItem(
  String? className,
  String serverId,
  WbxmlElement? props,
) {
  if (props == null) return null;
  return switch (className) {
    'Email' || 'SMS' => EasEmail.fromApplicationData(serverId, props),
    'Calendar' => EasCalendarEvent.fromApplicationData(serverId, props),
    'Contacts' => EasContact.fromApplicationData(serverId, props),
    'Tasks' => EasTask.fromApplicationData(serverId, props),
    'Notes' => EasNote.fromApplicationData(serverId, props),
    _ => null,
  };
}
