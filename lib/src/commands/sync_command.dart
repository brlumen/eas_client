/// Sync command — synchronizes folder contents.
///
/// Implements the Sync state machine:
/// - SyncKey=0 → get initial SyncKey (no data returned)
/// - SyncKey=N → get changes + new SyncKey
/// - Status=3 → invalid SyncKey, reset to 0
/// - Status=12 → folder hierarchy changed, FolderSync required
///
/// [MultiSyncCommand] synchronizes several collections in one request
/// (optionally as a Partial or empty request, with Wait/HeartbeatInterval
/// long-polling); [SyncCommand] is the single-collection convenience
/// wrapper.
///
/// Reference: MS-ASCMD section 2.2.1.21
library;

import '../models/eas_body.dart';
import '../models/eas_calendar_event.dart';
import '../models/eas_contact.dart';
import '../models/eas_email.dart';
import '../models/eas_note.dart';
import '../models/eas_task.dart';
import '../models/wbxml_helpers.dart';
import '../transport/eas_http_client.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Content type for Sync operations.
enum SyncContentType {
  /// Email messages (default).
  email,

  /// Calendar events (appointments and meetings).
  calendar,

  /// Tasks (to-do items).
  task,

  /// Contacts (address book entries).
  contact,

  /// Notes (sticky notes / IPM.StickyNote).
  note,

  /// SMS messages (EAS 14.0+, parsed as [EasEmail]).
  sms;

  /// Map an AirSync `Class` value to a content type (email by default).
  static SyncContentType fromClassName(String? className) =>
      switch (className) {
        'Calendar' => calendar,
        'Tasks' => task,
        'Contacts' => contact,
        'Notes' => note,
        'SMS' => sms,
        _ => email,
      };

  /// AirSync `Class` value of this content type.
  String get className => switch (this) {
    email => 'Email',
    calendar => 'Calendar',
    task => 'Tasks',
    contact => 'Contacts',
    note => 'Notes',
    sms => 'SMS',
  };
}

/// Sync status codes (MS-ASCMD 2.2.3.177.17).
enum SyncStatus {
  success(1, 'Success'),
  invalidSyncKey(3, 'Invalid synchronization key; resync from SyncKey 0'),
  protocolError(4, 'Protocol error in the Sync request'),
  serverError(5, 'Server error; retry'),
  conversionError(6, 'Error in client/server conversion (malformed item)'),
  conflict(7, 'Conflict: server change overwrote the client change'),
  objectNotFound(8, 'Object not found'),
  cannotComplete(9, 'Sync cannot be completed (mailbox may be full)'),
  folderHierarchyChanged(12, 'Folder hierarchy changed; run FolderSync'),
  incompleteRequest(13, 'Empty/partial request without cache; resend full'),
  invalidWaitOrHeartbeat(14, 'Wait/HeartbeatInterval outside server limits'),
  tooManyCollections(15, 'Too many collections in the Sync request'),
  retry(16, 'Retriable server error; resend the request');

  final int code;
  final String description;
  const SyncStatus(this.code, this.description);

  /// Status for [code], or `null` if not a Sync status code.
  static SyncStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }

  /// Whether the client should resend the same request.
  bool get isRetriable => this == serverError || this == retry;
}

/// Server-to-client delete (`Commands/Delete`).
class SyncDeletedItem {
  final String serverId;

  /// Item class when it differs from the collection class (e.g. `SMS`).
  final String? className;

  const SyncDeletedItem({required this.serverId, this.className});
}

/// Result of a Sync command for one collection.
class SyncResult {
  final int status;
  final String syncKey;
  final String collectionId;

  /// Collection class returned by the server (EAS ≤12.1 only).
  final String? className;

  // Email
  final List<EasEmail> addedEmails;
  final List<EasEmail> changedEmails;

  // SMS (EAS 14.0+, class `SMS`)
  final List<EasEmail> addedSms;
  final List<EasEmail> changedSms;

  // Calendar
  final List<EasCalendarEvent> addedCalendarEvents;
  final List<EasCalendarEvent> changedCalendarEvents;

  // Tasks
  final List<EasTask> addedTasks;
  final List<EasTask> changedTasks;

  // Contacts
  final List<EasContact> addedContacts;
  final List<EasContact> changedContacts;

  // Notes
  final List<EasNote> addedNotes;
  final List<EasNote> changedNotes;

  /// IDs of deleted items (all types).
  final List<String> deletedIds;

  /// Deleted items with their class.
  final List<SyncDeletedItem> deletedItems;

  /// IDs of items removed from the sync window (e.g. aged out of the
  /// FilterType range) but not deleted on the server (`SoftDelete`).
  final List<String> softDeletedIds;

  final bool moreAvailable;

  // ─── Client command responses ──────────────────────────────────────────

  /// Server responses to client Add operations.
  final List<SyncAddResponse> addResponses;

  /// Server responses to client Change operations.
  final List<SyncChangeResponse> changeResponses;

  /// Server responses to client Delete operations.
  final List<SyncDeleteResponse> deleteResponses;

  /// Server responses to client Fetch operations.
  final List<SyncFetchResponse> fetchResponses;

  const SyncResult({
    required this.status,
    required this.syncKey,
    required this.collectionId,
    this.className,
    this.addedEmails = const [],
    this.changedEmails = const [],
    this.addedSms = const [],
    this.changedSms = const [],
    this.addedCalendarEvents = const [],
    this.changedCalendarEvents = const [],
    this.addedTasks = const [],
    this.changedTasks = const [],
    this.addedContacts = const [],
    this.changedContacts = const [],
    this.addedNotes = const [],
    this.changedNotes = const [],
    this.deletedIds = const [],
    this.deletedItems = const [],
    this.softDeletedIds = const [],
    this.moreAvailable = false,
    this.addResponses = const [],
    this.changeResponses = const [],
    this.deleteResponses = const [],
    this.fetchResponses = const [],
  });

  /// Typed [status], or `null` for an unknown code.
  SyncStatus? get syncStatus => SyncStatus.fromCode(status);

  /// Whether the sync key is invalid and needs reset.
  bool get needsReset => status == 3;

  /// Whether the folder hierarchy changed and FolderSync is required
  /// (Status 12).
  bool get needsFolderSync => status == 12;
}

/// Result of a (possibly multi-collection) Sync request.
class MultiSyncResult {
  /// Top-level Sync status (1 if the server did not send one).
  final int status;

  /// Per-collection results, in server order.
  final List<SyncResult> collections;

  /// Whether the server answered with HTTP 200 and an empty body
  /// (no changes in any requested collection).
  final bool isEmpty;

  /// Server limit for Wait/HeartbeatInterval (Status 14), or the maximum
  /// number of collections (Status 15).
  final int? limit;

  const MultiSyncResult({
    this.status = 1,
    this.collections = const [],
    this.isEmpty = false,
    this.limit,
  });

  /// Result for HTTP 200 with an empty body.
  static const noChanges = MultiSyncResult(isEmpty: true);

  /// Typed top-level [status], or `null` for an unknown code.
  SyncStatus? get syncStatus => SyncStatus.fromCode(status);

  /// Result for [collectionId], or `null` if not present in the response.
  SyncResult? collection(String collectionId) {
    for (final c in collections) {
      if (c.collectionId == collectionId) return c;
    }
    return null;
  }

  /// Whether FolderSync is required (Status 12, top-level or per collection).
  bool get needsFolderSync =>
      status == 12 || collections.any((c) => c.needsFolderSync);

  /// Whether the server rejected an empty/partial request and needs the
  /// full request to be resent (Status 13).
  bool get needsFullRequest => status == 13;

  /// Whether Wait/HeartbeatInterval was out of range (Status 14, see
  /// [limit]).
  bool get invalidWaitOrHeartbeat => status == 14;
}

/// Time-based filter for Sync (MS-ASCMD 2.2.3.68.2).
///
/// Values 1-7 apply to Email and Calendar (1-3 Email only);
/// [incompleteTasks] applies to Tasks.
enum SyncFilterType {
  /// No filter — sync all items.
  noFilter(0),
  oneDay(1),
  threeDays(2),
  oneWeek(3),
  twoWeeks(4),
  oneMonth(5),
  threeMonths(6),
  sixMonths(7),

  /// Incomplete tasks only.
  incompleteTasks(8);

  final int value;
  const SyncFilterType(this.value);
}

/// Options block of a Sync collection (MS-ASCMD 2.2.3.125.6).
///
/// Up to two per collection: one for the folder's default class and one
/// for `SMS` (distinguished by [className]).
class SyncOptions {
  /// Class these options apply to (EAS 14.0+). Required when two Options
  /// are sent (e.g. `Email` and `SMS`).
  final String? className;

  /// Time window filter.
  final SyncFilterType? filterType;

  /// Body preferences (EAS 12.0+), one per body type.
  final List<EasBodyPreference> bodyPreferences;

  /// Body part preferences (EAS 14.1+, conversation body parts).
  final List<EasBodyPreference> bodyPartPreferences;

  /// Conflict resolution: 0 = client wins, 1 = server wins (default).
  final int? conflict;

  /// MIME support: 0=never, 1=S/MIME only, 2=all.
  final int? mimeSupport;

  /// MIME truncation code (0-8, MS-ASCMD 2.2.3.111).
  final int? mimeTruncation;

  /// Body truncation code (EAS 2.5 `Truncation`, 0-9).
  final int? truncation;

  /// Maximum number of recipient-information-cache items (RI folder).
  final int? maxItems;

  /// Request IRM-protected content decrypted with its license
  /// (EAS 14.1+, `rm:RightsManagementSupport`).
  final bool? rightsManagementSupport;

  const SyncOptions({
    this.className,
    this.filterType,
    this.bodyPreferences = const [],
    this.bodyPartPreferences = const [],
    this.conflict,
    this.mimeSupport,
    this.mimeTruncation,
    this.truncation,
    this.maxItems,
    this.rightsManagementSupport,
  });

  /// `Options` element for protocol version [v] (numeric, e.g. 161).
  WbxmlElement toElement(int v) {
    final c = <WbxmlElement>[];
    if (v >= 140) c.addText('AirSync', 'Class', className);
    if (filterType case final f? when f != SyncFilterType.noFilter) {
      c.add(textEl('AirSync', 'FilterType', '${f.value}'));
    }
    if (v >= 120) {
      c.addAll(
        bodyPreferences.map((p) => _forVersion(p, v).toBodyPreference()),
      );
    }
    if (v >= 141) {
      c.addAll(bodyPartPreferences.map((p) => p.toBodyPartPreference()));
    }
    c
      ..addText('AirSync', 'Conflict', conflict)
      ..addText('AirSync', 'MIMESupport', mimeSupport)
      ..addText('AirSync', 'MIMETruncation', mimeTruncation);
    if (v < 120) c.addText('AirSync', 'Truncation', truncation);
    if (v >= 120) c.addText('AirSync', 'MaxItems', maxItems);
    if (v >= 141) {
      c.addText(
        'RightsManagement',
        'RightsManagementSupport',
        rightsManagementSupport,
      );
    }
    return containerEl('AirSync', 'Options', c);
  }

  /// `airsyncbase:Preview` is supported only in EAS 14.0+.
  static EasBodyPreference _forVersion(EasBodyPreference p, int v) =>
      v >= 140 || p.preview == null
      ? p
      : EasBodyPreference(
          type: p.type,
          truncationSize: p.truncationSize,
          allOrNone: p.allOrNone,
        );
}

// ─── Client-to-Server Sync Commands ─────────────────────────────────────────

/// A client-to-server operation for the Sync Commands element.
sealed class SyncClientCommand {
  const SyncClientCommand();
}

/// Add a new item to the server.
class SyncAddItem extends SyncClientCommand {
  /// Unique client-assigned ID (used for dedup).
  final String clientId;

  /// WBXML ApplicationData element with the item data.
  final WbxmlElement applicationData;

  /// Item class when it differs from the collection default (e.g. `SMS`
  /// in the Inbox; EAS 14.0+).
  final String? className;

  /// Send the item right after adding it (EAS 16.x drafts,
  /// `email2:Send`).
  final bool send;

  const SyncAddItem({
    required this.clientId,
    required this.applicationData,
    this.className,
    this.send = false,
  });
}

/// Change an existing item on the server.
class SyncChangeItem extends SyncClientCommand {
  /// Server-assigned ID of the item to change.
  final String serverId;

  /// WBXML ApplicationData element with the changed fields.
  final WbxmlElement applicationData;

  /// Original start time of the occurrence to change; changes a single
  /// instance of a recurring calendar series (EAS 16.x
  /// `airsyncbase:InstanceId`).
  final DateTime? instanceId;

  /// Send the draft after applying the change (EAS 16.x `email2:Send`).
  final bool send;

  const SyncChangeItem({
    required this.serverId,
    required this.applicationData,
    this.instanceId,
    this.send = false,
  });
}

/// Delete an item from the server.
class SyncDeleteItem extends SyncClientCommand {
  /// Server-assigned ID of the item to delete.
  final String serverId;

  /// Original start time of the occurrence to delete; deletes a single
  /// instance of a recurring calendar series (EAS 16.x).
  final DateTime? instanceId;

  const SyncDeleteItem({required this.serverId, this.instanceId});
}

/// Fetch a specific item from the server (returned in
/// [SyncResult.fetchResponses]).
class SyncFetchItem extends SyncClientCommand {
  /// Server-assigned ID of the item to fetch.
  final String serverId;

  const SyncFetchItem({required this.serverId});
}

// ─── Sync Response models ───────────────────────────────────────────────────

/// Server response to a client Add operation.
class SyncAddResponse {
  final String clientId;
  final String? serverId;
  final int status;

  /// Item class if it differs from the collection class.
  final String? className;

  /// Attachment ClientId → server FileReference for attachments added
  /// with the item (EAS 16.x).
  final Map<String, String> attachmentFileReferences;

  /// Properties returned by the server (EAS 16.x, e.g. calendar `UID`),
  /// parsed as the collection's model type.
  final Object? item;

  bool get isSuccess => status == 1;

  SyncStatus? get syncStatus => SyncStatus.fromCode(status);

  const SyncAddResponse({
    required this.clientId,
    this.serverId,
    required this.status,
    this.className,
    this.attachmentFileReferences = const {},
    this.item,
  });
}

/// Server response to a client Change operation.
class SyncChangeResponse {
  final String serverId;
  final int status;

  /// Occurrence the change applied to (EAS 16.x).
  final DateTime? instanceId;

  /// Item class if it differs from the collection class.
  final String? className;

  /// Attachment ClientId → server FileReference for attachments added
  /// by the change (EAS 16.x).
  final Map<String, String> attachmentFileReferences;

  /// Properties returned by the server (EAS 16.x).
  final Object? item;

  bool get isSuccess => status == 1;

  /// Whether the server's version won a conflict (Status 7).
  bool get isConflict => status == 7;

  SyncStatus? get syncStatus => SyncStatus.fromCode(status);

  const SyncChangeResponse({
    required this.serverId,
    required this.status,
    this.instanceId,
    this.className,
    this.attachmentFileReferences = const {},
    this.item,
  });
}

/// Server response to a client Delete operation.
class SyncDeleteResponse {
  final String serverId;
  final int status;

  /// Occurrence the delete applied to (EAS 16.x).
  final DateTime? instanceId;

  bool get isSuccess => status == 1;

  SyncStatus? get syncStatus => SyncStatus.fromCode(status);

  const SyncDeleteResponse({
    required this.serverId,
    required this.status,
    this.instanceId,
  });
}

/// Server response to a client Fetch operation.
class SyncFetchResponse {
  final String serverId;
  final int status;

  /// Parsed item ([EasEmail], [EasCalendarEvent], [EasTask], [EasContact]
  /// or [EasNote] depending on the collection content type), or `null`
  /// if the fetch failed.
  final Object? item;

  bool get isSuccess => status == 1;

  SyncStatus? get syncStatus => SyncStatus.fromCode(status);

  const SyncFetchResponse({
    required this.serverId,
    required this.status,
    this.item,
  });
}

// ─── Request ────────────────────────────────────────────────────────────────

/// Per-collection parameters of a Sync request.
class SyncCollection {
  final String syncKey;
  final String collectionId;
  final int windowSize;
  final int bodyType;
  final int? bodyTruncationSize;
  final SyncContentType contentType;

  /// Time-based filter (MS-ASCMD). Only for Email, Calendar and Tasks.
  final SyncFilterType? filterType;

  /// Client-to-server operations (Add/Change/Delete/Fetch).
  final List<SyncClientCommand> clientCommands;

  /// Conflict resolution: 0 = client wins, 1 = server wins (default).
  final int? conflict;

  /// MIME support: 0=never, 1=S/MIME only, 2=all.
  final int? mimeSupport;

  /// MIME truncation code.
  final int? mimeTruncation;

  /// Content class for the collection ('Email', 'Calendar', 'Tasks',
  /// 'Contacts', 'Notes', 'SMS'). Sent as a child of `Collection` for
  /// EAS ≤12.1 and as a child of `Options` for EAS 14.0+.
  final String? className;

  /// Full Options blocks (up to two: default class and `SMS`). When set,
  /// replaces the Options built from [bodyType], [bodyTruncationSize],
  /// [filterType], [conflict], [mimeSupport], [mimeTruncation] and
  /// [className].
  final List<SyncOptions>? options;

  /// Ghosting: properties managed by the client, as `Namespace:Tag`
  /// (e.g. `Contacts:FirstName`). Sent only with SyncKey 0.
  final List<String>? supported;

  /// Move deleted items to Deleted Items (default true).
  final bool deletesAsMoves;

  /// Request server changes; defaults to true unless [clientCommands]
  /// are sent.
  final bool? getChanges;

  /// Conversation mode (EAS 14.0+, email only).
  final bool? conversationMode;

  /// Protocol version used for version-dependent elements.
  final String protocolVersion;

  const SyncCollection({
    this.syncKey = '0',
    required this.collectionId,
    this.windowSize = 50,
    this.bodyType = 2, // HTML
    this.bodyTruncationSize,
    this.contentType = SyncContentType.email,
    this.filterType,
    this.clientCommands = const [],
    this.conflict,
    this.mimeSupport,
    this.mimeTruncation,
    this.className,
    this.options,
    this.supported,
    this.deletesAsMoves = true,
    this.getChanges,
    this.conversationMode,
    this.protocolVersion = '16.1',
  });

  /// Copy with a different [syncKey] (and optionally [protocolVersion]).
  SyncCollection withSyncKey(String syncKey, {String? protocolVersion}) =>
      SyncCollection(
        syncKey: syncKey,
        collectionId: collectionId,
        windowSize: windowSize,
        bodyType: bodyType,
        bodyTruncationSize: bodyTruncationSize,
        contentType: contentType,
        filterType: filterType,
        clientCommands: clientCommands,
        conflict: conflict,
        mimeSupport: mimeSupport,
        mimeTruncation: mimeTruncation,
        className: className,
        options: options,
        supported: supported,
        deletesAsMoves: deletesAsMoves,
        getChanges: getChanges,
        conversationMode: conversationMode,
        protocolVersion: protocolVersion ?? this.protocolVersion,
      );

  List<SyncOptions> get _effectiveOptions =>
      options ??
      [
        SyncOptions(
          className: className,
          filterType: filterType,
          bodyPreferences: [
            EasBodyPreference(
              type: bodyType,
              truncationSize: bodyTruncationSize,
            ),
          ],
          conflict: conflict,
          mimeSupport: mimeSupport,
          mimeTruncation: mimeTruncation,
        ),
      ];

  WbxmlElement toElement() {
    final v = protocolVersionValue(protocolVersion);
    final children = <WbxmlElement>[
      _airSync('SyncKey', syncKey),
      _airSync('CollectionId', collectionId),
    ];

    if (syncKey == '0') {
      if (supported case final props? when props.isNotEmpty) {
        children.add(
          _airSyncParent('Supported', [
            for (final p in props)
              emptyEl(p.split(':').first, p.split(':').last),
          ]),
        );
      }
    } else {
      // EAS ≤12.1: Class is a child of Collection (MS-ASCMD 2.2.3.27.6).
      if (v < 140) children.addText('AirSync', 'Class', className);

      children
        ..add(_airSync('DeletesAsMoves', deletesAsMoves ? '1' : '0'))
        ..add(
          _airSync(
            'GetChanges',
            (getChanges ?? clientCommands.isEmpty) ? '1' : '0',
          ),
        )
        ..add(_airSync('WindowSize', windowSize.toString()));
      if (v >= 140) {
        children.addText('AirSync', 'ConversationMode', conversationMode);
      }
      children.addAll(_effectiveOptions.map((o) => o.toElement(v)));

      // Client-to-server Commands
      if (clientCommands.isNotEmpty) {
        children.add(
          _airSyncParent(
            'Commands',
            clientCommands.map(_buildClientCommand).toList(),
          ),
        );
      }
    }

    return _airSyncParent('Collection', children);
  }

  WbxmlElement _buildClientCommand(SyncClientCommand cmd) {
    final v16 = protocolVersionValue(protocolVersion) >= 160;
    WbxmlElement instance(DateTime id) =>
        textEl('AirSyncBase', 'InstanceId', compactDateTime(id));
    return switch (cmd) {
      SyncAddItem(
        :final clientId,
        :final applicationData,
        :final className,
        :final send,
      ) =>
        _airSyncParent('Add', [
          if (className != null) _airSync('Class', className),
          _airSync('ClientId', clientId),
          applicationData,
          if (send && v16) emptyEl('Email2', 'Send'),
        ]),
      SyncChangeItem(
        :final serverId,
        :final applicationData,
        :final instanceId,
        :final send,
      ) =>
        _airSyncParent('Change', [
          _airSync('ServerId', serverId),
          if (instanceId != null && v16) instance(instanceId),
          applicationData,
          if (send && v16) emptyEl('Email2', 'Send'),
        ]),
      SyncDeleteItem(:final serverId, :final instanceId) =>
        _airSyncParent('Delete', [
          _airSync('ServerId', serverId),
          if (instanceId != null && v16) instance(instanceId),
        ]),
      SyncFetchItem(:final serverId) => _airSyncParent('Fetch', [
        _airSync('ServerId', serverId),
      ]),
    };
  }
}

WbxmlElement _airSync(String tag, String text) => textEl('AirSync', tag, text);

WbxmlElement _airSyncParent(String tag, List<WbxmlElement> children) =>
    containerEl('AirSync', tag, children);

int _status(WbxmlElement el) => el.integer('AirSync', 'Status') ?? 0;

// ─── Commands ───────────────────────────────────────────────────────────────

/// Sync of one or more collections in a single request.
///
/// - [partial]: sends `<Partial/>` — the server merges [collections] with
///   the collections cached from the previous request.
/// - [emptyRequest]: sends an empty body so the server reuses the cached
///   previous request. If the server rejects it (Status 13) or answers
///   with an HTTP error, the full request built from [collections] is sent.
/// - [wait] (minutes, 1-59) / [heartbeatInterval] (seconds, 60-3540):
///   long-poll until changes arrive (mutually exclusive). Pass a matching
///   `timeout` to [execute].
/// - [windowSize]: overall item limit across collections (EAS 14.0+).
///
/// HTTP 200 with an empty body is returned as [MultiSyncResult.noChanges].
class MultiSyncCommand extends EasCommand<MultiSyncResult> {
  final List<SyncCollection> collections;
  final bool partial;
  final bool emptyRequest;
  final int? wait;
  final int? heartbeatInterval;
  final int? windowSize;

  MultiSyncCommand({
    required this.collections,
    this.partial = false,
    this.emptyRequest = false,
    this.wait,
    this.heartbeatInterval,
    this.windowSize,
  }) : assert(
         wait == null || heartbeatInterval == null,
         'Wait and HeartbeatInterval are mutually exclusive',
       );

  @override
  String get commandName => 'Sync';

  @override
  WbxmlDocument buildRequest() {
    final children = <WbxmlElement>[
      if (collections.isNotEmpty || !partial)
        _airSyncParent(
          'Collections',
          collections.map((c) => c.toElement()).toList(),
        ),
    ];
    children
      ..addText('AirSync', 'Wait', wait)
      ..addText('AirSync', 'HeartbeatInterval', heartbeatInterval)
      ..addText('AirSync', 'WindowSize', windowSize);
    if (partial) children.add(emptyEl('AirSync', 'Partial'));
    return WbxmlDocument(root: _airSyncParent('Sync', children));
  }

  @override
  Future<MultiSyncResult> execute(
    EasHttpClient client, {
    Duration? timeout,
  }) async {
    if (emptyRequest) {
      final response = await client.sendCommand(
        commandName,
        null,
        timeout: timeout,
      );
      if (response.isSuccess) {
        if (response.body.isEmpty) return MultiSyncResult.noChanges;
        final result = parseHttpResponse(response);
        if (!result.needsFullRequest) return result;
      }
      // Fall through: full request (also maps HTTP errors uniformly).
    }
    try {
      return await super.execute(client, timeout: timeout);
    } on EasCommandException catch (e) {
      // HTTP 200 with an empty body — no changes (MS-ASCMD 2.2.1.21).
      if (e.statusCode == 200 && e.easStatus == null) {
        return MultiSyncResult.noChanges;
      }
      rethrow;
    }
  }

  @override
  MultiSyncResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final results =
        root
            .findChild('AirSync', 'Collections')
            ?.findChildren('AirSync', 'Collection')
            .map(_parseCollection)
            .toList() ??
        const <SyncResult>[];
    return MultiSyncResult(
      status: root.integer('AirSync', 'Status') ?? 1,
      collections: results,
      limit: root.integer('AirSync', 'Limit'),
    );
  }

  SyncCollection? _request(String collectionId) {
    for (final c in collections) {
      if (c.collectionId == collectionId) return c;
    }
    return null;
  }

  SyncResult _parseCollection(WbxmlElement collection) {
    final collectionId =
        collection.str('AirSync', 'CollectionId') ??
        (collections.length == 1 ? collections.first.collectionId : '');
    final request = _request(collectionId);
    final collectionClass = collection.str('AirSync', 'Class');
    final type =
        request?.contentType ?? SyncContentType.fromClassName(collectionClass);

    final responses = collection.findChild('AirSync', 'Responses');
    final commands = collection.findChild('AirSync', 'Commands');

    List<WbxmlElement> responsesOf(String tag) =>
        responses?.findChildren('AirSync', tag) ?? const [];
    List<WbxmlElement> commandsOf(String tag) =>
        commands?.findChildren('AirSync', tag) ?? const [];
    SyncContentType typeOf(WbxmlElement e) {
      final cls = e.str('AirSync', 'Class');
      return cls == null ? type : SyncContentType.fromClassName(cls);
    }

    Object? itemOf(WbxmlElement e) =>
        e.findChild('AirSync', 'ApplicationData') == null
        ? null
        : _parseItem(typeOf(e), e);

    final added = [for (final e in commandsOf('Add')) _typed(typeOf(e), e)];
    final changed = [
      for (final e in commandsOf('Change')) _typed(typeOf(e), e),
    ];
    List<T> pick<T>(List<(SyncContentType, Object)> items, SyncContentType t) =>
        items.where((e) => e.$1 == t).map((e) => e.$2).whereType<T>().toList();

    final deletes = [
      for (final e in commandsOf('Delete'))
        SyncDeletedItem(
          serverId: e.str('AirSync', 'ServerId') ?? '',
          className: e.str('AirSync', 'Class'),
        ),
    ].where((d) => d.serverId.isNotEmpty).toList();

    return SyncResult(
      status: _status(collection),
      syncKey: collection.str('AirSync', 'SyncKey') ?? request?.syncKey ?? '0',
      collectionId: collectionId,
      className: collectionClass,
      addedEmails: pick<EasEmail>(added, SyncContentType.email),
      changedEmails: pick<EasEmail>(changed, SyncContentType.email),
      addedSms: pick<EasEmail>(added, SyncContentType.sms),
      changedSms: pick<EasEmail>(changed, SyncContentType.sms),
      addedCalendarEvents: pick<EasCalendarEvent>(
        added,
        SyncContentType.calendar,
      ),
      changedCalendarEvents: pick<EasCalendarEvent>(
        changed,
        SyncContentType.calendar,
      ),
      addedTasks: pick<EasTask>(added, SyncContentType.task),
      changedTasks: pick<EasTask>(changed, SyncContentType.task),
      addedContacts: pick<EasContact>(added, SyncContentType.contact),
      changedContacts: pick<EasContact>(changed, SyncContentType.contact),
      addedNotes: pick<EasNote>(added, SyncContentType.note),
      changedNotes: pick<EasNote>(changed, SyncContentType.note),
      deletedIds: [for (final d in deletes) d.serverId],
      deletedItems: deletes,
      softDeletedIds: commandsOf('SoftDelete')
          .map((e) => e.str('AirSync', 'ServerId') ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
      moreAvailable: collection.findChild('AirSync', 'MoreAvailable') != null,
      addResponses: [
        for (final e in responsesOf('Add'))
          SyncAddResponse(
            clientId: e.str('AirSync', 'ClientId') ?? '',
            serverId: e.str('AirSync', 'ServerId'),
            status: _status(e),
            className: e.str('AirSync', 'Class'),
            attachmentFileReferences: _attachmentRefs(e),
            item: itemOf(e),
          ),
      ],
      changeResponses: [
        for (final e in responsesOf('Change'))
          SyncChangeResponse(
            serverId: e.str('AirSync', 'ServerId') ?? '',
            status: _status(e),
            instanceId: e.date('AirSyncBase', 'InstanceId'),
            className: e.str('AirSync', 'Class'),
            attachmentFileReferences: _attachmentRefs(e),
            item: itemOf(e),
          ),
      ],
      deleteResponses: [
        for (final e in responsesOf('Delete'))
          SyncDeleteResponse(
            serverId: e.str('AirSync', 'ServerId') ?? '',
            status: _status(e),
            instanceId: e.date('AirSyncBase', 'InstanceId'),
          ),
      ],
      fetchResponses: [
        for (final e in responsesOf('Fetch'))
          SyncFetchResponse(
            serverId: e.str('AirSync', 'ServerId') ?? '',
            status: _status(e),
            item: _status(e) == 1 ? itemOf(e) : null,
          ),
      ],
    );
  }

  static (SyncContentType, Object) _typed(
    SyncContentType type,
    WbxmlElement e,
  ) => (type, _parseItem(type, e));

  /// Attachment ClientId → FileReference from a Responses Add/Change
  /// `ApplicationData/Attachments/Attachment` list.
  static Map<String, String> _attachmentRefs(WbxmlElement response) {
    final attachments = response
        .findChild('AirSync', 'ApplicationData')
        ?.findChild('AirSyncBase', 'Attachments');
    if (attachments == null) return const {};
    return {
      for (final a in attachments.findChildren('AirSyncBase', 'Attachment'))
        ?a.str('AirSyncBase', 'ClientId'):
            a.str('AirSyncBase', 'FileReference') ?? '',
    };
  }
}

/// Single-collection Sync (backward-compatible wrapper over
/// [MultiSyncCommand]).
class SyncCommand extends EasCommand<SyncResult> {
  final String syncKey;
  final String collectionId;
  final int windowSize;
  final int bodyType;
  final int? bodyTruncationSize;
  final SyncContentType contentType;

  /// Time-based filter (MS-ASCMD). Only for Email, Calendar and Tasks.
  final SyncFilterType? filterType;

  /// Client-to-server operations (Add/Change/Delete/Fetch).
  final List<SyncClientCommand> clientCommands;

  /// Conflict resolution: 0 = client wins, 1 = server wins (default).
  final int? conflict;

  /// MIME support: 0=never, 1=S/MIME only, 2=all.
  final int? mimeSupport;

  /// MIME truncation code.
  final int? mimeTruncation;

  /// Content class for the collection (see [SyncCollection.className]).
  final String? className;

  /// Full Options blocks (see [SyncCollection.options]).
  final List<SyncOptions>? options;

  /// Ghosted properties (see [SyncCollection.supported]).
  final List<String>? supported;

  /// See [SyncCollection.getChanges].
  final bool? getChanges;

  /// See [SyncCollection.deletesAsMoves].
  final bool deletesAsMoves;

  /// See [SyncCollection.conversationMode].
  final bool? conversationMode;

  /// Protocol version used for version-dependent elements.
  final String protocolVersion;

  SyncCommand({
    required this.syncKey,
    required this.collectionId,
    this.windowSize = 50,
    this.bodyType = 2, // HTML
    this.bodyTruncationSize,
    this.contentType = SyncContentType.email,
    this.filterType,
    this.clientCommands = const [],
    this.conflict,
    this.mimeSupport,
    this.mimeTruncation,
    this.className,
    this.options,
    this.supported,
    this.getChanges,
    this.deletesAsMoves = true,
    this.conversationMode,
    this.protocolVersion = '16.1',
  });

  @override
  String get commandName => 'Sync';

  MultiSyncCommand get _multi => MultiSyncCommand(
    collections: [
      SyncCollection(
        syncKey: syncKey,
        collectionId: collectionId,
        windowSize: windowSize,
        bodyType: bodyType,
        bodyTruncationSize: bodyTruncationSize,
        contentType: contentType,
        filterType: filterType,
        clientCommands: clientCommands,
        conflict: conflict,
        mimeSupport: mimeSupport,
        mimeTruncation: mimeTruncation,
        className: className,
        options: options,
        supported: supported,
        getChanges: getChanges,
        deletesAsMoves: deletesAsMoves,
        conversationMode: conversationMode,
        protocolVersion: protocolVersion,
      ),
    ],
  );

  @override
  WbxmlDocument buildRequest() => _multi.buildRequest();

  @override
  SyncResult parseResponse(WbxmlDocument response) =>
      _select(_multi.parseResponse(response));

  @override
  Future<SyncResult> execute(EasHttpClient client, {Duration? timeout}) async =>
      _select(await _multi.execute(client, timeout: timeout));

  SyncResult _select(MultiSyncResult result) =>
      result.collection(collectionId) ??
      SyncResult(
        status: result.status,
        syncKey: syncKey,
        collectionId: collectionId,
      );
}

// ─── Item parsing ───────────────────────────────────────────────────────────

/// Parse the `ApplicationData` of a Sync Add/Change/Fetch element.
Object _parseItem(SyncContentType type, WbxmlElement command) {
  final serverId = command.str('AirSync', 'ServerId') ?? '';
  final data =
      command.findChild('AirSync', 'ApplicationData') ??
      WbxmlElement(namespace: 'AirSync', tag: 'ApplicationData');
  return switch (type) {
    SyncContentType.email ||
    SyncContentType.sms => EasEmail.fromApplicationData(serverId, data),
    SyncContentType.calendar => EasCalendarEvent.fromApplicationData(
      serverId,
      data,
    ),
    SyncContentType.task => EasTask.fromApplicationData(serverId, data),
    SyncContentType.contact => EasContact.fromApplicationData(serverId, data),
    SyncContentType.note => EasNote.fromApplicationData(serverId, data),
  };
}
