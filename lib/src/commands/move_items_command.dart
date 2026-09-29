/// MoveItems command — moves items between folders.
///
/// Reference: MS-ASCMD section 2.2.1.12
library;

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'Move';

/// MoveItems status codes (MS-ASCMD 2.2.3.177.10).
enum MoveItemsStatus {
  invalidSource(1, 'Invalid source collection ID or item ID'),
  invalidDestination(2, 'Invalid destination collection ID'),
  success(3, 'Success'),
  sameSourceAndDestination(4, 'Source and destination are the same'),
  moveFailed(5, 'Item cannot be moved to more than one place, or locked'),
  locked(7, 'Source or destination item was locked');

  final int code;
  final String description;

  const MoveItemsStatus(this.code, this.description);

  static MoveItemsStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

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

  /// Typed [status], `null` if unknown.
  MoveItemsStatus? get statusInfo => MoveItemsStatus.fromCode(status);
}

/// One item to move.
class MoveItem {
  final String srcMsgId;
  final String srcFldId;
  final String dstFldId;

  MoveItem({
    required this.srcMsgId,
    required this.srcFldId,
    required this.dstFldId,
  }) {
    checkLength(srcMsgId, 64, 'srcMsgId');
    checkLength(srcFldId, 64, 'srcFldId');
    checkLength(dstFldId, 64, 'dstFldId');
  }
}

class MoveItemsCommand extends EasCommand<List<MoveItemResult>> {
  final List<MoveItem> moves;

  /// Move items, each with its own source/destination folder.
  MoveItemsCommand.items(this.moves) {
    if (moves.isEmpty) {
      throw ArgumentError.value(0, 'moves', 'Must not be empty');
    }
  }

  /// Move [serverIds] from [srcFolderId] to [dstFolderId].
  factory MoveItemsCommand({
    required List<String> serverIds,
    required String srcFolderId,
    required String dstFolderId,
  }) => MoveItemsCommand.items([
    for (final id in serverIds)
      MoveItem(srcMsgId: id, srcFldId: srcFolderId, dstFldId: dstFolderId),
  ]);

  @override
  String get commandName => 'MoveItems';

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'MoveItems', [
      for (final m in moves)
        xEl(_ns, 'Move', [
          xText(_ns, 'SrcMsgId', m.srcMsgId),
          xText(_ns, 'SrcFldId', m.srcFldId),
          xText(_ns, 'DstFldId', m.dstFldId),
        ]),
    ]),
  );

  @override
  List<MoveItemResult> parseResponse(WbxmlDocument response) {
    final root = response.root;
    final responses = root.findChildren(_ns, 'Response');
    if (responses.isEmpty && root.findChild(_ns, 'Status') != null) {
      // Whole-request failure (optional MoveItems/Status).
      final status = xStatus(root, _ns);
      return [
        for (final m in moves)
          MoveItemResult(srcMsgId: m.srcMsgId, status: status),
      ];
    }
    return responses
        .map(
          (resp) => MoveItemResult(
            srcMsgId: resp.childText(_ns, 'SrcMsgId') ?? '',
            status: xStatus(resp, _ns),
            dstMsgId: resp.childText(_ns, 'DstMsgId'),
          ),
        )
        .toList();
  }
}
