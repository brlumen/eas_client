/// ValidateCert command — validate S/MIME certificates.
///
/// Sends DER-encoded certificates to the server for validation.
/// The server checks revocation status (CRL/OCSP) and chain trust.
///
/// Reference: MS-ASCMD section 2.2.1.22
library;

import 'dart:typed_data';

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Validation result for a single certificate.
class CertValidationResult {
  /// Validation status: 1=valid, 17=invalid certificate, 18=revoked,
  /// 19=expiration date invalid, 20=chain missing, 21=chain not trusted.
  final int status;

  bool get isValid => status == 1;

  const CertValidationResult({required this.status});
}

class ValidateCertCommand extends EasCommand<List<CertValidationResult>> {
  /// DER-encoded certificates to validate.
  final List<Uint8List> certificates;

  /// Whether to check certificate revocation list.
  final bool checkCRL;

  /// Certificate chain (intermediate CA certificates), if available.
  final List<Uint8List> certificateChain;

  ValidateCertCommand({
    required this.certificates,
    this.checkCRL = true,
    this.certificateChain = const [],
  });

  @override
  String get commandName => 'ValidateCert';

  @override
  WbxmlDocument buildRequest() {
    final certChildren = certificates.map((cert) {
      return WbxmlElement(
        namespace: 'ValidateCert',
        tag: 'Certificate',
        codePageIndex: 11,
        opaque: cert,
      );
    }).toList();

    final chainChildren = certificateChain.map((cert) {
      return WbxmlElement(
        namespace: 'ValidateCert',
        tag: 'Certificate',
        codePageIndex: 11,
        opaque: cert,
      );
    }).toList();

    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'ValidateCert',
        tag: 'ValidateCert',
        codePageIndex: 11,
        children: [
          WbxmlElement(
            namespace: 'ValidateCert',
            tag: 'Certificates',
            codePageIndex: 11,
            children: certChildren,
          ),
          if (chainChildren.isNotEmpty)
            WbxmlElement(
              namespace: 'ValidateCert',
              tag: 'CertificateChain',
              codePageIndex: 11,
              children: chainChildren,
            ),
          WbxmlElement.withText(
            namespace: 'ValidateCert',
            tag: 'CheckCRL',
            text: checkCRL ? '1' : '0',
            codePageIndex: 11,
          ),
        ],
      ),
    );
  }

  @override
  List<CertValidationResult> parseResponse(WbxmlDocument response) {
    final root = response.root;
    // Each Certificate element in the response has a Status child.
    final certsEl = root.findChild('ValidateCert', 'Certificates');
    if (certsEl == null) return [];

    return certsEl
        .findChildren('ValidateCert', 'Certificate')
        .map((cert) {
          final status =
              int.tryParse(cert.childText('ValidateCert', 'Status') ?? '') ?? 0;
          return CertValidationResult(status: status);
        })
        .toList();
  }
}
