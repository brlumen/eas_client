/// Search command — server-side search (Mailbox and GAL).
///
/// Reference: MS-ASCMD section 2.2.1.16
library;

import '../models/eas_email.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

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
  });

  @override
  String toString() => 'GalEntry($displayName <$emailAddress>)';
}

/// Result of a GAL Search.
class GalSearchResult {
  final int status;
  final List<GalEntry> entries;
  final int total;

  const GalSearchResult({
    required this.status,
    this.entries = const [],
    this.total = 0,
  });
}

/// Result of a Search command.
class SearchResult {
  final int status;
  final List<SearchResultItem> items;
  final int total;

  const SearchResult({
    required this.status,
    this.items = const [],
    this.total = 0,
  });
}

/// Individual search result item.
class SearchResultItem {
  final String? longId;
  final String? collectionId;
  final EasEmail? email;

  const SearchResultItem({
    this.longId,
    this.collectionId,
    this.email,
  });
}

class SearchCommand extends EasCommand<SearchResult> {
  final String query;
  final String? collectionId;
  final int rangeStart;
  final int rangeEnd;
  final bool deepTraversal;
  final int bodyType;
  final int bodyTruncationSize;
  final bool rebuildResults;

  SearchCommand({
    required this.query,
    this.collectionId,
    this.rangeStart = 0,
    this.rangeEnd = 49,
    this.deepTraversal = true,
    this.bodyType = 2,
    this.bodyTruncationSize = 512,
    this.rebuildResults = false,
  });

  @override
  String get commandName => 'Search';

  @override
  WbxmlDocument buildRequest() {
    final optionChildren = <WbxmlElement>[
      WbxmlElement.withText(
        namespace: 'Search',
        tag: 'Range',
        text: '$rangeStart-$rangeEnd',
        codePageIndex: 15,
      ),
    ];

    if (deepTraversal) {
      optionChildren.add(WbxmlElement(
        namespace: 'Search',
        tag: 'DeepTraversal',
        codePageIndex: 15,
      ));
    }

    if (rebuildResults) {
      optionChildren.add(WbxmlElement(
        namespace: 'Search',
        tag: 'RebuildResults',
        codePageIndex: 15,
      ));
    }

    optionChildren.add(WbxmlElement(
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
        WbxmlElement.withText(
          namespace: 'AirSyncBase',
          tag: 'TruncationSize',
          text: bodyTruncationSize.toString(),
          codePageIndex: 17,
        ),
      ],
    ));

    final queryElement = WbxmlElement(
      namespace: 'Search',
      tag: 'Query',
      codePageIndex: 15,
      children: [
        WbxmlElement.withText(
          namespace: 'Search',
          tag: 'FreeText',
          text: query,
          codePageIndex: 15,
        ),
        if (collectionId != null)
          WbxmlElement.withText(
            namespace: 'AirSync',
            tag: 'CollectionId',
            text: collectionId!,
            codePageIndex: 0,
          ),
      ],
    );

    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Search',
        tag: 'Search',
        codePageIndex: 15,
        children: [
          WbxmlElement(
            namespace: 'Search',
            tag: 'Store',
            codePageIndex: 15,
            children: [
              WbxmlElement.withText(
                namespace: 'Search',
                tag: 'Name',
                text: 'Mailbox',
                codePageIndex: 15,
              ),
              queryElement,
              WbxmlElement(
                namespace: 'Search',
                tag: 'Options',
                codePageIndex: 15,
                children: optionChildren,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  SearchResult parseResponse(WbxmlDocument response) {
    final root = response.root;

    final statusStr = root.childText('Search', 'Status');
    final status = int.tryParse(statusStr ?? '') ?? 0;

    final resp = root.findChild('Search', 'Response');
    if (resp == null) {
      return SearchResult(status: status);
    }

    final store = resp.findChild('Search', 'Store');
    if (store == null) {
      return SearchResult(status: status);
    }

    final totalStr = store.childText('Search', 'Total');
    final total = int.tryParse(totalStr ?? '') ?? 0;

    final results = store.findChildren('Search', 'Result');
    final items = results.map((result) {
      final longId = result.childText('Search', 'LongId');
      final collId = result.childText('AirSync', 'CollectionId');
      final props = result.findChild('Search', 'Properties');

      EasEmail? email;
      if (props != null) {
        email = _parseEmailProperties(props);
      }

      return SearchResultItem(
        longId: longId,
        collectionId: collId,
        email: email,
      );
    }).toList();

    return SearchResult(
      status: status,
      items: items,
      total: total,
    );
  }

  EasEmail _parseEmailProperties(WbxmlElement props) {
    final subject = props.childText('Email', 'Subject') ?? '';
    final from = props.childText('Email', 'From') ?? '';
    final to = props.childText('Email', 'To') ?? '';
    final dateStr = props.childText('Email', 'DateReceived');
    final readStr = props.childText('Email', 'Read');

    final bodyElement = props.findChild('AirSyncBase', 'Body');
    String? body;
    int bodyType = 1;
    if (bodyElement != null) {
      body = bodyElement.childText('AirSyncBase', 'Data');
      bodyType = int.tryParse(
            bodyElement.childText('AirSyncBase', 'Type') ?? '',
          ) ??
          1;
    }

    return EasEmail(
      serverId: '',
      subject: subject,
      from: from,
      to: to,
      dateReceived: dateStr != null ? DateTime.tryParse(dateStr) : null,
      read: readStr == '1',
      body: body,
      bodyType: bodyType,
    );
  }
}

/// Search the Global Address List (GAL).
///
/// Uses the Search command with Store='GAL'.
/// Reference: MS-ASCMD section 2.2.1.16
class GalSearchCommand extends EasCommand<GalSearchResult> {
  final String query;
  final int rangeStart;
  final int rangeEnd;

  GalSearchCommand({
    required this.query,
    this.rangeStart = 0,
    this.rangeEnd = 99,
  });

  @override
  String get commandName => 'Search';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Search',
        tag: 'Search',
        codePageIndex: 15,
        children: [
          WbxmlElement(
            namespace: 'Search',
            tag: 'Store',
            codePageIndex: 15,
            children: [
              WbxmlElement.withText(
                namespace: 'Search',
                tag: 'Name',
                text: 'GAL',
                codePageIndex: 15,
              ),
              WbxmlElement(
                namespace: 'Search',
                tag: 'Query',
                codePageIndex: 15,
                children: [
                  WbxmlElement.withText(
                    namespace: 'Search',
                    tag: 'FreeText',
                    text: query,
                    codePageIndex: 15,
                  ),
                ],
              ),
              WbxmlElement(
                namespace: 'Search',
                tag: 'Options',
                codePageIndex: 15,
                children: [
                  WbxmlElement.withText(
                    namespace: 'Search',
                    tag: 'Range',
                    text: '$rangeStart-$rangeEnd',
                    codePageIndex: 15,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  GalSearchResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final status =
        int.tryParse(root.childText('Search', 'Status') ?? '') ?? 0;

    final resp = root.findChild('Search', 'Response');
    if (resp == null) return GalSearchResult(status: status);

    final store = resp.findChild('Search', 'Store');
    if (store == null) return GalSearchResult(status: status);

    final totalStr = store.childText('Search', 'Total');
    final total = int.tryParse(totalStr ?? '') ?? 0;

    final entries = store.findChildren('Search', 'Result').map((result) {
      final props = result.findChild('Search', 'Properties');
      if (props == null) return const GalEntry();
      return GalEntry(
        displayName: props.childText('GAL', 'DisplayName'),
        emailAddress: props.childText('GAL', 'EmailAddress'),
        phone: props.childText('GAL', 'Phone'),
        office: props.childText('GAL', 'Office'),
        title: props.childText('GAL', 'Title'),
        company: props.childText('GAL', 'Company'),
        alias: props.childText('GAL', 'Alias'),
        firstName: props.childText('GAL', 'FirstName'),
        lastName: props.childText('GAL', 'LastName'),
        homePhone: props.childText('GAL', 'HomePhone'),
        mobilePhone: props.childText('GAL', 'MobilePhone'),
      );
    }).toList();

    return GalSearchResult(
      status: status,
      entries: entries,
      total: total,
    );
  }
}
