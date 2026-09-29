/// GetItemEstimate command — estimate the number of items that will be synced.
///
/// Reference: MS-ASCMD section 2.2.1.9
library;

import '../models/wbxml_helpers.dart' show protocolVersionValue;
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'GetItemEstimate';
const _as = 'AirSync';

/// GetItemEstimate status codes (MS-ASCMD 2.2.3.177.7).
enum ItemEstimateStatus {
  success(1, 'Success'),
  invalidCollection(2, 'A collection or collection ID was invalid'),
  syncStateNotPrimed(3, 'Sync state not primed: issue Sync with SyncKey 0'),
  invalidSyncKey(4, 'The synchronization key was invalid');

  final int code;
  final String description;

  const ItemEstimateStatus(this.code, this.description);

  static ItemEstimateStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Result for a single collection estimate.
class ItemEstimateResult {
  final int status;
  final String collectionId;

  /// Estimated number of items to sync.
  final int estimate;

  bool get isSuccess => status == 1;

  /// Typed [status], `null` if unknown.
  ItemEstimateStatus? get statusInfo => ItemEstimateStatus.fromCode(status);

  const ItemEstimateResult({
    required this.status,
    required this.collectionId,
    required this.estimate,
  });
}

/// `airsync:Options` of a GetItemEstimate collection (up to two per
/// collection, e.g. Email and SMS).
class ItemEstimateOptions {
  /// Content class (`airsync:Class`), e.g. 'Email', 'SMS'.
  final String? className;

  /// Sync filter type 0-8 (`airsync:FilterType`).
  final int? filterType;

  /// Max recipients; only valid for the recipient information cache
  /// (CollectionId "RI").
  final int? maxItems;

  const ItemEstimateOptions({this.className, this.filterType, this.maxItems});

  bool get isEmpty =>
      className == null && filterType == null && maxItems == null;

  WbxmlElement toElement() => xEl(_as, 'Options', [
    if (className != null) xText(_as, 'Class', className!),
    if (filterType != null) xText(_as, 'FilterType', filterType!),
    if (maxItems != null) xText(_as, 'MaxItems', maxItems!),
  ]);
}

/// One collection of a GetItemEstimate request.
class ItemEstimateCollection {
  final String collectionId;
  final String syncKey;

  /// Count conversations instead of items (`airsync:ConversationMode`,
  /// EAS 14.0+).
  final bool? conversationMode;

  /// Filters (0-2 entries, each non-empty).
  final List<ItemEstimateOptions> options;

  ItemEstimateCollection({
    required this.collectionId,
    required this.syncKey,
    this.conversationMode,
    this.options = const [],
  }) {
    checkLength(collectionId, 64, 'collectionId');
    checkLength(syncKey, 64, 'syncKey');
    if (options.length > 2 || options.any((o) => o.isEmpty)) {
      throw ArgumentError.value(
        options.length,
        'options',
        'At most 2 non-empty Options (MS-ASCMD 2.2.3.125.2)',
      );
    }
  }

  WbxmlElement toElement(String protocolVersion) {
    if (protocolVersionValue(protocolVersion) < 140) {
      // 2.5 / 12.x form: Class, CollectionId, FilterType, SyncKey.
      final opt = options.isEmpty ? null : options.first;
      return xEl(_ns, 'Collection', [
        if (opt?.className != null) xText(_ns, 'Class', opt!.className!),
        xText(_ns, 'CollectionId', collectionId),
        xText(_as, 'FilterType', opt?.filterType ?? 0),
        xText(_as, 'SyncKey', syncKey),
      ]);
    }
    return xEl(_ns, 'Collection', [
      xText(_as, 'SyncKey', syncKey),
      xText(_ns, 'CollectionId', collectionId),
      if (conversationMode != null)
        xText(_as, 'ConversationMode', conversationMode! ? '1' : '0'),
      for (final o in options) o.toElement(),
    ]);
  }
}

class GetItemEstimateCommand extends EasCommand<List<ItemEstimateResult>> {
  final List<ItemEstimateCollection> collections;

  /// Request item estimates for several collections.
  GetItemEstimateCommand.collections(this.collections) {
    if (collections.isEmpty) {
      throw ArgumentError.value(0, 'collections', 'Must not be empty');
    }
  }

  /// Request item estimate for one folder.
  factory GetItemEstimateCommand.single({
    required String collectionId,
    required String syncKey,
    int? filterType,
    String? className,
    bool? conversationMode,
    int? maxItems,
  }) => GetItemEstimateCommand.collections([
    ItemEstimateCollection(
      collectionId: collectionId,
      syncKey: syncKey,
      conversationMode: conversationMode,
      options: [
        if (className != null || filterType != null || maxItems != null)
          ItemEstimateOptions(
            className: className,
            filterType: filterType,
            maxItems: maxItems,
          ),
      ],
    ),
  ]);

  /// Several folders sharing the same [syncKey] and filter.
  factory GetItemEstimateCommand({
    required List<String> collectionIds,
    required String syncKey,
    int? filterType,
    String? className,
  }) => GetItemEstimateCommand.collections([
    for (final id in collectionIds)
      ItemEstimateCollection(
        collectionId: id,
        syncKey: syncKey,
        options: [
          if (className != null || filterType != null)
            ItemEstimateOptions(className: className, filterType: filterType),
        ],
      ),
  ]);

  @override
  String get commandName => 'GetItemEstimate';

  @override
  WbxmlDocument buildRequest() => buildRequestFor('16.1');

  @override
  WbxmlDocument buildRequestFor(String protocolVersion) => WbxmlDocument(
    root: xEl(_ns, 'GetItemEstimate', [
      xEl(_ns, 'Collections', [
        for (final c in collections) c.toElement(protocolVersion),
      ]),
    ]),
  );

  @override
  List<ItemEstimateResult> parseResponse(WbxmlDocument response) {
    final root = response.root;
    final responses = root.findChildren(_ns, 'Response');
    if (responses.isEmpty && root.findChild(_ns, 'Status') != null) {
      // Whole-request failure: status on the root element.
      final status = xStatus(root, _ns);
      return [
        for (final c in collections)
          ItemEstimateResult(
            status: status,
            collectionId: c.collectionId,
            estimate: 0,
          ),
      ];
    }
    return responses.map((resp) {
      final collEl = resp.findChild(_ns, 'Collection');
      return ItemEstimateResult(
        status: xStatus(resp, _ns),
        collectionId: collEl?.childText(_ns, 'CollectionId') ?? '',
        estimate: int.tryParse(collEl?.childText(_ns, 'Estimate') ?? '') ?? 0,
      );
    }).toList();
  }
}
