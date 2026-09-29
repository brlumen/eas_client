/// Full content of a provisioning document (MS-ASPROV 2.2.2.28): every
/// `EASProvisionDoc` element as sent by the server, plus the typed values
/// not covered by [EasPolicy]'s defaults-based fields.
///
/// Policies are exposed, never enforced by this package.
library;

import '../wbxml/wbxml_document.dart';

const _ns = 'Provision';

/// `AllowBluetooth` values (MS-ASPROV 2.2.2.4).
enum BluetoothPolicy {
  /// 0 — Bluetooth is disabled.
  disabled(0),

  /// 1 — only hands-free configurations are allowed.
  handsFreeOnly(1),

  /// 2 — Bluetooth is allowed.
  allowed(2);

  final int value;
  const BluetoothPolicy(this.value);

  static BluetoothPolicy? fromValue(int? value) {
    for (final p in values) {
      if (p.value == value) return p;
    }
    return null;
  }
}

class EasProvisionDoc {
  /// Raw text of each scalar element present, keyed by tag
  /// (e.g. `MaxEmailAgeFilter`). An empty string means "no limit" for the
  /// `unsigned*OrEmpty` elements.
  final Map<String, String> values;

  /// `UnapprovedInROMApplicationList/ApplicationName`.
  final List<String> unapprovedInRomApplications;

  /// `ApprovedApplicationList/Hash` (SHA-1 hashes, base64/hex as sent).
  final List<String> approvedApplicationHashes;

  /// Raw `Data` text for `MS-WAP-Provisioning-XML` (protocol 2.5).
  final String? wapProvisioningXml;

  const EasProvisionDoc({
    this.values = const {},
    this.unapprovedInRomApplications = const [],
    this.approvedApplicationHashes = const [],
    this.wapProvisioningXml,
  });

  static const _lists = {
    'UnapprovedInROMApplicationList',
    'ApprovedApplicationList',
  };

  /// Parse an `EASProvisionDoc` element.
  factory EasProvisionDoc.fromElement(WbxmlElement doc) {
    List<String> list(String container, String item) => [
      ...?doc
          .findChild(_ns, container)
          ?.findChildren(_ns, item)
          .map((e) => e.text ?? '')
          .where((t) => t.isNotEmpty),
    ];
    return EasProvisionDoc(
      values: {
        for (final e in doc.children)
          if (e.namespace == _ns && !_lists.contains(e.tag))
            e.tag: e.text ?? '',
      },
      unapprovedInRomApplications: list(
        'UnapprovedInROMApplicationList',
        'ApplicationName',
      ),
      approvedApplicationHashes: list('ApprovedApplicationList', 'Hash'),
    );
  }

  /// Whether [tag] was present in the document.
  bool has(String tag) => values.containsKey(tag);

  /// Integer value of [tag]; null when absent or empty (no limit).
  int? integer(String tag) => int.tryParse(values[tag] ?? '');

  /// Boolean value of [tag] (`1`/`true`); null when absent.
  bool? boolean(String tag) => switch (values[tag]?.toLowerCase()) {
    null => null,
    '1' || 'true' => true,
    _ => false,
  };

  /// `MaxCalendarAgeFilter` (0 = all, 4 = 2 weeks, 5 = 1 month,
  /// 6 = 3 months, 7 = 6 months).
  int? get maxCalendarAgeFilter => integer('MaxCalendarAgeFilter');

  /// `MaxEmailAgeFilter` (0 = all, 1-5 = 1 day ... 1 month).
  int? get maxEmailAgeFilter => integer('MaxEmailAgeFilter');

  /// `RequireSignedSMIMEAlgorithm` (0 = SHA1, 1 = MD5).
  int? get requireSignedSMIMEAlgorithm =>
      integer('RequireSignedSMIMEAlgorithm');

  /// `RequireEncryptionSMIMEAlgorithm` (0 = 3DES, 1 = DES, 2 = RC2-128,
  /// 3 = RC2-64, 4 = RC2-40).
  int? get requireEncryptionSMIMEAlgorithm =>
      integer('RequireEncryptionSMIMEAlgorithm');

  /// `AllowSMIMEEncryptionAlgorithmNegotiation` (0 = not allowed,
  /// 1 = strongest only, 2 = any).
  int? get allowSMIMEEncryptionAlgorithmNegotiation =>
      integer('AllowSMIMEEncryptionAlgorithmNegotiation');

  /// `AllowBluetooth` (0/1/2).
  BluetoothPolicy? get allowBluetooth =>
      BluetoothPolicy.fromValue(integer('AllowBluetooth'));

  @override
  String toString() => 'EasProvisionDoc(${values.length} elements)';
}
