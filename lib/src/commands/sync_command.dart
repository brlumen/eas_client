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
import '../models/eas_email.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Result of a Sync command.
class SyncResult {
  final int status;
  final String syncKey;
  final String collectionId;
  final List<EasEmail> addedEmails;
  final List<EasEmail> changedEmails;
  final List<String> deletedIds;
  final bool moreAvailable;

  const SyncResult({
    required this.status,
    required this.syncKey,
    required this.collectionId,
    this.addedEmails = const [],
    this.changedEmails = const [],
    this.deletedIds = const [],
    this.moreAvailable = false,
  });

  /// Whether the sync key is invalid and needs reset.
  bool get needsReset => status == 3;
}

class SyncCommand extends EasCommand<SyncResult> {
  final String syncKey;
  final String collectionId;
  final int windowSize;
  final int bodyType;
  final int? bodyTruncationSize;

  SyncCommand({
    required this.syncKey,
    required this.collectionId,
    this.windowSize = 50,
    this.bodyType = 2, // HTML
    this.bodyTruncationSize,
  });

  @override
  String get commandName => 'Sync';

  @override
  WbxmlDocument buildRequest() {
    final options = <WbxmlElement>[
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
    ];

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

    // Only add these for non-initial sync
    if (syncKey != '0') {
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
          text: '1',
          codePageIndex: 0,
        ),
        WbxmlElement.withText(
          namespace: 'AirSync',
          tag: 'WindowSize',
          text: windowSize.toString(),
          codePageIndex: 0,
        ),
        WbxmlElement(
          namespace: 'AirSync',
          tag: 'Options',
          codePageIndex: 0,
          children: options,
        ),
      ]);
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

    final commands = collection.findChild('AirSync', 'Commands');
    if (commands == null) {
      return SyncResult(
        status: status,
        syncKey: newSyncKey,
        collectionId: collectionId,
        moreAvailable: moreAvailable,
      );
    }

    final added = commands
        .findChildren('AirSync', 'Add')
        .map(_parseEmailFromCommand)
        .toList();

    final changed = commands
        .findChildren('AirSync', 'Change')
        .map(_parseEmailFromCommand)
        .toList();

    final deleted = commands
        .findChildren('AirSync', 'Delete')
        .map((e) => e.childText('AirSync', 'ServerId') ?? '')
        .where((id) => id.isNotEmpty)
        .toList();

    return SyncResult(
      status: status,
      syncKey: newSyncKey,
      collectionId: collectionId,
      addedEmails: added,
      changedEmails: changed,
      deletedIds: deleted,
      moreAvailable: moreAvailable,
    );
  }

  EasEmail _parseEmailFromCommand(WbxmlElement command) {
    final serverId = command.childText('AirSync', 'ServerId') ?? '';
    final appData = command.findChild('AirSync', 'ApplicationData');

    if (appData == null) {
      return EasEmail(serverId: serverId);
    }

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

    // Body from AirSyncBase
    final bodyElement = data.findChild('AirSyncBase', 'Body');
    String? body;
    int bodyTypeVal = 1;
    bool bodyTruncated = false;
    int? estimatedBodySize;

    if (bodyElement != null) {
      body = bodyElement.childText('AirSyncBase', 'Data');
      bodyTypeVal = int.tryParse(
            bodyElement.childText('AirSyncBase', 'Type') ?? '',
          ) ??
          1;
      bodyTruncated =
          bodyElement.childText('AirSyncBase', 'Truncated') == '1';
      estimatedBodySize = int.tryParse(
        bodyElement.childText('AirSyncBase', 'EstimatedDataSize') ?? '',
      );
    }

    // Attachments
    final attachmentsElement = data.findChild('AirSyncBase', 'Attachments');
    final attachments = <EasAttachment>[];
    if (attachmentsElement != null) {
      for (final att
          in attachmentsElement.findChildren('AirSyncBase', 'Attachment')) {
        attachments.add(EasAttachment(
          displayName: att.childText('AirSyncBase', 'DisplayName') ?? '',
          fileReference: att.childText('AirSyncBase', 'FileReference') ?? '',
          method: int.tryParse(
                att.childText('AirSyncBase', 'Method') ?? '',
              ) ??
              1,
          contentId: att.childText('AirSyncBase', 'ContentId'),
          isInline: att.childText('AirSyncBase', 'IsInline') == '1',
          contentType: att.childText('AirSyncBase', 'ContentType'),
        ));
      }
    }

    // Flag
    final flagElement = data.findChild('Email', 'Flag');
    int flagStatus = 0;
    if (flagElement != null) {
      flagStatus = int.tryParse(
            flagElement.childText('Email', 'FlagStatus') ?? '',
          ) ??
          0;
    }

    // Email2 fields
    final conversationId = data.childText('Email2', 'ConversationId');
    final isDraft = data.childText('Email2', 'IsDraft') == '1';
    final bcc = data.childText('Email2', 'Bcc');

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
    );
  }
}
