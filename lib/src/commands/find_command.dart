/// Find command — GAL search with picture support (EAS 16.1).
///
/// Replacement for Search with Store='GAL' in newer protocol versions.
/// Supports returning contact pictures.
///
/// Reference: MS-ASCMD section 2.2.1.2 (EAS 16.1)
library;

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

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

  /// Base64-encoded picture data.
  final String? picture;

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
    this.picture,
  });

  @override
  String toString() => 'FindGalEntry($displayName <$emailAddress>)';
}

/// Result of a Find command.
class FindResult {
  final int status;
  final List<FindGalEntry> entries;
  final int total;

  const FindResult({
    required this.status,
    this.entries = const [],
    this.total = 0,
  });
}

/// Find command for GAL search (EAS 16.1).
class FindCommand extends EasCommand<FindResult> {
  final String query;
  final int rangeStart;
  final int rangeEnd;
  final bool deepTraversal;

  /// Request pictures in results.
  final bool requestPicture;

  /// Max picture size in bytes (0 = no limit).
  final int maxPictureSize;

  FindCommand({
    required this.query,
    this.rangeStart = 0,
    this.rangeEnd = 99,
    this.deepTraversal = false,
    this.requestPicture = false,
    this.maxPictureSize = 0,
  });

  @override
  String get commandName => 'Find';

  @override
  WbxmlDocument buildRequest() {
    final optionChildren = <WbxmlElement>[
      WbxmlElement.withText(
        namespace: 'Find',
        tag: 'Range',
        text: '$rangeStart-$rangeEnd',
        codePageIndex: 25,
      ),
    ];

    if (deepTraversal) {
      optionChildren.add(WbxmlElement(
        namespace: 'Find',
        tag: 'DeepTraversal',
        codePageIndex: 25,
      ));
    }

    if (requestPicture) {
      final pictureChildren = <WbxmlElement>[];
      if (maxPictureSize > 0) {
        pictureChildren.add(WbxmlElement.withText(
          namespace: 'AirSyncBase',
          tag: 'MaxSize',
          text: maxPictureSize.toString(),
          codePageIndex: 17,
        ));
      }
      optionChildren.add(WbxmlElement(
        namespace: 'AirSyncBase',
        tag: 'Picture',
        codePageIndex: 17,
        children: pictureChildren,
      ));
    }

    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Find',
        tag: 'Find',
        codePageIndex: 25,
        children: [
          WbxmlElement.withText(
            namespace: 'Find',
            tag: 'SearchId',
            text: 'GAL',
            codePageIndex: 25,
          ),
          WbxmlElement(
            namespace: 'Find',
            tag: 'ExecuteSearch',
            codePageIndex: 25,
            children: [
              WbxmlElement(
                namespace: 'Find',
                tag: 'GALSearchCriterion',
                codePageIndex: 25,
                children: [
                  WbxmlElement.withText(
                    namespace: 'Find',
                    tag: 'Query',
                    text: query,
                    codePageIndex: 25,
                  ),
                ],
              ),
              WbxmlElement(
                namespace: 'Find',
                tag: 'Options',
                codePageIndex: 25,
                children: optionChildren,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  FindResult parseResponse(WbxmlDocument response) {
    final root = response.root;
    final status =
        int.tryParse(root.childText('Find', 'Status') ?? '') ?? 0;

    final resp = root.findChild('Find', 'Response');
    if (resp == null) return FindResult(status: status);

    final totalStr = resp.childText('Find', 'Total');
    final total = int.tryParse(totalStr ?? '') ?? 0;

    final entries = resp.findChildren('Find', 'Result').map((result) {
      final props = result.findChild('Find', 'Properties');
      if (props == null) return const FindGalEntry();

      // Picture
      String? picture;
      final picEl = props.findChild('AirSyncBase', 'Picture');
      if (picEl != null) {
        picture = picEl.childText('AirSyncBase', 'Data');
      }

      return FindGalEntry(
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
        picture: picture,
      );
    }).toList();

    return FindResult(
      status: status,
      entries: entries,
      total: total,
    );
  }
}
