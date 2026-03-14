/// Code Page 0: AirSync namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.1
library;

import 'code_page.dart';

class AirSyncCodePage extends CodePage {
  static final AirSyncCodePage instance = AirSyncCodePage._();

  AirSyncCodePage._();

  @override
  int get pageIndex => 0;

  @override
  String get namespace => 'AirSync';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Sync',
        0x06: 'Responses',
        0x07: 'Add',
        0x08: 'Change',
        0x09: 'Delete',
        0x0A: 'Fetch',
        0x0B: 'SyncKey',
        0x0C: 'ClientId',
        0x0D: 'ServerId',
        0x0E: 'Status',
        0x0F: 'Collection',
        0x10: 'Class',
        0x12: 'CollectionId',
        0x13: 'GetChanges',
        0x14: 'MoreAvailable',
        0x15: 'WindowSize',
        0x16: 'Commands',
        0x17: 'Options',
        0x18: 'FilterType',
        0x19: 'Truncation',
        0x1B: 'Conflict',
        0x1C: 'Collections',
        0x1D: 'ApplicationData',
        0x1E: 'DeletesAsMoves',
        0x20: 'Supported',
        0x21: 'SoftDelete',
        0x22: 'MIMESupport',
        0x23: 'MIMETruncation',
        0x24: 'Wait',
        0x25: 'Limit',
        0x26: 'Partial',
        0x27: 'ConversationMode',
        0x28: 'MaxItems',
        0x29: 'HeartbeatInterval',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
