/// Serializes EasEmail to WBXML ApplicationData for Sync Add/Change.
library;

import '../models/eas_email.dart';
import '../wbxml/wbxml_document.dart';

/// Serializer for email items (Sync Add/Change).
///
/// Only serializes fields that are writable via Sync command.
/// Read-only server fields (serverId, dateReceived, etc.) are skipped.
class EmailSerializer {
  const EmailSerializer._();

  /// Serialize email for Sync Add/Change ApplicationData.
  ///
  /// Writable fields per MS-ASEMAIL:
  /// - Read, Flag, Importance, Subject, To, Cc, Body (for drafts)
  static WbxmlElement serialize(EasEmail email) {
    final children = <WbxmlElement>[];

    if (email.to.isNotEmpty) {
      children.add(WbxmlElement.withText(
        namespace: 'Email',
        tag: 'To',
        text: email.to,
        codePageIndex: 2,
      ));
    }

    if (email.from.isNotEmpty) {
      children.add(WbxmlElement.withText(
        namespace: 'Email',
        tag: 'From',
        text: email.from,
        codePageIndex: 2,
      ));
    }

    if (email.cc != null && email.cc!.isNotEmpty) {
      children.add(WbxmlElement.withText(
        namespace: 'Email',
        tag: 'Cc',
        text: email.cc!,
        codePageIndex: 2,
      ));
    }

    if (email.subject.isNotEmpty) {
      children.add(WbxmlElement.withText(
        namespace: 'Email',
        tag: 'Subject',
        text: email.subject,
        codePageIndex: 2,
      ));
    }

    children.add(WbxmlElement.withText(
      namespace: 'Email',
      tag: 'Importance',
      text: email.importance.value.toString(),
      codePageIndex: 2,
    ));

    children.add(WbxmlElement.withText(
      namespace: 'Email',
      tag: 'Read',
      text: email.read ? '1' : '0',
      codePageIndex: 2,
    ));

    if (email.messageClass != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Email',
        tag: 'MessageClass',
        text: email.messageClass!,
        codePageIndex: 2,
      ));
    }

    // Flag
    if (email.flagStatus != 0) {
      children.add(WbxmlElement(
        namespace: 'Email',
        tag: 'Flag',
        codePageIndex: 2,
        children: [
          WbxmlElement.withText(
            namespace: 'Email',
            tag: 'Status',
            text: email.flagStatus.toString(),
            codePageIndex: 2,
          ),
        ],
      ));
    }

    // Body
    if (email.body != null) {
      children.add(WbxmlElement(
        namespace: 'AirSyncBase',
        tag: 'Body',
        codePageIndex: 17,
        children: [
          WbxmlElement.withText(
            namespace: 'AirSyncBase',
            tag: 'Type',
            text: email.bodyType.toString(),
            codePageIndex: 17,
          ),
          WbxmlElement.withText(
            namespace: 'AirSyncBase',
            tag: 'Data',
            text: email.body!,
            codePageIndex: 17,
          ),
        ],
      ));
    }

    // Categories
    if (email.categories.isNotEmpty) {
      children.add(WbxmlElement(
        namespace: 'Email',
        tag: 'Categories',
        codePageIndex: 2,
        children: email.categories
            .map((c) => WbxmlElement.withText(
                  namespace: 'Email',
                  tag: 'Category',
                  text: c,
                  codePageIndex: 2,
                ))
            .toList(),
      ));
    }

    return WbxmlElement(
      namespace: 'AirSync',
      tag: 'ApplicationData',
      codePageIndex: 0,
      children: children,
    );
  }

  /// Serialize only the Read field (for mark read/unread).
  static WbxmlElement serializeReadFlag(bool read) {
    return WbxmlElement(
      namespace: 'AirSync',
      tag: 'ApplicationData',
      codePageIndex: 0,
      children: [
        WbxmlElement.withText(
          namespace: 'Email',
          tag: 'Read',
          text: read ? '1' : '0',
          codePageIndex: 2,
        ),
      ],
    );
  }

  /// Serialize only the Flag field.
  static WbxmlElement serializeFlag(int flagStatus) {
    return WbxmlElement(
      namespace: 'AirSync',
      tag: 'ApplicationData',
      codePageIndex: 0,
      children: [
        WbxmlElement(
          namespace: 'Email',
          tag: 'Flag',
          codePageIndex: 2,
          children: [
            WbxmlElement.withText(
              namespace: 'Email',
              tag: 'Status',
              text: flagStatus.toString(),
              codePageIndex: 2,
            ),
          ],
        ),
      ],
    );
  }
}
