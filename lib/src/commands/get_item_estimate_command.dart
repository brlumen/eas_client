/// GetItemEstimate command — estimate the number of items that will be synced.
///
/// Useful to check how many items exist before performing a full sync.
/// Returns the estimated count for the given folder.
///
/// Reference: MS-ASCMD section 2.2.1.9
library;

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Result for a single collection estimate.
class ItemEstimateResult {
  final int status;
  final String collectionId;

  /// Estimated number of items to sync.
  final int estimate;

  bool get isSuccess => status == 1;

  const ItemEstimateResult({
    required this.status,
    required this.collectionId,
    required this.estimate,
  });
}

class GetItemEstimateCommand extends EasCommand<List<ItemEstimateResult>> {
  final List<String> collectionIds;
  final String syncKey;

  /// Filter type per collection (0-7, same as SyncFilterType).
  final int? filterType;

  /// Content class per collection ('Email', 'Calendar', 'Tasks', 'Contacts', 'Notes').
  final String? className;

  /// Request item estimate for one folder.
  factory GetItemEstimateCommand.single({
    required String collectionId,
    required String syncKey,
    int? filterType,
    String? className,
  }) =>
      GetItemEstimateCommand(
        collectionIds: [collectionId],
        syncKey: syncKey,
        filterType: filterType,
        className: className,
      );

  GetItemEstimateCommand({
    required this.collectionIds,
    required this.syncKey,
    this.filterType,
    this.className,
  });

  @override
  String get commandName => 'GetItemEstimate';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'GetItemEstimate',
        tag: 'GetItemEstimate',
        codePageIndex: 6,
        children: [
          WbxmlElement(
            namespace: 'GetItemEstimate',
            tag: 'Collections',
            codePageIndex: 6,
            children: collectionIds.map((id) {
              final collChildren = <WbxmlElement>[
                WbxmlElement.withText(
                  namespace: 'AirSync',
                  tag: 'SyncKey',
                  text: syncKey,
                  codePageIndex: 0,
                ),
                WbxmlElement.withText(
                  namespace: 'GetItemEstimate',
                  tag: 'CollectionId',
                  text: id,
                  codePageIndex: 6,
                ),
              ];

              // Options with Class and FilterType
              if (className != null || filterType != null) {
                collChildren.add(WbxmlElement(
                  namespace: 'GetItemEstimate',
                  tag: 'Options',
                  codePageIndex: 6,
                  children: [
                    if (className != null)
                      WbxmlElement.withText(
                        namespace: 'AirSync',
                        tag: 'Class',
                        text: className!,
                        codePageIndex: 0,
                      ),
                    if (filterType != null)
                      WbxmlElement.withText(
                        namespace: 'AirSync',
                        tag: 'FilterType',
                        text: filterType.toString(),
                        codePageIndex: 0,
                      ),
                  ],
                ));
              }

              return WbxmlElement(
                namespace: 'GetItemEstimate',
                tag: 'Collection',
                codePageIndex: 6,
                children: collChildren,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  List<ItemEstimateResult> parseResponse(WbxmlDocument response) {
    final root = response.root;
    return root
        .findChildren('GetItemEstimate', 'Response')
        .map((resp) {
          final status =
              int.tryParse(resp.childText('GetItemEstimate', 'Status') ?? '') ??
                  0;
          final collEl = resp.findChild('GetItemEstimate', 'Collection');
          final collectionId =
              collEl?.childText('GetItemEstimate', 'CollectionId') ?? '';
          final estimate =
              int.tryParse(collEl?.childText('GetItemEstimate', 'Estimate') ?? '') ??
                  0;
          return ItemEstimateResult(
            status: status,
            collectionId: collectionId,
            estimate: estimate,
          );
        })
        .toList();
  }
}
