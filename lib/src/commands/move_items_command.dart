/// MoveItems command — moves items between folders.
///
/// Reference: MS-ASCMD section 2.2.1.12
library;

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Result of a single move operation.
class MoveItemResult {
  final String srcMsgId;
  final int status;
  final String? dstMsgId;

  const MoveItemResult({
    required this.srcMsgId,
    required this.status,
    this.dstMsgId,
  });

  /// Whether the move was successful.
  bool get isSuccess => status == 3;
}

class MoveItemsCommand extends EasCommand<List<MoveItemResult>> {
  final List<String> serverIds;
  final String srcFolderId;
  final String dstFolderId;

  MoveItemsCommand({
    required this.serverIds,
    required this.srcFolderId,
    required this.dstFolderId,
  });

  @override
  String get commandName => 'MoveItems';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Move',
        tag: 'MoveItems',
        codePageIndex: 5,
        children: serverIds
            .map(
              (id) => WbxmlElement(
                namespace: 'Move',
                tag: 'Move',
                codePageIndex: 5,
                children: [
                  WbxmlElement.withText(
                    namespace: 'Move',
                    tag: 'SrcMsgId',
                    text: id,
                    codePageIndex: 5,
                  ),
                  WbxmlElement.withText(
                    namespace: 'Move',
                    tag: 'SrcFldId',
                    text: srcFolderId,
                    codePageIndex: 5,
                  ),
                  WbxmlElement.withText(
                    namespace: 'Move',
                    tag: 'DstFldId',
                    text: dstFolderId,
                    codePageIndex: 5,
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  List<MoveItemResult> parseResponse(WbxmlDocument response) {
    final root = response.root;
    final responses = root.findChildren('Move', 'Response');

    return responses.map((resp) {
      final srcMsgId = resp.childText('Move', 'SrcMsgId') ?? '';
      final status =
          int.tryParse(resp.childText('Move', 'Status') ?? '') ?? 0;
      final dstMsgId = resp.childText('Move', 'DstMsgId');

      return MoveItemResult(
        srcMsgId: srcMsgId,
        status: status,
        dstMsgId: dstMsgId,
      );
    }).toList();
  }
}
