/// Search command — server-side search (Mailbox, GAL and DocumentLibrary).
///
/// Reference: MS-ASCMD section 2.2.1.16, MS-ASDOC
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/eas_body.dart';
import '../models/eas_document_library_item.dart';
import '../models/eas_email.dart';
import '../models/eas_rights_management_license.dart';
import '../models/wbxml_helpers.dart' show isoDateTime;
import '../wbxml/wbxml_document.dart';
import 'content_item_parser.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'Search';

/// `Store/Status` codes of a Search response (MS-ASCMD 2.2.3.177.13).
enum SearchStatus {
  success(1, 'Success'),
  invalidRequest(2, 'One or more search parameters was invalid'),
  serverError(3, 'An error occurred on the server'),
  badLink(4, 'A bad link was supplied'),
  accessDenied(5, 'Access was denied to the resource'),
  notFound(6, 'Resource was not found'),
  connectionFailed(7, 'Failed to connect to the resource'),
  tooComplex(8, 'The query was too complex'),
  timedOut(10, 'The search timed out'),
  folderSyncRequired(11, 'Folder hierarchy is out of date'),
  endOfRange(12, 'The requested range is past the retrievable results'),
  accessBlocked(13, 'Access is blocked to the specified resource'),
  credentialsRequired(14, 'Basic credentials are required');

  final int code;
  final String description;

  const SearchStatus(this.code, this.description);

  static SearchStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

// ─── Query ──────────────────────────────────────────────────────────────────

/// A node of a Search `Query` (MS-ASCMD 2.2.3.142.2).
sealed class SearchQuery {
  const SearchQuery();

  WbxmlElement toElement();
}

/// `And` of [children].
class SearchAnd extends SearchQuery {
  final List<SearchQuery> children;
  const SearchAnd(this.children);

  @override
  WbxmlElement toElement() =>
      xEl(_ns, 'And', [for (final c in children) c.toElement()]);
}

/// `Or` of [children].
class SearchOr extends SearchQuery {
  final List<SearchQuery> children;
  const SearchOr(this.children);

  @override
  WbxmlElement toElement() =>
      xEl(_ns, 'Or', [for (final c in children) c.toElement()]);
}

/// `FreeText` keywords (GAL: prefix match on ANR properties).
class SearchFreeText extends SearchQuery {
  final String text;
  const SearchFreeText(this.text);

  @override
  WbxmlElement toElement() => xText(_ns, 'FreeText', text);
}

/// `airsync:Class` restriction (Email, Calendar, Contacts, Tasks, Notes,
/// SMS).
class SearchClass extends SearchQuery {
  final String className;
  const SearchClass(this.className);

  @override
  WbxmlElement toElement() => xText('AirSync', 'Class', className);
}

/// `airsync:CollectionId` restriction (folder).
class SearchCollectionId extends SearchQuery {
  final String collectionId;
  const SearchCollectionId(this.collectionId);

  @override
  WbxmlElement toElement() => xText('AirSync', 'CollectionId', collectionId);
}

/// `ConversationId` restriction (GUID, EAS 14.0+; only inside [SearchAnd]).
class SearchConversationId extends SearchQuery {
  final String conversationId;
  const SearchConversationId(this.conversationId);

  @override
  WbxmlElement toElement() => xText(_ns, 'ConversationId', conversationId);
}

/// `EqualTo` on `documentlibrary:LinkId` — the only query supported by a
/// document library search (MS-ASDOC 3.1.5.2, MS-ASCMD 2.2.3.62). [linkId]
/// is a UNC path or http(s) URL (see [validateDocumentLinkId]).
class SearchLinkIdEqualTo extends SearchQuery {
  final String linkId;

  SearchLinkIdEqualTo(this.linkId) {
    validateDocumentLinkId(linkId);
  }

  @override
  WbxmlElement toElement() => xEl(_ns, 'EqualTo', [
    xEl('DocumentLibrary', 'LinkId'),
    xText(_ns, 'Value', linkId),
  ]);
}

/// `GreaterThan` on `email:DateReceived`.
class SearchReceivedAfter extends SearchQuery {
  final DateTime date;
  const SearchReceivedAfter(this.date);

  @override
  WbxmlElement toElement() => xEl(_ns, 'GreaterThan', [
    xEl('Email', 'DateReceived'),
    xText(_ns, 'Value', isoDateTime(date)),
  ]);
}

/// `LessThan` on `email:DateReceived`.
class SearchReceivedBefore extends SearchQuery {
  final DateTime date;
  const SearchReceivedBefore(this.date);

  @override
  WbxmlElement toElement() => xEl(_ns, 'LessThan', [
    xEl('Email', 'DateReceived'),
    xText(_ns, 'Value', isoDateTime(date)),
  ]);
}

// ─── Options ────────────────────────────────────────────────────────────────

/// Search `Options` (MS-ASCMD 2.2.3.125.5). Valid options depend on the
/// store: GAL — range, credentials, picture; Mailbox — range,
/// deepTraversal, rebuildResults, body preferences, IRM, MIME;
/// DocumentLibrary — range, credentials.
///
/// [password] is kept private and never exposed via fields or
/// `toString()`. Credentials MUST only be sent after a Store status 14.
class SearchOptions {
  final int? rangeStart;
  final int? rangeEnd;
  final bool deepTraversal;
  final bool rebuildResults;

  /// `airsync:MIMESupport`: 0 = never, 1 = S/MIME only, 2 = all.
  final int? mimeSupport;
  final List<EasBodyPreference> bodyPreferences;

  /// Only valid with a [SearchConversationId] query (EAS 14.1+).
  final EasBodyPreference? bodyPartPreference;
  final bool? rightsManagementSupport;
  final String? userName;
  final String? _password;

  /// Request contact photos (GAL, EAS 14.1+).
  final bool picture;
  final int? pictureMaxSize;
  final int? maxPictures;

  SearchOptions({
    this.rangeStart,
    this.rangeEnd,
    this.deepTraversal = false,
    this.rebuildResults = false,
    this.mimeSupport,
    this.bodyPreferences = const [],
    this.bodyPartPreference,
    this.rightsManagementSupport,
    this.userName,
    String? password,
    this.picture = false,
    this.pictureMaxSize,
    this.maxPictures,
  }) : _password = password {
    if ((rangeStart == null) != (rangeEnd == null)) {
      throw ArgumentError('Specify both rangeStart and rangeEnd');
    }
    if (rangeStart != null) checkRange(rangeStart!, rangeEnd!, 999, 'range');
    if (userName != null) checkLength(userName!, 100, 'userName');
    if (password != null) {
      checkLength(password, 100, 'password', allowEmpty: true);
      if (userName == null) {
        throw ArgumentError('password requires userName', 'password');
      }
    }
    if (mimeSupport != null && (mimeSupport! < 0 || mimeSupport! > 2)) {
      throw ArgumentError.value(mimeSupport, 'mimeSupport', 'Must be 0-2');
    }
  }

  bool get isEmpty =>
      rangeStart == null &&
      !deepTraversal &&
      !rebuildResults &&
      mimeSupport == null &&
      bodyPreferences.isEmpty &&
      bodyPartPreference == null &&
      rightsManagementSupport == null &&
      userName == null &&
      _password == null &&
      !picture;

  /// Whether only `Range`/`UserName`/`Password` are set — the options
  /// valid for a DocumentLibrary store (MS-ASCMD 2.2.3.125.5).
  bool get _onlyDocumentOptions =>
      !deepTraversal &&
      !rebuildResults &&
      mimeSupport == null &&
      bodyPreferences.isEmpty &&
      bodyPartPreference == null &&
      rightsManagementSupport == null &&
      !picture;

  WbxmlElement toElement() => xEl(_ns, 'Options', [
    if (mimeSupport != null) xText('AirSync', 'MIMESupport', mimeSupport!),
    for (final p in bodyPreferences) p.toBodyPreference(),
    if (bodyPartPreference != null) bodyPartPreference!.toBodyPartPreference(),
    if (rightsManagementSupport != null)
      xText(
        'RightsManagement',
        'RightsManagementSupport',
        rightsManagementSupport! ? '1' : '0',
      ),
    if (rangeStart != null) xText(_ns, 'Range', '$rangeStart-$rangeEnd'),
    if (userName != null) xText(_ns, 'UserName', userName!),
    if (_password != null) xText(_ns, 'Password', _password),
    if (deepTraversal) xEl(_ns, 'DeepTraversal'),
    if (rebuildResults) xEl(_ns, 'RebuildResults'),
    if (picture)
      xEl(_ns, 'Picture', [
        if (pictureMaxSize != null) xText(_ns, 'MaxSize', pictureMaxSize!),
        if (maxPictures != null) xText(_ns, 'MaxPictures', maxPictures!),
      ]),
  ]);

  @override
  String toString() => 'SearchOptions(...)';
}

// ─── Results ────────────────────────────────────────────────────────────────

/// Contact photo of a GAL result (`gal:Picture`, EAS 14.1+).
class GalPicture {
  /// 1 = success, 173 = no photo, 174 = too large, 175 = limit reached.
  final int status;

  /// Photo bytes (decoded from base64), if returned.
  final Uint8List? data;

  const GalPicture({required this.status, this.data});

  static GalPicture? of(WbxmlElement props) {
    final el = props.findChild('GAL', 'Picture');
    if (el == null) return null;
    final text = el.childText('GAL', 'Data');
    Uint8List? data = el.findChild('GAL', 'Data')?.opaque;
    if (data == null && text != null) {
      try {
        data = base64.decode(text.replaceAll(RegExp(r'\s'), ''));
      } on FormatException {
        data = null;
      }
    }
    return GalPicture(status: xStatus(el, 'GAL'), data: data);
  }
}

/// A GAL (Global Address List) entry.
class GalEntry {
  final String? displayName;
  final String? emailAddress;
  final String? phone;
  final String? office;
  final String? title;
  final String? company;
  final String? alias;
  final String? firstName;
  final String? lastName;
  final String? homePhone;
  final String? mobilePhone;
  final GalPicture? picture;

  const GalEntry({
    this.displayName,
    this.emailAddress,
    this.phone,
    this.office,
    this.title,
    this.company,
    this.alias,
    this.firstName,
    this.lastName,
    this.homePhone,
    this.mobilePhone,
    this.picture,
  });

  /// Parse `gal:*` properties.
  factory GalEntry.fromProperties(WbxmlElement props) {
    String? t(String tag) => props.childText('GAL', tag);
    return GalEntry(
      displayName: t('DisplayName'),
      emailAddress: t('EmailAddress'),
      phone: t('Phone'),
      office: t('Office'),
      title: t('Title'),
      company: t('Company'),
      alias: t('Alias'),
      firstName: t('FirstName'),
      lastName: t('LastName'),
      homePhone: t('HomePhone'),
      mobilePhone: t('MobilePhone'),
      picture: GalPicture.of(props),
    );
  }

  @override
  String toString() => 'GalEntry(...)';
}

/// Individual search result item.
class SearchResultItem {
  final String? longId;
  final String? collectionId;

  /// Content class (`airsync:Class`).
  final String? className;

  /// Email properties (Email/SMS results).
  final EasEmail? email;

  /// Typed item for [className] (see [parseContentItem]).
  final Object? item;

  /// Body metadata / IRM license of the result.
  final EasBody? body;
  final EasRightsManagementLicense? rightsManagementLicense;

  /// Raw `Properties` element.
  final WbxmlElement? properties;

  const SearchResultItem({
    this.longId,
    this.collectionId,
    this.className,
    this.email,
    this.item,
    this.body,
    this.rightsManagementLicense,
    this.properties,
  });
}

/// Parsed `Response/Store` of a Search response.
class SearchStoreResponse {
  /// `Search/Status`: 1 = success, 3 = server error.
  final int searchStatus;

  /// `Store/Status` (see [SearchStatus]); equals [searchStatus] when the
  /// store is absent.
  final int status;

  /// Raw `Result` elements.
  final List<WbxmlElement> results;

  /// Returned range (`m-n`) and estimated total matches.
  final String? range;
  final int total;

  const SearchStoreResponse({
    required this.searchStatus,
    required this.status,
    this.results = const [],
    this.range,
    this.total = 0,
  });

  factory SearchStoreResponse.parse(WbxmlDocument response) {
    final root = response.root;
    final searchStatus = xStatus(root, _ns);
    final store = root.findChild(_ns, 'Response')?.findChild(_ns, 'Store');
    if (store == null) {
      return SearchStoreResponse(
        searchStatus: searchStatus,
        status: searchStatus,
      );
    }
    return SearchStoreResponse(
      searchStatus: searchStatus,
      status:
          int.tryParse(store.childText(_ns, 'Status') ?? '') ?? searchStatus,
      results: store.findChildren(_ns, 'Result'),
      range: store.childText(_ns, 'Range'),
      total: int.tryParse(store.childText(_ns, 'Total') ?? '') ?? 0,
    );
  }

  SearchStatus? get statusInfo => SearchStatus.fromCode(status);
}

/// Result of a Mailbox Search.
class SearchResult {
  /// Store status (see [SearchStatus]).
  final int status;
  final List<SearchResultItem> items;
  final int total;
  final String? range;

  const SearchResult({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.range,
  });

  bool get isSuccess => status == 1;
  SearchStatus? get statusInfo => SearchStatus.fromCode(status);
}

/// Result of a GAL Search.
class GalSearchResult {
  final int status;
  final List<GalEntry> entries;
  final int total;
  final String? range;

  const GalSearchResult({
    required this.status,
    this.entries = const [],
    this.total = 0,
    this.range,
  });

  bool get isSuccess => status == 1;
  SearchStatus? get statusInfo => SearchStatus.fromCode(status);
}

/// Result of a DocumentLibrary Search. [statusInfo] covers the document
/// library statuses: bad link (4), access denied (5), not found (6),
/// connection failed (7), credentials required (14).
class DocumentLibrarySearchResult {
  final int status;
  final List<EasDocumentLibraryItem> items;
  final int total;
  final String? range;

  const DocumentLibrarySearchResult({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.range,
  });

  bool get isSuccess => status == 1;
  SearchStatus? get statusInfo => SearchStatus.fromCode(status);
}

// ─── Commands ───────────────────────────────────────────────────────────────

/// Generic Search of any store with an arbitrary [query].
class StoreSearchCommand extends EasCommand<SearchStoreResponse> {
  /// `Mailbox`, `GAL` or `DocumentLibrary`.
  final String store;
  final SearchQuery query;
  final SearchOptions? options;

  /// For `DocumentLibrary` the [query] MUST be a [SearchLinkIdEqualTo] and
  /// only range/credential [options] are valid; [SearchLinkIdEqualTo] is
  /// rejected for other stores (MS-ASCMD 2.2.3.62, 2.2.3.125.5).
  StoreSearchCommand({required this.store, required this.query, this.options}) {
    checkLength(store, 256, 'store');
    if (store == 'DocumentLibrary') {
      if (query is! SearchLinkIdEqualTo) {
        throw ArgumentError(
          'A DocumentLibrary search requires a SearchLinkIdEqualTo query',
          'query',
        );
      }
      if (options != null && !options!._onlyDocumentOptions) {
        throw ArgumentError(
          'Only Range, UserName and Password are valid DocumentLibrary '
              'search options',
          'options',
        );
      }
    } else if (_hasLinkId(query)) {
      throw ArgumentError(
        'SearchLinkIdEqualTo requires Store=DocumentLibrary',
        'query',
      );
    }
  }

  static bool _hasLinkId(SearchQuery q) => switch (q) {
    SearchLinkIdEqualTo() => true,
    SearchAnd(:final children) ||
    SearchOr(:final children) => children.any(_hasLinkId),
    _ => false,
  };

  @override
  String get commandName => 'Search';

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'Search', [
      xEl(_ns, 'Store', [
        xText(_ns, 'Name', store),
        xEl(_ns, 'Query', [query.toElement()]),
        if (options != null && !options!.isEmpty) options!.toElement(),
      ]),
    ]),
  );

  @override
  SearchStoreResponse parseResponse(WbxmlDocument response) =>
      SearchStoreResponse.parse(response);
}

/// Mailbox search: `And(Class?, CollectionId?, FreeText,
/// GreaterThan/LessThan DateReceived?)`.
class SearchCommand extends EasCommand<SearchResult> {
  final String query;
  final String? collectionId;

  /// Content class restriction (e.g. 'Email').
  final String? className;
  final DateTime? receivedAfter;
  final DateTime? receivedBefore;

  /// Restrict to a conversation (GUID); enables [bodyPartPreference].
  final String? conversationId;
  final int rangeStart;
  final int rangeEnd;
  final bool deepTraversal;
  final int bodyType;
  final int? bodyTruncationSize;
  final bool rebuildResults;
  final int? mimeSupport;
  final EasBodyPreference? bodyPartPreference;
  final bool? rightsManagementSupport;

  /// Full body preferences; when set, [bodyType]/[bodyTruncationSize] are
  /// ignored.
  final List<EasBodyPreference>? bodyPreferences;

  SearchCommand({
    required this.query,
    this.collectionId,
    this.className,
    this.receivedAfter,
    this.receivedBefore,
    this.conversationId,
    this.rangeStart = 0,
    this.rangeEnd = 49,
    this.deepTraversal = true,
    this.bodyType = 2,
    this.bodyTruncationSize = 512,
    this.rebuildResults = false,
    this.mimeSupport,
    this.bodyPartPreference,
    this.rightsManagementSupport,
    this.bodyPreferences,
  }) {
    checkRange(rangeStart, rangeEnd, 999, 'range');
  }

  late final StoreSearchCommand _inner = StoreSearchCommand(
    store: 'Mailbox',
    query: SearchAnd([
      if (className != null) SearchClass(className!),
      if (collectionId != null) SearchCollectionId(collectionId!),
      if (conversationId != null) SearchConversationId(conversationId!),
      SearchFreeText(query),
      if (receivedAfter != null) SearchReceivedAfter(receivedAfter!),
      if (receivedBefore != null) SearchReceivedBefore(receivedBefore!),
    ]),
    options: SearchOptions(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      deepTraversal: deepTraversal,
      rebuildResults: rebuildResults,
      mimeSupport: mimeSupport,
      bodyPreferences:
          bodyPreferences ??
          [
            EasBodyPreference(
              type: bodyType,
              truncationSize: bodyTruncationSize,
            ),
          ],
      bodyPartPreference: bodyPartPreference,
      rightsManagementSupport: rightsManagementSupport,
    ),
  );

  @override
  String get commandName => 'Search';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  @override
  SearchResult parseResponse(WbxmlDocument response) {
    final store = SearchStoreResponse.parse(response);
    return SearchResult(
      status: store.status,
      total: store.total,
      range: store.range,
      items: [for (final result in store.results) _parseResult(result)],
    );
  }

  static SearchResultItem _parseResult(WbxmlElement result) {
    final longId = result.childText(_ns, 'LongId');
    final className = result.childText('AirSync', 'Class');
    final props = result.findChild(_ns, 'Properties');
    final item = parseContentItem(className ?? 'Email', longId ?? '', props);
    return SearchResultItem(
      longId: longId,
      collectionId: result.childText('AirSync', 'CollectionId'),
      className: className,
      email: item is EasEmail ? item : null,
      item: item,
      body: props == null ? null : EasBody.of(props),
      rightsManagementLicense: props == null
          ? null
          : EasRightsManagementLicense.of(props),
      properties: props,
    );
  }
}

/// Search the Global Address List (GAL).
///
/// [picture] requests contact photos (EAS 14.1+). Credentials may be
/// supplied after a Store status 14.
class GalSearchCommand extends EasCommand<GalSearchResult> {
  final String query;
  final int rangeStart;
  final int rangeEnd;
  final bool picture;
  final int? pictureMaxSize;
  final int? maxPictures;
  final String? userName;
  final String? _password;

  GalSearchCommand({
    required this.query,
    this.rangeStart = 0,
    this.rangeEnd = 99,
    this.picture = false,
    this.pictureMaxSize,
    this.maxPictures,
    this.userName,
    String? password,
  }) : _password = password {
    checkRange(rangeStart, rangeEnd, 999, 'range');
  }

  late final StoreSearchCommand _inner = StoreSearchCommand(
    store: 'GAL',
    query: SearchFreeText(query),
    options: SearchOptions(
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      picture: picture,
      pictureMaxSize: pictureMaxSize,
      maxPictures: maxPictures,
      userName: userName,
      password: _password,
    ),
  );

  @override
  String get commandName => 'Search';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  @override
  GalSearchResult parseResponse(WbxmlDocument response) {
    final store = SearchStoreResponse.parse(response);
    return GalSearchResult(
      status: store.status,
      total: store.total,
      range: store.range,
      entries: [
        for (final result in store.results)
          switch (result.findChild(_ns, 'Properties')) {
            final props? => GalEntry.fromProperties(props),
            null => const GalEntry(),
          },
      ],
    );
  }
}

/// List a SharePoint / UNC document library location, or get the metadata
/// of a single document, by LinkId (MS-ASDOC 3.1.5.2).
///
/// For a folder the first result is the folder itself, followed by its
/// contents; [rangeStart]/[rangeEnd] index this combined list (default and
/// maximum 0-999). Optional [userName]/password are sent in `Options`
/// (send them after a Store status 14); the password is kept private. The
/// LinkId and options are validated on construction.
///
/// Reference: MS-ASCMD section 2.2.1.16, MS-ASDOC
class DocumentLibrarySearchCommand
    extends EasCommand<DocumentLibrarySearchResult> {
  final String linkId;
  final int rangeStart;
  final int rangeEnd;
  final String? userName;
  final StoreSearchCommand _inner;

  DocumentLibrarySearchCommand({
    required this.linkId,
    this.rangeStart = 0,
    this.rangeEnd = 999,
    this.userName,
    String? password,
  }) : _inner = StoreSearchCommand(
         store: 'DocumentLibrary',
         query: SearchLinkIdEqualTo(linkId),
         options: SearchOptions(
           rangeStart: rangeStart,
           rangeEnd: rangeEnd,
           userName: userName,
           password: password,
         ),
       );

  @override
  String get commandName => 'Search';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  @override
  DocumentLibrarySearchResult parseResponse(WbxmlDocument response) {
    final store = SearchStoreResponse.parse(response);
    return DocumentLibrarySearchResult(
      status: store.status,
      total: store.total,
      range: store.range,
      items: [
        for (final result in store.results)
          if (result.findChild(_ns, 'Properties') case final props?)
            EasDocumentLibraryItem.fromWbxml(props),
      ],
    );
  }
}
