/// FolderSync command — synchronizes folder hierarchy.
///
/// Reference: MS-ASCMD section 2.2.1.4
library;

import '../models/eas_folder.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Result of a FolderSync command.
class FolderSyncResult {
  final int status;
  final String syncKey;
  final List<EasFolder> addedFolders;
  final List<EasFolder> updatedFolders;
  final List<String> deletedFolderIds;

  const FolderSyncResult({
    required this.status,
    required this.syncKey,
    this.addedFolders = const [],
    this.updatedFolders = const [],
    this.deletedFolderIds = const [],
  });
}

class FolderSyncCommand extends EasCommand<FolderSyncResult> {
  final String syncKey;

  /// Create a FolderSync command.
  /// Use syncKey '0' for initial sync.
  FolderSyncCommand({this.syncKey = '0'});

  @override
  String get commandName => 'FolderSync';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'FolderHierarchy',
        tag: 'FolderSync',
        codePageIndex: 7,
        children: [
          WbxmlElement.withText(
            namespace: 'FolderHierarchy',
            tag: 'SyncKey',
            text: syncKey,
            codePageIndex: 7,
          ),
        ],
      ),
    );
  }

  @override
  FolderSyncResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final status =
        int.tryParse(root.childText('FolderHierarchy', 'Status') ?? '') ?? 0;
    final newSyncKey =
        root.childText('FolderHierarchy', 'SyncKey') ?? syncKey;

    final changes = root.findChild('FolderHierarchy', 'Changes');
    if (changes == null) {
      return FolderSyncResult(
        status: status,
        syncKey: newSyncKey,
      );
    }

    final added = changes
        .findChildren('FolderHierarchy', 'Add')
        .map(_parseFolder)
        .toList();

    final updated = changes
        .findChildren('FolderHierarchy', 'Update')
        .map(_parseFolder)
        .toList();

    final deleted = changes
        .findChildren('FolderHierarchy', 'Delete')
        .map((e) => e.childText('FolderHierarchy', 'ServerId') ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    return FolderSyncResult(
      status: status,
      syncKey: newSyncKey,
      addedFolders: added,
      updatedFolders: updated,
      deletedFolderIds: deleted,
    );
  }

  EasFolder _parseFolder(WbxmlElement element) {
    final serverId =
        element.childText('FolderHierarchy', 'ServerId') ?? '';
    final parentId =
        element.childText('FolderHierarchy', 'ParentId') ?? '0';
    final displayName =
        element.childText('FolderHierarchy', 'DisplayName') ?? '';
    final typeValue = int.tryParse(
          element.childText('FolderHierarchy', 'Type') ?? '',
        ) ??
        1;

    return EasFolder(
      serverId: serverId,
      parentId: parentId,
      displayName: displayName,
      type: EasFolderType.fromValue(typeValue),
    );
  }
}
