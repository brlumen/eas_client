/// EAS calendar event model (MS-ASCAL).
library;

import '../wbxml/wbxml_document.dart';
import 'eas_attachment.dart';
import 'eas_body.dart';
import 'eas_exception.dart';
import 'eas_location.dart';
import 'eas_recurrence.dart';
import 'wbxml_helpers.dart';

/// Attendee status in a meeting.
enum AttendeeStatus {
  responseUnknown(0),
  tentative(2),
  accepted(3),
  declined(4),
  notResponded(5);

  final int value;
  const AttendeeStatus(this.value);

  static AttendeeStatus fromValue(int value) =>
      AttendeeStatus.values.firstWhere(
        (e) => e.value == value,
        orElse: () => AttendeeStatus.responseUnknown,
      );
}

/// Attendee type in a meeting.
enum AttendeeType {
  required(1),
  optional(2),
  resource(3);

  final int value;
  const AttendeeType(this.value);

  static AttendeeType fromValue(int value) => AttendeeType.values.firstWhere(
    (e) => e.value == value,
    orElse: () => AttendeeType.required,
  );
}

/// A meeting/calendar event attendee.
class EasAttendee {
  /// Email address.
  final String email;

  /// Display name.
  final String? name;

  /// Response status.
  final AttendeeStatus status;

  /// Attendee type (required/optional/resource).
  final AttendeeType type;

  /// Start time proposed by the attendee (EAS 16.x).
  final DateTime? proposedStartTime;

  /// End time proposed by the attendee (EAS 16.x).
  final DateTime? proposedEndTime;

  const EasAttendee({
    required this.email,
    this.name,
    this.status = AttendeeStatus.responseUnknown,
    this.type = AttendeeType.required,
    this.proposedStartTime,
    this.proposedEndTime,
  });

  factory EasAttendee.fromElement(WbxmlElement att) => EasAttendee(
    email: att.str('Calendar', 'Email') ?? '',
    name: att.str('Calendar', 'Name'),
    status: AttendeeStatus.fromValue(
      att.integer('Calendar', 'AttendeeStatus') ?? 0,
    ),
    type: AttendeeType.fromValue(att.integer('Calendar', 'AttendeeType') ?? 1),
    proposedStartTime: att.date('MeetingResponse', 'ProposedStartTime'),
    proposedEndTime: att.date('MeetingResponse', 'ProposedEndTime'),
  );

  /// `Calendar:Attendees` of [parent], or `null` if absent.
  static List<EasAttendee>? listOf(WbxmlElement parent) => parent
      .findChild('Calendar', 'Attendees')
      ?.findChildren('Calendar', 'Attendee')
      .map(EasAttendee.fromElement)
      .toList();
}

/// EAS calendar event (appointment or meeting).
class EasCalendarEvent {
  /// Server-assigned ID.
  final String serverId;

  /// Event subject/title.
  final String subject;

  /// Start time (UTC).
  final DateTime? startTime;

  /// End time (UTC).
  final DateTime? endTime;

  /// Location string (`calendar:Location` for EAS ≤14.1; for 16.x the
  /// display name of [locationDetails]).
  final String? location;

  /// Structured location (`airsyncbase:Location`, EAS 16.x).
  final EasLocation? locationDetails;

  /// Event body/notes (HTML or plain text).
  final String? body;

  /// Full `airsyncbase:Body` (type, truncation, preview), if present.
  final EasBody? bodyDetails;

  /// Whether this is an all-day event.
  final bool allDayEvent;

  /// Busy status: 0=free, 1=tentative, 2=busy, 3=out-of-office,
  /// 4=working elsewhere.
  final int busyStatus;

  /// Sensitivity: 0=normal, 1=personal, 2=private, 3=confidential.
  final int sensitivity;

  /// Server-assigned UID (client-assigned for EAS ≤14.1).
  final String? uid;

  /// Client-generated unique ID sent on creation (EAS 16.x `ClientUid`).
  final String? clientUid;

  /// Organizer display name.
  final String? organizerName;

  /// Organizer email.
  final String? organizerEmail;

  /// Reminder in minutes before event (null = no reminder).
  final int? reminder;

  /// Meeting status: 0=appointment, 1=meeting, 3=received, 5=cancelled,
  /// 7=received+cancelled (9/11/13/15 are aliases).
  final int meetingStatus;

  /// Attendee list (only for meetings).
  final List<EasAttendee> attendees;

  /// Categories.
  final List<String> categories;

  /// Recurrence pattern (null = non-recurring).
  final EasRecurrence? recurrence;

  /// Exceptions to the recurrence pattern.
  final List<EasCalendarException> exceptions;

  /// Time zone (base64-encoded TIME_ZONE_INFORMATION structure).
  final String? timezone;

  /// Date/time stamp (UTC).
  final DateTime? dtStamp;

  /// Response type: 0=none, 1=organizer, 2=tentative, 3=accepted,
  /// 4=declined, 5=not responded. Server-only.
  final int? responseType;

  /// Whether a response to the meeting request is required.
  final bool? responseRequested;

  /// Time when the attendee replied (UTC). Server-only.
  final DateTime? appointmentReplyTime;

  /// Native body type (1=plain, 2=HTML, 3=RTF).
  final int? nativeBodyType;

  /// Whether new time proposals are disallowed.
  final bool? disallowNewTimeProposal;

  /// Online meeting conference link. Server-only.
  final String? onlineMeetingConfLink;

  /// Online meeting external link. Server-only.
  final String? onlineMeetingExternalLink;

  /// Attachments (EAS 16.x).
  final List<EasAttachment> attachments;

  /// Original start time of an orphan instance (EAS 16.x
  /// `airsyncbase:InstanceId` in `ApplicationData`).
  final DateTime? instanceId;

  const EasCalendarEvent({
    required this.serverId,
    this.subject = '',
    this.startTime,
    this.endTime,
    this.location,
    this.locationDetails,
    this.body,
    this.bodyDetails,
    this.allDayEvent = false,
    this.busyStatus = 2,
    this.sensitivity = 0,
    this.uid,
    this.clientUid,
    this.organizerName,
    this.organizerEmail,
    this.reminder,
    this.meetingStatus = 0,
    this.attendees = const [],
    this.categories = const [],
    this.recurrence,
    this.exceptions = const [],
    this.timezone,
    this.dtStamp,
    this.responseType,
    this.responseRequested,
    this.appointmentReplyTime,
    this.nativeBodyType,
    this.disallowNewTimeProposal,
    this.onlineMeetingConfLink,
    this.onlineMeetingExternalLink,
    this.attachments = const [],
    this.instanceId,
  });

  /// Parse a calendar item from `ApplicationData` / `Properties`.
  factory EasCalendarEvent.fromApplicationData(
    String serverId,
    WbxmlElement data,
  ) {
    const ns = 'Calendar';
    final bodyDetails = EasBody.anyOf(data, ns);
    final locationDetails = EasLocation.of(data);
    final recurrenceEl = data.findChild(ns, 'Recurrence');
    return EasCalendarEvent(
      serverId: serverId,
      subject: data.str(ns, 'Subject') ?? '',
      startTime: data.date(ns, 'StartTime'),
      endTime: data.date(ns, 'EndTime'),
      location: data.str(ns, 'Location') ?? locationDetails?.displayName,
      locationDetails: locationDetails,
      body: bodyDetails?.data,
      bodyDetails: bodyDetails,
      allDayEvent: data.boolean(ns, 'AllDayEvent') ?? false,
      busyStatus: data.integer(ns, 'BusyStatus') ?? 2,
      sensitivity: data.integer(ns, 'Sensitivity') ?? 0,
      uid: data.str(ns, 'UID'),
      clientUid: data.str(ns, 'ClientUid'),
      organizerName: data.str(ns, 'OrganizerName'),
      organizerEmail: data.str(ns, 'OrganizerEmail'),
      reminder: data.integer(ns, 'Reminder'),
      meetingStatus: data.integer(ns, 'MeetingStatus') ?? 0,
      attendees: EasAttendee.listOf(data) ?? const [],
      categories: data.list(ns, 'Categories', 'Category') ?? const [],
      recurrence: recurrenceEl == null
          ? null
          : EasRecurrence.fromElement(recurrenceEl, ns),
      exceptions:
          data
              .findChild(ns, 'Exceptions')
              ?.findChildren(ns, 'Exception')
              .map(EasCalendarException.fromElement)
              .toList() ??
          const [],
      timezone: data.str(ns, 'Timezone'),
      dtStamp: data.date(ns, 'DtStamp'),
      responseType: data.integer(ns, 'ResponseType'),
      responseRequested: data.boolean(ns, 'ResponseRequested'),
      appointmentReplyTime: data.date(ns, 'AppointmentReplyTime'),
      nativeBodyType: data.integer('AirSyncBase', 'NativeBodyType'),
      disallowNewTimeProposal: data.boolean(ns, 'DisallowNewTimeProposal'),
      onlineMeetingConfLink: data.str(ns, 'OnlineMeetingConfLink'),
      onlineMeetingExternalLink: data.str(ns, 'OnlineMeetingExternalLink'),
      attachments: EasAttachment.listOf(data),
      instanceId: data.date('AirSyncBase', 'InstanceId'),
    );
  }

  @override
  String toString() => 'EasCalendarEvent($serverId, start: $startTime)';
}
