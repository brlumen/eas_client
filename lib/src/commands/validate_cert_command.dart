/// ValidateCert command — validate S/MIME certificates on the server.
///
/// Reference: MS-ASCMD sections 2.2.1.22, 6.47, 6.48
library;

import 'dart:convert';
import 'dart:typed_data';

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'ValidateCert';

/// ValidateCert status codes (MS-ASCMD 2.2.3.177.18).
enum ValidateCertStatus {
  success(1, 'Success'),
  protocolError(2, 'Protocol error'),
  invalidSignature(3, 'The signature in the digital ID cannot be validated'),
  untrustedSource(4, 'The digital ID was issued by an untrusted source'),
  invalidChain(5, 'The certificate chain was not created correctly'),
  notForEmail(6, 'The digital ID is not valid for signing email messages'),
  expired(7, 'The digital ID has expired or is not yet valid'),
  inconsistentTimes(8, 'Validity periods in the chain are inconsistent'),
  improperUsage(9, 'A digital ID in the chain is used incorrectly'),
  missingInformation(10, 'Information of the digital ID is missing/incorrect'),
  chainRoleMismatch(11, 'End-entity/CA digital ID used in the wrong role'),
  addressMismatch(12, 'The digital ID does not match the email address'),
  revoked(13, 'The digital ID has been revoked'),
  revocationUnknown(14, 'Revocation status cannot be determined'),
  chainRevoked(15, 'A digital ID in the chain has been revoked'),
  cannotValidate(16, 'The digital ID cannot be validated'),
  serverError(17, 'An unknown server error occurred');

  final int code;
  final String description;

  const ValidateCertStatus(this.code, this.description);

  static ValidateCertStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Validation result for a single certificate.
class CertValidationResult {
  final int status;

  bool get isValid => status == 1;

  /// Typed [status], `null` if unknown.
  ValidateCertStatus? get statusInfo => ValidateCertStatus.fromCode(status);

  const CertValidationResult({required this.status});
}

/// Validate [certificates] (DER-encoded), optionally with the
/// intermediate [certificateChain].
///
/// Certificates are sent base64-encoded as string content (MS-ASCMD
/// 2.2.3.19.2). The result list has one entry per `Certificate` of the
/// response, or one per requested certificate with the top-level status
/// when the whole request failed.
class ValidateCertCommand extends EasCommand<List<CertValidationResult>> {
  final List<Uint8List> certificates;
  final List<Uint8List> certificateChain;

  /// `CheckCRL`: fail when the revocation status cannot be verified;
  /// null omits the element.
  final bool? checkCRL;

  ValidateCertCommand({
    required this.certificates,
    this.checkCRL = true,
    this.certificateChain = const [],
  }) {
    if (certificates.isEmpty) {
      throw ArgumentError.value(0, 'certificates', 'Must not be empty');
    }
  }

  @override
  String get commandName => 'ValidateCert';

  static List<WbxmlElement> _certs(List<Uint8List> certs) => [
    for (final c in certs) xText(_ns, 'Certificate', base64.encode(c)),
  ];

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'ValidateCert', [
      if (certificateChain.isNotEmpty)
        xEl(_ns, 'CertificateChain', _certs(certificateChain)),
      xEl(_ns, 'Certificates', _certs(certificates)),
      if (checkCRL != null) xText(_ns, 'CheckCRL', checkCRL! ? '1' : '0'),
    ]),
  );

  @override
  List<CertValidationResult> parseResponse(WbxmlDocument response) {
    final root = response.root;
    final certs = root.findChildren(_ns, 'Certificate');
    if (certs.isEmpty) {
      final status = xStatus(root, _ns);
      return [
        for (var i = 0; i < certificates.length; i++)
          CertValidationResult(status: status),
      ];
    }
    return [
      for (final c in certs) CertValidationResult(status: xStatus(c, _ns)),
    ];
  }
}
