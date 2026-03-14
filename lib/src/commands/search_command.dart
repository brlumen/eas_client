/// Search command — server-side search.
///
/// Reference: MS-ASCMD section 2.2.1.16
library;

import '../models/eas_email.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

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

  SearchCommand({
    required this.query,
    this.collectionId,
    this.rangeStart = 0,
    this.rangeEnd = 49,
    this.deepTraversal = true,
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

    optionChildren.add(WbxmlElement(
      namespace: 'AirSyncBase',
      tag: 'BodyPreference',
      codePageIndex: 17,
      children: [
        WbxmlElement.withText(
          namespace: 'AirSyncBase',
          tag: 'Type',
          text: '2', // HTML
          codePageIndex: 17,
        ),
        WbxmlElement.withText(
          namespace: 'AirSyncBase',
          tag: 'TruncationSize',
          text: '512',
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
