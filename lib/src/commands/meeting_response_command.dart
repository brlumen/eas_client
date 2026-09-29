/// MeetingResponse command — accept, decline, or tentatively accept a meeting.
///
/// Reference: MS-ASCMD section 2.2.1.11
library;

import '../models/eas_body.dart';
import '../models/wbxml_helpers.dart' show compactDateTime, isoDateTime;
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'MeetingResponse';

/// User response to a meeting request.
enum MeetingResponseStatus {
  /// Accept the meeting.
  accepted(1),

  /// Tentatively accept the meeting.
  tentative(2),

  /// Decline the meeting.
  declined(3);

  final int value;
  const MeetingResponseStatus(this.value);
}

/// MeetingResponse `Result/Status` codes (MS-ASCMD 2.2.3.177.9).
enum MeetingResponseResultStatus {
  success(1, 'Success'),
  invalidMeetingRequest(2, 'Invalid meeting request'),
  mailboxError(3, 'An error occurred on the server mailbox'),
  serverError(4, 'An error occurred on the server');

  final int code;
  final String description;

  const MeetingResponseResultStatus(this.code, this.description);

  static MeetingResponseResultStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Result of a single MeetingResponse request.
class MeetingResponseResult {
  /// The calendar item ID created for an accepted meeting (null if declined).
  final String? calendarId;

  /// The status code returned by the server.
  final int status;

  /// RequestId echoed by the server.
  final String? requestId;

  /// Occurrence the response applied to (EAS 16.x).
  final DateTime? instanceId;

  /// Whether the response was successful (status 1).
  bool get isSuccess => status == 1;

  /// Typed [status], `null` if unknown (global codes >= 101 included).
  MeetingResponseResultStatus? get statusInfo =>
      MeetingResponseResultStatus.fromCode(status);

  const MeetingResponseResult({
    required this.status,
    this.calendarId,
    this.requestId,
    this.instanceId,
  });
}

/// Response message sent to the organizer (`SendResponse`, EAS 16.0+).
///
/// An empty `SendResponse` sends a message without body. A new time
/// proposal requires both [proposedStartTime] and [proposedEndTime].
/// Children are emitted in schema order: Body, ProposedStartTime,
/// ProposedEndTime (MS-ASCMD 6.25).
class MeetingSendResponse {
  /// Body of the response message.
  final String? body;

  /// Body type of [body]: 1 = plain text, 2 = HTML.
  final int bodyType;
  final DateTime? proposedStartTime;
  final DateTime? proposedEndTime;

  const MeetingSendResponse({
    this.body,
    this.bodyType = 1,
    this.proposedStartTime,
    this.proposedEndTime,
  });
}

/// A single meeting response request entry.
///
/// Identify the meeting request either by [collectionId] + [requestId] or
/// by [longId] (a Search result).
class MeetingRequestEntry {
  final String? requestId;
  final String? collectionId;
  final String? longId;
  final MeetingResponseStatus userResponse;

  /// Start time of the recurring meeting occurrence to respond to
  /// (EAS 14.1+); null responds to the whole series.
  final DateTime? instanceId;

  /// Send a response message to the organizer (EAS 16.0+).
  final MeetingSendResponse? sendResponse;

  const MeetingRequestEntry({
    this.requestId,
    this.collectionId,
    this.longId,
    required this.userResponse,
    this.instanceId,
    this.sendResponse,
  });
}

/// Respond to one or more meeting requests.
class MeetingResponseCommand extends EasCommand<List<MeetingResponseResult>> {
  final List<MeetingRequestEntry> requests;

  MeetingResponseCommand({required this.requests}) {
    if (requests.isEmpty) {
      throw ArgumentError.value(0, 'requests', 'Must not be empty');
    }
    for (final r in requests) {
      final byId = r.requestId != null && r.collectionId != null;
      final partialId = (r.requestId != null) != (r.collectionId != null);
      if (partialId || byId == (r.longId != null)) {
        throw ArgumentError(
          'Specify either requestId + collectionId, or longId',
        );
      }
      if (byId) {
        checkLength(r.requestId!, 64, 'requestId');
        checkLength(r.collectionId!, 64, 'collectionId');
      } else {
        checkLength(r.longId!, 256, 'longId');
      }
      final send = r.sendResponse;
      if (send == null) continue;
      if ((send.proposedStartTime == null) != (send.proposedEndTime == null)) {
        throw ArgumentError(
          'ProposedStartTime and ProposedEndTime must be set together '
          '(MS-ASCMD 2.2.3.140/2.2.3.141)',
        );
      }
    }
  }

  /// Convenience constructor for a single meeting response.
  factory MeetingResponseCommand.single({
    String? requestId,
    String? collectionId,
    String? longId,
    required MeetingResponseStatus response,
    DateTime? instanceId,
    MeetingSendResponse? sendResponse,
  }) => MeetingResponseCommand(
    requests: [
      MeetingRequestEntry(
        requestId: requestId,
        collectionId: collectionId,
        longId: longId,
        userResponse: response,
        instanceId: instanceId,
        sendResponse: sendResponse,
      ),
    ],
  );

  @override
  String get commandName => 'MeetingResponse';

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'MeetingResponse', requests.map(_buildEntry).toList()),
  );

  static WbxmlElement _buildEntry(MeetingRequestEntry r) {
    final send = r.sendResponse;
    return xEl(_ns, 'Request', [
      xText(_ns, 'UserResponse', r.userResponse.value),
      if (r.longId != null)
        xText('Search', 'LongId', r.longId!)
      else ...[
        xText(_ns, 'CollectionId', r.collectionId!),
        xText(_ns, 'RequestId', r.requestId!),
      ],
      // dateTime with separators, e.g. 2010-04-08T18:16:00.000Z.
      if (r.instanceId != null)
        xText(_ns, 'InstanceId', isoDateTime(r.instanceId!)),
      if (send != null)
        xEl(_ns, 'SendResponse', [
          if (send.body != null)
            EasBody.toElement(send.body!, type: send.bodyType),
          // Compact DateTime (MS-ASDTYPE 2.7.2), e.g. 20100408T181600Z.
          if (send.proposedStartTime != null)
            xText(
              _ns,
              'ProposedStartTime',
              compactDateTime(send.proposedStartTime!),
            ),
          if (send.proposedEndTime != null)
            xText(
              _ns,
              'ProposedEndTime',
              compactDateTime(send.proposedEndTime!),
            ),
        ]),
    ]);
  }

  @override
  List<MeetingResponseResult> parseResponse(WbxmlDocument response) => response
      .root
      .findChildren(_ns, 'Result')
      .map(
        (result) => MeetingResponseResult(
          status: xStatus(result, _ns),
          calendarId: result.childText(_ns, 'CalendarId'),
          requestId: result.childText(_ns, 'RequestId'),
          instanceId: DateTime.tryParse(
            result.childText(_ns, 'InstanceId') ?? '',
          ),
        ),
      )
      .toList();
}
