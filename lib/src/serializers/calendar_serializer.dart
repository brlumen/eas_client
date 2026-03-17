/// Serializes EasCalendarEvent to WBXML ApplicationData for Sync Add/Change.
library;

import '../models/eas_calendar_event.dart';
import '../models/eas_recurrence.dart';
import '../wbxml/wbxml_document.dart';

/// Serializer for calendar events (Sync Add/Change).
class CalendarSerializer {
  const CalendarSerializer._();

  /// Serialize calendar event for Sync Add/Change ApplicationData.
  static WbxmlElement serialize(EasCalendarEvent event) {
    final children = <WbxmlElement>[];

    if (event.subject.isNotEmpty) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'Subject',
        text: event.subject,
        codePageIndex: 4,
      ));
    }

    if (event.startTime != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'StartTime',
        text: event.startTime!.toUtc().toIso8601String(),
        codePageIndex: 4,
      ));
    }

    if (event.endTime != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'EndTime',
        text: event.endTime!.toUtc().toIso8601String(),
        codePageIndex: 4,
      ));
    }

    if (event.location != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'Location',
        text: event.location!,
        codePageIndex: 4,
      ));
    }

    children.add(WbxmlElement.withText(
      namespace: 'Calendar',
      tag: 'AllDayEvent',
      text: event.allDayEvent ? '1' : '0',
      codePageIndex: 4,
    ));

    children.add(WbxmlElement.withText(
      namespace: 'Calendar',
      tag: 'BusyStatus',
      text: event.busyStatus.toString(),
      codePageIndex: 4,
    ));

    children.add(WbxmlElement.withText(
      namespace: 'Calendar',
      tag: 'Sensitivity',
      text: event.sensitivity.toString(),
      codePageIndex: 4,
    ));

    if (event.uid != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'UID',
        text: event.uid!,
        codePageIndex: 4,
      ));
    }

    if (event.organizerName != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'OrganizerName',
        text: event.organizerName!,
        codePageIndex: 4,
      ));
    }

    if (event.organizerEmail != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'OrganizerEmail',
        text: event.organizerEmail!,
        codePageIndex: 4,
      ));
    }

    if (event.reminder != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'Reminder',
        text: event.reminder.toString(),
        codePageIndex: 4,
      ));
    }

    children.add(WbxmlElement.withText(
      namespace: 'Calendar',
      tag: 'MeetingStatus',
      text: event.meetingStatus.toString(),
      codePageIndex: 4,
    ));

    if (event.timezone != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'Timezone',
        text: event.timezone!,
        codePageIndex: 4,
      ));
    }

    if (event.dtStamp != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'DtStamp',
        text: event.dtStamp!.toUtc().toIso8601String(),
        codePageIndex: 4,
      ));
    }

    if (event.responseType != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'ResponseType',
        text: event.responseType.toString(),
        codePageIndex: 4,
      ));
    }

    if (event.disallowNewTimeProposal == true) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'DisallowNewTimeProposal',
        text: '1',
        codePageIndex: 4,
      ));
    }

    // Attendees
    if (event.attendees.isNotEmpty) {
      children.add(WbxmlElement(
        namespace: 'Calendar',
        tag: 'Attendees',
        codePageIndex: 4,
        children: event.attendees
            .map((att) => WbxmlElement(
                  namespace: 'Calendar',
                  tag: 'Attendee',
                  codePageIndex: 4,
                  children: [
                    WbxmlElement.withText(
                      namespace: 'Calendar',
                      tag: 'Email',
                      text: att.email,
                      codePageIndex: 4,
                    ),
                    if (att.name != null)
                      WbxmlElement.withText(
                        namespace: 'Calendar',
                        tag: 'Name',
                        text: att.name!,
                        codePageIndex: 4,
                      ),
                    WbxmlElement.withText(
                      namespace: 'Calendar',
                      tag: 'AttendeeStatus',
                      text: att.status.value.toString(),
                      codePageIndex: 4,
                    ),
                    WbxmlElement.withText(
                      namespace: 'Calendar',
                      tag: 'AttendeeType',
                      text: att.type.value.toString(),
                      codePageIndex: 4,
                    ),
                  ],
                ))
            .toList(),
      ));
    }

    // Recurrence
    if (event.recurrence != null) {
      children.add(serializeRecurrence(event.recurrence!));
    }

    // Categories
    if (event.categories.isNotEmpty) {
      children.add(WbxmlElement(
        namespace: 'Calendar',
        tag: 'Categories',
        codePageIndex: 4,
        children: event.categories
            .map((c) => WbxmlElement.withText(
                  namespace: 'Calendar',
                  tag: 'Category',
                  text: c,
                  codePageIndex: 4,
                ))
            .toList(),
      ));
    }

    // Body
    if (event.body != null) {
      children.add(WbxmlElement(
        namespace: 'AirSyncBase',
        tag: 'Body',
        codePageIndex: 17,
        children: [
          WbxmlElement.withText(
            namespace: 'AirSyncBase',
            tag: 'Type',
            text: '1', // plain text
            codePageIndex: 17,
          ),
          WbxmlElement.withText(
            namespace: 'AirSyncBase',
            tag: 'Data',
            text: event.body!,
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

  /// Serialize recurrence element.
  static WbxmlElement serializeRecurrence(EasRecurrence rec) {
    final children = <WbxmlElement>[
      WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'Type',
        text: rec.type.toString(),
        codePageIndex: 4,
      ),
      WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'Interval',
        text: rec.interval.toString(),
        codePageIndex: 4,
      ),
    ];

    if (rec.until != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'Until',
        text: rec.until!.toUtc().toIso8601String(),
        codePageIndex: 4,
      ));
    }

    if (rec.occurrences != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'Occurrences',
        text: rec.occurrences.toString(),
        codePageIndex: 4,
      ));
    }

    if (rec.dayOfWeek != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'DayOfWeek',
        text: rec.dayOfWeek.toString(),
        codePageIndex: 4,
      ));
    }

    if (rec.dayOfMonth != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'DayOfMonth',
        text: rec.dayOfMonth.toString(),
        codePageIndex: 4,
      ));
    }

    if (rec.weekOfMonth != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'WeekOfMonth',
        text: rec.weekOfMonth.toString(),
        codePageIndex: 4,
      ));
    }

    if (rec.monthOfYear != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'MonthOfYear',
        text: rec.monthOfYear.toString(),
        codePageIndex: 4,
      ));
    }

    if (rec.calendarType != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'CalendarType',
        text: rec.calendarType.toString(),
        codePageIndex: 4,
      ));
    }

    if (rec.isLeapMonth == true) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'IsLeapMonth',
        text: '1',
        codePageIndex: 4,
      ));
    }

    if (rec.firstDayOfWeek != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Calendar',
        tag: 'FirstDayOfWeek',
        text: rec.firstDayOfWeek.toString(),
        codePageIndex: 4,
      ));
    }

    return WbxmlElement(
      namespace: 'Calendar',
      tag: 'Recurrence',
      codePageIndex: 4,
      children: children,
    );
  }
}
