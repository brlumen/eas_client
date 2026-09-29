/// EAS calendar exception model (modified/deleted instances of recurring
/// events) and single-occurrence changes (EAS 16.x).
///
/// Reference: MS-ASCAL section 2.2.2.21
library;

import '../wbxml/wbxml_document.dart';
import 'eas_attachment.dart';
import 'eas_body.dart';
import 'eas_calendar_event.dart';
import 'eas_location.dart';
import 'wbxml_helpers.dart';

/// An exception to a recurring calendar event.
///
/// Represents either a deleted occurrence or a modified occurrence
/// of a recurring event. Also used as the change set for a single
/// occurrence edit (EAS 16.x Sync Change with `InstanceId`).
class EasCalendarException {
  /// Original start time of this occurrence (UTC). Serialized as
  /// `ExceptionStartTime` (EAS ≤14.1) or `airsyncbase:InstanceId` (16.x).
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

  /// Modified structured location (EAS 16.x).
  final EasLocation? locationDetails;

  /// Modified body (null = same as parent).
  final String? body;

  /// Full `airsyncbase:Body` of the exception, if present.
  final EasBody? bodyDetails;

  /// Modified all-day flag (null = same as parent).
  final bool? allDayEvent;

  /// Modified busy status (null = same as parent).
  final int? busyStatus;

  /// Modified sensitivity (null = same as parent).
  final int? sensitivity;

  /// Modified reminder (null = same as parent).
  final int? reminder;

  /// Modified attendees (null = same as parent, EAS 14.0+).
  final List<EasAttendee>? attendees;

  /// Modified categories (null = same as parent).
  final List<String>? categories;

  /// Exception time stamp.
  final DateTime? dtStamp;

  /// Exception meeting status (EAS 12.0+).
  final int? meetingStatus;

  /// Instance id reported by the server (EAS 16.x).
  final DateTime? instanceId;

  /// Server-only: reply time, response type, online meeting links.
  final DateTime? appointmentReplyTime;
  final int? responseType;
  final String? onlineMeetingConfLink;
  final String? onlineMeetingExternalLink;

  /// UID of the exception (EAS 2.5 only).
  final String? uid;

  /// Attachments of the exception (EAS 16.x).
  final List<EasAttachment> attachments;

  /// Request-only: attachments to add to the exception (EAS 16.x).
  final List<EasAttachmentAdd> addAttachments;

  /// Request-only: FileReferences of attachments to delete (EAS 16.x).
  final List<String> deleteAttachments;

  const EasCalendarException({
    required this.exceptionStartTime,
    this.deleted = false,
    this.subject,
    this.startTime,
    this.endTime,
    this.location,
    this.locationDetails,
    this.body,
    this.bodyDetails,
    this.allDayEvent,
    this.busyStatus,
    this.sensitivity,
    this.reminder,
    this.attendees,
    this.categories,
    this.dtStamp,
    this.meetingStatus,
    this.instanceId,
    this.appointmentReplyTime,
    this.responseType,
    this.onlineMeetingConfLink,
    this.onlineMeetingExternalLink,
    this.uid,
    this.attachments = const [],
    this.addAttachments = const [],
    this.deleteAttachments = const [],
  });

  /// Parse a `Calendar:Exception` element.
  factory EasCalendarException.fromElement(WbxmlElement el) {
    const ns = 'Calendar';
    final instanceId = el.date('AirSyncBase', 'InstanceId');
    final bodyDetails = EasBody.anyOf(el, ns);
    final locationDetails = EasLocation.of(el);
    return EasCalendarException(
      exceptionStartTime:
          el.date(ns, 'ExceptionStartTime') ??
          instanceId ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deleted: el.boolean(ns, 'Deleted') ?? false,
      subject: el.str(ns, 'Subject'),
      startTime: el.date(ns, 'StartTime'),
      endTime: el.date(ns, 'EndTime'),
      location: el.str(ns, 'Location') ?? locationDetails?.displayName,
      locationDetails: locationDetails,
      body: bodyDetails?.data,
      bodyDetails: bodyDetails,
      allDayEvent: el.boolean(ns, 'AllDayEvent'),
      busyStatus: el.integer(ns, 'BusyStatus'),
      sensitivity: el.integer(ns, 'Sensitivity'),
      reminder: el.integer(ns, 'Reminder'),
      attendees: EasAttendee.listOf(el),
      categories: el.list(ns, 'Categories', 'Category'),
      dtStamp: el.date(ns, 'DtStamp'),
      meetingStatus: el.integer(ns, 'MeetingStatus'),
      instanceId: instanceId,
      appointmentReplyTime: el.date(ns, 'AppointmentReplyTime'),
      responseType: el.integer(ns, 'ResponseType'),
      onlineMeetingConfLink: el.str(ns, 'OnlineMeetingConfLink'),
      onlineMeetingExternalLink: el.str(ns, 'OnlineMeetingExternalLink'),
      uid: el.str(ns, 'UID'),
      attachments: EasAttachment.listOf(el),
    );
  }

  @override
  String toString() =>
      'EasCalendarException(${deleted ? "deleted" : "modified"}, $exceptionStartTime)';
}
