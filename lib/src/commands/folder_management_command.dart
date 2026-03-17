/// Folder management commands — create, delete, and rename folders.
///
/// All three commands (FolderCreate, FolderDelete, FolderUpdate) return
/// a new FolderSyncKey that must replace the existing one.
///
/// Reference: MS-ASCMD sections 2.2.1.2, 2.2.1.3, 2.2.1.6
library;

import '../models/eas_folder.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Result of FolderCreate.
class FolderCreateResult {
  final int status;

  /// New FolderSyncKey — must be stored for future FolderSync calls.
  final String syncKey;

  /// Server-assigned ID for the newly created folder.
  final String? serverId;

  bool get isSuccess => status == 1;

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

  const FolderChangeResult({required this.status, required this.syncKey});
}

/// Create a new folder on the server.
class FolderCreateCommand extends EasCommand<FolderCreateResult> {
  final String syncKey;
  final String parentId;
  final String displayName;
  final EasFolderType type;

  /// Max folder display name length (Exchange generally limits to 256).
  static const int maxDisplayNameLength = 256;

  FolderCreateCommand({
    required this.syncKey,
    required this.parentId,
    required this.displayName,
    required this.type,
  }) {
    if (displayName.isEmpty || displayName.length > maxDisplayNameLength) {
      throw ArgumentError.value(
        displayName.length,
        'displayName',
        'Must be 1-$maxDisplayNameLength characters',
      );
    }
  }

  @override
  String get commandName => 'FolderCreate';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'FolderHierarchy',
        tag: 'FolderCreate',
        codePageIndex: 7,
        children: [
          WbxmlElement.withText(
            namespace: 'FolderHierarchy',
            tag: 'SyncKey',
            text: syncKey,
            codePageIndex: 7,
          ),
          WbxmlElement.withText(
            namespace: 'FolderHierarchy',
            tag: 'ParentId',
            text: parentId,
            codePageIndex: 7,
          ),
          WbxmlElement.withText(
            namespace: 'FolderHierarchy',
            tag: 'DisplayName',
            text: displayName,
            codePageIndex: 7,
          ),
          WbxmlElement.withText(
            namespace: 'FolderHierarchy',
            tag: 'Type',
            text: type.value.toString(),
            codePageIndex: 7,
          ),
        ],
      ),
    );
  }

  @override
  FolderCreateResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final status =
        int.tryParse(root.childText('FolderHierarchy', 'Status') ?? '') ?? 0;
    final newSyncKey = root.childText('FolderHierarchy', 'SyncKey') ?? syncKey;
    final serverId = root.childText('FolderHierarchy', 'ServerId');
    return FolderCreateResult(
      status: status,
      syncKey: newSyncKey,
      serverId: serverId,
    );
  }
}

/// Delete a folder from the server.
class FolderDeleteCommand extends EasCommand<FolderChangeResult> {
  final String syncKey;
  final String serverId;

  FolderDeleteCommand({required this.syncKey, required this.serverId});

  @override
  String get commandName => 'FolderDelete';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'FolderHierarchy',
        tag: 'FolderDelete',
        codePageIndex: 7,
        children: [
          WbxmlElement.withText(
            namespace: 'FolderHierarchy',
            tag: 'SyncKey',
            text: syncKey,
            codePageIndex: 7,
          ),
          WbxmlElement.withText(
            namespace: 'FolderHierarchy',
            tag: 'ServerId',
            text: serverId,
            codePageIndex: 7,
          ),
        ],
      ),
    );
  }

  @override
  FolderChangeResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final status =
        int.tryParse(root.childText('FolderHierarchy', 'Status') ?? '') ?? 0;
    final newSyncKey = root.childText('FolderHierarchy', 'SyncKey') ?? syncKey;
    return FolderChangeResult(status: status, syncKey: newSyncKey);
  }
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
    if (displayName.isEmpty ||
        displayName.length > FolderCreateCommand.maxDisplayNameLength) {
      throw ArgumentError.value(
        displayName.length,
        'displayName',
        'Must be 1-${FolderCreateCommand.maxDisplayNameLength} characters',
      );
    }
  }

  @override
  String get commandName => 'FolderUpdate';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'FolderHierarchy',
        tag: 'FolderUpdate',
        codePageIndex: 7,
        children: [
          WbxmlElement.withText(
            namespace: 'FolderHierarchy',
            tag: 'SyncKey',
            text: syncKey,
            codePageIndex: 7,
          ),
          WbxmlElement.withText(
            namespace: 'FolderHierarchy',
            tag: 'ServerId',
            text: serverId,
            codePageIndex: 7,
          ),
          WbxmlElement.withText(
            namespace: 'FolderHierarchy',
            tag: 'ParentId',
            text: parentId,
            codePageIndex: 7,
          ),
          WbxmlElement.withText(
            namespace: 'FolderHierarchy',
            tag: 'DisplayName',
            text: displayName,
            codePageIndex: 7,
          ),
        ],
      ),
    );
  }

  @override
  FolderChangeResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final status =
        int.tryParse(root.childText('FolderHierarchy', 'Status') ?? '') ?? 0;
    final newSyncKey = root.childText('FolderHierarchy', 'SyncKey') ?? syncKey;
    return FolderChangeResult(status: status, syncKey: newSyncKey);
  }
}
