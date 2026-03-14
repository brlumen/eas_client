/// High-level EAS client API.
///
/// Provides a simple interface for interacting with Exchange ActiveSync servers.
/// Handles provisioning, folder sync, email sync, and other EAS operations.
library;

import 'package:http/http.dart' as http;

import 'dart:typed_data';

import '../commands/eas_command.dart';
import '../models/eas_policy.dart';
import '../commands/folder_sync_command.dart';
import '../commands/item_operations_command.dart';
import '../commands/move_items_command.dart';
import '../commands/options_command.dart';
import '../commands/ping_command.dart';
import '../commands/provision_command.dart';
import '../commands/search_command.dart';
import '../commands/send_mail_command.dart';
import '../commands/sync_command.dart';
import '../models/eas_email.dart';
import '../models/server_info.dart';
import '../models/sync_state.dart';
import '../transport/autodiscover.dart';
import '../transport/eas_credentials.dart';
import '../transport/eas_http_client.dart';

/// High-level EAS client.
class EasClient {
  final EasHttpClient _httpClient;
  String _folderSyncKey = '0';
  final Map<String, SyncState> _syncStates = {};

  EasClient({
    required String server,
    required EasCredentials credentials,
    String protocolVersion = '16.1',
    required String deviceId,
    String deviceType = 'FlutterEAS',
    Duration commandTimeout = const Duration(seconds: 120),
    Duration pingTimeoutBuffer = const Duration(seconds: 120),
    int maxResponseSize = 25 * 1024 * 1024,
    http.Client? httpClient,
  }) : _httpClient = EasHttpClient(
          server: server,
          credentials: credentials,
          protocolVersion: protocolVersion,
          deviceId: deviceId,
          deviceType: deviceType,
          commandTimeout: commandTimeout,
          pingTimeoutBuffer: pingTimeoutBuffer,
          maxResponseSize: maxResponseSize,
          httpClient: httpClient,
        );

  /// Create an EasClient by discovering the server from an email address.
  ///
  /// Uses Autodiscover protocol to find the EAS endpoint.
  /// Only requires email and password — server is discovered automatically.
  static Future<EasClient> autodiscover({
    required String email,
    required String password,
    String protocolVersion = '16.1',
    required String deviceId,
    String deviceType = 'FlutterEAS',
    Duration commandTimeout = const Duration(seconds: 120),
    Duration pingTimeoutBuffer = const Duration(seconds: 120),
    int maxResponseSize = 25 * 1024 * 1024,
    http.Client? httpClient,
  }) async {
    final credentials = BasicCredentials(
      username: email,
      password: password,
    );

    final discovery = Autodiscover(httpClient: httpClient);
    try {
      final result = await discovery.discover(
        email: email,
        credentials: credentials,
      );

      return EasClient(
        server: result.server,
        credentials: credentials,
        protocolVersion: protocolVersion,
        deviceId: deviceId,
        deviceType: deviceType,
        commandTimeout: commandTimeout,
        pingTimeoutBuffer: pingTimeoutBuffer,
        maxResponseSize: maxResponseSize,
        httpClient: httpClient,
      );
    } finally {
      if (httpClient == null) discovery.dispose();
    }
  }

  /// Underlying HTTP client for advanced usage.
  EasHttpClient get httpClient => _httpClient;

  /// Discover server capabilities via OPTIONS.
  Future<ServerInfo> discoverCapabilities() async {
    return OptionsCommand().execute(_httpClient);
  }

  /// Run the Provision flow.
  ///
  /// Returns [EasPolicy] with parsed security policies from the server,
  /// or `null` if server doesn't require provisioning.
  /// PolicyKey is set internally for subsequent commands.
  Future<EasPolicy?> provision() async {
    return ProvisionCommand().execute(_httpClient);
  }

  /// Sync folder hierarchy.
  /// Returns all folders on initial sync, or changes on subsequent syncs.
  Future<FolderSyncResult> syncFolders() async {
    final command = FolderSyncCommand(syncKey: _folderSyncKey);
    final result = await command.execute(_httpClient);
    _folderSyncKey = result.syncKey;
    return result;
  }

  /// Sync contents of a specific folder.
  ///
  /// Uses internal sync state tracking. On first call for a folder,
  /// performs initial sync (SyncKey=0). Subsequent calls sync changes.
  Future<SyncResult> syncFolder(
    String folderId, {
    int windowSize = 50,
    int bodyType = 2,
    int? bodyTruncationSize,
  }) async {
    final state = _syncStates.putIfAbsent(
      folderId,
      () => SyncState(collectionId: folderId),
    );

    final command = SyncCommand(
      syncKey: state.syncKey,
      collectionId: folderId,
      windowSize: windowSize,
      bodyType: bodyType,
      bodyTruncationSize: bodyTruncationSize,
    );

    final result = await command.execute(_httpClient);

    if (result.needsReset) {
      // Invalid SyncKey — reset and retry
      state.syncKey = '0';
      final retryCommand = SyncCommand(
        syncKey: '0',
        collectionId: folderId,
        windowSize: windowSize,
        bodyType: bodyType,
        bodyTruncationSize: bodyTruncationSize,
      );
      final retryResult = await retryCommand.execute(_httpClient);
      state.syncKey = retryResult.syncKey;
      return retryResult;
    }

    state.syncKey = result.syncKey;
    return result;
  }

  /// Perform full initial sync: get SyncKey, then fetch all items.
  ///
  /// Convenience method that handles the two-step initial sync process.
  ///
  /// [maxIterations] — maximum sync iterations to prevent infinite loops.
  /// MS-ASCMD does not define a protocol-level protection against infinite
  /// MoreAvailable loops, so the client must enforce a limit.
  ///
  /// [stopOnEmptyResponse] — stop if server returns MoreAvailable without
  /// any actual changes (documented MS behavior).
  Future<List<EasEmail>> fullSync(
    String folderId, {
    int windowSize = 100,
    int bodyType = 2,
    int? bodyTruncationSize,
    int maxIterations = 1000,
    bool stopOnEmptyResponse = true,
  }) async {
    final allEmails = <EasEmail>[];

    // First call: get initial SyncKey
    var result = await syncFolder(
      folderId,
      windowSize: windowSize,
      bodyType: bodyType,
      bodyTruncationSize: bodyTruncationSize,
    );

    // Second call: get actual data
    result = await syncFolder(
      folderId,
      windowSize: windowSize,
      bodyType: bodyType,
      bodyTruncationSize: bodyTruncationSize,
    );

    allEmails.addAll(result.addedEmails);

    // Continue fetching if more available
    var iterations = 0;
    var previousSyncKey = result.syncKey;
    while (result.moreAvailable) {
      iterations++;
      if (iterations >= maxIterations) {
        throw EasCommandException(
          command: 'Sync',
          message: 'fullSync exceeded maxIterations ($maxIterations). '
              'Fetched ${allEmails.length} emails so far.',
        );
      }

      result = await syncFolder(
        folderId,
        windowSize: windowSize,
        bodyType: bodyType,
        bodyTruncationSize: bodyTruncationSize,
      );

      final hasChanges = result.addedEmails.isNotEmpty ||
          result.changedEmails.isNotEmpty ||
          result.deletedIds.isNotEmpty;

      if (stopOnEmptyResponse && !hasChanges) {
        break;
      }

      if (result.syncKey == previousSyncKey) {
        break; // SyncKey not progressing — stuck loop
      }
      previousSyncKey = result.syncKey;

      allEmails.addAll(result.addedEmails);
    }

    return allEmails;
  }

  /// Ping — wait for changes in specified folders.
  ///
  /// Long-poll: connection stays open until changes occur or heartbeat expires.
  /// HTTP timeout = [heartbeatInterval] + [EasHttpClient.pingTimeoutBuffer].
  Future<PingResult> ping(
    List<String> folderIds, {
    int heartbeatInterval = 480,
  }) async {
    final command = PingCommand(
      folderIds: folderIds,
      heartbeatInterval: heartbeatInterval,
    );
    final pingTimeout = Duration(seconds: heartbeatInterval) +
        _httpClient.pingTimeoutBuffer;
    return command.execute(_httpClient, timeout: pingTimeout);
  }

  /// Fetch full email body.
  Future<ItemOperationsResult> fetchEmailBody(
    String serverId,
    String collectionId, {
    int bodyType = 2,
  }) async {
    final command = FetchEmailBodyCommand(
      serverId: serverId,
      collectionId: collectionId,
      bodyType: bodyType,
    );
    return command.execute(_httpClient);
  }

  /// Fetch attachment by file reference.
  Future<Uint8List?> fetchAttachment(String fileReference) async {
    final command = FetchAttachmentCommand(fileReference: fileReference);
    final result = await command.execute(_httpClient);
    return result.data;
  }

  /// Send an email.
  ///
  /// [clientId] — unique ID to prevent duplicates.
  /// [mimeContent] — full MIME content of the email.
  Future<void> sendMail({
    required String clientId,
    required String mimeContent,
    bool saveInSentItems = true,
  }) async {
    final command = SendMailCommand(
      clientId: clientId,
      mimeContent: mimeContent,
      saveInSentItems: saveInSentItems,
    );
    await command.execute(_httpClient);
  }

  /// Move items to a different folder.
  Future<List<MoveItemResult>> moveItems({
    required List<String> serverIds,
    required String srcFolderId,
    required String dstFolderId,
  }) async {
    final command = MoveItemsCommand(
      serverIds: serverIds,
      srcFolderId: srcFolderId,
      dstFolderId: dstFolderId,
    );
    return command.execute(_httpClient);
  }

  /// Server-side search.
  Future<SearchResult> search(
    String query, {
    String? collectionId,
    int rangeStart = 0,
    int rangeEnd = 49,
  }) async {
    final command = SearchCommand(
      query: query,
      collectionId: collectionId,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
    return command.execute(_httpClient);
  }

  /// Reset sync state for a folder.
  void resetSyncState(String folderId) {
    _syncStates.remove(folderId);
  }

  /// Reset all sync states.
  void resetAllSyncStates() {
    _syncStates.clear();
    _folderSyncKey = '0';
  }

  /// Dispose of resources.
  void dispose() {
    _httpClient.dispose();
  }
}
