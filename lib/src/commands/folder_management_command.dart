/// Folder management commands — create, delete, and rename folders.
///
/// All three commands (FolderCreate, FolderDelete, FolderUpdate) return
/// a new FolderSyncKey that must replace the existing one.
///
/// Reference: MS-ASCMD sections 2.2.1.3, 2.2.1.4, 2.2.1.6
library;

import '../models/eas_folder.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'folder_sync_command.dart';
import 'wbxml_builders.dart';

const _ns = 'FolderHierarchy';

/// Result of FolderCreate.
class FolderCreateResult {
  final int status;

  /// New FolderSyncKey — must be stored for future FolderSync calls.
  final String syncKey;

  /// Server-assigned ID for the newly created folder.
  final String? serverId;

  bool get isSuccess => status == 1;

  /// Typed [status], `null` if unknown.
  FolderHierarchyStatus? get statusInfo =>
      FolderHierarchyStatus.fromCode(status);

  const FolderCreateResult({
    required this.status,
    required this.syncKey,
    this.serverId,
  });
}

/// Result of FolderDelete or FolderUpdate.
class FolderChangeResult {
  final int status;

  /// New FolderSyncKey — must be stored for future FolderSync calls.
  final String syncKey;

  bool get isSuccess => status == 1;

  /// Typed [status], `null` if unknown.
  FolderHierarchyStatus? get statusInfo =>
      FolderHierarchyStatus.fromCode(status);

  const FolderChangeResult({required this.status, required this.syncKey});
}

/// Max length of SyncKey/ServerId/ParentId (MS-ASCMD 6.13).
const _maxIdLength = 64;

/// Create a new folder on the server.
class FolderCreateCommand extends EasCommand<FolderCreateResult> {
  final String syncKey;
  final String parentId;
  final String displayName;
  final EasFolderType type;

  /// Max folder display name length (MS-ASCMD 6.9).
  static const int maxDisplayNameLength = 256;

  FolderCreateCommand({
    required this.syncKey,
    required this.parentId,
    required this.displayName,
    required this.type,
  }) {
    checkLength(syncKey, _maxIdLength, 'syncKey');
    checkLength(parentId, _maxIdLength, 'parentId');
    checkLength(displayName, maxDisplayNameLength, 'displayName');
  }

  @override
  String get commandName => 'FolderCreate';

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'FolderCreate', [
      xText(_ns, 'SyncKey', syncKey),
      xText(_ns, 'ParentId', parentId),
      xText(_ns, 'DisplayName', displayName),
      xText(_ns, 'Type', type.value),
    ]),
  );

  @override
  FolderCreateResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    return FolderCreateResult(
      status: xStatus(root, _ns),
      syncKey: root.childText(_ns, 'SyncKey') ?? syncKey,
      serverId: root.childText(_ns, 'ServerId'),
    );
  }
}

/// Delete a folder from the server.
class FolderDeleteCommand extends EasCommand<FolderChangeResult> {
  final String syncKey;
  final String serverId;

  FolderDeleteCommand({required this.syncKey, required this.serverId}) {
    checkLength(syncKey, _maxIdLength, 'syncKey');
    checkLength(serverId, _maxIdLength, 'serverId');
  }

  @override
  String get commandName => 'FolderDelete';

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'FolderDelete', [
      xText(_ns, 'SyncKey', syncKey),
      xText(_ns, 'ServerId', serverId),
    ]),
  );

  @override
  FolderChangeResult parseResponse(WbxmlDocument response) =>
      _parseChange(response, syncKey);
}

/// Rename or move a folder on the server.
class FolderUpdateCommand extends EasCommand<FolderChangeResult> {
  final String syncKey;
  final String serverId;
  final String displayName;

  /// New parent ID. Pass the existing parent ID to keep the folder in place.
  final String parentId;

  FolderUpdateCommand({
    required this.syncKey,
    required this.serverId,
    required this.displayName,
    required this.parentId,
  }) {
    checkLength(syncKey, _maxIdLength, 'syncKey');
    checkLength(serverId, _maxIdLength, 'serverId');
    checkLength(parentId, _maxIdLength, 'parentId');
    checkLength(
      displayName,
      FolderCreateCommand.maxDisplayNameLength,
      'displayName',
    );
  }

  @override
  String get commandName => 'FolderUpdate';

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'FolderUpdate', [
      xText(_ns, 'SyncKey', syncKey),
      xText(_ns, 'ServerId', serverId),
      xText(_ns, 'ParentId', parentId),
      xText(_ns, 'DisplayName', displayName),
    ]),
  );

  @override
  FolderChangeResult parseResponse(WbxmlDocument response) =>
      _parseChange(response, syncKey);
}

FolderChangeResult _parseChange(WbxmlDocument response, String syncKey) =>
    FolderChangeResult(
      status: xStatus(response.root, _ns),
      syncKey: response.root.childText(_ns, 'SyncKey') ?? syncKey,
    );
