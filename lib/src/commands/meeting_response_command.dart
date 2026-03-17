/// MeetingResponse command — accept, decline, or tentatively accept a meeting.
///
/// Reference: MS-ASCMD section 2.2.1.11
library;

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

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

/// Result of a single MeetingResponse request.
class MeetingResponseResult {
  /// The calendar item ID created for an accepted meeting (null if declined).
  final String? calendarId;

  /// The status code returned by the server.
  final int status;

  /// Whether the response was successful (status 1).
  bool get isSuccess => status == 1;

  const MeetingResponseResult({required this.status, this.calendarId});
}

/// A single meeting response request entry.
class MeetingRequestEntry {
  final String requestId;
  final String collectionId;
  final MeetingResponseStatus userResponse;

  const MeetingRequestEntry({
    required this.requestId,
    required this.collectionId,
    required this.userResponse,
  });
}

/// Respond to one or more meeting requests.
class MeetingResponseCommand
    extends EasCommand<List<MeetingResponseResult>> {
  final List<MeetingRequestEntry> requests;

  MeetingResponseCommand({required this.requests});

  /// Convenience constructor for a single meeting response.
  factory MeetingResponseCommand.single({
    required String requestId,
    required String collectionId,
    required MeetingResponseStatus response,
  }) =>
      MeetingResponseCommand(requests: [
        MeetingRequestEntry(
          requestId: requestId,
          collectionId: collectionId,
          userResponse: response,
        ),
      ]);

  @override
  String get commandName => 'MeetingResponse';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'MeetingResponse',
        tag: 'MeetingResponse',
        codePageIndex: 8,
        children: requests.map((r) {
          return WbxmlElement(
            namespace: 'MeetingResponse',
            tag: 'Request',
            codePageIndex: 8,
            children: [
              WbxmlElement.withText(
                namespace: 'MeetingResponse',
                tag: 'UserResponse',
                text: r.userResponse.value.toString(),
                codePageIndex: 8,
              ),
              WbxmlElement.withText(
                namespace: 'MeetingResponse',
                tag: 'CollectionId',
                text: r.collectionId,
                codePageIndex: 8,
              ),
              WbxmlElement.withText(
                namespace: 'MeetingResponse',
                tag: 'RequestId',
                text: r.requestId,
                codePageIndex: 8,
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  @override
  List<MeetingResponseResult> parseResponse(WbxmlDocument response) {
    final root = response.root;
    return root
        .findChildren('MeetingResponse', 'Result')
        .map((result) {
          final status =
              int.tryParse(result.childText('MeetingResponse', 'Status') ?? '') ??
                  0;
          final calendarId = result.childText('MeetingResponse', 'CalendarId');
          return MeetingResponseResult(status: status, calendarId: calendarId);
        })
        .toList();
  }
}

