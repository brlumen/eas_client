/// Ping command — push notifications (long-poll).
///
/// Keeps a long-lived HTTP connection open. Server responds when
/// changes occur in monitored folders or when heartbeat expires.
///
/// Reference: MS-ASCMD section 2.2.1.13
library;

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Ping status codes.
enum PingStatus {
  /// No changes detected (heartbeat expired).
  noChanges(1),

  /// Changes detected in one or more folders.
  changesAvailable(2),

  /// Missing required parameters.
  missingParameters(3),

  /// Syntax error in request.
  syntaxError(4),

  /// Invalid heartbeat interval (too long or too short).
  invalidHeartbeat(5),

  /// Too many folders.
  tooManyFolders(6),

  /// Folder sync required first.
  folderSyncRequired(7),

  /// Server error.
  serverError(8);

  final int value;
  const PingStatus(this.value);

  static PingStatus fromValue(int value) {
    return PingStatus.values.firstWhere(
      (s) => s.value == value,
      orElse: () => PingStatus.serverError,
    );
  }
}

/// Result of a Ping command.
class PingResult {
  final PingStatus status;

  /// Folder IDs that have changes (when status = changesAvailable).
  final List<String> changedFolderIds;

  /// Server-suggested heartbeat interval (when status = invalidHeartbeat).
  final int? suggestedHeartbeat;

  /// Server-suggested max folders (when status = tooManyFolders).
  final int? maxFolders;

  const PingResult({
    required this.status,
    this.changedFolderIds = const [],
    this.suggestedHeartbeat,
    this.maxFolders,
  });
}

class PingCommand extends EasCommand<PingResult> {
  final List<String> folderIds;
  final int heartbeatInterval;

  /// Create a Ping command.
  ///
  /// [folderIds] — folders to monitor for changes.
  /// [heartbeatInterval] — seconds to keep connection open (60-900 per MS-ASCMD).
  PingCommand({
    required this.folderIds,
    this.heartbeatInterval = 480,
  });

  @override
  String get commandName => 'Ping';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Ping',
        tag: 'Ping',
        codePageIndex: 13,
        children: [
          WbxmlElement.withText(
            namespace: 'Ping',
            tag: 'HeartbeatInterval',
            text: heartbeatInterval.toString(),
            codePageIndex: 13,
          ),
          WbxmlElement(
            namespace: 'Ping',
            tag: 'Folders',
            codePageIndex: 13,
            children: folderIds
                .map(
                  (id) => WbxmlElement(
                    namespace: 'Ping',
                    tag: 'Folder',
                    codePageIndex: 13,
                    children: [
                      WbxmlElement.withText(
                        namespace: 'Ping',
                        tag: 'Id',
                        text: id,
                        codePageIndex: 13,
                      ),
                      WbxmlElement.withText(
                        namespace: 'Ping',
                        tag: 'Class',
                        text: 'Email',
                        codePageIndex: 13,
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  @override
  PingResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final statusStr = root.childText('Ping', 'Status') ?? '8';
    final status = PingStatus.fromValue(int.tryParse(statusStr) ?? 8);

    final folders = root.findChild('Ping', 'Folders');
    final changedIds = <String>[];
    if (folders != null) {
      for (final folder in folders.findChildren('Ping', 'Folder')) {
        final id = folder.text ?? folder.childText('Ping', 'Id') ?? '';
        if (id.isNotEmpty) changedIds.add(id);
      }
    }

    final heartbeat = root.childText('Ping', 'HeartbeatInterval');
    final maxFolders = root.childText('Ping', 'MaxFolders');

    return PingResult(
      status: status,
      changedFolderIds: changedIds,
      suggestedHeartbeat:
          heartbeat != null ? int.tryParse(heartbeat) : null,
      maxFolders:
          maxFolders != null ? int.tryParse(maxFolders) : null,
    );
  }
}
