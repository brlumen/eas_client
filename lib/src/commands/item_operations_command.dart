/// ItemOperations command — fetch items, attachments, search results and
/// document library items; empty folders; move conversations. Several
/// operations can be batched in one request.
///
/// Reference: MS-ASCMD section 2.2.1.10, MS-ASDOC, MS-ASRM
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/eas_body.dart';
import '../models/eas_document_library_item.dart';
import '../models/eas_rights_management_license.dart';
import '../transport/eas_http_client.dart';
import '../transport/eas_multipart.dart';
import '../wbxml/wbxml_document.dart';
import 'content_item_parser.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'ItemOperations';

/// ItemOperations status codes (MS-ASCMD 2.2.3.177.8). Codes 155/156 are
/// reported as global statuses.
enum ItemOperationsStatus {
  success(1, 'Success'),
  protocolError(2, 'Protocol error - protocol violation/XML validation'),
  serverError(3, 'Server error'),
  badUri(4, 'Document library access - the specified URI is bad'),
  accessDenied(5, 'Document library - access denied'),
  notFound(6, 'Document library - object not found or access denied'),
  connectionFailed(7, 'Document library - failed to connect to the server'),
  invalidRange(8, 'The byte-range is invalid or too large'),
  unknownStore(9, 'The store is unknown or unsupported'),
  emptyFile(10, 'The file is empty'),
  dataTooLarge(11, 'The requested data size is too large'),
  ioFailure(12, 'Failed to download file because of I/O failure'),
  conversionFailed(14, 'Mailbox fetch provider - item conversion failed'),
  invalidAttachment(15, 'Attachment or attachment ID is invalid'),
  resourceAccessDenied(16, 'Access to the resource is denied'),
  partialSuccess(17, 'Partial success'),
  credentialsRequired(18, 'Credentials required');

  final int code;
  final String description;

  const ItemOperationsStatus(this.code, this.description);

  static ItemOperationsStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// A property requested via Fetch `Schema` (e.g. `Email:Subject`).
class EasSchemaProperty {
  final String namespace;
  final String tag;

  const EasSchemaProperty(this.namespace, this.tag);
}

/// Options of a Fetch operation (MS-ASCMD 2.2.3.125.3).
///
/// [password] is kept private and never exposed via fields or
/// `toString()`.
class ItemFetchOptions {
  /// Properties to return (PIM items only).
  final List<EasSchemaProperty> schema;

  /// Zero-based byte range (document library items and attachments).
  final int? rangeStart;
  final int? rangeEnd;

  /// Credentials for a document library item.
  final String? userName;
  final String? _password;

  /// `airsync:MIMESupport`: 0 = never, 1 = S/MIME only, 2 = all.
  final int? mimeSupport;

  /// `airsyncbase:BodyPreference` entries (up to 256).
  final List<EasBodyPreference> bodyPreferences;

  /// `airsyncbase:BodyPartPreference` (EAS 14.1+).
  final EasBodyPreference? bodyPartPreference;

  /// `rm:RightsManagementSupport` (EAS 14.1+): return IRM content in its
  /// schematized form.
  final bool? rightsManagementSupport;

  ItemFetchOptions({
    this.schema = const [],
    this.rangeStart,
    this.rangeEnd,
    this.userName,
    String? password,
    this.mimeSupport,
    this.bodyPreferences = const [],
    this.bodyPartPreference,
    this.rightsManagementSupport,
  }) : _password = password {
    if ((rangeStart == null) != (rangeEnd == null)) {
      throw ArgumentError('Specify both rangeStart and rangeEnd');
    }
    if (rangeStart != null) {
      checkRange(rangeStart!, rangeEnd!, 999999999, 'range');
    }
    if (userName != null) checkLength(userName!, 100, 'userName');
    if (password != null) {
      checkLength(password, 256, 'password', allowEmpty: true);
      if (userName == null) {
        throw ArgumentError('password requires userName', 'password');
      }
    }
    if (mimeSupport != null && (mimeSupport! < 0 || mimeSupport! > 2)) {
      throw ArgumentError.value(mimeSupport, 'mimeSupport', 'Must be 0-2');
    }
    if (bodyPreferences.length > 256) {
      throw ArgumentError.value(bodyPreferences.length, 'bodyPreferences');
    }
  }

  /// Whether only `Range` is set (valid with a FileReference).
  bool get _onlyRange =>
      _onlyDocumentOptions && userName == null && _password == null;

  /// Whether only `Range`/`UserName`/`Password` are set — the options
  /// valid for a document library item (MS-ASCMD 2.2.3.125.3: Schema and
  /// body preferences are not supported for document library items).
  bool get _onlyDocumentOptions =>
      schema.isEmpty &&
      mimeSupport == null &&
      bodyPreferences.isEmpty &&
      bodyPartPreference == null &&
      rightsManagementSupport == null;

  WbxmlElement toElement() => xEl(_ns, 'Options', [
    if (schema.isNotEmpty)
      xEl(_ns, 'Schema', [for (final p in schema) xEl(p.namespace, p.tag)]),
    if (rangeStart != null) xText(_ns, 'Range', '$rangeStart-$rangeEnd'),
    if (userName != null) xText(_ns, 'UserName', userName!),
    if (_password != null) xText(_ns, 'Password', _password),
    if (mimeSupport != null) xText('AirSync', 'MIMESupport', mimeSupport!),
    for (final p in bodyPreferences) p.toBodyPreference(),
    if (bodyPartPreference != null) bodyPartPreference!.toBodyPartPreference(),
    if (rightsManagementSupport != null)
      xText(
        'RightsManagement',
        'RightsManagementSupport',
        rightsManagementSupport! ? '1' : '0',
      ),
  ]);

  @override
  String toString() => 'ItemFetchOptions(...)';
}

/// One operation of an ItemOperations request.
sealed class ItemOperation {
  const ItemOperation();

  WbxmlElement toElement();
}

/// Fetch an item, attachment, Search result or document.
class ItemFetch extends ItemOperation {
  /// `Mailbox` or `DocumentLibrary`.
  final String store;
  final String? collectionId;
  final String? serverId;
  final String? longId;
  final String? linkId;
  final String? fileReference;
  final ItemFetchOptions? options;

  /// Fetch an IRM-protected message without protection
  /// (`rm:RemoveRightsManagementProtection`, EAS 14.1+).
  final bool removeRightsManagementProtection;

  ItemFetch._({
    required this.store,
    this.collectionId,
    this.serverId,
    this.longId,
    this.linkId,
    this.fileReference,
    this.options,
    this.removeRightsManagementProtection = false,
  }) {
    if (collectionId != null) checkLength(collectionId!, 64, 'collectionId');
    if (serverId != null) checkLength(serverId!, 64, 'serverId');
    if (longId != null) checkLength(longId!, 256, 'longId');
    if (fileReference != null && options != null && !options!._onlyRange) {
      throw ArgumentError(
        'Range is the only valid option with a FileReference '
        '(MS-ASCMD 2.2.3.125.3)',
      );
    }
    if (store == 'DocumentLibrary') {
      if (linkId == null) throw ArgumentError('linkId is required', 'linkId');
      validateDocumentLinkId(linkId!);
      if (options != null && !options!._onlyDocumentOptions) {
        throw ArgumentError(
          'Only Range, UserName and Password are valid options for a '
              'document library item (MS-ASCMD 2.2.3.125.3)',
          'options',
        );
      }
      if (removeRightsManagementProtection) {
        throw ArgumentError(
          'Not applicable to a document library item',
          'removeRightsManagementProtection',
        );
      }
    } else if (linkId != null) {
      throw ArgumentError('linkId requires Store=DocumentLibrary', 'linkId');
    }
  }

  /// Mailbox item by [collectionId] + [serverId].
  ItemFetch.item({
    required String collectionId,
    required String serverId,
    ItemFetchOptions? options,
    bool removeRightsManagementProtection = false,
  }) : this._(
         store: 'Mailbox',
         collectionId: collectionId,
         serverId: serverId,
         options: options,
         removeRightsManagementProtection: removeRightsManagementProtection,
       );

  /// Search result by [longId].
  ItemFetch.longId(
    String longId, {
    ItemFetchOptions? options,
    bool removeRightsManagementProtection = false,
  }) : this._(
         store: 'Mailbox',
         longId: longId,
         options: options,
         removeRightsManagementProtection: removeRightsManagementProtection,
       );

  /// Attachment by `airsyncbase:FileReference` (optional byte range).
  ItemFetch.attachment(String fileReference, {int? rangeStart, int? rangeEnd})
    : this._(
        store: 'Mailbox',
        fileReference: fileReference,
        options: rangeStart == null && rangeEnd == null
            ? null
            : ItemFetchOptions(rangeStart: rangeStart, rangeEnd: rangeEnd),
      );

  /// Document library item by [linkId] (MS-ASDOC 3.1.5.1): a UNC path or
  /// http(s) URL (see [validateDocumentLinkId]). Valid [options]: byte
  /// range and credentials only.
  ItemFetch.document(String linkId, {ItemFetchOptions? options})
    : this._(store: 'DocumentLibrary', linkId: linkId, options: options);

  @override
  WbxmlElement toElement() => xEl(_ns, 'Fetch', [
    xText(_ns, 'Store', store),
    if (collectionId != null) xText('AirSync', 'CollectionId', collectionId!),
    if (serverId != null) xText('AirSync', 'ServerId', serverId!),
    if (longId != null) xText('Search', 'LongId', longId!),
    if (linkId != null) xText('DocumentLibrary', 'LinkId', linkId!),
    if (fileReference != null)
      xText('AirSyncBase', 'FileReference', fileReference!),
    if (options != null) options!.toElement(),
    if (removeRightsManagementProtection)
      xEl('RightsManagement', 'RemoveRightsManagementProtection'),
  ]);
}

/// Delete all items of a folder (`EmptyFolderContents`).
class ItemEmptyFolderContents extends ItemOperation {
  final String collectionId;

  /// Also delete subfolders (`DeleteSubFolders`).
  final bool deleteSubFolders;

  ItemEmptyFolderContents(this.collectionId, {this.deleteSubFolders = false}) {
    checkLength(collectionId, 64, 'collectionId');
  }

  @override
  WbxmlElement toElement() => xEl(_ns, 'EmptyFolderContents', [
    xText('AirSync', 'CollectionId', collectionId),
    if (deleteSubFolders) xEl(_ns, 'Options', [xEl(_ns, 'DeleteSubFolders')]),
  ]);
}

/// Move a conversation (`Move`, EAS 14.0+).
class ItemMoveConversation extends ItemOperation {
  /// Conversation ID as raw bytes (`Email2:ConversationId`).
  final Uint8List conversationId;
  final String dstFolderId;

  /// `MoveAlways`: also move future messages. The server returns status
  /// 155 when it is missing (MS-ASCMD 2.2.3.118), so it defaults to true.
  final bool moveAlways;

  ItemMoveConversation({
    required this.conversationId,
    required this.dstFolderId,
    this.moveAlways = true,
  }) {
    checkLength(dstFolderId, 64, 'dstFolderId');
  }

  @override
  WbxmlElement toElement() => xEl(_ns, 'Move', [
    xOpaque(_ns, 'ConversationId', conversationId),
    xText(_ns, 'DstFldId', dstFolderId),
    if (moveAlways) xEl(_ns, 'Options', [xEl(_ns, 'MoveAlways')]),
  ]);
}

/// Result of a Fetch operation.
class ItemOperationsResult {
  final int status;

  /// Body data (inline or resolved multipart part, decoded as UTF-8).
  final String? body;

  /// Body type of [body].
  final int? bodyType;

  /// Binary data: attachment/document content (inline or multipart).
  final Uint8List? data;

  final String? collectionId;
  final String? serverId;
  final String? longId;
  final String? linkId;
  final String? fileReference;

  /// Content class (`airsync:Class`).
  final String? className;

  /// Returned byte range `m-n` (authoritative) and total size in bytes.
  final String? range;
  final int? total;

  /// [range] parsed into zero-based inclusive byte offsets.
  ({int start, int end})? get byteRange {
    final m = RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$').firstMatch(range ?? '');
    final start = int.tryParse(m?[1] ?? '');
    final end = int.tryParse(m?[2] ?? '');
    return start == null || end == null ? null : (start: start, end: end);
  }

  /// Last modification time of a document library item (`Version`).
  final DateTime? version;

  /// Full `airsyncbase:Body` metadata (truncation, size, preview).
  final EasBody? bodyInfo;

  /// `airsyncbase:BodyPart` (EAS 14.1+).
  final EasBodyPart? bodyPart;
  final int? nativeBodyType;
  final String? contentType;

  /// IRM license (EAS 14.1+).
  final EasRightsManagementLicense? rightsManagementLicense;

  /// Raw `Properties` element (content-class properties, attachments).
  final WbxmlElement? properties;

  const ItemOperationsResult({
    required this.status,
    this.body,
    this.bodyType,
    this.data,
    this.collectionId,
    this.serverId,
    this.longId,
    this.linkId,
    this.fileReference,
    this.className,
    this.range,
    this.total,
    this.version,
    this.bodyInfo,
    this.bodyPart,
    this.nativeBodyType,
    this.contentType,
    this.rightsManagementLicense,
    this.properties,
  });

  bool get isSuccess => status == 1;

  /// Typed [status], `null` if unknown.
  ItemOperationsStatus? get statusInfo => ItemOperationsStatus.fromCode(status);

  /// Typed item for [className] ([EasEmail], [EasCalendarEvent],
  /// [EasContact], [EasTask], [EasNote]), parsed from [properties].
  Object? get item =>
      parseContentItem(className, serverId ?? longId ?? '', properties);

  /// Parse a response `Fetch` element. Inline data is taken from `Data`;
  /// multipart data is resolved from `Part` references via [multipart].
  factory ItemOperationsResult.fromFetch(
    WbxmlElement fetch, [
    EasMultipartResponse? multipart,
  ]) {
    Uint8List? resolve(WbxmlElement parent) {
      final part = parent.childText(_ns, 'Part');
      if (part == null) return null;
      if (multipart == null) {
        throw EasCommandException(
          command: 'ItemOperations',
          message: 'Part reference in a non-multipart response',
        );
      }
      return multipart.partAt(part);
    }

    final props = fetch.findChild(_ns, 'Properties');
    final bodyEl = props?.findChild('AirSyncBase', 'Body');
    String? body = bodyEl?.childText('AirSyncBase', 'Data');
    if (bodyEl != null) {
      final part = resolve(bodyEl);
      if (part != null) body = utf8.decode(part, allowMalformed: true);
    }
    final bodyPartEl = props?.findChild('AirSyncBase', 'BodyPart');
    final dataEl = props?.findChild(_ns, 'Data');

    return ItemOperationsResult(
      status: xStatus(fetch, _ns),
      collectionId: fetch.childText('AirSync', 'CollectionId'),
      serverId: fetch.childText('AirSync', 'ServerId'),
      longId: fetch.childText('Search', 'LongId'),
      className: fetch.childText('AirSync', 'Class'),
      linkId: fetch.childText('DocumentLibrary', 'LinkId'),
      fileReference: fetch.childText('AirSyncBase', 'FileReference'),
      body: body,
      bodyType: bodyEl == null
          ? null
          : int.tryParse(bodyEl.childText('AirSyncBase', 'Type') ?? ''),
      bodyInfo: bodyEl == null ? null : EasBody.fromElement(bodyEl),
      bodyPart: bodyPartEl == null ? null : EasBodyPart.fromElement(bodyPartEl),
      data:
          dataEl?.opaque ??
          (dataEl?.text == null ? null : _base64OrNull(dataEl!.text!)) ??
          (props == null ? null : resolve(props)),
      range: props?.childText(_ns, 'Range'),
      total: int.tryParse(props?.childText(_ns, 'Total') ?? ''),
      version: DateTime.tryParse(props?.childText(_ns, 'Version') ?? ''),
      nativeBodyType: int.tryParse(
        props?.childText('AirSyncBase', 'NativeBodyType') ?? '',
      ),
      contentType: props?.childText('AirSyncBase', 'ContentType'),
      rightsManagementLicense: props == null
          ? null
          : EasRightsManagementLicense.of(props),
      properties: props,
    );
  }

  /// Inline `Data` is base64-encoded text when not sent as opaque.
  static Uint8List? _base64OrNull(String text) {
    try {
      return base64.decode(text.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      return Uint8List.fromList(utf8.encode(text));
    }
  }
}

/// Result of an ItemOperations Move (conversation move).
class ConversationMoveResult {
  final int status;

  /// Conversation ID echoed by the server (raw bytes).
  final Uint8List? conversationId;

  /// Whether the move succeeded (status 1).
  bool get isSuccess => status == 1;

  const ConversationMoveResult({required this.status, this.conversationId});
}

/// Result of an `EmptyFolderContents` operation.
class EmptyFolderContentsResult {
  final int status;
  final String? collectionId;

  bool get isSuccess => status == 1;

  const EmptyFolderContentsResult({required this.status, this.collectionId});
}

/// Parsed ItemOperations response.
class ItemOperationsResponse {
  /// Overall status (`ItemOperations/Status`).
  final int status;
  final List<ItemOperationsResult> fetches;
  final List<EmptyFolderContentsResult> emptyFolderContents;
  final List<ConversationMoveResult> moves;

  const ItemOperationsResponse({
    required this.status,
    this.fetches = const [],
    this.emptyFolderContents = const [],
    this.moves = const [],
  });

  bool get isSuccess => status == 1;
}

/// Generic ItemOperations with any mix of [operations].
///
/// When [acceptMultiPart] is set, binary content is returned as separate
/// parts of an `application/vnd.ms-sync.multipart` response.
class ItemOperationsCommand extends EasCommand<ItemOperationsResponse> {
  final List<ItemOperation> operations;

  @override
  final bool acceptMultiPart;

  ItemOperationsCommand(this.operations, {this.acceptMultiPart = false}) {
    if (operations.isEmpty) {
      throw ArgumentError.value(0, 'operations', 'Must not be empty');
    }
  }

  @override
  String get commandName => 'ItemOperations';

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'ItemOperations', [
      for (final op in operations) op.toElement(),
    ]),
  );

  /// Multipart body of the response being parsed (set only during
  /// [parseHttpResponse]).
  EasMultipartResponse? _multipart;

  @override
  ItemOperationsResponse parseResponse(WbxmlDocument response) {
    final root = response.root;
    final resp = root.findChild(_ns, 'Response');
    return ItemOperationsResponse(
      status: xStatus(root, _ns),
      fetches: [
        for (final f in resp?.findChildren(_ns, 'Fetch') ?? <WbxmlElement>[])
          ItemOperationsResult.fromFetch(f, _multipart),
      ],
      emptyFolderContents: [
        for (final e
            in resp?.findChildren(_ns, 'EmptyFolderContents') ??
                <WbxmlElement>[])
          EmptyFolderContentsResult(
            status: xStatus(e, _ns),
            collectionId: e.childText('AirSync', 'CollectionId'),
          ),
      ],
      moves: [
        for (final m in resp?.findChildren(_ns, 'Move') ?? <WbxmlElement>[])
          ConversationMoveResult(
            status: xStatus(m, _ns),
            conversationId: _conversationId(m),
          ),
      ],
    );
  }

  static Uint8List? _conversationId(WbxmlElement move) {
    final el = move.findChild(_ns, 'ConversationId');
    if (el?.opaque != null) return el!.opaque;
    final text = el?.text;
    return text == null ? null : Uint8List.fromList(utf8.encode(text));
  }

  @override
  ItemOperationsResponse parseHttpResponse(EasResponse response) {
    if (!EasMultipartResponse.isMultipart(response.contentType)) {
      return super.parseHttpResponse(response);
    }
    // Part 0 is the WBXML document; decode it via the base class so that
    // global status handling still applies.
    final multipart = _multipart = EasMultipartResponse.parse(response.body);
    try {
      return super.parseHttpResponse(
        EasResponse(
          statusCode: response.statusCode,
          headers: response.headers,
          body: multipart.parts.first,
        ),
      );
    } finally {
      _multipart = null;
    }
  }
}

/// Base class for single-item ItemOperations Fetch commands.
abstract class ItemOperationsFetchCommand
    extends EasCommand<ItemOperationsResult> {
  late final ItemOperationsCommand _inner = ItemOperationsCommand([
    buildFetch(),
  ], acceptMultiPart: acceptMultiPart);

  /// Request a multipart response (MS-ASCMD 2.2.1.10.1).
  @override
  final bool acceptMultiPart;

  ItemOperationsFetchCommand({this.acceptMultiPart = false});

  /// The single Fetch operation.
  ItemFetch buildFetch();

  @override
  String get commandName => 'ItemOperations';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  ItemOperationsResult _first(ItemOperationsResponse r) =>
      r.fetches.firstOrNull ?? ItemOperationsResult(status: r.status);

  @override
  ItemOperationsResult parseResponse(WbxmlDocument response) =>
      _first(_inner.parseResponse(response));

  @override
  ItemOperationsResult parseHttpResponse(EasResponse response) =>
      _first(_inner.parseHttpResponse(response));
}

/// Fetch an email (or other mailbox item) by ServerId.
class FetchEmailBodyCommand extends ItemOperationsFetchCommand {
  final String serverId;
  final String collectionId;
  final int bodyType;

  /// Full options; when set, [bodyType] is ignored.
  final ItemFetchOptions? options;
  final bool removeRightsManagementProtection;

  FetchEmailBodyCommand({
    required this.serverId,
    required this.collectionId,
    this.bodyType = 2, // HTML
    this.options,
    this.removeRightsManagementProtection = false,
    super.acceptMultiPart,
  });

  @override
  ItemFetch buildFetch() => ItemFetch.item(
    collectionId: collectionId,
    serverId: serverId,
    options:
        options ??
        ItemFetchOptions(bodyPreferences: [EasBodyPreference(type: bodyType)]),
    removeRightsManagementProtection: removeRightsManagementProtection,
  );
}

/// Fetch a Search result item by its LongId (MS-ASCMD 2.2.3.98.3).
class FetchByLongIdCommand extends ItemOperationsFetchCommand {
  final String longId;
  final int bodyType;

  /// Full options; when set, [bodyType] is ignored.
  final ItemFetchOptions? options;
  final bool removeRightsManagementProtection;

  FetchByLongIdCommand({
    required this.longId,
    this.bodyType = 2,
    this.options,
    this.removeRightsManagementProtection = false,
    super.acceptMultiPart,
  });

  @override
  ItemFetch buildFetch() => ItemFetch.longId(
    longId,
    options:
        options ??
        ItemFetchOptions(bodyPreferences: [EasBodyPreference(type: bodyType)]),
    removeRightsManagementProtection: removeRightsManagementProtection,
  );
}

/// Fetch attachment by FileReference (optionally a byte range).
class FetchAttachmentCommand extends ItemOperationsFetchCommand {
  final String fileReference;
  final int? rangeStart;
  final int? rangeEnd;

  FetchAttachmentCommand({
    required this.fileReference,
    this.rangeStart,
    this.rangeEnd,
    super.acceptMultiPart,
  });

  @override
  ItemFetch buildFetch() => ItemFetch.attachment(
    fileReference,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
  );
}

/// Fetch a document from a Windows SharePoint Services / UNC library by
/// its LinkId (MS-ASDOC 3.1.4.3). The content is returned in
/// [ItemOperationsResult.data] (inline base64 or, with [acceptMultiPart],
/// a binary part), with [ItemOperationsResult.range],
/// [ItemOperationsResult.total] and [ItemOperationsResult.version].
///
/// Optional [userName]/password are sent in `Options`; the password is
/// kept private and never exposed via fields or `toString()`. The LinkId
/// and options are validated on construction.
class FetchDocumentCommand extends ItemOperationsFetchCommand {
  final ItemFetch _fetch;

  FetchDocumentCommand({
    required String linkId,
    String? userName,
    String? password,
    int? rangeStart,
    int? rangeEnd,
    super.acceptMultiPart,
  }) : _fetch = ItemFetch.document(
         linkId,
         options:
             userName == null &&
                 password == null &&
                 rangeStart == null &&
                 rangeEnd == null
             ? null
             : ItemFetchOptions(
                 userName: userName,
                 password: password,
                 rangeStart: rangeStart,
                 rangeEnd: rangeEnd,
               ),
       );

  String get linkId => _fetch.linkId!;

  @override
  ItemFetch buildFetch() => _fetch;
}

/// Move all items of a conversation to another folder (EAS 14.0+).
///
/// Reference: MS-ASCMD section 2.2.3.117.1
class MoveConversationCommand extends EasCommand<ConversationMoveResult> {
  late final ItemOperationsCommand _inner = ItemOperationsCommand([
    ItemMoveConversation(
      conversationId: conversationId,
      dstFolderId: dstFolderId,
      moveAlways: moveAlways,
    ),
  ]);

  /// Conversation ID as raw bytes (`Email2:ConversationId`).
  final Uint8List conversationId;
  final String dstFolderId;

  /// See [ItemMoveConversation.moveAlways].
  final bool moveAlways;

  MoveConversationCommand({
    required this.conversationId,
    required this.dstFolderId,
    this.moveAlways = true,
  });

  @override
  String get commandName => 'ItemOperations';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  @override
  ConversationMoveResult parseResponse(WbxmlDocument response) {
    final r = _inner.parseResponse(response);
    return r.moves.firstOrNull ?? ConversationMoveResult(status: r.status);
  }
}

/// Empty the contents of a folder (delete all items).
///
/// [deleteSubFolders] — if true, also deletes sub-folders within the folder.
///
/// Reference: MS-ASCMD section 2.2.3.58
class EmptyFolderCommand extends EasCommand<int> {
  late final ItemOperationsCommand _inner = ItemOperationsCommand([
    ItemEmptyFolderContents(folderId, deleteSubFolders: deleteSubFolders),
  ]);

  final String folderId;
  final bool deleteSubFolders;

  EmptyFolderCommand({required this.folderId, this.deleteSubFolders = false});

  @override
  String get commandName => 'ItemOperations';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  @override
  int parseResponse(WbxmlDocument response) {
    final r = _inner.parseResponse(response);
    return r.emptyFolderContents.firstOrNull?.status ?? r.status;
  }
}

/// Batch fetch multiple email bodies in a single ItemOperations request.
class BatchFetchEmailBodiesCommand
    extends EasCommand<List<ItemOperationsResult>> {
  late final ItemOperationsCommand _inner = ItemOperationsCommand([
    for (final item in items)
      ItemFetch.item(
        collectionId: item.collectionId,
        serverId: item.serverId,
        options:
            options ??
            ItemFetchOptions(
              bodyPreferences: [EasBodyPreference(type: bodyType)],
            ),
      ),
  ], acceptMultiPart: acceptMultiPart);

  /// List of (serverId, collectionId) pairs to fetch.
  final List<({String serverId, String collectionId})> items;
  final int bodyType;

  /// Full options; when set, [bodyType] is ignored.
  final ItemFetchOptions? options;

  @override
  final bool acceptMultiPart;

  BatchFetchEmailBodiesCommand({
    required this.items,
    this.bodyType = 2,
    this.options,
    this.acceptMultiPart = false,
  });

  @override
  String get commandName => 'ItemOperations';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  @override
  List<ItemOperationsResult> parseResponse(WbxmlDocument response) =>
      _inner.parseResponse(response).fetches;

  @override
  List<ItemOperationsResult> parseHttpResponse(EasResponse response) =>
      _inner.parseHttpResponse(response).fetches;
}
