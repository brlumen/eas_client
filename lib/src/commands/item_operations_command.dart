/// ItemOperations command — fetch email body, attachments, and empty folders.
///
/// Reference: MS-ASCMD section 2.2.1.10
library;

import 'dart:typed_data';

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Result of an ItemOperations Fetch.
class ItemOperationsResult {
  final int status;
  final String? body;
  final int? bodyType;
  final Uint8List? data;

  const ItemOperationsResult({
    required this.status,
    this.body,
    this.bodyType,
    this.data,
  });
}

/// Fetch email body by ServerId.
class FetchEmailBodyCommand extends EasCommand<ItemOperationsResult> {
  final String serverId;
  final String collectionId;
  final int bodyType;

  FetchEmailBodyCommand({
    required this.serverId,
    required this.collectionId,
    this.bodyType = 2, // HTML
  });

  @override
  String get commandName => 'ItemOperations';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'ItemOperations',
        tag: 'ItemOperations',
        codePageIndex: 20,
        children: [
          WbxmlElement(
            namespace: 'ItemOperations',
            tag: 'Fetch',
            codePageIndex: 20,
            children: [
              WbxmlElement.withText(
                namespace: 'ItemOperations',
                tag: 'Store',
                text: 'Mailbox',
                codePageIndex: 20,
              ),
              WbxmlElement.withText(
                namespace: 'AirSync',
                tag: 'CollectionId',
                text: collectionId,
                codePageIndex: 0,
              ),
              WbxmlElement.withText(
                namespace: 'AirSync',
                tag: 'ServerId',
                text: serverId,
                codePageIndex: 0,
              ),
              WbxmlElement(
                namespace: 'ItemOperations',
                tag: 'Options',
                codePageIndex: 20,
                children: [
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
                    ],
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
  ItemOperationsResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final resp = root.findChild('ItemOperations', 'Response');
    if (resp == null) {
      return const ItemOperationsResult(status: 0);
    }

    final fetch = resp.findChild('ItemOperations', 'Fetch');
    if (fetch == null) {
      return const ItemOperationsResult(status: 0);
    }

    final status = int.tryParse(
          fetch.childText('ItemOperations', 'Status') ?? '',
        ) ??
        0;

    final props = fetch.findChild('ItemOperations', 'Properties');
    if (props == null) {
      return ItemOperationsResult(status: status);
    }

    final bodyElement = props.findChild('AirSyncBase', 'Body');
    String? body;
    int? bodyTypeVal;
    if (bodyElement != null) {
      body = bodyElement.childText('AirSyncBase', 'Data');
      bodyTypeVal = int.tryParse(
        bodyElement.childText('AirSyncBase', 'Type') ?? '',
      );
    }

    return ItemOperationsResult(
      status: status,
      body: body,
      bodyType: bodyTypeVal,
    );
  }
}

/// Fetch attachment by FileReference.
class FetchAttachmentCommand extends EasCommand<ItemOperationsResult> {
  final String fileReference;

  FetchAttachmentCommand({required this.fileReference});

  @override
  String get commandName => 'ItemOperations';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'ItemOperations',
        tag: 'ItemOperations',
        codePageIndex: 20,
        children: [
          WbxmlElement(
            namespace: 'ItemOperations',
            tag: 'Fetch',
            codePageIndex: 20,
            children: [
              WbxmlElement.withText(
                namespace: 'ItemOperations',
                tag: 'Store',
                text: 'Mailbox',
                codePageIndex: 20,
              ),
              WbxmlElement.withText(
                namespace: 'AirSyncBase',
                tag: 'FileReference',
                text: fileReference,
                codePageIndex: 17,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  ItemOperationsResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final resp = root.findChild('ItemOperations', 'Response');
    if (resp == null) {
      return const ItemOperationsResult(status: 0);
    }

    final fetch = resp.findChild('ItemOperations', 'Fetch');
    if (fetch == null) {
      return const ItemOperationsResult(status: 0);
    }

    final status = int.tryParse(
          fetch.childText('ItemOperations', 'Status') ?? '',
        ) ??
        0;

    final props = fetch.findChild('ItemOperations', 'Properties');
    Uint8List? data;
    if (props != null) {
      final dataElement = props.findChild('ItemOperations', 'Data');
      data = dataElement?.opaque;
    }

    return ItemOperationsResult(
      status: status,
      data: data,
    );
  }
}

/// Empty the contents of a folder (delete all items).
///
/// [deleteSubFolders] — if true, also deletes sub-folders within the folder.
///
/// Reference: MS-ASCMD section 2.2.1.10.2
class EmptyFolderCommand extends EasCommand<int> {
  final String folderId;
  final bool deleteSubFolders;

  EmptyFolderCommand({
    required this.folderId,
    this.deleteSubFolders = false,
  });

  @override
  String get commandName => 'ItemOperations';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'ItemOperations',
        tag: 'ItemOperations',
        codePageIndex: 20,
        children: [
          WbxmlElement(
            namespace: 'ItemOperations',
            tag: 'EmptyFolderContents',
            codePageIndex: 20,
            children: [
              WbxmlElement.withText(
                namespace: 'AirSync',
                tag: 'CollectionId',
                text: folderId,
                codePageIndex: 0,
              ),
              WbxmlElement(
                namespace: 'ItemOperations',
                tag: 'Options',
                codePageIndex: 20,
                children: [
                  if (deleteSubFolders)
                    WbxmlElement.withText(
                      namespace: 'ItemOperations',
                      tag: 'DeleteSubFolders',
                      text: '1',
                      codePageIndex: 20,
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
  int parseResponse(WbxmlDocument response) {
    final root = response.root;
    final resp = root.findChild('ItemOperations', 'Response');
    if (resp == null) return 0;
    final emptyEl = resp.findChild('ItemOperations', 'EmptyFolderContents');
    if (emptyEl == null) return 0;
    return int.tryParse(
          emptyEl.childText('ItemOperations', 'Status') ?? '',
        ) ??
        0;
  }
}

/// Batch fetch multiple email bodies in a single ItemOperations request.
class BatchFetchEmailBodiesCommand
    extends EasCommand<List<ItemOperationsResult>> {
  /// List of (serverId, collectionId) pairs to fetch.
  final List<({String serverId, String collectionId})> items;
  final int bodyType;

  BatchFetchEmailBodiesCommand({
    required this.items,
    this.bodyType = 2,
  });

  @override
  String get commandName => 'ItemOperations';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'ItemOperations',
        tag: 'ItemOperations',
        codePageIndex: 20,
        children: items
            .map(
              (item) => WbxmlElement(
                namespace: 'ItemOperations',
                tag: 'Fetch',
                codePageIndex: 20,
                children: [
                  WbxmlElement.withText(
                    namespace: 'ItemOperations',
                    tag: 'Store',
                    text: 'Mailbox',
                    codePageIndex: 20,
                  ),
                  WbxmlElement.withText(
                    namespace: 'AirSync',
                    tag: 'CollectionId',
                    text: item.collectionId,
                    codePageIndex: 0,
                  ),
                  WbxmlElement.withText(
                    namespace: 'AirSync',
                    tag: 'ServerId',
                    text: item.serverId,
                    codePageIndex: 0,
                  ),
                  WbxmlElement(
                    namespace: 'ItemOperations',
                    tag: 'Options',
                    codePageIndex: 20,
                    children: [
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
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  List<ItemOperationsResult> parseResponse(WbxmlDocument response) {
    final root = response.root;
    final resp = root.findChild('ItemOperations', 'Response');
    if (resp == null) return [];

    return resp.findChildren('ItemOperations', 'Fetch').map((fetch) {
      final status = int.tryParse(
            fetch.childText('ItemOperations', 'Status') ?? '',
          ) ??
          0;

      final props = fetch.findChild('ItemOperations', 'Properties');
      String? body;
      int? bodyTypeVal;
      if (props != null) {
        final bodyElement = props.findChild('AirSyncBase', 'Body');
        if (bodyElement != null) {
          body = bodyElement.childText('AirSyncBase', 'Data');
          bodyTypeVal = int.tryParse(
            bodyElement.childText('AirSyncBase', 'Type') ?? '',
          );
        }
      }

      return ItemOperationsResult(
        status: status,
        body: body,
        bodyType: bodyTypeVal,
      );
    }).toList();
  }
}
