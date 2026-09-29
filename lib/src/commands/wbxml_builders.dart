/// Internal WBXML element builders for command requests.
///
/// The code page index is resolved from the namespace via
/// [CodePageRegistry]. Not exported from the public API.
library;

import 'dart:typed_data';

import '../wbxml/code_pages/code_page_registry.dart';
import '../wbxml/wbxml_document.dart';

int _cp(String ns) {
  final page = CodePageRegistry.instance.getByNamespace(ns);
  if (page == null) throw ArgumentError.value(ns, 'ns', 'Unknown namespace');
  return page.pageIndex;
}

/// Container element (empty tag when [children] is empty).
WbxmlElement xEl(String ns, String tag, [List<WbxmlElement>? children]) =>
    WbxmlElement(
      namespace: ns,
      tag: tag,
      codePageIndex: _cp(ns),
      children: children,
    );

/// Leaf element with text content.
WbxmlElement xText(String ns, String tag, Object value) =>
    WbxmlElement.withText(
      namespace: ns,
      tag: tag,
      text: '$value',
      codePageIndex: _cp(ns),
    );

/// Leaf element with opaque content.
WbxmlElement xOpaque(String ns, String tag, Uint8List data) =>
    WbxmlElement(namespace: ns, tag: tag, codePageIndex: _cp(ns), opaque: data);

/// Status code of the direct `Status` child of [el] (0 if absent).
int xStatus(WbxmlElement? el, String ns) =>
    int.tryParse(el?.childText(ns, 'Status') ?? '') ?? 0;

/// Validate a zero-based `m-n` range (0 <= m <= n <= [max]).
void checkRange(int start, int end, int max, String name) {
  if (start < 0 || end < start || end > max) {
    throw ArgumentError.value(
      '$start-$end',
      name,
      'Must satisfy 0 <= start <= end <= $max',
    );
  }
}

/// Validate a string length (1..[max] characters, or 0..[max] if
/// [allowEmpty]).
void checkLength(
  String value,
  int max,
  String name, {
  bool allowEmpty = false,
}) {
  if ((!allowEmpty && value.isEmpty) || value.length > max) {
    throw ArgumentError.value(
      value.length,
      name,
      'Length must be ${allowEmpty ? 0 : 1}-$max',
    );
  }
}
