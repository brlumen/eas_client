/// High-level EAS client API.
///
/// Provides a simple interface for interacting with Exchange ActiveSync servers.
/// Handles provisioning, folder sync, email/calendar/tasks/contacts sync,
/// and all other EAS operations.
library;

import 'package:http/http.dart' as http;

import 'dart:typed_data';

import '../commands/eas_command.dart';
import '../models/eas_attachment.dart';
import '../models/eas_body.dart';
import '../models/eas_device_information.dart';
import '../models/eas_calendar_event.dart';
import '../models/eas_contact.dart';
import '../models/eas_exception.dart';
import '../models/eas_folder.dart';
import '../models/eas_note.dart';
import '../models/eas_policy.dart';
import '../models/wbxml_helpers.dart' show protocolVersionValue;
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
import '../transport/dns_srv_resolver.dart';
import '../transport/eas_credentials.dart';
import '../transport/eas_http_client.dart';
import '../wbxml/wbxml_document.dart';

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
    bool useBase64QueryString = false,
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
         useBase64QueryString: useBase64QueryString,
         httpClient: httpClient,
       );

  /// Create an EasClient by discovering the server from an email address.
  ///
  /// Uses Autodiscover protocol to find the EAS endpoint.
  /// Only requires email and password — server is discovered automatically.
  /// [username] is the login when it differs from [email] (e.g. a UPN or
  /// `DOMAIN\user`); defaults to [email].
  static Future<EasClient> autodiscover({
    required String email,
    required String password,
    String? username,
    String protocolVersion = '16.1',
    required String deviceId,
    String deviceType = 'FlutterEAS',
    Duration commandTimeout = const Duration(seconds: 120),
    Duration pingTimeoutBuffer = const Duration(seconds: 120),
    int maxResponseSize = 25 * 1024 * 1024,
    bool useBase64QueryString = false,
    http.Client? httpClient,
    bool enableHttpRedirectStep = false,
    DnsSrvResolver? srvResolver,
    AutodiscoverRedirectConfirmation? confirmRedirect,
  }) async {
    final credentials = BasicCredentials(
      username: username ?? email,
      password: password,
    );

    final discovery = Autodiscover(
      httpClient: httpClient,
      enableHttpRedirectStep: enableHttpRedirectStep,
      srvResolver: srvResolver,
      confirmRedirect: confirmRedirect,
    );
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
        useBase64QueryString: useBase64QueryString,
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
  ///
  /// Throws [EasRemoteWipeException] if the server requests a remote wipe.
  /// The library does not wipe anything: perform the wipe, then call
  /// [acknowledgeRemoteWipe].
  ///
  /// [deviceInformation] is sent in the initial request for protocol
  /// 14.1+ (must contain `model`); a minimal one is used when omitted.
  Future<EasPolicy?> provision({
    required PolicyAckStatus policyAckStatus,
    EasDeviceInformation? deviceInformation,
  }) async {
    return ProvisionCommand(
      policyAckStatus: policyAckStatus,
      deviceInformation: deviceInformation,
    ).execute(_httpClient);
  }

  /// Acknowledge a remote wipe directive received from [provision]
  /// (MS-ASPROV). [type] must match [EasRemoteWipeException.type];
  /// [status] reports whether the consumer's wipe succeeded.
  Future<void> acknowledgeRemoteWipe({
    required RemoteWipeType type,
    required RemoteWipeAckStatus status,
  }) async {
    final result = await RemoteWipeAckCommand(
      type: type,
      status: status,
    ).execute(_httpClient);
    if (result != ProvisionStatus.success) {
      throw EasCommandException(
        command: 'Provision',
        easStatus: result.code,
        message: 'Remote wipe acknowledgement failed',
      );
    }
  }

  // ─── Folder management ────────────────────────────────────────────────────

  /// Sync folder hierarchy.
  /// Returns all folders on initial sync, or changes on subsequent syncs.
  ///
  /// On Status 9 (invalid sync key) the key is reset to '0' and the full
  /// hierarchy is re-synced once; the consumer should then replace its
  /// folder list and reset per-folder sync states.
  Future<FolderSyncResult> syncFolders() async {
    var result = await FolderSyncCommand(
      syncKey: _folderSyncKey,
    ).execute(_httpClient);
    if (result.needsReset && _folderSyncKey != '0') {
      _folderSyncKey = '0';
      result = await FolderSyncCommand().execute(_httpClient);
    }
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
      protocolVersion: _httpClient.protocolVersion,
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
        protocolVersion: _httpClient.protocolVersion,
      );
      final retryResult = await retryCommand.execute(_httpClient);
      state.syncKey = retryResult.syncKey;
      return retryResult;
    }

    state.syncKey = result.syncKey;
    return result;
  }

  /// Sync several folders in a single Sync request.
  ///
  /// Sync keys come from (and are stored to) the internal per-folder state;
  /// the `syncKey` of each [SyncCollection] is ignored. A collection that
  /// answers Status 3 is reset to SyncKey '0' (call again to re-initialize).
  /// Check [MultiSyncResult.needsFolderSync] (Status 12) and run
  /// [syncFolders]. See [MultiSyncCommand] for [partial] / [emptyRequest].
  Future<MultiSyncResult> syncMultipleFolders(
    List<SyncCollection> collections, {
    bool partial = false,
    bool emptyRequest = false,
  }) async {
    final command = MultiSyncCommand(
      collections: [
        for (final c in collections)
          c.withSyncKey(
            _syncStates
                .putIfAbsent(
                  c.collectionId,
                  () => SyncState(collectionId: c.collectionId),
                )
                .syncKey,
            protocolVersion: _httpClient.protocolVersion,
          ),
      ],
      partial: partial,
      emptyRequest: emptyRequest,
    );
    final result = await command.execute(_httpClient);
    for (final r in result.collections) {
      _syncStates[r.collectionId]?.syncKey = r.needsReset ? '0' : r.syncKey;
    }
    return result;
  }

  /// Fetch specific items of a folder by ServerId (Sync `Fetch`).
  ///
  /// Items are returned in [SyncResult.fetchResponses].
  Future<SyncResult> fetchItems(
    String folderId,
    List<String> serverIds, {
    SyncContentType contentType = SyncContentType.email,
  }) {
    return syncWithCommands(
      folderId,
      contentType: contentType,
      commands: [for (final id in serverIds) SyncFetchItem(serverId: id)],
    );
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
          message:
              'fullSync exceeded maxIterations ($maxIterations). '
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

      final hasChanges =
          getAdded(result).isNotEmpty ||
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
        message:
            'Must sync folder at least once before sending commands. '
            'Call syncFolder() first.',
      );
    }

    final command = SyncCommand(
      syncKey: state.syncKey,
      collectionId: folderId,
      contentType: contentType,
      clientCommands: commands,
      conflict: conflict,
      protocolVersion: _httpClient.protocolVersion,
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
      commands: serverIds.map((id) => SyncDeleteItem(serverId: id)).toList(),
    );
  }

  /// Create a calendar event on the server.
  ///
  /// Returns the SyncResult with addResponses containing server-assigned ID.
  /// [attachments] are added with the event (EAS 16.x); their
  /// FileReferences are in [SyncAddResponse.attachmentFileReferences].
  Future<SyncResult> createCalendarEvent(
    String folderId,
    EasCalendarEvent event, {
    required String clientId,
    List<EasAttachmentAdd> attachments = const [],
  }) {
    return syncWithCommands(
      folderId,
      contentType: SyncContentType.calendar,
      commands: [
        SyncAddItem(
          clientId: clientId,
          applicationData: CalendarSerializer.serialize(
            event,
            protocolVersion: _httpClient.protocolVersion,
            addAttachments: attachments,
          ),
        ),
      ],
    );
  }

  /// Update a calendar event on the server; optionally add attachments or
  /// delete them by FileReference (EAS 16.x).
  Future<SyncResult> updateCalendarEvent(
    String folderId,
    String serverId,
    EasCalendarEvent event, {
    List<EasAttachmentAdd> addAttachments = const [],
    List<String> deleteAttachments = const [],
  }) {
    return syncWithCommands(
      folderId,
      contentType: SyncContentType.calendar,
      commands: [
        SyncChangeItem(
          serverId: serverId,
          applicationData: CalendarSerializer.serialize(
            event,
            protocolVersion: _httpClient.protocolVersion,
            addAttachments: addAttachments,
            deleteAttachments: deleteAttachments,
            isChange: true,
          ),
        ),
      ],
    );
  }

  /// Change a single occurrence of a recurring series (EAS 16.x): the
  /// occurrence is identified by [changes].exceptionStartTime (its
  /// original start time, sent as `airsyncbase:InstanceId`).
  Future<SyncResult> updateCalendarOccurrence(
    String folderId,
    String serverId,
    EasCalendarException changes,
  ) {
    return syncWithCommands(
      folderId,
      contentType: SyncContentType.calendar,
      commands: [
        SyncChangeItem(
          serverId: serverId,
          instanceId: changes.exceptionStartTime,
          applicationData: CalendarSerializer.serializeOccurrence(
            changes,
            protocolVersion: _httpClient.protocolVersion,
          ),
        ),
      ],
    );
  }

  /// Delete a single occurrence (original start [instanceId]) of a
  /// recurring series (EAS 16.x).
  Future<SyncResult> deleteCalendarOccurrence(
    String folderId,
    String serverId,
    DateTime instanceId,
  ) {
    return syncWithCommands(
      folderId,
      contentType: SyncContentType.calendar,
      commands: [SyncDeleteItem(serverId: serverId, instanceId: instanceId)],
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
          applicationData: ContactSerializer.serialize(
            contact,
            protocolVersion: _httpClient.protocolVersion,
          ),
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
          applicationData: TaskSerializer.serialize(
            task,
            protocolVersion: _httpClient.protocolVersion,
          ),
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

  /// Update a contact on the server.
  Future<SyncResult> updateContact(
    String folderId,
    String serverId,
    EasContact contact,
  ) => _changeItem(
    folderId,
    serverId,
    SyncContentType.contact,
    ContactSerializer.serialize(
      contact,
      protocolVersion: _httpClient.protocolVersion,
    ),
  );

  /// Update a task on the server.
  Future<SyncResult> updateTask(
    String folderId,
    String serverId,
    EasTask task,
  ) => _changeItem(
    folderId,
    serverId,
    SyncContentType.task,
    TaskSerializer.serialize(
      task,
      protocolVersion: _httpClient.protocolVersion,
    ),
  );

  /// Update a note on the server.
  Future<SyncResult> updateNote(
    String folderId,
    String serverId,
    EasNote note,
  ) => _changeItem(
    folderId,
    serverId,
    SyncContentType.note,
    NoteSerializer.serialize(note),
  );

  /// Create a draft email in the Drafts folder (EAS 16.x).
  ///
  /// The server-assigned ID is in [SyncResult.addResponses]; attachment
  /// FileReferences in [SyncAddResponse.attachmentFileReferences].
  Future<SyncResult> createDraft(
    String draftsFolderId,
    EasEmail draft, {
    required String clientId,
    List<EasAttachmentAdd> attachments = const [],
  }) {
    return syncWithCommands(
      draftsFolderId,
      contentType: SyncContentType.email,
      commands: [
        SyncAddItem(
          clientId: clientId,
          applicationData: EmailSerializer.serializeDraft(
            draft,
            addAttachments: attachments,
          ),
        ),
      ],
    );
  }

  /// Update a draft email (EAS 16.x): change fields, add attachments,
  /// delete attachments by FileReference, and optionally [send] it.
  Future<SyncResult> updateDraft(
    String draftsFolderId,
    String serverId,
    EasEmail draft, {
    List<EasAttachmentAdd> addAttachments = const [],
    List<String> deleteAttachments = const [],
    bool send = false,
  }) => syncWithCommands(
    draftsFolderId,
    contentType: SyncContentType.email,
    commands: [
      SyncChangeItem(
        serverId: serverId,
        applicationData: EmailSerializer.serializeDraft(
          draft,
          addAttachments: addAttachments,
          deleteAttachments: deleteAttachments,
        ),
        send: send,
      ),
    ],
  );

  Future<SyncResult> _changeItem(
    String folderId,
    String serverId,
    SyncContentType contentType,
    WbxmlElement applicationData,
  ) {
    return syncWithCommands(
      folderId,
      contentType: contentType,
      commands: [
        SyncChangeItem(serverId: serverId, applicationData: applicationData),
      ],
    );
  }

  // ─── Push / estimate ──────────────────────────────────────────────────────

  /// Ping — wait for changes in specified folders.
  ///
  /// [folders] — list of PingFolder with id and className.
  /// Use [PingCommand.fromIds] with [execute] for the simpler API that
  /// treats all folders as Email.
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
    final pingTimeout =
        Duration(seconds: heartbeatInterval) + _httpClient.pingTimeoutBuffer;
    return command.execute(_httpClient, timeout: pingTimeout);
  }

  /// Get an estimate of the number of items that will be synced for a folder.
  ///
  /// Requires an existing sync key (after at least one syncFolder call).
  Future<int> getItemEstimate(
    String folderId, {
    int? filterType,
    String? className,
    bool? conversationMode,
    int? maxItems,
  }) async {
    final state = _syncStates[folderId];
    final syncKey = state?.syncKey ?? '0';
    final command = GetItemEstimateCommand.single(
      collectionId: folderId,
      syncKey: syncKey,
      filterType: filterType,
      className: className,
      conversationMode: conversationMode,
      maxItems: maxItems,
    );
    final results = await command.execute(_httpClient);
    return results.firstOrNull?.estimate ?? 0;
  }

  /// Estimates for several collections, each with its own sync key,
  /// ConversationMode and up to two `Options`.
  Future<List<ItemEstimateResult>> getItemEstimates(
    List<ItemEstimateCollection> collections,
  ) => GetItemEstimateCommand.collections(collections).execute(_httpClient);

  // ─── Item operations ──────────────────────────────────────────────────────

  /// Fetch full email body.
  ///
  /// [options] gives full control (Schema, BodyPreference,
  /// BodyPartPreference, MIMESupport, RightsManagementSupport).
  Future<ItemOperationsResult> fetchEmailBody(
    String serverId,
    String collectionId, {
    int bodyType = 2,
    ItemFetchOptions? options,
    bool removeRightsManagementProtection = false,
    bool acceptMultiPart = false,
  }) async {
    final command = FetchEmailBodyCommand(
      serverId: serverId,
      collectionId: collectionId,
      bodyType: bodyType,
      options: options,
      removeRightsManagementProtection: removeRightsManagementProtection,
      acceptMultiPart: acceptMultiPart,
    );
    return command.execute(_httpClient);
  }

  /// Run several ItemOperations (Fetch / EmptyFolderContents / Move) in
  /// one request.
  Future<ItemOperationsResponse> itemOperations(
    List<ItemOperation> operations, {
    bool acceptMultiPart = false,
  }) => ItemOperationsCommand(
    operations,
    acceptMultiPart: acceptMultiPart,
  ).execute(_httpClient);

  /// Fetch attachment by file reference.
  ///
  /// [acceptMultiPart] requests a binary multipart response
  /// (no WBXML opaque wrapping).
  Future<Uint8List?> fetchAttachment(
    String fileReference, {
    bool acceptMultiPart = false,
    int? rangeStart,
    int? rangeEnd,
  }) async {
    final command = FetchAttachmentCommand(
      fileReference: fileReference,
      acceptMultiPart: acceptMultiPart,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
    final result = await command.execute(_httpClient);
    return result.data;
  }

  /// Fetch a Search result item by its LongId.
  Future<ItemOperationsResult> fetchByLongId(
    String longId, {
    int bodyType = 2,
    ItemFetchOptions? options,
    bool removeRightsManagementProtection = false,
  }) => FetchByLongIdCommand(
    longId: longId,
    bodyType: bodyType,
    options: options,
    removeRightsManagementProtection: removeRightsManagementProtection,
  ).execute(_httpClient);

  /// Document library (MS-ASDOC) is not supported in EAS 2.5.
  void _requireDocumentLibrary() {
    if (protocolVersionValue(_httpClient.protocolVersion) < 120) {
      throw UnsupportedError('Document library requires EAS 12.0 or later');
    }
  }

  /// Fetch a document library item (SharePoint / UNC) by LinkId
  /// (MS-ASDOC 3.1.4.3). Content is in [ItemOperationsResult.data]; use
  /// [rangeStart]/[rangeEnd] to download in chunks
  /// ([ItemOperationsResult.byteRange], [ItemOperationsResult.total]).
  Future<ItemOperationsResult> fetchDocument(
    String linkId, {
    String? userName,
    String? password,
    int? rangeStart,
    int? rangeEnd,
    bool acceptMultiPart = false,
  }) async {
    _requireDocumentLibrary();
    return FetchDocumentCommand(
      linkId: linkId,
      userName: userName,
      password: password,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      acceptMultiPart: acceptMultiPart,
    ).execute(_httpClient);
  }

  /// Fetch several document library items in one ItemOperations request
  /// (MS-ASDOC 3.1.4.2); results are in request order.
  Future<List<ItemOperationsResult>> fetchDocuments(
    List<String> linkIds, {
    String? userName,
    String? password,
    bool acceptMultiPart = false,
  }) async {
    _requireDocumentLibrary();
    final options = userName == null && password == null
        ? null
        : ItemFetchOptions(userName: userName, password: password);
    final response = await ItemOperationsCommand([
      for (final id in linkIds) ItemFetch.document(id, options: options),
    ], acceptMultiPart: acceptMultiPart).execute(_httpClient);
    return response.fetches;
  }

  /// Move a whole conversation to [dstFolderId] (ItemOperations Move).
  ///
  /// [moveAlways] also moves future messages of the conversation.
  Future<ConversationMoveResult> moveConversation({
    required Uint8List conversationId,
    required String dstFolderId,
    bool moveAlways = true,
  }) => MoveConversationCommand(
    conversationId: conversationId,
    dstFolderId: dstFolderId,
    moveAlways: moveAlways,
  ).execute(_httpClient);

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
    ItemFetchOptions? options,
    bool acceptMultiPart = false,
  }) async {
    final command = BatchFetchEmailBodiesCommand(
      items: items,
      bodyType: bodyType,
      options: options,
      acceptMultiPart: acceptMultiPart,
    );
    return command.execute(_httpClient);
  }

  // ─── Mail composition ─────────────────────────────────────────────────────

  /// Send an email.
  ///
  /// [clientId] — unique ID to prevent duplicates.
  /// [mimeContent] — full MIME content of the email.
  /// [accountId] — send-as account (EAS 14.1+, Settings UserInformation).
  Future<void> sendMail({
    required String clientId,
    required String mimeContent,
    bool saveInSentItems = true,
    String? templateId,
    String? accountId,
  }) async {
    final command = SendMailCommand(
      clientId: clientId,
      mimeContent: mimeContent,
      saveInSentItems: saveInSentItems,
      templateId: templateId,
      accountId: accountId,
    );
    await command.execute(_httpClient);
  }

  /// Reply to an email, including the original message body (server-side).
  ///
  /// Source: [serverId] + [collectionId] (optionally [instanceId] for a
  /// recurring meeting occurrence) or [longId] (Search result).
  Future<void> smartReply({
    required String clientId,
    String? serverId,
    String? collectionId,
    String? longId,
    DateTime? instanceId,
    required String mimeContent,
    bool saveInSentItems = true,
    bool replaceMime = false,
    String? templateId,
    String? accountId,
  }) async {
    final command = SmartReplyCommand(
      clientId: clientId,
      serverId: serverId,
      collectionId: collectionId,
      longId: longId,
      instanceId: instanceId,
      mimeContent: mimeContent,
      saveInSentItems: saveInSentItems,
      replaceMime: replaceMime,
      templateId: templateId,
      accountId: accountId,
    );
    await command.execute(_httpClient);
  }

  /// Forward an email, including the original message body (server-side).
  ///
  /// Source is specified as in [smartReply].
  Future<void> smartForward({
    required String clientId,
    String? serverId,
    String? collectionId,
    String? longId,
    DateTime? instanceId,
    required String mimeContent,
    bool saveInSentItems = true,
    bool replaceMime = false,
    String? templateId,
    String? accountId,
  }) async {
    final command = SmartForwardCommand(
      clientId: clientId,
      serverId: serverId,
      collectionId: collectionId,
      longId: longId,
      instanceId: instanceId,
      mimeContent: mimeContent,
      saveInSentItems: saveInSentItems,
      replaceMime: replaceMime,
      templateId: templateId,
      accountId: accountId,
    );
    await command.execute(_httpClient);
  }

  /// Forward a calendar item to [forwardees] with an optional [body]
  /// (EAS 16.0+, MS-ASCMD 2.2.3.169 — no MIME content).
  Future<void> smartForwardMeeting({
    required String clientId,
    String? serverId,
    String? collectionId,
    String? longId,
    DateTime? instanceId,
    List<Forwardee> forwardees = const [],
    String? body,
    int bodyType = 1,
    String? accountId,
  }) async {
    final command = SmartForwardCommand.meeting(
      clientId: clientId,
      serverId: serverId,
      collectionId: collectionId,
      longId: longId,
      instanceId: instanceId,
      forwardees: forwardees,
      body: body,
      bodyType: bodyType,
      accountId: accountId,
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

  /// Move items between arbitrary folders in one request.
  Future<List<MoveItemResult>> moveItemsBatch(List<MoveItem> moves) =>
      MoveItemsCommand.items(moves).execute(_httpClient);

  /// Server-side mailbox search.
  Future<SearchResult> search(
    String query, {
    String? collectionId,
    String? className,
    DateTime? receivedAfter,
    DateTime? receivedBefore,
    String? conversationId,
    int rangeStart = 0,
    int rangeEnd = 49,
    bool deepTraversal = true,
    bool rebuildResults = false,
    int bodyType = 2,
    int bodyTruncationSize = 512,
    List<EasBodyPreference>? bodyPreferences,
    EasBodyPreference? bodyPartPreference,
    int? mimeSupport,
    bool? rightsManagementSupport,
  }) async {
    final command = SearchCommand(
      query: query,
      collectionId: collectionId,
      className: className,
      receivedAfter: receivedAfter,
      receivedBefore: receivedBefore,
      conversationId: conversationId,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      deepTraversal: deepTraversal,
      rebuildResults: rebuildResults,
      bodyType: bodyType,
      bodyTruncationSize: bodyTruncationSize,
      bodyPreferences: bodyPreferences,
      bodyPartPreference: bodyPartPreference,
      mimeSupport: mimeSupport,
      rightsManagementSupport: rightsManagementSupport,
    );
    return command.execute(_httpClient);
  }

  /// Search the Global Address List (GAL).
  Future<GalSearchResult> searchGal(
    String query, {
    int rangeStart = 0,
    int rangeEnd = 99,
    bool picture = false,
    int? pictureMaxSize,
    int? maxPictures,
    String? userName,
    String? password,
  }) async {
    final command = GalSearchCommand(
      query: query,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      picture: picture,
      pictureMaxSize: pictureMaxSize,
      maxPictures: maxPictures,
      userName: userName,
      password: password,
    );
    return command.execute(_httpClient);
  }

  /// List a document library location (SharePoint / UNC) or get a
  /// document's metadata by LinkId (MS-ASDOC 3.1.4.1). For a folder the
  /// first item is the folder itself.
  Future<DocumentLibrarySearchResult> searchDocumentLibrary(
    String linkId, {
    int rangeStart = 0,
    int rangeEnd = 999,
    String? userName,
    String? password,
  }) async {
    _requireDocumentLibrary();
    return DocumentLibrarySearchCommand(
      linkId: linkId,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      userName: userName,
      password: password,
    ).execute(_httpClient);
  }

  /// Find command (EAS 16.1) — GAL search with picture support.
  Future<FindResult> find(
    String query, {
    int rangeStart = 0,
    int rangeEnd = 99,
    bool requestPicture = false,
    int maxPictureSize = 0,
    int? maxPictures,
  }) async {
    final command = FindCommand(
      query: query,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      requestPicture: requestPicture,
      maxPictureSize: maxPictureSize,
      maxPictures: maxPictures,
    );
    return command.execute(_httpClient);
  }

  /// Find command (EAS 16.1) — mailbox search (KQL free text).
  Future<FindResult> findInMailbox(
    String query, {
    String? className,
    String? collectionId,
    int rangeStart = 0,
    int rangeEnd = 99,
    bool deepTraversal = false,
    bool requestPicture = false,
    int maxPictureSize = 0,
    int? maxPictures,
  }) => FindCommand.mailbox(
    query: query,
    className: className,
    collectionId: collectionId,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    deepTraversal: deepTraversal,
    requestPicture: requestPicture,
    maxPictureSize: maxPictureSize,
    maxPictures: maxPictures,
  ).execute(_httpClient);

  // ─── Calendar ─────────────────────────────────────────────────────────────

  /// Respond to a meeting request (accept, tentative, or decline).
  ///
  /// Identify the request by [requestId] + [collectionId] or by [longId].
  /// [instanceId] targets one occurrence of a recurring meeting;
  /// [sendResponse] (EAS 16.0+) sends a reply / proposes a new time.
  Future<List<MeetingResponseResult>> respondToMeeting({
    String? requestId,
    String? collectionId,
    String? longId,
    required MeetingResponseStatus response,
    DateTime? instanceId,
    MeetingSendResponse? sendResponse,
  }) async {
    final command = MeetingResponseCommand.single(
      requestId: requestId,
      collectionId: collectionId,
      longId: longId,
      response: response,
      instanceId: instanceId,
      sendResponse: sendResponse,
    );
    return command.execute(_httpClient);
  }

  /// Respond to several meeting requests in one request.
  Future<List<MeetingResponseResult>> respondToMeetings(
    List<MeetingRequestEntry> requests,
  ) => MeetingResponseCommand(requests: requests).execute(_httpClient);

  // ─── Settings ─────────────────────────────────────────────────────────────

  /// Get current server settings: OOF state and user information.
  ///
  /// [oofBodyType] — requested OOF reply format ('Text' or 'HTML').
  Future<EasSettings> getSettings({String oofBodyType = 'Text'}) async {
    return SettingsGetCommand(oofBodyType: oofBodyType).execute(_httpClient);
  }

  /// Settings with any combination of sub-commands; returns every
  /// sub-command status.
  Future<SettingsResponse> settings(SettingsCommand command) =>
      command.execute(_httpClient);

  /// Update Out-of-Office settings.
  Future<void> setOutOfOffice(EasOofSettings oof) async {
    final status = await SettingsSetOofCommand(oof: oof).execute(_httpClient);
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
    String? model,
    String? imei,
    String? friendlyName,
    String? os,
    String? osLanguage,
    String? phoneNumber,
    String? userAgent,
    bool? enableOutboundSms,
    String? mobileOperator,
  }) async {
    final status = await SettingsSendDeviceInfoCommand(
      model: model,
      imei: imei,
      friendlyName: friendlyName,
      os: os,
      osLanguage: osLanguage,
      phoneNumber: phoneNumber,
      userAgent: userAgent,
      enableOutboundSms: enableOutboundSms,
      mobileOperator: mobileOperator,
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

  /// Resolve recipients (up to 100) to GAL entries / contacts.
  ///
  /// Optionally requests S/MIME certificates ([certificateRetrieval],
  /// [maxCertificates]), free/busy data ([availabilityStartTime] /
  /// [availabilityEndTime], EAS 14.0+) and contact photos ([picture],
  /// EAS 14.1+).
  Future<List<ResolveRecipientsResponse>> resolveRecipients(
    List<String> recipients, {
    int? maxAmbiguousRecipients,
    DateTime? availabilityStartTime,
    DateTime? availabilityEndTime,
    CertificateRetrieval? certificateRetrieval,
    int? maxCertificates,
    bool picture = false,
    int? pictureMaxSize,
    int? maxPictures,
  }) => ResolveRecipientsCommand(
    recipients: recipients,
    maxAmbiguousRecipients: maxAmbiguousRecipients,
    availabilityStartTime: availabilityStartTime,
    availabilityEndTime: availabilityEndTime,
    certificateRetrieval: certificateRetrieval,
    maxCertificates: maxCertificates,
    picture: picture,
    pictureMaxSize: pictureMaxSize,
    maxPictures: maxPictures,
  ).execute(_httpClient);

  // ─── S/MIME ───────────────────────────────────────────────────────────────

  /// Validate S/MIME certificates (DER-encoded).
  Future<List<CertValidationResult>> validateCertificates(
    List<Uint8List> certificates, {
    bool? checkCRL = true,
    List<Uint8List> certificateChain = const [],
  }) => ValidateCertCommand(
    certificates: certificates,
    checkCRL: checkCRL,
    certificateChain: certificateChain,
  ).execute(_httpClient);

  // ─── Generic ──────────────────────────────────────────────────────────────

  /// Execute any [EasCommand] with this client's transport (policy key,
  /// protocol version, credentials). Gives access to every request option
  /// of the command classes, e.g. [ItemOperationsCommand] batches,
  /// [StoreSearchCommand] queries or [SettingsCommand] combinations.
  Future<T> execute<T>(EasCommand<T> command, {Duration? timeout}) =>
      command.execute(_httpClient, timeout: timeout);

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
