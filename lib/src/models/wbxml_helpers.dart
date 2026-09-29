/// Internal helpers for reading/writing EAS content-class elements.
///
/// Not exported from the public API.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../wbxml/wbxml_document.dart';

/// Code page index by namespace (MS-ASWBXML) for the namespaces used by
/// content classes.
const Map<String, int> _codePages = {
  'AirSync': 0,
  'Contacts': 1,
  'Email': 2,
  'Calendar': 4,
  'MeetingResponse': 8,
  'Tasks': 9,
  'Contacts2': 12,
  'AirSyncBase': 17,
  'ComposeMail': 21,
  'Email2': 22,
  'Notes': 23,
  'RightsManagement': 24,
};

int _cp(String ns) => _codePages[ns] ?? 0;

/// Leaf element with text.
WbxmlElement textEl(String ns, String tag, String text) =>
    WbxmlElement.withText(
      namespace: ns,
      tag: tag,
      text: text,
      codePageIndex: _cp(ns),
    );

/// Container element.
WbxmlElement containerEl(String ns, String tag, List<WbxmlElement> children) =>
    WbxmlElement(
      namespace: ns,
      tag: tag,
      codePageIndex: _cp(ns),
      children: children,
    );

/// Empty element (e.g. `<Email2:Send/>`, ghosting `Supported` entries).
WbxmlElement emptyEl(String ns, String tag) =>
    WbxmlElement(namespace: ns, tag: tag, codePageIndex: _cp(ns));

/// Opaque element.
WbxmlElement opaqueEl(String ns, String tag, Uint8List data) =>
    WbxmlElement(namespace: ns, tag: tag, codePageIndex: _cp(ns), opaque: data);

/// `ApplicationData` container.
WbxmlElement applicationData(List<WbxmlElement> children) =>
    containerEl('AirSync', 'ApplicationData', children);

/// Adds text elements only for non-null values.
extension WbxmlChildrenBuilder on List<WbxmlElement> {
  void addText(String ns, String tag, Object? value) {
    if (value == null) return;
    if (value is String && value.isEmpty) return;
    add(textEl(ns, tag, value is bool ? (value ? '1' : '0') : '$value'));
  }

  /// [wallClock]: write the wall-clock components of [value] without
  /// converting to UTC (for "local time" elements such as
  /// `tasks:StartDate`).
  void addDate(
    String ns,
    String tag,
    DateTime? value, {
    bool compact = false,
    bool wallClock = false,
  }) {
    if (value == null) return;
    add(
      textEl(
        ns,
        tag,
        compact
            ? compactDateTime(value)
            : isoDateTime(value, wallClock: wallClock),
      ),
    );
  }

  void addList(String ns, String container, String item, List<String>? values) {
    if (values == null || values.isEmpty) return;
    add(
      containerEl(ns, container, [for (final v in values) textEl(ns, item, v)]),
    );
  }
}

/// Compact DateTime (MS-ASDTYPE 2.7.2): `yyyyMMddTHHmmssZ`.
String compactDateTime(DateTime dt) {
  final u = dt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
      'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// dateTime (MS-ASDTYPE 2.3): `yyyy-MM-ddTHH:mm:ss.SSSZ`.
String isoDateTime(DateTime dt, {bool wallClock = false}) {
  final u = wallClock ? dt : dt.toUtc();
  String pad(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  return '${pad(u.year, 4)}-${pad(u.month)}-${pad(u.day)}'
      'T${pad(u.hour)}:${pad(u.minute)}:${pad(u.second)}.${pad(u.millisecond, 3)}Z';
}

/// Numeric protocol version, e.g. '16.1' → 161, '2.5' → 25, '12.0' → 120.
int protocolVersionValue(String version) {
  final parts = version.split('.');
  final major = int.tryParse(parts.first) ?? 0;
  final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return major * 10 + minor;
}

/// Read helpers for content-class elements.
extension WbxmlReader on WbxmlElement {
  /// Text of child (opaque content is decoded as UTF-8).
  String? str(String ns, String tag) {
    final el = findChild(ns, tag);
    if (el == null) return null;
    if (el.text != null) return el.text;
    final o = el.opaque;
    return o == null ? null : utf8.decode(o, allowMalformed: true);
  }

  int? integer(String ns, String tag) => int.tryParse(str(ns, tag) ?? '');

  double? dbl(String ns, String tag) => double.tryParse(str(ns, tag) ?? '');

  /// Boolean (`1`/`true`), `null` if absent.
  bool? boolean(String ns, String tag) {
    final v = str(ns, tag);
    if (v == null) return null;
    return v == '1' || v.toLowerCase() == 'true';
  }

  /// DateTime in dateTime or Compact DateTime format.
  DateTime? date(String ns, String tag) {
    final v = str(ns, tag);
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Raw bytes: opaque data, or the UTF-8 text.
  Uint8List? bytes(String ns, String tag) {
    final el = findChild(ns, tag);
    if (el == null) return null;
    if (el.opaque != null) return el.opaque;
    final t = el.text;
    return t == null ? null : Uint8List.fromList(utf8.encode(t));
  }

  /// Text of a string-or-opaque child; opaque content is base64-encoded
  /// (used for binary IDs such as `Email2:ConversationId`).
  String? idString(String ns, String tag) {
    final el = findChild(ns, tag);
    if (el == null) return null;
    if (el.opaque != null) return base64.encode(el.opaque!);
    return el.text;
  }

  /// Items of a list container (e.g. `Categories/Category`).
  List<String>? list(String ns, String container, String item) =>
      findChild(ns, container)
          ?.findChildren(ns, item)
          .map((e) => e.text ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
}
