/// EAS calendar event model.
library;

import 'eas_exception.dart';
import 'eas_recurrence.dart';

/// Attendee status in a meeting.
enum AttendeeStatus {
  responseUnknown(0),
  tentative(2),
  accepted(3),
  declined(4),
  notResponded(5);

  final int value;
  const AttendeeStatus(this.value);

  static AttendeeStatus fromValue(int value) => AttendeeStatus.values
      .firstWhere((e) => e.value == value, orElse: () => AttendeeStatus.responseUnknown);
}

/// Attendee type in a meeting.
enum AttendeeType {
  required(1),
  optional(2),
  resource(3);

  final int value;
  const AttendeeType(this.value);

  static AttendeeType fromValue(int value) => AttendeeType.values
      .firstWhere((e) => e.value == value, orElse: () => AttendeeType.required);
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

  const EasAttendee({
    required this.email,
    this.name,
    this.status = AttendeeStatus.responseUnknown,
    this.type = AttendeeType.required,
  });
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

  /// Location string.
  final String? location;

  /// Event body/notes (HTML or plain text).
  final String? body;

  /// Whether this is an all-day event.
  final bool allDayEvent;

  /// Busy status: 0=free, 1=tentative, 2=busy, 3=out-of-office.
  final int busyStatus;

  /// Sensitivity: 0=normal, 1=personal, 2=private, 3=confidential.
  final int sensitivity;

  /// Server-assigned UID.
  final String? uid;

  /// Organizer display name.
  final String? organizerName;

  /// Organizer email.
  final String? organizerEmail;

  /// Reminder in minutes before event (null = no reminder).
  final int? reminder;

  /// Meeting status: 0=appointment, 1=meeting, 3=accepted, 5=cancelled, 7=tentative.
  final int meetingStatus;

  /// Attendee list (only for meetings).
  final List<EasAttendee> attendees;

  /// Categories.
  final List<String> categories;

  /// Recurrence pattern (null = non-recurring).
  final EasRecurrence? recurrence;

  /// Exceptions to the recurrence pattern.
  final List<EasCalendarException> exceptions;

  /// Time zone (base64-encoded SYSTEMTIME structure).
  final String? timezone;

  /// Date/time stamp (UTC).
  final DateTime? dtStamp;

  /// Response type: 0=none, 1=organizer, 2=tentative, 3=accepted, 4=declined.
  final int? responseType;

  /// Time when the attendee replied (UTC).
  final DateTime? appointmentReplyTime;

  /// Native body type (1=plain, 2=HTML, 3=RTF).
  final int? nativeBodyType;

  /// Whether new time proposals are disallowed.
  final bool? disallowNewTimeProposal;

  /// Online meeting conference link.
  final String? onlineMeetingConfLink;

  /// Online meeting external link.
  final String? onlineMeetingExternalLink;

  const EasCalendarEvent({
    required this.serverId,
    this.subject = '',
    this.startTime,
    this.endTime,
    this.location,
    this.body,
    this.allDayEvent = false,
    this.busyStatus = 2,
    this.sensitivity = 0,
    this.uid,
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
    this.appointmentReplyTime,
    this.nativeBodyType,
    this.disallowNewTimeProposal,
    this.onlineMeetingConfLink,
    this.onlineMeetingExternalLink,
  });

  @override
  String toString() =>
      'EasCalendarEvent($serverId, subject: $subject, start: $startTime)';
}
