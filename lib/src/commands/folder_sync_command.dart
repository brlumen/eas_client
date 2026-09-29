/// FolderSync command — synchronizes folder hierarchy; GetHierarchy
/// (protocol versions 2.5-12.1).
///
/// Reference: MS-ASCMD sections 2.2.1.5, 2.2.1.8
library;

import 'dart:typed_data';

import '../models/eas_folder.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'FolderHierarchy';

/// Status codes of FolderSync/FolderCreate/FolderDelete/FolderUpdate
/// (MS-ASCMD 2.2.3.177.3-6).
enum FolderHierarchyStatus {
  success(1, 'Success'),
  alreadyExists(2, 'A folder with that name already exists'),
  specialFolder(3, 'The folder is a special system folder'),
  folderNotFound(4, 'The specified folder does not exist'),
  parentNotFound(5, 'The specified parent folder was not found'),
  serverError(6, 'An error occurred on the server'),
  invalidSyncKey(9, 'Synchronization key mismatch or invalid'),
  malformedRequest(10, 'Incorrectly formatted request'),
  unknownError(11, 'An unknown error occurred'),
  codeUnknown(12, 'Code unknown (unusual back-end issue)');

  final int code;
  final String description;

  const FolderHierarchyStatus(this.code, this.description);

  static FolderHierarchyStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Result of a FolderSync command.
class FolderSyncResult {
  final int status;
  final String syncKey;
  final List<EasFolder> addedFolders;
  final List<EasFolder> updatedFolders;
  final List<String> deletedFolderIds;

  /// Number of changes reported by the server (`Count`).
  final int? count;

  const FolderSyncResult({
    required this.status,
    required this.syncKey,
    this.addedFolders = const [],
    this.updatedFolders = const [],
    this.deletedFolderIds = const [],
    this.count,
  });

  bool get isSuccess => status == 1;

  /// Typed [status], `null` if unknown.
  FolderHierarchyStatus? get statusInfo =>
      FolderHierarchyStatus.fromCode(status);

  /// Whether the FolderSync key is invalid and the hierarchy must be
  /// re-synced from SyncKey 0 (Status 9).
  bool get needsReset => status == 9;
}

/// Parse a folder (`Add`/`Update` of FolderSync, `Folder` of
/// GetHierarchy).
EasFolder parseFolderElement(WbxmlElement element) => EasFolder(
  serverId: element.childText(_ns, 'ServerId') ?? '',
  parentId: element.childText(_ns, 'ParentId') ?? '0',
  displayName: element.childText(_ns, 'DisplayName') ?? '',
  type: EasFolderType.fromValue(
    int.tryParse(element.childText(_ns, 'Type') ?? '') ?? 1,
  ),
);

class FolderSyncCommand extends EasCommand<FolderSyncResult> {
  final String syncKey;

  /// Create a FolderSync command.
  /// Use syncKey '0' for initial sync.
  FolderSyncCommand({this.syncKey = '0'}) {
    checkLength(syncKey, 64, 'syncKey');
  }

  @override
  String get commandName => 'FolderSync';

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'FolderSync', [xText(_ns, 'SyncKey', syncKey)]),
  );

  @override
  FolderSyncResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final status = xStatus(root, _ns);
    final newSyncKey = root.childText(_ns, 'SyncKey') ?? syncKey;

    final changes = root.findChild(_ns, 'Changes');
    if (changes == null) {
      return FolderSyncResult(status: status, syncKey: newSyncKey);
    }

    return FolderSyncResult(
      status: status,
      syncKey: newSyncKey,
      count: int.tryParse(changes.childText(_ns, 'Count') ?? ''),
      addedFolders: changes
          .findChildren(_ns, 'Add')
          .map(parseFolderElement)
          .toList(),
      updatedFolders: changes
          .findChildren(_ns, 'Update')
          .map(parseFolderElement)
          .toList(),
      deletedFolderIds: changes
          .findChildren(_ns, 'Delete')
          .map((e) => e.childText(_ns, 'ServerId') ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
    );
  }
}

/// GetHierarchy — list of email folders (protocol versions 2.5, 12.0,
/// 12.1 only; later versions use FolderSync).
///
/// The request has no body; the response root is `Folders`. HTTP 500 is
/// returned on failure.
class GetHierarchyCommand extends EasCommand<List<EasFolder>> {
  @override
  String get commandName => 'GetHierarchy';

  /// Not used: the request has no body.
  @override
  WbxmlDocument buildRequest() =>
      throw UnsupportedError('GetHierarchy request has no body');

  @override
  Uint8List? encodeRequest(String protocolVersion) => null;

  @override
  List<EasFolder> parseEmptyResponse() => const [];

  @override
  List<EasFolder> parseResponse(WbxmlDocument response) => response.root
      .findChildren(_ns, 'Folder')
      .map(parseFolderElement)
      .toList();
}
