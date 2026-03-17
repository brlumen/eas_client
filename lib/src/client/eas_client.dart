/// High-level EAS client API.
///
/// Provides a simple interface for interacting with Exchange ActiveSync servers.
/// Handles provisioning, folder sync, email/calendar/tasks/contacts sync,
/// and all other EAS operations.
library;

import 'package:http/http.dart' as http;

import 'dart:typed_data';

import '../commands/eas_command.dart';
import '../models/eas_calendar_event.dart';
import '../models/eas_contact.dart';
import '../models/eas_folder.dart';
import '../models/eas_note.dart';
import '../models/eas_policy.dart';
import '../serializers/calendar_serializer.dart';
import '../serializers/contact_serializer.dart';
import '../serializers/email_serializer.dart';
import '../serializers/note_serializer.dart';
import '../serializers/task_serializer.dart';
import '../commands/find_command.dart';
import '../commands/folder_management_command.dart';
import '../commands/folder_sync_command.dart';
import '../commands/get_item_estimate_command.dart';
import '../commands/item_operations_command.dart';
import '../commands/meeting_response_command.dart';
import '../commands/move_items_command.dart';
import '../commands/options_command.dart';
import '../commands/ping_command.dart';
import '../commands/provision_command.dart';
import '../commands/resolve_recipients_command.dart';
import '../commands/search_command.dart';
import '../commands/send_mail_command.dart';
import '../commands/settings_command.dart';
import '../commands/smart_forward_command.dart';
import '../commands/smart_reply_command.dart';
import '../commands/sync_command.dart';
import '../commands/validate_cert_command.dart';
import '../models/eas_email.dart';
import '../models/eas_task.dart';
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

  // ─── Core ─────────────────────────────────────────────────────────────────

  /// Discover server capabilities via OPTIONS.
  Future<ServerInfo> discoverCapabilities() async {
    return OptionsCommand().execute(_httpClient);
  }

  /// Run the Provision flow.
  ///
  /// [policyAckStatus] — status to report to the server during policy
  /// acknowledgement (MS-ASPROV 2.2.2.54.1). The consumer must explicitly
  /// indicate whether policies have been applied on the device.
  ///
  /// Returns [EasPolicy] with parsed security policies from the server,
  /// or `null` if server doesn't require provisioning.
  /// PolicyKey is set internally for subsequent commands.
  Future<EasPolicy?> provision({
    required PolicyAckStatus policyAckStatus,
  }) async {
    return ProvisionCommand(
      policyAckStatus: policyAckStatus,
    ).execute(_httpClient);
  }

  // ─── Folder management ────────────────────────────────────────────────────

  /// Sync folder hierarchy.
  /// Returns all folders on initial sync, or changes on subsequent syncs.
  Future<FolderSyncResult> syncFolders() async {
    final command = FolderSyncCommand(syncKey: _folderSyncKey);
    final result = await command.execute(_httpClient);
    _folderSyncKey = result.syncKey;
    return result;
  }

  /// Create a new folder on the server.
  ///
  /// Returns the server-assigned ID of the new folder.
  Future<String?> createFolder(
    String displayName, {
    String parentId = '0',
    EasFolderType type = EasFolderType.userMail,
  }) async {
    final command = FolderCreateCommand(
      syncKey: _folderSyncKey,
      parentId: parentId,
      displayName: displayName,
      type: type,
    );
    final result = await command.execute(_httpClient);
    _folderSyncKey = result.syncKey;
    if (!result.isSuccess) {
      throw EasCommandException(
        command: 'FolderCreate',
        easStatus: result.status,
        message: 'FolderCreate failed (status ${result.status})',
      );
    }
    return result.serverId;
  }

  /// Delete a folder from the server.
  Future<void> deleteFolder(String serverId) async {
    final command = FolderDeleteCommand(
      syncKey: _folderSyncKey,
      serverId: serverId,
    );
    final result = await command.execute(_httpClient);
    _folderSyncKey = result.syncKey;
    if (!result.isSuccess) {
      throw EasCommandException(
        command: 'FolderDelete',
        easStatus: result.status,
        message: 'FolderDelete failed (status ${result.status})',
      );
    }
  }

  /// Rename or move a folder on the server.
  Future<void> renameFolder(
    String serverId,
    String newDisplayName, {
    String? newParentId,
  }) async {
    // Determine current parent — we need it for FolderUpdate.
    // If not provided, attempt with '0' (server typically ignores it on rename-only).
    final command = FolderUpdateCommand(
      syncKey: _folderSyncKey,
      serverId: serverId,
      displayName: newDisplayName,
      parentId: newParentId ?? '0',
    );
    final result = await command.execute(_httpClient);
    _folderSyncKey = result.syncKey;
    if (!result.isSuccess) {
      throw EasCommandException(
        command: 'FolderUpdate',
        easStatus: result.status,
        message: 'FolderUpdate failed (status ${result.status})',
      );
    }
  }

  // ─── Sync ─────────────────────────────────────────────────────────────────

  /// Sync contents of a specific folder.
  ///
  /// Uses internal sync state tracking. On first call for a folder,
  /// performs initial sync (SyncKey=0). Subsequent calls sync changes.
  Future<SyncResult> syncFolder(
    String folderId, {
    SyncContentType contentType = SyncContentType.email,
    int windowSize = 50,
    int bodyType = 2,
    int? bodyTruncationSize,
    SyncFilterType? filterType,
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
      contentType: contentType,
      filterType: filterType,
    );

    final result = await command.execute(_httpClient);

    if (result.needsReset) {
      state.syncKey = '0';
      final retryCommand = SyncCommand(
        syncKey: '0',
        collectionId: folderId,
        windowSize: windowSize,
        bodyType: bodyType,
        bodyTruncationSize: bodyTruncationSize,
        contentType: contentType,
        filterType: filterType,
      );
      final retryResult = await retryCommand.execute(_httpClient);
      state.syncKey = retryResult.syncKey;
      return retryResult;
    }

    state.syncKey = result.syncKey;
    return result;
  }

  // ─── Full sync helpers ────────────────────────────────────────────────────

  /// Perform full initial sync of email in a folder.
  ///
  /// [maxIterations] — maximum sync iterations to prevent infinite loops.
  Future<List<EasEmail>> fullSync(
    String folderId, {
    int windowSize = 100,
    int bodyType = 2,
    int? bodyTruncationSize,
    int maxIterations = 1000,
    bool stopOnEmptyResponse = true,
    SyncFilterType? filterType,
  }) async {
    return _fullSyncTyped<EasEmail>(
      folderId,
      contentType: SyncContentType.email,
      windowSize: windowSize,
      bodyType: bodyType,
      bodyTruncationSize: bodyTruncationSize,
      maxIterations: maxIterations,
      stopOnEmptyResponse: stopOnEmptyResponse,
      filterType: filterType,
      getAdded: (r) => r.addedEmails,
      getChanged: (r) => r.changedEmails,
    );
  }

  /// Perform full initial sync of calendar events in a folder.
  Future<List<EasCalendarEvent>> fullSyncCalendar(
    String folderId, {
    int windowSize = 100,
    int bodyType = 2,
    int? bodyTruncationSize,
    int maxIterations = 1000,
    bool stopOnEmptyResponse = true,
  }) async {
    return _fullSyncTyped<EasCalendarEvent>(
      folderId,
      contentType: SyncContentType.calendar,
      windowSize: windowSize,
      bodyType: bodyType,
      bodyTruncationSize: bodyTruncationSize,
      maxIterations: maxIterations,
      stopOnEmptyResponse: stopOnEmptyResponse,
      getAdded: (r) => r.addedCalendarEvents,
      getChanged: (r) => r.changedCalendarEvents,
    );
  }

  /// Perform full initial sync of tasks in a folder.
  Future<List<EasTask>> fullSyncTasks(
    String folderId, {
    int windowSize = 100,
    int maxIterations = 1000,
    bool stopOnEmptyResponse = true,
  }) async {
    return _fullSyncTyped<EasTask>(
      folderId,
      contentType: SyncContentType.task,
      windowSize: windowSize,
      maxIterations: maxIterations,
      stopOnEmptyResponse: stopOnEmptyResponse,
      getAdded: (r) => r.addedTasks,
      getChanged: (r) => r.changedTasks,
    );
  }

  /// Perform full initial sync of contacts in a folder.
  Future<List<EasContact>> fullSyncContacts(
    String folderId, {
    int windowSize = 100,
    int maxIterations = 1000,
    bool stopOnEmptyResponse = true,
  }) async {
    return _fullSyncTyped<EasContact>(
      folderId,
      contentType: SyncContentType.contact,
      windowSize: windowSize,
      maxIterations: maxIterations,
      stopOnEmptyResponse: stopOnEmptyResponse,
      getAdded: (r) => r.addedContacts,
      getChanged: (r) => r.changedContacts,
    );
  }

  /// Perform full initial sync of notes in a folder.
  Future<List<EasNote>> fullSyncNotes(
    String folderId, {
    int windowSize = 100,
    int bodyType = 2,
    int maxIterations = 1000,
    bool stopOnEmptyResponse = true,
  }) async {
    return _fullSyncTyped<EasNote>(
      folderId,
      contentType: SyncContentType.note,
      windowSize: windowSize,
      bodyType: bodyType,
      maxIterations: maxIterations,
      stopOnEmptyResponse: stopOnEmptyResponse,
      getAdded: (r) => r.addedNotes,
      getChanged: (r) => r.changedNotes,
    );
  }

  Future<List<T>> _fullSyncTyped<T>(
    String folderId, {
    required SyncContentType contentType,
    int windowSize = 100,
    int bodyType = 2,
    int? bodyTruncationSize,
    int maxIterations = 1000,
    bool stopOnEmptyResponse = true,
    SyncFilterType? filterType,
    required List<T> Function(SyncResult) getAdded,
    required List<T> Function(SyncResult) getChanged,
  }) async {
    final all = <T>[];

    // First call: get initial SyncKey
    var result = await syncFolder(
      folderId,
      contentType: contentType,
      windowSize: windowSize,
      bodyType: bodyType,
      bodyTruncationSize: bodyTruncationSize,
      filterType: filterType,
    );

    // Second call: get actual data
    result = await syncFolder(
      folderId,
      contentType: contentType,
      windowSize: windowSize,
      bodyType: bodyType,
      bodyTruncationSize: bodyTruncationSize,
      filterType: filterType,
    );

    all.addAll(getAdded(result));

    var iterations = 0;
    var previousSyncKey = result.syncKey;
    while (result.moreAvailable) {
      iterations++;
      if (iterations >= maxIterations) {
        throw EasCommandException(
          command: 'Sync',
          message: 'fullSync exceeded maxIterations ($maxIterations). '
              'Fetched ${all.length} items so far.',
        );
      }

      result = await syncFolder(
        folderId,
        contentType: contentType,
        windowSize: windowSize,
        bodyType: bodyType,
        bodyTruncationSize: bodyTruncationSize,
        filterType: filterType,
      );

      final hasChanges = getAdded(result).isNotEmpty ||
          getChanged(result).isNotEmpty ||
          result.deletedIds.isNotEmpty;

      if (stopOnEmptyResponse && !hasChanges) break;
      if (result.syncKey == previousSyncKey) break;
      previousSyncKey = result.syncKey;

      all.addAll(getAdded(result));
    }

    return all;
  }

  // ─── Sync write operations ───────────────────────────────────────────────

  /// Execute Sync with client-to-server commands (Add/Change/Delete).
  ///
  /// Requires an existing sync key (at least one syncFolder call first).
  Future<SyncResult> syncWithCommands(
    String folderId, {
    required SyncContentType contentType,
    required List<SyncClientCommand> commands,
    int? conflict,
  }) async {
    final state = _syncStates[folderId];
    if (state == null || state.syncKey == '0') {
      throw EasCommandException(
        command: 'Sync',
        message: 'Must sync folder at least once before sending commands. '
            'Call syncFolder() first.',
      );
    }

    final command = SyncCommand(
      syncKey: state.syncKey,
      collectionId: folderId,
      contentType: contentType,
      clientCommands: commands,
      conflict: conflict,
    );

    final result = await command.execute(_httpClient);
    state.syncKey = result.syncKey;
    return result;
  }

  /// Mark an email as read or unread.
  Future<SyncResult> markEmailRead(
    String folderId,
    String serverId,
    bool read,
  ) {
    return syncWithCommands(
      folderId,
      contentType: SyncContentType.email,
      commands: [
        SyncChangeItem(
          serverId: serverId,
          applicationData: EmailSerializer.serializeReadFlag(read),
        ),
      ],
    );
  }

  /// Set email flag status (0=cleared, 1=complete, 2=active).
  Future<SyncResult> setEmailFlag(
    String folderId,
    String serverId,
    int flagStatus,
  ) {
    return syncWithCommands(
      folderId,
      contentType: SyncContentType.email,
      commands: [
        SyncChangeItem(
          serverId: serverId,
          applicationData: EmailSerializer.serializeFlag(flagStatus),
        ),
      ],
    );
  }

  /// Delete items from a folder.
  Future<SyncResult> deleteItems(
    String folderId, {
    required List<String> serverIds,
    SyncContentType contentType = SyncContentType.email,
  }) {
    return syncWithCommands(
      folderId,
      contentType: contentType,
      commands:
          serverIds.map((id) => SyncDeleteItem(serverId: id)).toList(),
    );
  }

  /// Create a calendar event on the server.
  ///
  /// Returns the SyncResult with addResponses containing server-assigned ID.
  Future<SyncResult> createCalendarEvent(
    String folderId,
    EasCalendarEvent event, {
    required String clientId,
  }) {
    return syncWithCommands(
      folderId,
      contentType: SyncContentType.calendar,
      commands: [
        SyncAddItem(
          clientId: clientId,
          applicationData: CalendarSerializer.serialize(event),
        ),
      ],
    );
  }

  /// Update a calendar event on the server.
  Future<SyncResult> updateCalendarEvent(
    String folderId,
    String serverId,
    EasCalendarEvent event,
  ) {
    return syncWithCommands(
      folderId,
      contentType: SyncContentType.calendar,
      commands: [
        SyncChangeItem(
          serverId: serverId,
          applicationData: CalendarSerializer.serialize(event),
        ),
      ],
    );
  }

  /// Create a contact on the server.
  Future<SyncResult> createContact(
    String folderId,
    EasContact contact, {
    required String clientId,
  }) {
    return syncWithCommands(
      folderId,
      contentType: SyncContentType.contact,
      commands: [
        SyncAddItem(
          clientId: clientId,
          applicationData: ContactSerializer.serialize(contact),
        ),
      ],
    );
  }

  /// Create a task on the server.
  Future<SyncResult> createTask(
    String folderId,
    EasTask task, {
    required String clientId,
  }) {
    return syncWithCommands(
      folderId,
      contentType: SyncContentType.task,
      commands: [
        SyncAddItem(
          clientId: clientId,
          applicationData: TaskSerializer.serialize(task),
        ),
      ],
    );
  }

  /// Create a note on the server.
  Future<SyncResult> createNote(
    String folderId,
    EasNote note, {
    required String clientId,
  }) {
    return syncWithCommands(
      folderId,
      contentType: SyncContentType.note,
      commands: [
        SyncAddItem(
          clientId: clientId,
          applicationData: NoteSerializer.serialize(note),
        ),
      ],
    );
  }

  // ─── Push / estimate ──────────────────────────────────────────────────────

  /// Ping — wait for changes in specified folders.
  ///
  /// [folders] — list of PingFolder with id and className.
  /// Use [pingFolderIds] for the simpler API that treats all as Email.
  ///
  /// Long-poll: connection stays open until changes occur or heartbeat expires.
  Future<PingResult> ping(
    List<PingFolder> folders, {
    int heartbeatInterval = 480,
  }) async {
    final command = PingCommand(
      folders: folders,
      heartbeatInterval: heartbeatInterval,
    );
    final pingTimeout = Duration(seconds: heartbeatInterval) +
        _httpClient.pingTimeoutBuffer;
    return command.execute(_httpClient, timeout: pingTimeout);
  }

  /// Get an estimate of the number of items that will be synced for a folder.
  ///
  /// Requires an existing sync key (after at least one syncFolder call).
  Future<int> getItemEstimate(String folderId) async {
    final state = _syncStates[folderId];
    final syncKey = state?.syncKey ?? '0';
    final command = GetItemEstimateCommand.single(
      collectionId: folderId,
      syncKey: syncKey,
    );
    final results = await command.execute(_httpClient);
    return results.firstOrNull?.estimate ?? 0;
  }

  // ─── Item operations ──────────────────────────────────────────────────────

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

  /// Delete all items in a folder (empty folder).
  Future<void> emptyFolder(
    String folderId, {
    bool deleteSubFolders = false,
  }) async {
    final command = EmptyFolderCommand(
      folderId: folderId,
      deleteSubFolders: deleteSubFolders,
    );
    final status = await command.execute(_httpClient);
    if (status != 1) {
      throw EasCommandException(
        command: 'ItemOperations',
        easStatus: status,
        message: 'EmptyFolderContents failed (status $status)',
      );
    }
  }

  /// Batch fetch multiple email bodies in a single request.
  Future<List<ItemOperationsResult>> batchFetchEmailBodies(
    List<({String serverId, String collectionId})> items, {
    int bodyType = 2,
  }) async {
    final command = BatchFetchEmailBodiesCommand(
      items: items,
      bodyType: bodyType,
    );
    return command.execute(_httpClient);
  }

  // ─── Mail composition ─────────────────────────────────────────────────────

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

  /// Reply to an email, including the original message body (server-side).
  Future<void> smartReply({
    required String clientId,
    required String serverId,
    required String collectionId,
    required String mimeContent,
    bool saveInSentItems = true,
  }) async {
    final command = SmartReplyCommand(
      clientId: clientId,
      serverId: serverId,
      collectionId: collectionId,
      mimeContent: mimeContent,
      saveInSentItems: saveInSentItems,
    );
    await command.execute(_httpClient);
  }

  /// Forward an email, including the original message body (server-side).
  Future<void> smartForward({
    required String clientId,
    required String serverId,
    required String collectionId,
    required String mimeContent,
    bool saveInSentItems = true,
  }) async {
    final command = SmartForwardCommand(
      clientId: clientId,
      serverId: serverId,
      collectionId: collectionId,
      mimeContent: mimeContent,
      saveInSentItems: saveInSentItems,
    );
    await command.execute(_httpClient);
  }

  // ─── Move / search ────────────────────────────────────────────────────────

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

  /// Server-side mailbox search.
  Future<SearchResult> search(
    String query, {
    String? collectionId,
    int rangeStart = 0,
    int rangeEnd = 49,
    int bodyType = 2,
    int bodyTruncationSize = 512,
  }) async {
    final command = SearchCommand(
      query: query,
      collectionId: collectionId,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      bodyType: bodyType,
      bodyTruncationSize: bodyTruncationSize,
    );
    return command.execute(_httpClient);
  }

  /// Search the Global Address List (GAL).
  Future<GalSearchResult> searchGal(
    String query, {
    int rangeStart = 0,
    int rangeEnd = 99,
  }) async {
    final command = GalSearchCommand(
      query: query,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
    return command.execute(_httpClient);
  }

  /// Find command (EAS 16.1) — GAL search with picture support.
  Future<FindResult> find(
    String query, {
    int rangeStart = 0,
    int rangeEnd = 99,
    bool requestPicture = false,
    int maxPictureSize = 0,
  }) async {
    final command = FindCommand(
      query: query,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      requestPicture: requestPicture,
      maxPictureSize: maxPictureSize,
    );
    return command.execute(_httpClient);
  }

  // ─── Calendar ─────────────────────────────────────────────────────────────

  /// Respond to a meeting request (accept, tentative, or decline).
  Future<List<MeetingResponseResult>> respondToMeeting({
    required String requestId,
    required String collectionId,
    required MeetingResponseStatus response,
  }) async {
    final command = MeetingResponseCommand.single(
      requestId: requestId,
      collectionId: collectionId,
      response: response,
    );
    return command.execute(_httpClient);
  }

  // ─── Settings ─────────────────────────────────────────────────────────────

  /// Get current server settings: OOF state and user information.
  Future<EasSettings> getSettings() async {
    return SettingsGetCommand().execute(_httpClient);
  }

  /// Update Out-of-Office settings.
  Future<void> setOutOfOffice(EasOofSettings oof) async {
    final status =
        await SettingsSetOofCommand(oof: oof).execute(_httpClient);
    if (status != 1) {
      throw EasCommandException(
        command: 'Settings',
        easStatus: status,
        message: 'Settings/OOF set failed (status $status)',
      );
    }
  }

  /// Send device information to the server.
  Future<void> sendDeviceInfo({
    required String model,
    required String friendlyName,
    required String os,
    String? osLanguage,
    String? phoneNumber,
  }) async {
    final status = await SettingsSendDeviceInfoCommand(
      model: model,
      friendlyName: friendlyName,
      os: os,
      osLanguage: osLanguage,
      phoneNumber: phoneNumber,
    ).execute(_httpClient);
    if (status != 1) {
      throw EasCommandException(
        command: 'Settings',
        easStatus: status,
        message: 'Settings/DeviceInformation failed (status $status)',
      );
    }
  }

  /// Get RightsManagement (IRM) templates from the server.
  Future<EasRightsManagementInfo> getRightsManagementInfo() async {
    return SettingsGetRightsManagementCommand().execute(_httpClient);
  }

  /// Set/enable device password.
  Future<void> setDevicePassword(String password) async {
    final status = await SettingsSetDevicePasswordCommand(
      password: password,
    ).execute(_httpClient);
    if (status != 1) {
      throw EasCommandException(
        command: 'Settings',
        easStatus: status,
        message: 'Settings/DevicePassword failed (status $status)',
      );
    }
  }

  // ─── Address book ─────────────────────────────────────────────────────────

  /// Resolve email addresses to contact information.
  ///
  /// Optionally request free/busy availability by providing
  /// [availabilityStartTime] and [availabilityEndTime].
  Future<List<ResolveRecipientsResponse>> resolveRecipients(
    List<String> recipients, {
    int maxAmbiguousRecipients = 20,
    DateTime? availabilityStartTime,
    DateTime? availabilityEndTime,
    int? certificateRetrieval,
  }) async {
    final command = ResolveRecipientsCommand(
      recipients: recipients,
      maxAmbiguousRecipients: maxAmbiguousRecipients,
      availabilityStartTime: availabilityStartTime,
      availabilityEndTime: availabilityEndTime,
      certificateRetrieval: certificateRetrieval,
    );
    return command.execute(_httpClient);
  }

  // ─── S/MIME ───────────────────────────────────────────────────────────────

  /// Validate S/MIME certificates.
  Future<List<CertValidationResult>> validateCertificates(
    List<Uint8List> certificates, {
    bool checkCRL = true,
    List<Uint8List> certificateChain = const [],
  }) async {
    final command = ValidateCertCommand(
      certificates: certificates,
      checkCRL: checkCRL,
      certificateChain: certificateChain,
    );
    return command.execute(_httpClient);
  }

  // ─── State management ─────────────────────────────────────────────────────

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
