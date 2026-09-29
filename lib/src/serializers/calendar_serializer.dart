/// Serializes EasCalendarEvent to WBXML ApplicationData for Sync Add/Change.
///
/// Version-specific rules (MS-ASCAL 2.2.2):
/// - 16.0/16.1: `UID`, `DtStamp`, `OrganizerName`, `OrganizerEmail` and
///   `AttendeeStatus` MUST NOT be sent; `ClientUid` is sent instead of
///   `UID`; `airsyncbase:Location` replaces `calendar:Location`;
///   exceptions are identified by `airsyncbase:InstanceId`; attachments
///   can be added/deleted.
/// - ≤14.1: `calendar:Location`, `ExceptionStartTime`.
/// - 2.5: `calendar:Body`, exception `UID`.
/// - 16.0/16.1: an all-day event is sent without `Timezone`; exceptions
///   are not sent in a Change (occurrences are changed via `InstanceId`,
///   see [CalendarSerializer.serializeOccurrence]); an empty `Reminder`
///   removes the reminder.
/// - `BusyStatus` 4 (working elsewhere) is not allowed in command requests
///   in any version and is omitted.
/// - `ResponseType`, `AppointmentReplyTime` and online meeting links are
///   server-only and never sent.
library;

import '../models/eas_attachment.dart';
import '../models/eas_body.dart';
import '../models/eas_calendar_event.dart';
import '../models/eas_exception.dart';
import '../models/eas_location.dart';
import '../models/eas_recurrence.dart';
import '../models/wbxml_helpers.dart';
import '../wbxml/wbxml_document.dart';
import 'attachment_serializer.dart';

/// Serializer for calendar events (Sync Add/Change).
class CalendarSerializer {
  const CalendarSerializer._();

  static const _ns = 'Calendar';

  /// Serialize a calendar event for Sync Add/Change ApplicationData.
  ///
  /// [addAttachments] / [deleteAttachments] (FileReferences) are sent only
  /// for protocol 16.0+. [isChange]: the data is for a Sync Change (16.x
  /// forbids `Exceptions` there). [removeReminder]: with a `null`
  /// reminder, send an empty `Reminder` to create/update the event without
  /// a reminder (16.x only).
  static WbxmlElement serialize(
    EasCalendarEvent event, {
    String protocolVersion = '16.1',
    List<EasAttachmentAdd> addAttachments = const [],
    List<String> deleteAttachments = const [],
    bool isChange = false,
    bool removeReminder = false,
  }) {
    final v = protocolVersionValue(protocolVersion);
    final v16 = v >= 160;
    final c = <WbxmlElement>[];
    if (!(v16 && event.allDayEvent)) {
      c.addText(_ns, 'Timezone', event.timezone);
    }
    c.addText(_ns, 'AllDayEvent', event.allDayEvent);
    _addBody(c, event.body, event.bodyDetails?.type ?? 1, v);
    _addBusyStatus(c, event.busyStatus);
    if (!v16) {
      c
        ..addText(_ns, 'OrganizerName', event.organizerName)
        ..addText(_ns, 'OrganizerEmail', event.organizerEmail)
        ..addDate(_ns, 'DtStamp', event.dtStamp, compact: true);
    }
    c.addDate(_ns, 'EndTime', event.endTime, compact: true);
    _addLocation(c, event.location, event.locationDetails, v);
    _addReminder(c, event.reminder, removeReminder, v);
    c
      ..addText(_ns, 'Sensitivity', event.sensitivity)
      ..addText(_ns, 'Subject', event.subject)
      ..addDate(_ns, 'StartTime', event.startTime, compact: true);
    if (v16) {
      c.addText(_ns, 'ClientUid', event.clientUid);
    } else {
      c.addText(_ns, 'UID', event.uid);
    }
    c.addText(_ns, 'MeetingStatus', event.meetingStatus);
    if (event.attendees.isNotEmpty) {
      c.add(_attendees(event.attendees, v));
    }
    c.addList(_ns, 'Categories', 'Category', event.categories);
    if (event.recurrence case final rec?) {
      c.add(serializeRecurrence(rec, protocolVersion: protocolVersion));
    }
    if (event.exceptions.isNotEmpty && !(v16 && isChange)) {
      c.add(
        containerEl(_ns, 'Exceptions', [
          for (final e in event.exceptions) _exception(e, v),
        ]),
      );
    }
    if (v >= 140) {
      c
        ..addText(_ns, 'ResponseRequested', event.responseRequested)
        ..addText(
          _ns,
          'DisallowNewTimeProposal',
          event.disallowNewTimeProposal,
        );
    }
    if (v16) {
      final atts = AttachmentSerializer.serialize(
        add: addAttachments,
        delete: deleteAttachments,
      );
      if (atts != null) c.add(atts);
    }
    return applicationData(c);
  }

  /// Serialize the changes of a single occurrence of a recurring series
  /// for a Sync Change carrying `airsyncbase:InstanceId` (EAS 16.x).
  ///
  /// Only the properties that are set in [changes] are sent;
  /// `exceptionStartTime` identifies the occurrence and goes to
  /// [SyncChangeItem.instanceId], not into ApplicationData.
  static WbxmlElement serializeOccurrence(
    EasCalendarException changes, {
    String protocolVersion = '16.1',
    bool removeReminder = false,
  }) {
    final v = protocolVersionValue(protocolVersion);
    return applicationData(
      _exceptionProperties(changes, v, removeReminder: removeReminder),
    );
  }

  /// Serialize a `Calendar:Recurrence` element.
  static WbxmlElement serializeRecurrence(
    EasRecurrence rec, {
    String protocolVersion = '16.1',
  }) {
    final v = protocolVersionValue(protocolVersion);
    final c = <WbxmlElement>[]
      ..addText(_ns, 'Type', rec.type)
      ..addText(_ns, 'Occurrences', rec.occurrences)
      ..addText(_ns, 'Interval', rec.interval)
      ..addText(_ns, 'WeekOfMonth', rec.weekOfMonth)
      ..addText(_ns, 'DayOfWeek', rec.dayOfWeek)
      ..addText(_ns, 'MonthOfYear', rec.monthOfYear)
      ..addDate(_ns, 'Until', rec.until, compact: true)
      ..addText(_ns, 'DayOfMonth', rec.dayOfMonth);
    if (v >= 140) {
      c
        ..addText(_ns, 'CalendarType', rec.calendarType)
        ..addText(_ns, 'IsLeapMonth', rec.isLeapMonth);
    }
    if (v >= 141) c.addText(_ns, 'FirstDayOfWeek', rec.firstDayOfWeek);
    return containerEl(_ns, 'Recurrence', c);
  }

  // ─── internals ──────────────────────────────────────────────────────────

  static void _addBody(List<WbxmlElement> c, String? body, int type, int v) {
    if (body == null) return;
    if (v < 120) {
      c.addText(_ns, 'Body', body);
    } else {
      c.add(EasBody.toElement(body, type: type));
    }
  }

  static void _addBusyStatus(List<WbxmlElement> c, int? busyStatus) {
    // 4 (working elsewhere) is response-only (MS-ASCAL 2.2.2.9).
    if (busyStatus != 4) c.addText(_ns, 'BusyStatus', busyStatus);
  }

  static void _addReminder(
    List<WbxmlElement> c,
    int? reminder,
    bool remove,
    int v,
  ) {
    if (reminder != null) {
      c.addText(_ns, 'Reminder', reminder);
    } else if (remove && v >= 160) {
      c.add(emptyEl(_ns, 'Reminder'));
    }
  }

  static void _addLocation(
    List<WbxmlElement> c,
    String? location,
    EasLocation? details,
    int v,
  ) {
    if (v >= 160) {
      final loc =
          details ??
          (location == null ? null : EasLocation(displayName: location));
      if (loc != null) c.add(loc.toElement());
    } else {
      c.addText(_ns, 'Location', location ?? details?.displayName);
    }
  }

  static WbxmlElement _attendees(List<EasAttendee> attendees, int v) =>
      containerEl(_ns, 'Attendees', [
        for (final a in attendees)
          containerEl(
            _ns,
            'Attendee',
            <WbxmlElement>[
                textEl(_ns, 'Email', a.email),
                textEl(_ns, 'Name', a.name ?? a.email),
              ]
              ..addText(
                _ns,
                'AttendeeStatus',
                v >= 120 && v < 160 ? a.status.value : null,
              )
              ..addText(_ns, 'AttendeeType', v >= 120 ? a.type.value : null),
          ),
      ]);

  static WbxmlElement _exception(EasCalendarException e, int v) {
    final c = <WbxmlElement>[]
      ..addText(_ns, 'Deleted', e.deleted ? true : null);
    if (v >= 160) {
      c.add(
        textEl(
          'AirSyncBase',
          'InstanceId',
          compactDateTime(e.exceptionStartTime),
        ),
      );
    } else {
      c.addDate(_ns, 'ExceptionStartTime', e.exceptionStartTime, compact: true);
      if (v < 120) c.addText(_ns, 'UID', e.uid);
    }
    c.addAll(_exceptionProperties(e, v));
    return containerEl(_ns, 'Exception', c);
  }

  /// Writable properties of an exception / occurrence.
  static List<WbxmlElement> _exceptionProperties(
    EasCalendarException e,
    int v, {
    bool removeReminder = false,
  }) {
    final c = <WbxmlElement>[]
      ..addText(_ns, 'Subject', e.subject)
      ..addDate(_ns, 'StartTime', e.startTime, compact: true)
      ..addDate(_ns, 'EndTime', e.endTime, compact: true);
    _addBody(c, e.body, e.bodyDetails?.type ?? 1, v);
    _addLocation(c, e.location, e.locationDetails, v);
    if (e.categories case final cats?) {
      c.add(
        containerEl(_ns, 'Categories', [
          for (final cat in cats) textEl(_ns, 'Category', cat),
        ]),
      );
    }
    c.addText(_ns, 'Sensitivity', e.sensitivity);
    _addBusyStatus(c, e.busyStatus);
    c.addText(_ns, 'AllDayEvent', e.allDayEvent);
    _addReminder(c, e.reminder, removeReminder, v);
    if (v < 160) c.addDate(_ns, 'DtStamp', e.dtStamp, compact: true);
    if (v >= 120) c.addText(_ns, 'MeetingStatus', e.meetingStatus);
    if (v >= 140 && e.attendees != null) c.add(_attendees(e.attendees!, v));
    if (v >= 160) {
      final atts = AttachmentSerializer.serialize(
        add: e.addAttachments,
        delete: e.deleteAttachments,
      );
      if (atts != null) c.add(atts);
    }
    return c;
  }
}
