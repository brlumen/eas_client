/// Sync state tracking for EAS sync operations.
library;

/// Tracks sync state per collection (folder).
class SyncState {
  /// Current sync key. '0' means initial sync needed.
  String syncKey;

  /// Collection (folder) ID.
  final String collectionId;

  SyncState({
    this.syncKey = '0',
    required this.collectionId,
  });

  /// Whether this is the initial sync (SyncKey = '0').
  bool get isInitialSync => syncKey == '0';

  @override
  String toString() =>
      'SyncState(collection: $collectionId, key: $syncKey)';
}
