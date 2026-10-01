/// Storage of EAS synchronization keys.
library;

import 'dart:async';

/// Storage of the FolderSync key and the per-collection Sync keys used by
/// `EasClient`.
///
/// Implement it to persist sync state across restarts (e.g. in a
/// database), so the client resumes with the stored keys instead of a
/// full resync. `null` / absence means "initial sync" (SyncKey `0`).
///
/// Methods may be synchronous or asynchronous ([FutureOr]). The client
/// writes a new key right after the server returned it; for atomicity with
/// locally applied changes, a consumer may instead drive sync keys itself
/// through the command classes.
abstract interface class EasSyncStateStore {
  /// FolderSync key, or `null` before the first FolderSync.
  FutureOr<String?> getFolderSyncKey();

  /// Store the FolderSync key.
  FutureOr<void> setFolderSyncKey(String syncKey);

  /// Sync key of [collectionId], or `null` if the collection has not been
  /// synchronized yet.
  FutureOr<String?> getSyncKey(String collectionId);

  /// Store the Sync key of [collectionId].
  FutureOr<void> setSyncKey(String collectionId, String syncKey);

  /// Forget the Sync key of [collectionId].
  FutureOr<void> removeSyncKey(String collectionId);

  /// Forget the FolderSync key and all collection keys.
  FutureOr<void> clear();
}

/// In-memory [EasSyncStateStore] (the default): state is lost when the
/// process ends.
class InMemoryEasSyncStateStore implements EasSyncStateStore {
  String? _folderSyncKey;
  final Map<String, String> _syncKeys = {};

  @override
  String? getFolderSyncKey() => _folderSyncKey;

  @override
  void setFolderSyncKey(String syncKey) => _folderSyncKey = syncKey;

  @override
  String? getSyncKey(String collectionId) => _syncKeys[collectionId];

  @override
  void setSyncKey(String collectionId, String syncKey) =>
      _syncKeys[collectionId] = syncKey;

  @override
  void removeSyncKey(String collectionId) => _syncKeys.remove(collectionId);

  @override
  void clear() {
    _folderSyncKey = null;
    _syncKeys.clear();
  }
}
