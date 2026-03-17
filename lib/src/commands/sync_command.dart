/// Sync command — synchronizes folder contents.
///
/// Implements the Sync state machine:
/// - SyncKey=0 → get initial SyncKey (no data returned)
/// - SyncKey=N → get changes + new SyncKey
/// - Status=3 → invalid SyncKey, reset to 0
///
/// Reference: MS-ASCMD section 2.2.1.21
library;

import '../models/eas_attachment.dart';
import '../models/eas_calendar_event.dart';
import '../models/eas_contact.dart';
import '../models/eas_email.dart';
import '../models/eas_exception.dart';
import '../models/eas_note.dart';
import '../models/eas_recurrence.dart';
import '../models/eas_task.dart';
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
}

/// Result of a Sync command.
class SyncResult {
  final int status;
  final String syncKey;
  final String collectionId;

  // Email
  final List<EasEmail> addedEmails;
  final List<EasEmail> changedEmails;

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

  final bool moreAvailable;

  // ─── Client command responses ──────────────────────────────────────────

  /// Server responses to client Add operations.
  final List<SyncAddResponse> addResponses;

  /// Server responses to client Change operations.
  final List<SyncChangeResponse> changeResponses;

  /// Server responses to client Delete operations.
  final List<SyncDeleteResponse> deleteResponses;

  const SyncResult({
    required this.status,
    required this.syncKey,
    required this.collectionId,
    this.addedEmails = const [],
    this.changedEmails = const [],
    this.addedCalendarEvents = const [],
    this.changedCalendarEvents = const [],
    this.addedTasks = const [],
    this.changedTasks = const [],
    this.addedContacts = const [],
    this.changedContacts = const [],
    this.addedNotes = const [],
    this.changedNotes = const [],
    this.deletedIds = const [],
    this.moreAvailable = false,
    this.addResponses = const [],
    this.changeResponses = const [],
    this.deleteResponses = const [],
  });

  /// Whether the sync key is invalid and needs reset.
  bool get needsReset => status == 3;
}

/// Time-based filter for Sync (MS-ASCMD 2.2.1.21.3.1).
///
/// Limits the sync window to items within a specific time range.
/// Only applicable to Email and Calendar content types.
enum SyncFilterType {
  /// No filter — sync all items.
  noFilter(0),
  oneDay(1),
  threeDays(2),
  oneWeek(3),
  twoWeeks(4),
  oneMonth(5),
  threeMonths(6),
  sixMonths(7);

  final int value;
  const SyncFilterType(this.value);
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

  const SyncAddItem({
    required this.clientId,
    required this.applicationData,
  });
}

/// Change an existing item on the server.
class SyncChangeItem extends SyncClientCommand {
  /// Server-assigned ID of the item to change.
  final String serverId;

  /// WBXML ApplicationData element with the changed fields.
  final WbxmlElement applicationData;

  const SyncChangeItem({
    required this.serverId,
    required this.applicationData,
  });
}

/// Delete an item from the server.
class SyncDeleteItem extends SyncClientCommand {
  /// Server-assigned ID of the item to delete.
  final String serverId;

  const SyncDeleteItem({required this.serverId});
}

// ─── Sync Response models ───────────────────────────────────────────────────

/// Server response to a client Add operation.
class SyncAddResponse {
  final String clientId;
  final String? serverId;
  final int status;

  bool get isSuccess => status == 1;

  const SyncAddResponse({
    required this.clientId,
    this.serverId,
    required this.status,
  });
}

/// Server response to a client Change operation.
class SyncChangeResponse {
  final String serverId;
  final int status;

  bool get isSuccess => status == 1;

  const SyncChangeResponse({
    required this.serverId,
    required this.status,
  });
}

/// Server response to a client Delete operation.
class SyncDeleteResponse {
  final String serverId;
  final int status;

  bool get isSuccess => status == 1;

  const SyncDeleteResponse({
    required this.serverId,
    required this.status,
  });
}

class SyncCommand extends EasCommand<SyncResult> {
  final String syncKey;
  final String collectionId;
  final int windowSize;
  final int bodyType;
  final int? bodyTruncationSize;
  final SyncContentType contentType;

  /// Time-based filter (MS-ASCMD). Only for Email and Calendar.
  final SyncFilterType? filterType;

  /// Client-to-server operations (Add/Change/Delete).
  final List<SyncClientCommand> clientCommands;

  /// Conflict resolution: 0 = server wins (default), 1 = client wins.
  final int? conflict;

  /// MIME support: 0=never, 1=S/MIME only, 2=all.
  final int? mimeSupport;

  /// MIME truncation size in bytes.
  final int? mimeTruncation;

  /// Content class for the collection ('Email', 'Calendar', 'Tasks', 'Contacts', 'Notes').
  final String? className;

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
  });

  @override
  String get commandName => 'Sync';

  @override
  WbxmlDocument buildRequest() {
    final collectionChildren = <WbxmlElement>[
      WbxmlElement.withText(
        namespace: 'AirSync',
        tag: 'SyncKey',
        text: syncKey,
        codePageIndex: 0,
      ),
      WbxmlElement.withText(
        namespace: 'AirSync',
        tag: 'CollectionId',
        text: collectionId,
        codePageIndex: 0,
      ),
    ];

    if (syncKey != '0') {
      // Class element (before DeletesAsMoves per spec)
      if (className != null) {
        collectionChildren.add(WbxmlElement.withText(
          namespace: 'AirSync',
          tag: 'Class',
          text: className!,
          codePageIndex: 0,
        ));
      }

      collectionChildren.addAll([
        WbxmlElement.withText(
          namespace: 'AirSync',
          tag: 'DeletesAsMoves',
          text: '1',
          codePageIndex: 0,
        ),
        WbxmlElement.withText(
          namespace: 'AirSync',
          tag: 'GetChanges',
          text: clientCommands.isEmpty ? '1' : '0',
          codePageIndex: 0,
        ),
        WbxmlElement.withText(
          namespace: 'AirSync',
          tag: 'WindowSize',
          text: windowSize.toString(),
          codePageIndex: 0,
        ),
        // Options
        WbxmlElement(
          namespace: 'AirSync',
          tag: 'Options',
          codePageIndex: 0,
          children: [
            if (filterType != null &&
                filterType != SyncFilterType.noFilter)
              WbxmlElement.withText(
                namespace: 'AirSync',
                tag: 'FilterType',
                text: filterType!.value.toString(),
                codePageIndex: 0,
              ),
            if (conflict != null)
              WbxmlElement.withText(
                namespace: 'AirSync',
                tag: 'Conflict',
                text: conflict.toString(),
                codePageIndex: 0,
              ),
            if (mimeSupport != null)
              WbxmlElement.withText(
                namespace: 'AirSync',
                tag: 'MIMESupport',
                text: mimeSupport.toString(),
                codePageIndex: 0,
              ),
            if (mimeTruncation != null)
              WbxmlElement.withText(
                namespace: 'AirSync',
                tag: 'MIMETruncation',
                text: mimeTruncation.toString(),
                codePageIndex: 0,
              ),
            WbxmlElement(
              namespace: 'AirSyncBase',
              tag: 'BodyPreference',
              codePageIndex: 17,
              children: [
                WbxmlElement.withText(
                  namespace: 'AirSyncBase',
                  tag: 'Type',
                  text: bodyType.toString(),
                  codePageIndex: 17,
                ),
                if (bodyTruncationSize != null)
                  WbxmlElement.withText(
                    namespace: 'AirSyncBase',
                    tag: 'TruncationSize',
                    text: bodyTruncationSize.toString(),
                    codePageIndex: 17,
                  ),
              ],
            ),
          ],
        ),
      ]);

      // Client-to-server Commands
      if (clientCommands.isNotEmpty) {
        collectionChildren.add(WbxmlElement(
          namespace: 'AirSync',
          tag: 'Commands',
          codePageIndex: 0,
          children: clientCommands.map(_buildClientCommand).toList(),
        ));
      }
    }

    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'AirSync',
        tag: 'Sync',
        codePageIndex: 0,
        children: [
          WbxmlElement(
            namespace: 'AirSync',
            tag: 'Collections',
            codePageIndex: 0,
            children: [
              WbxmlElement(
                namespace: 'AirSync',
                tag: 'Collection',
                codePageIndex: 0,
                children: collectionChildren,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  SyncResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final collections = root.findChild('AirSync', 'Collections');
    if (collections == null) {
      return SyncResult(
        status: 1,
        syncKey: syncKey,
        collectionId: collectionId,
      );
    }

    final collection = collections.findChild('AirSync', 'Collection');
    if (collection == null) {
      return SyncResult(
        status: 1,
        syncKey: syncKey,
        collectionId: collectionId,
      );
    }

    final status =
        int.tryParse(collection.childText('AirSync', 'Status') ?? '') ?? 0;
    final newSyncKey =
        collection.childText('AirSync', 'SyncKey') ?? syncKey;
    final moreAvailable =
        collection.findChild('AirSync', 'MoreAvailable') != null;

    // Parse client command Responses
    final responses = collection.findChild('AirSync', 'Responses');
    final addResponses = <SyncAddResponse>[];
    final changeResponses = <SyncChangeResponse>[];
    final deleteResponses = <SyncDeleteResponse>[];

    if (responses != null) {
      for (final add in responses.findChildren('AirSync', 'Add')) {
        addResponses.add(SyncAddResponse(
          clientId: add.childText('AirSync', 'ClientId') ?? '',
          serverId: add.childText('AirSync', 'ServerId'),
          status: int.tryParse(add.childText('AirSync', 'Status') ?? '') ?? 0,
        ));
      }
      for (final change in responses.findChildren('AirSync', 'Change')) {
        changeResponses.add(SyncChangeResponse(
          serverId: change.childText('AirSync', 'ServerId') ?? '',
          status:
              int.tryParse(change.childText('AirSync', 'Status') ?? '') ?? 0,
        ));
      }
      for (final delete in responses.findChildren('AirSync', 'Delete')) {
        deleteResponses.add(SyncDeleteResponse(
          serverId: delete.childText('AirSync', 'ServerId') ?? '',
          status:
              int.tryParse(delete.childText('AirSync', 'Status') ?? '') ?? 0,
        ));
      }
    }

    final commands = collection.findChild('AirSync', 'Commands');
    if (commands == null) {
      return SyncResult(
        status: status,
        syncKey: newSyncKey,
        collectionId: collectionId,
        moreAvailable: moreAvailable,
        addResponses: addResponses,
        changeResponses: changeResponses,
        deleteResponses: deleteResponses,
      );
    }

    final deleted = commands
        .findChildren('AirSync', 'Delete')
        .map((e) => e.childText('AirSync', 'ServerId') ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    switch (contentType) {
      case SyncContentType.email:
        return SyncResult(
          status: status,
          syncKey: newSyncKey,
          collectionId: collectionId,
          addedEmails: commands
              .findChildren('AirSync', 'Add')
              .map(_parseEmailFromCommand)
              .toList(),
          changedEmails: commands
              .findChildren('AirSync', 'Change')
              .map(_parseEmailFromCommand)
              .toList(),
          deletedIds: deleted,
          moreAvailable: moreAvailable,
          addResponses: addResponses,
          changeResponses: changeResponses,
          deleteResponses: deleteResponses,
        );

      case SyncContentType.calendar:
        return SyncResult(
          status: status,
          syncKey: newSyncKey,
          collectionId: collectionId,
          addedCalendarEvents: commands
              .findChildren('AirSync', 'Add')
              .map(_parseCalendarFromCommand)
              .toList(),
          changedCalendarEvents: commands
              .findChildren('AirSync', 'Change')
              .map(_parseCalendarFromCommand)
              .toList(),
          deletedIds: deleted,
          moreAvailable: moreAvailable,
          addResponses: addResponses,
          changeResponses: changeResponses,
          deleteResponses: deleteResponses,
        );

      case SyncContentType.task:
        return SyncResult(
          status: status,
          syncKey: newSyncKey,
          collectionId: collectionId,
          addedTasks: commands
              .findChildren('AirSync', 'Add')
              .map(_parseTaskFromCommand)
              .toList(),
          changedTasks: commands
              .findChildren('AirSync', 'Change')
              .map(_parseTaskFromCommand)
              .toList(),
          deletedIds: deleted,
          moreAvailable: moreAvailable,
          addResponses: addResponses,
          changeResponses: changeResponses,
          deleteResponses: deleteResponses,
        );

      case SyncContentType.contact:
        return SyncResult(
          status: status,
          syncKey: newSyncKey,
          collectionId: collectionId,
          addedContacts: commands
              .findChildren('AirSync', 'Add')
              .map(_parseContactFromCommand)
              .toList(),
          changedContacts: commands
              .findChildren('AirSync', 'Change')
              .map(_parseContactFromCommand)
              .toList(),
          deletedIds: deleted,
          moreAvailable: moreAvailable,
          addResponses: addResponses,
          changeResponses: changeResponses,
          deleteResponses: deleteResponses,
        );

      case SyncContentType.note:
        return SyncResult(
          status: status,
          syncKey: newSyncKey,
          collectionId: collectionId,
          addedNotes: commands
              .findChildren('AirSync', 'Add')
              .map(_parseNoteFromCommand)
              .toList(),
          changedNotes: commands
              .findChildren('AirSync', 'Change')
              .map(_parseNoteFromCommand)
              .toList(),
          deletedIds: deleted,
          moreAvailable: moreAvailable,
          addResponses: addResponses,
          changeResponses: changeResponses,
          deleteResponses: deleteResponses,
        );
    }
  }

  WbxmlElement _buildClientCommand(SyncClientCommand cmd) {
    return switch (cmd) {
      SyncAddItem(:final clientId, :final applicationData) => WbxmlElement(
          namespace: 'AirSync',
          tag: 'Add',
          codePageIndex: 0,
          children: [
            WbxmlElement.withText(
              namespace: 'AirSync',
              tag: 'ClientId',
              text: clientId,
              codePageIndex: 0,
            ),
            applicationData,
          ],
        ),
      SyncChangeItem(:final serverId, :final applicationData) => WbxmlElement(
          namespace: 'AirSync',
          tag: 'Change',
          codePageIndex: 0,
          children: [
            WbxmlElement.withText(
              namespace: 'AirSync',
              tag: 'ServerId',
              text: serverId,
              codePageIndex: 0,
            ),
            applicationData,
          ],
        ),
      SyncDeleteItem(:final serverId) => WbxmlElement(
          namespace: 'AirSync',
          tag: 'Delete',
          codePageIndex: 0,
          children: [
            WbxmlElement.withText(
              namespace: 'AirSync',
              tag: 'ServerId',
              text: serverId,
              codePageIndex: 0,
            ),
          ],
        ),
    };
  }

  // ─── Email ──────────────────────────────────────────────────────────────────

  EasEmail _parseEmailFromCommand(WbxmlElement command) {
    final serverId = command.childText('AirSync', 'ServerId') ?? '';
    final appData = command.findChild('AirSync', 'ApplicationData');
    if (appData == null) return EasEmail(serverId: serverId);
    return _parseEmail(serverId, appData);
  }

  EasEmail _parseEmail(String serverId, WbxmlElement data) {
    final subject = data.childText('Email', 'Subject') ?? '';
    final from = data.childText('Email', 'From') ?? '';
    final to = data.childText('Email', 'To') ?? '';
    final cc = data.childText('Email', 'Cc');
    final displayTo = data.childText('Email', 'DisplayTo');
    final dateStr = data.childText('Email', 'DateReceived');
    final readStr = data.childText('Email', 'Read');
    final importanceStr = data.childText('Email', 'Importance');
    final messageClass = data.childText('Email', 'MessageClass');
    final threadTopic = data.childText('Email', 'ThreadTopic');
    final replyTo = data.childText('Email', 'ReplyTo');

    final bodyElement = data.findChild('AirSyncBase', 'Body');
    String? body;
    int bodyTypeVal = 1;
    bool bodyTruncated = false;
    int? estimatedBodySize;
    if (bodyElement != null) {
      body = bodyElement.childText('AirSyncBase', 'Data');
      bodyTypeVal =
          int.tryParse(bodyElement.childText('AirSyncBase', 'Type') ?? '') ??
              1;
      bodyTruncated =
          bodyElement.childText('AirSyncBase', 'Truncated') == '1';
      estimatedBodySize = int.tryParse(
        bodyElement.childText('AirSyncBase', 'EstimatedDataSize') ?? '',
      );
    }

    final attachmentsElement = data.findChild('AirSyncBase', 'Attachments');
    final attachments = <EasAttachment>[];
    if (attachmentsElement != null) {
      for (final att
          in attachmentsElement.findChildren('AirSyncBase', 'Attachment')) {
        attachments.add(EasAttachment(
          displayName: att.childText('AirSyncBase', 'DisplayName') ?? '',
          fileReference: att.childText('AirSyncBase', 'FileReference') ?? '',
          method:
              int.tryParse(att.childText('AirSyncBase', 'Method') ?? '') ?? 1,
          contentId: att.childText('AirSyncBase', 'ContentId'),
          isInline: att.childText('AirSyncBase', 'IsInline') == '1',
          contentType: att.childText('AirSyncBase', 'ContentType'),
        ));
      }
    }

    final flagElement = data.findChild('Email', 'Flag');
    int flagStatus = 0;
    if (flagElement != null) {
      flagStatus =
          int.tryParse(flagElement.childText('Email', 'Status') ?? '') ??
              0;
    }

    final conversationId = data.childText('Email2', 'ConversationId');
    final isDraft = data.childText('Email2', 'IsDraft') == '1';
    final bcc = data.childText('Email2', 'Bcc');
    final receivedAsBccStr = data.childText('Email2', 'ReceivedAsBcc');

    final contentClass = data.childText('Email', 'ContentClass');
    final internetCPIDStr = data.childText('Email', 'InternetCPID');
    final sensitivityStr = data.childText('Email', 'Sensitivity');
    final lastVerbStr = data.childText('Email2', 'LastVerbExecuted');
    final lastVerbTimeStr = data.childText('Email2', 'LastVerbExecutionTime');

    // Categories
    final categoriesEl = data.findChild('Email', 'Categories');
    final categories = categoriesEl
            ?.findChildren('Email', 'Category')
            .map((e) => e.text ?? '')
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    return EasEmail(
      serverId: serverId,
      subject: subject,
      from: from,
      to: to,
      cc: cc,
      bcc: bcc,
      displayTo: displayTo,
      dateReceived: dateStr != null ? DateTime.tryParse(dateStr) : null,
      read: readStr == '1',
      importance: EmailImportance.fromValue(
        int.tryParse(importanceStr ?? '') ?? 1,
      ),
      messageClass: messageClass,
      body: body,
      bodyType: bodyTypeVal,
      bodyTruncated: bodyTruncated,
      estimatedBodySize: estimatedBodySize,
      threadTopic: threadTopic,
      replyTo: replyTo,
      attachments: attachments,
      conversationId: conversationId,
      flagStatus: flagStatus,
      isDraft: isDraft,
      contentClass: contentClass,
      internetCPID:
          internetCPIDStr != null ? int.tryParse(internetCPIDStr) : null,
      categories: categories,
      lastVerbExecuted: lastVerbStr != null ? int.tryParse(lastVerbStr) : null,
      lastVerbExecutionTime: lastVerbTimeStr != null
          ? DateTime.tryParse(lastVerbTimeStr)
          : null,
      receivedAsBcc: receivedAsBccStr == '1' ? true : null,
      sensitivity: sensitivityStr != null ? int.tryParse(sensitivityStr) : null,
    );
  }

  // ─── Calendar ────────────────────────────────────────────────────────────────

  EasCalendarEvent _parseCalendarFromCommand(WbxmlElement command) {
    final serverId = command.childText('AirSync', 'ServerId') ?? '';
    final appData = command.findChild('AirSync', 'ApplicationData');
    if (appData == null) return EasCalendarEvent(serverId: serverId);
    return _parseCalendar(serverId, appData);
  }

  EasCalendarEvent _parseCalendar(String serverId, WbxmlElement data) {
    final subject = data.childText('Calendar', 'Subject') ?? '';
    final startStr = data.childText('Calendar', 'StartTime');
    final endStr = data.childText('Calendar', 'EndTime');
    final location = data.childText('Calendar', 'Location');
    final allDayStr = data.childText('Calendar', 'AllDayEvent');
    final busyStr = data.childText('Calendar', 'BusyStatus');
    final sensitivityStr = data.childText('Calendar', 'Sensitivity');
    final uid = data.childText('Calendar', 'UID');
    final organizerName = data.childText('Calendar', 'OrganizerName');
    final organizerEmail = data.childText('Calendar', 'OrganizerEmail');
    final reminderStr = data.childText('Calendar', 'Reminder');
    final meetingStatusStr = data.childText('Calendar', 'MeetingStatus');

    final bodyElement = data.findChild('AirSyncBase', 'Body');
    String? body;
    if (bodyElement != null) {
      body = bodyElement.childText('AirSyncBase', 'Data');
    }

    final attendeesEl = data.findChild('Calendar', 'Attendees');
    final attendees = <EasAttendee>[];
    if (attendeesEl != null) {
      for (final att in attendeesEl.findChildren('Calendar', 'Attendee')) {
        attendees.add(EasAttendee(
          email: att.childText('Calendar', 'Email') ?? '',
          name: att.childText('Calendar', 'Name'),
          status: AttendeeStatus.fromValue(
            int.tryParse(att.childText('Calendar', 'AttendeeStatus') ?? '') ??
                0,
          ),
          type: AttendeeType.fromValue(
            int.tryParse(att.childText('Calendar', 'AttendeeType') ?? '') ?? 1,
          ),
        ));
      }
    }

    final categoriesEl = data.findChild('Calendar', 'Categories');
    final categories = categoriesEl
            ?.findChildren('Calendar', 'Category')
            .map((e) => e.text ?? '')
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    // Recurrence
    final recurrenceEl = data.findChild('Calendar', 'Recurrence');
    EasRecurrence? recurrence;
    if (recurrenceEl != null) {
      recurrence = _parseRecurrence(recurrenceEl);
    }

    // Exceptions
    final exceptionsEl = data.findChild('Calendar', 'Exceptions');
    final exceptions = <EasCalendarException>[];
    if (exceptionsEl != null) {
      for (final exc
          in exceptionsEl.findChildren('Calendar', 'Exception')) {
        exceptions.add(_parseCalendarException(exc));
      }
    }

    // New fields
    final timezone = data.childText('Calendar', 'Timezone');
    final dtStampStr = data.childText('Calendar', 'DtStamp');
    final responseTypeStr = data.childText('Calendar', 'ResponseType');
    final appointmentReplyTimeStr =
        data.childText('Calendar', 'AppointmentReplyTime');
    final nativeBodyTypeStr = data.childText('AirSyncBase', 'NativeBodyType');
    final disallowNewTimeStr =
        data.childText('Calendar', 'DisallowNewTimeProposal');
    final onlineMeetingConfLink =
        data.childText('Calendar', 'OnlineMeetingConfLink');
    final onlineMeetingExternalLink =
        data.childText('Calendar', 'OnlineMeetingExternalLink');

    return EasCalendarEvent(
      serverId: serverId,
      subject: subject,
      startTime: startStr != null ? DateTime.tryParse(startStr) : null,
      endTime: endStr != null ? DateTime.tryParse(endStr) : null,
      location: location,
      body: body,
      allDayEvent: allDayStr == '1',
      busyStatus: int.tryParse(busyStr ?? '') ?? 2,
      sensitivity: int.tryParse(sensitivityStr ?? '') ?? 0,
      uid: uid,
      organizerName: organizerName,
      organizerEmail: organizerEmail,
      reminder: reminderStr != null ? int.tryParse(reminderStr) : null,
      meetingStatus: int.tryParse(meetingStatusStr ?? '') ?? 0,
      attendees: attendees,
      categories: categories,
      recurrence: recurrence,
      exceptions: exceptions,
      timezone: timezone,
      dtStamp: dtStampStr != null ? DateTime.tryParse(dtStampStr) : null,
      responseType:
          responseTypeStr != null ? int.tryParse(responseTypeStr) : null,
      appointmentReplyTime: appointmentReplyTimeStr != null
          ? DateTime.tryParse(appointmentReplyTimeStr)
          : null,
      nativeBodyType:
          nativeBodyTypeStr != null ? int.tryParse(nativeBodyTypeStr) : null,
      disallowNewTimeProposal: disallowNewTimeStr == '1' ? true : null,
      onlineMeetingConfLink: onlineMeetingConfLink,
      onlineMeetingExternalLink: onlineMeetingExternalLink,
    );
  }

  EasRecurrence _parseRecurrence(WbxmlElement el) {
    return EasRecurrence(
      type: int.tryParse(el.childText('Calendar', 'Type') ?? '') ?? 0,
      until: el.childText('Calendar', 'Until') != null
          ? DateTime.tryParse(el.childText('Calendar', 'Until')!)
          : null,
      occurrences: el.childText('Calendar', 'Occurrences') != null
          ? int.tryParse(el.childText('Calendar', 'Occurrences')!)
          : null,
      interval:
          int.tryParse(el.childText('Calendar', 'Interval') ?? '') ?? 1,
      dayOfWeek: el.childText('Calendar', 'DayOfWeek') != null
          ? int.tryParse(el.childText('Calendar', 'DayOfWeek')!)
          : null,
      dayOfMonth: el.childText('Calendar', 'DayOfMonth') != null
          ? int.tryParse(el.childText('Calendar', 'DayOfMonth')!)
          : null,
      weekOfMonth: el.childText('Calendar', 'WeekOfMonth') != null
          ? int.tryParse(el.childText('Calendar', 'WeekOfMonth')!)
          : null,
      monthOfYear: el.childText('Calendar', 'MonthOfYear') != null
          ? int.tryParse(el.childText('Calendar', 'MonthOfYear')!)
          : null,
      calendarType: el.childText('Calendar', 'CalendarType') != null
          ? int.tryParse(el.childText('Calendar', 'CalendarType')!)
          : null,
      isLeapMonth: el.childText('Calendar', 'IsLeapMonth') == '1'
          ? true
          : null,
      firstDayOfWeek: el.childText('Calendar', 'FirstDayOfWeek') != null
          ? int.tryParse(el.childText('Calendar', 'FirstDayOfWeek')!)
          : null,
    );
  }

  EasCalendarException _parseCalendarException(WbxmlElement el) {
    final exStartStr = el.childText('Calendar', 'ExceptionStartTime') ?? '';
    final deleted = el.childText('Calendar', 'Deleted') == '1';
    final subject = el.childText('Calendar', 'Subject');
    final startStr = el.childText('Calendar', 'StartTime');
    final endStr = el.childText('Calendar', 'EndTime');
    final location = el.childText('Calendar', 'Location');
    final allDayStr = el.childText('Calendar', 'AllDayEvent');
    final busyStr = el.childText('Calendar', 'BusyStatus');
    final sensitivityStr = el.childText('Calendar', 'Sensitivity');
    final reminderStr = el.childText('Calendar', 'Reminder');

    final bodyElement = el.findChild('AirSyncBase', 'Body');
    String? body;
    if (bodyElement != null) {
      body = bodyElement.childText('AirSyncBase', 'Data');
    }

    return EasCalendarException(
      exceptionStartTime:
          DateTime.tryParse(exStartStr) ?? DateTime.fromMillisecondsSinceEpoch(0),
      deleted: deleted,
      subject: subject,
      startTime: startStr != null ? DateTime.tryParse(startStr) : null,
      endTime: endStr != null ? DateTime.tryParse(endStr) : null,
      location: location,
      body: body,
      allDayEvent: allDayStr != null ? allDayStr == '1' : null,
      busyStatus: busyStr != null ? int.tryParse(busyStr) : null,
      sensitivity:
          sensitivityStr != null ? int.tryParse(sensitivityStr) : null,
      reminder: reminderStr != null ? int.tryParse(reminderStr) : null,
    );
  }

  // ─── Tasks ───────────────────────────────────────────────────────────────────

  EasTask _parseTaskFromCommand(WbxmlElement command) {
    final serverId = command.childText('AirSync', 'ServerId') ?? '';
    final appData = command.findChild('AirSync', 'ApplicationData');
    if (appData == null) return EasTask(serverId: serverId);
    return _parseTask(serverId, appData);
  }

  EasTask _parseTask(String serverId, WbxmlElement data) {
    final subject = data.childText('Tasks', 'Subject') ?? '';
    final completeStr = data.childText('Tasks', 'Complete');
    final dueDateStr = data.childText('Tasks', 'DueDate');
    final startDateStr = data.childText('Tasks', 'StartDate');
    final dateCompletedStr = data.childText('Tasks', 'DateCompleted');
    final importanceStr = data.childText('Tasks', 'Importance');
    final body = data.childText('Tasks', 'Body');
    final sensitivityStr = data.childText('Tasks', 'Sensitivity');
    final reminderSetStr = data.childText('Tasks', 'ReminderSet');
    final reminderTimeStr = data.childText('Tasks', 'ReminderTime');

    final categoriesEl = data.findChild('Tasks', 'Categories');
    final categories = categoriesEl
            ?.findChildren('Tasks', 'Category')
            .map((e) => e.text ?? '')
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    // Recurrence
    final recurrenceEl = data.findChild('Tasks', 'Recurrence');
    EasRecurrence? recurrence;
    if (recurrenceEl != null) {
      recurrence = EasRecurrence(
        type: int.tryParse(recurrenceEl.childText('Tasks', 'Type') ??
                recurrenceEl.childText('Calendar', 'Type') ??
                '') ??
            0,
        interval: int.tryParse(recurrenceEl.childText('Tasks', 'Interval') ??
                recurrenceEl.childText('Calendar', 'Interval') ??
                '') ??
            1,
        until: recurrenceEl.childText('Tasks', 'Until') != null
            ? DateTime.tryParse(recurrenceEl.childText('Tasks', 'Until')!)
            : null,
        occurrences: recurrenceEl.childText('Tasks', 'Occurrences') != null
            ? int.tryParse(
                recurrenceEl.childText('Tasks', 'Occurrences')!)
            : null,
        dayOfWeek: recurrenceEl.childText('Tasks', 'DayOfWeek') != null
            ? int.tryParse(
                recurrenceEl.childText('Tasks', 'DayOfWeek')!)
            : null,
        dayOfMonth: recurrenceEl.childText('Tasks', 'DayOfMonth') != null
            ? int.tryParse(
                recurrenceEl.childText('Tasks', 'DayOfMonth')!)
            : null,
        weekOfMonth: recurrenceEl.childText('Tasks', 'WeekOfMonth') != null
            ? int.tryParse(
                recurrenceEl.childText('Tasks', 'WeekOfMonth')!)
            : null,
        monthOfYear: recurrenceEl.childText('Tasks', 'MonthOfYear') != null
            ? int.tryParse(
                recurrenceEl.childText('Tasks', 'MonthOfYear')!)
            : null,
        calendarType: recurrenceEl.childText('Tasks', 'CalendarType') != null
            ? int.tryParse(
                recurrenceEl.childText('Tasks', 'CalendarType')!)
            : null,
      );
    }

    final ordinalDate = data.childText('Tasks', 'OrdinalDate');
    final subOrdinalDate = data.childText('Tasks', 'SubOrdinalDate');
    final calendarTypeStr = data.childText('Tasks', 'CalendarType');

    return EasTask(
      serverId: serverId,
      subject: subject,
      complete: completeStr == '1',
      dueDate: dueDateStr != null ? DateTime.tryParse(dueDateStr) : null,
      startDate: startDateStr != null ? DateTime.tryParse(startDateStr) : null,
      dateCompleted:
          dateCompletedStr != null ? DateTime.tryParse(dateCompletedStr) : null,
      importance: int.tryParse(importanceStr ?? '') ?? 1,
      body: body,
      sensitivity: int.tryParse(sensitivityStr ?? '') ?? 0,
      reminderSet: reminderSetStr == '1',
      reminderTime:
          reminderTimeStr != null ? DateTime.tryParse(reminderTimeStr) : null,
      categories: categories,
      recurrence: recurrence,
      ordinalDate: ordinalDate,
      subOrdinalDate: subOrdinalDate,
      calendarType:
          calendarTypeStr != null ? int.tryParse(calendarTypeStr) : null,
    );
  }

  // ─── Contacts ────────────────────────────────────────────────────────────────

  EasContact _parseContactFromCommand(WbxmlElement command) {
    final serverId = command.childText('AirSync', 'ServerId') ?? '';
    final appData = command.findChild('AirSync', 'ApplicationData');
    if (appData == null) return EasContact(serverId: serverId);
    return _parseContact(serverId, appData);
  }

  EasContact _parseContact(String serverId, WbxmlElement data) {
    final birthdayStr = data.childText('Contacts', 'Birthday');
    final anniversaryStr = data.childText('Contacts', 'Anniversary');

    final categoriesEl = data.findChild('Contacts', 'Categories');
    final categories = categoriesEl
            ?.findChildren('Contacts', 'Category')
            .map((e) => e.text ?? '')
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    final bodyElement = data.findChild('AirSyncBase', 'Body');
    String? body;
    if (bodyElement != null) {
      body = bodyElement.childText('AirSyncBase', 'Data');
    }

    return EasContact(
      serverId: serverId,
      fileAs: data.childText('Contacts', 'FileAs'),
      firstName: data.childText('Contacts', 'FirstName'),
      middleName: data.childText('Contacts', 'MiddleName'),
      lastName: data.childText('Contacts', 'LastName'),
      nickName: data.childText('Contacts', 'NickName'),
      email1: data.childText('Contacts', 'Email1Address'),
      email2: data.childText('Contacts', 'Email2Address'),
      email3: data.childText('Contacts', 'Email3Address'),
      mobilePhone: data.childText('Contacts', 'MobilePhoneNumber'),
      businessPhone: data.childText('Contacts', 'BusinessPhoneNumber'),
      homePhone: data.childText('Contacts', 'HomePhoneNumber'),
      businessFax: data.childText('Contacts', 'BusinessFaxNumber'),
      companyName: data.childText('Contacts', 'CompanyName'),
      department: data.childText('Contacts', 'Department'),
      jobTitle: data.childText('Contacts', 'JobTitle'),
      title: data.childText('Contacts', 'Title'),
      suffix: data.childText('Contacts', 'Suffix'),
      businessAddressStreet:
          data.childText('Contacts', 'BusinessAddressStreet'),
      businessAddressCity: data.childText('Contacts', 'BusinessAddressCity'),
      businessAddressPostalCode:
          data.childText('Contacts', 'BusinessAddressPostalCode'),
      businessAddressCountry:
          data.childText('Contacts', 'BusinessAddressCountry'),
      homeAddressStreet: data.childText('Contacts', 'HomeAddressStreet'),
      homeAddressCity: data.childText('Contacts', 'HomeAddressCity'),
      homeAddressPostalCode:
          data.childText('Contacts', 'HomeAddressPostalCode'),
      homeAddressCountry: data.childText('Contacts', 'HomeAddressCountry'),
      birthday:
          birthdayStr != null ? DateTime.tryParse(birthdayStr) : null,
      anniversary:
          anniversaryStr != null ? DateTime.tryParse(anniversaryStr) : null,
      body: body,
      webPage: data.childText('Contacts', 'WebPage'),
      officeLocation: data.childText('Contacts', 'OfficeLocation'),
      picture: data.childText('Contacts', 'Picture'),
      categories: categories,
      // Contacts2 fields
      imAddress: data.childText('Contacts2', 'IMAddress'),
      imAddress2: data.childText('Contacts2', 'IMAddress2'),
      imAddress3: data.childText('Contacts2', 'IMAddress3'),
      companyMainPhone: data.childText('Contacts2', 'CompanyMainPhone'),
      accountName: data.childText('Contacts2', 'AccountName'),
      mms: data.childText('Contacts2', 'MMS'),
      customerId: data.childText('Contacts2', 'CustomerId'),
      governmentId: data.childText('Contacts2', 'GovernmentId'),
      managerName: data.childText('Contacts2', 'ManagerName'),
    );
  }

  // ─── Notes ───────────────────────────────────────────────────────────────────

  EasNote _parseNoteFromCommand(WbxmlElement command) {
    final serverId = command.childText('AirSync', 'ServerId') ?? '';
    final appData = command.findChild('AirSync', 'ApplicationData');
    if (appData == null) return EasNote(serverId: serverId);
    return _parseNote(serverId, appData);
  }

  EasNote _parseNote(String serverId, WbxmlElement data) {
    final subject = data.childText('Notes', 'Subject') ?? '';
    final lastModifiedStr = data.childText('Notes', 'LastModifiedDate');
    final isReadStr = data.childText('Notes', 'IsRead');

    final categoriesEl = data.findChild('Notes', 'Categories');
    final categories = categoriesEl
            ?.findChildren('Notes', 'Category')
            .map((e) => e.text ?? '')
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];

    final bodyElement = data.findChild('AirSyncBase', 'Body');
    String? body;
    if (bodyElement != null) {
      body = bodyElement.childText('AirSyncBase', 'Data');
    }

    return EasNote(
      serverId: serverId,
      subject: subject,
      body: body,
      lastModifiedDate:
          lastModifiedStr != null ? DateTime.tryParse(lastModifiedStr) : null,
      isRead: isReadStr == '1',
      categories: categories,
    );
  }
}
