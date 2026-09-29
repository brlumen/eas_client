/// Ping command — push notifications (long-poll).
///
/// Keeps a long-lived HTTP connection open. Server responds when
/// changes occur in monitored folders or when heartbeat expires.
///
/// Reference: MS-ASCMD section 2.2.1.13
library;

import 'dart:typed_data';

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'Ping';

/// Ping status codes (MS-ASCMD 2.2.3.177.11).
enum PingStatus {
  /// No changes detected (heartbeat expired).
  noChanges(1),

  /// Changes detected in one or more folders.
  changesAvailable(2),

  /// Missing required parameters: resend with heartbeat and folders.
  missingParameters(3),

  /// Syntax error in request.
  syntaxError(4),

  /// Invalid heartbeat interval; see [PingResult.suggestedHeartbeat].
  invalidHeartbeat(5),

  /// Too many folders; see [PingResult.maxFolders].
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

  /// Allowed heartbeat interval (when status = invalidHeartbeat): the
  /// shortest one if the request was too short, the longest otherwise.
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

/// A folder to monitor with Ping, including its content class.
class PingFolder {
  /// Server-assigned folder ID.
  final String id;

  /// Content class: 'Email', 'Calendar', 'Contacts', 'Tasks', 'Notes'.
  final String className;

  static const classes = {'Email', 'Calendar', 'Contacts', 'Tasks', 'Notes'};

  const PingFolder({required this.id, this.className = 'Email'});
}

class PingCommand extends EasCommand<PingResult> {
  /// Folders to monitor; `null` reuses the list cached by the server.
  final List<PingFolder>? folders;

  /// Heartbeat in seconds; `null` reuses the interval cached by the
  /// server.
  final int? heartbeatInterval;

  /// Minimum heartbeat interval per MS-ASCMD.
  static const int minHeartbeat = 60;

  /// Maximum heartbeat interval per MS-ASCMD.
  static const int maxHeartbeat = 3540;

  /// Create from folder IDs only (all treated as Email class).
  factory PingCommand.fromIds({
    required List<String> folderIds,
    int heartbeatInterval = 480,
  }) => PingCommand(
    folders: folderIds.map((id) => PingFolder(id: id)).toList(),
    heartbeatInterval: heartbeatInterval,
  );

  /// Ping with an empty body: the server reuses the heartbeat interval
  /// and folder list of the previous Ping (MS-ASCMD 2.2.1.13). Status 3
  /// means the server has no cached parameters.
  PingCommand.empty() : folders = null, heartbeatInterval = null;

  /// Create a Ping command.
  ///
  /// [folders] — folders to monitor for changes.
  /// [heartbeatInterval] — seconds to keep connection open
  ///   ($minHeartbeat-$maxHeartbeat per MS-ASCMD 2.2.3.88.1).
  /// Either may be `null` to reuse the value cached by the server.
  PingCommand({this.folders, this.heartbeatInterval = 480}) {
    final hb = heartbeatInterval;
    if (hb != null && (hb < minHeartbeat || hb > maxHeartbeat)) {
      throw ArgumentError.value(
        hb,
        'heartbeatInterval',
        'Must be $minHeartbeat-$maxHeartbeat (MS-ASCMD 2.2.1.13)',
      );
    }
    for (final f in folders ?? const <PingFolder>[]) {
      checkLength(f.id, 64, 'folders.id');
      if (!PingFolder.classes.contains(f.className)) {
        throw ArgumentError.value(f.className, 'folders.className');
      }
    }
  }

  bool get _isEmpty => folders == null && heartbeatInterval == null;

  @override
  String get commandName => 'Ping';

  @override
  Uint8List? encodeRequest(String protocolVersion) =>
      _isEmpty ? null : super.encodeRequest(protocolVersion);

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'Ping', [
      if (heartbeatInterval != null)
        xText(_ns, 'HeartbeatInterval', heartbeatInterval!),
      if (folders != null && folders!.isNotEmpty)
        xEl(_ns, 'Folders', [
          for (final f in folders!)
            xEl(_ns, 'Folder', [
              xText(_ns, 'Id', f.id),
              xText(_ns, 'Class', f.className),
            ]),
        ]),
    ]),
  );

  @override
  PingResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final status = PingStatus.fromValue(
      int.tryParse(root.childText(_ns, 'Status') ?? '') ?? 8,
    );

    final changedIds = <String>[
      for (final folder
          in root.findChild(_ns, 'Folders')?.findChildren(_ns, 'Folder') ??
              const <WbxmlElement>[])
        if ((folder.text ?? folder.childText(_ns, 'Id') ?? '') case final id
            when id.isNotEmpty)
          id,
    ];

    return PingResult(
      status: status,
      changedFolderIds: changedIds,
      suggestedHeartbeat: int.tryParse(
        root.childText(_ns, 'HeartbeatInterval') ?? '',
      ),
      maxFolders: int.tryParse(root.childText(_ns, 'MaxFolders') ?? ''),
    );
  }
}
