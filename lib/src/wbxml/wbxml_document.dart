/// WBXML DOM model for representing parsed WBXML documents.
library;

import 'dart:typed_data';

/// A WBXML document containing a root element.
class WbxmlDocument {
  /// WBXML version (typically 0x03 for version 1.3).
  final int version;

  /// Public identifier.
  final int publicId;

  /// Character set (IANA MIBenum, typically 0x6A for UTF-8).
  final int charset;

  /// Root element.
  final WbxmlElement root;

  WbxmlDocument({
    this.version = 0x03,
    this.publicId = 0x01,
    this.charset = 0x6A,
    required this.root,
  });

  @override
  String toString() => root.toXmlString();
}

/// A WBXML element node.
class WbxmlElement {
  /// Code page namespace (e.g., 'AirSync', 'FolderHierarchy').
  final String namespace;

  /// Tag name (e.g., 'Sync', 'SyncKey').
  final String tag;

  /// Code page index for encoding.
  final int codePageIndex;

  /// Text content (for leaf elements).
  String? text;

  /// Opaque binary data.
  Uint8List? opaque;

  /// Child elements.
  final List<WbxmlElement> children;

  WbxmlElement({
    required this.namespace,
    required this.tag,
    this.codePageIndex = 0,
    this.text,
    this.opaque,
    List<WbxmlElement>? children,
  }) : children = children ?? [];

  /// Find first child matching [ns] and [tagName].
  WbxmlElement? findChild(String ns, String tagName) {
    for (final child in children) {
      if (child.namespace == ns && child.tag == tagName) return child;
    }
    return null;
  }

  /// Find all children matching [ns] and [tagName].
  List<WbxmlElement> findChildren(String ns, String tagName) {
    return children
        .where((c) => c.namespace == ns && c.tag == tagName)
        .toList();
  }

  /// Get text content of first child matching [ns] and [tagName].
  String? childText(String ns, String tagName) {
    return findChild(ns, tagName)?.text;
  }

  /// Whether this element has any content (children, text, or opaque data).
  bool get hasContent => children.isNotEmpty || text != null || opaque != null;

  /// Create a simple element with text content.
  factory WbxmlElement.withText({
    required String namespace,
    required String tag,
    required String text,
    int codePageIndex = 0,
  }) {
    return WbxmlElement(
      namespace: namespace,
      tag: tag,
      codePageIndex: codePageIndex,
      text: text,
    );
  }

  /// Pretty-print as XML string for debugging.
  String toXmlString({int indent = 0}) {
    final pad = '  ' * indent;
    final buf = StringBuffer();

    if (text != null && children.isEmpty) {
      buf.write('$pad<$namespace:$tag>$text</$namespace:$tag>');
    } else if (opaque != null && children.isEmpty) {
      buf.write('$pad<$namespace:$tag>[opaque ${opaque!.length} bytes]'
          '</$namespace:$tag>');
    } else if (children.isEmpty && text == null && opaque == null) {
      buf.write('$pad<$namespace:$tag/>');
    } else {
      buf.writeln('$pad<$namespace:$tag>');
      for (final child in children) {
        buf.writeln(child.toXmlString(indent: indent + 1));
      }
      buf.write('$pad</$namespace:$tag>');
    }

    return buf.toString();
  }

  @override
  String toString() => toXmlString();
}
