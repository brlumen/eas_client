/// Find command — mailbox and GAL search using KQL (EAS 16.1).
///
/// Reference: MS-ASCMD section 2.2.1.2
library;

import 'dart:math';

import '../models/eas_email.dart';
import '../wbxml/wbxml_document.dart';
import 'content_item_parser.dart';
import 'eas_command.dart';
import 'search_command.dart' show GalPicture;
import 'wbxml_builders.dart';

const _ns = 'Find';

/// Find status codes (MS-ASCMD 2.2.3.177.2).
enum FindStatus {
  success(1, 'Success'),
  invalidRequest(2, 'The request was invalid'),
  folderSyncRequired(3, 'FolderSync required'),
  startWithRangeZero(4, 'Issue a new Find request with a Range from 0');

  final int code;
  final String description;

  const FindStatus(this.code, this.description);

  static FindStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// A GAL result from the Find command.
class FindGalEntry {
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

  /// Contact photo (`gal:Picture`).
  final GalPicture? galPicture;

  const FindGalEntry({
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
    this.galPicture,
  });

  factory FindGalEntry.fromProperties(WbxmlElement props) {
    String? t(String tag) => props.childText('GAL', tag);
    return FindGalEntry(
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
      galPicture: GalPicture.of(props),
    );
  }

  @override
  String toString() => 'FindGalEntry(...)';
}

/// A mailbox result of the Find command.
class FindMailboxResult {
  final String? className;
  final String? serverId;
  final String? collectionId;

  /// Email properties (Subject, DateReceived, DisplayTo, Importance, Read,
  /// IsDraft, From).
  final EasEmail? email;
  final String? displayCc;
  final String? displayBcc;
  final String? preview;
  final bool? hasAttachments;

  /// Raw `Properties` element.
  final WbxmlElement? properties;

  const FindMailboxResult({
    this.className,
    this.serverId,
    this.collectionId,
    this.email,
    this.displayCc,
    this.displayBcc,
    this.preview,
    this.hasAttachments,
    this.properties,
  });
}

/// Result of a Find command.
class FindResult {
  /// `Response/Status` when present, otherwise `Find/Status`.
  final int status;

  /// GAL results (GAL search).
  final List<FindGalEntry> entries;

  /// Mailbox results (mailbox search).
  final List<FindMailboxResult> mailboxResults;

  /// Store name echoed by the server (`itemoperations:Store`).
  final String? store;
  final String? range;
  final int total;

  const FindResult({
    required this.status,
    this.entries = const [],
    this.mailboxResults = const [],
    this.store,
    this.range,
    this.total = 0,
  });

  bool get isSuccess => status == 1;
  FindStatus? get statusInfo => FindStatus.fromCode(status);
}

/// Find command (EAS 16.1): GAL search ([FindCommand.new]) or mailbox
/// search ([FindCommand.mailbox]).
class FindCommand extends EasCommand<FindResult> {
  /// GAL query (4-256 characters) or mailbox free text.
  final String query;

  /// Mailbox search: class and folder restrictions.
  final bool isMailbox;
  final String? className;
  final String? collectionId;

  final int rangeStart;
  final int rangeEnd;

  /// Mailbox search only: include subfolders.
  final bool deepTraversal;

  /// Request pictures in results.
  final bool requestPicture;

  /// Max picture size in bytes (0 = no limit).
  final int maxPictureSize;

  /// Max number of pictures (null = server default).
  final int? maxPictures;

  /// Search ID (GUID); generated when not given.
  final String searchId;

  static final _guidPattern = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-'
    r'[a-fA-F0-9]{12}$',
  );

  /// GAL search.
  FindCommand({
    required this.query,
    this.rangeStart = 0,
    this.rangeEnd = 99,
    this.requestPicture = false,
    this.maxPictureSize = 0,
    this.maxPictures,
    String? searchId,
  }) : isMailbox = false,
       className = null,
       collectionId = null,
       deepTraversal = false,
       searchId = searchId ?? newSearchId() {
    checkLength(query, 256, 'query');
    if (query.length < 4) {
      throw ArgumentError.value(
        query.length,
        'query',
        'GAL query must be 4-256 characters',
      );
    }
    _validate();
  }

  /// Mailbox search (KQL free text, optionally restricted by class and
  /// folder).
  FindCommand.mailbox({
    required this.query,
    this.className,
    this.collectionId,
    this.rangeStart = 0,
    this.rangeEnd = 99,
    this.deepTraversal = false,
    this.requestPicture = false,
    this.maxPictureSize = 0,
    this.maxPictures,
    String? searchId,
  }) : isMailbox = true,
       searchId = searchId ?? newSearchId() {
    _validate();
  }

  void _validate() {
    checkRange(rangeStart, rangeEnd, 999, 'range');
    if (!_guidPattern.hasMatch(searchId)) {
      throw ArgumentError.value(searchId, 'searchId', 'Must be a GUID');
    }
  }

  /// Random (version 4) GUID for `SearchId`.
  static String newSearchId() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  @override
  String get commandName => 'Find';

  @override
  WbxmlDocument buildRequest() {
    final options = xEl(_ns, 'Options', [
      xText(_ns, 'Range', '$rangeStart-$rangeEnd'),
      if (isMailbox && deepTraversal) xEl(_ns, 'DeepTraversal'),
      if (requestPicture)
        xEl(_ns, 'Picture', [
          if (maxPictureSize > 0) xText(_ns, 'MaxSize', maxPictureSize),
          if (maxPictures != null) xText(_ns, 'MaxPictures', maxPictures!),
        ]),
    ]);
    final criterion = isMailbox
        ? xEl(_ns, 'MailBoxSearchCriterion', [
            xEl(_ns, 'Query', [
              xText(_ns, 'FreeText', query),
              if (className != null) xText('AirSync', 'Class', className!),
              if (collectionId != null)
                xText('AirSync', 'CollectionId', collectionId!),
            ]),
            options,
          ])
        : xEl(_ns, 'GALSearchCriterion', [xText(_ns, 'Query', query), options]);
    return WbxmlDocument(
      root: xEl(_ns, 'Find', [
        xText(_ns, 'SearchId', searchId),
        xEl(_ns, 'ExecuteSearch', [criterion]),
      ]),
    );
  }

  @override
  FindResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final status = xStatus(root, _ns);
    final resp = root.findChild(_ns, 'Response');
    if (resp == null) return FindResult(status: status);

    final gal = <FindGalEntry>[];
    final mailbox = <FindMailboxResult>[];
    for (final result in resp.findChildren(_ns, 'Result')) {
      final props = result.findChild(_ns, 'Properties');
      final className = result.childText('AirSync', 'Class');
      final serverId = result.childText('AirSync', 'ServerId');
      if (!isMailbox) {
        gal.add(
          props == null
              ? const FindGalEntry()
              : FindGalEntry.fromProperties(props),
        );
        continue;
      }
      final item = parseContentItem(
        className ?? 'Email',
        serverId ?? '',
        props,
      );
      final hasAtt = props?.childText(_ns, 'HasAttachments');
      mailbox.add(
        FindMailboxResult(
          className: className,
          serverId: serverId,
          collectionId: result.childText('AirSync', 'CollectionId'),
          email: item is EasEmail ? item : null,
          displayCc: props?.childText(_ns, 'DisplayCc'),
          displayBcc: props?.childText(_ns, 'DisplayBcc'),
          preview: props?.childText(_ns, 'Preview'),
          hasAttachments: hasAtt == null
              ? null
              : hasAtt == '1' || hasAtt.toLowerCase() == 'true',
          properties: props,
        ),
      );
    }

    return FindResult(
      status: int.tryParse(resp.childText(_ns, 'Status') ?? '') ?? status,
      store: resp.childText('ItemOperations', 'Store'),
      range: resp.childText(_ns, 'Range'),
      total: int.tryParse(resp.childText(_ns, 'Total') ?? '') ?? 0,
      entries: gal,
      mailboxResults: mailbox,
    );
  }
}
