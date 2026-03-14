/// ItemOperations command — fetch email body and attachments.
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
