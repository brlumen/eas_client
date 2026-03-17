/// ResolveRecipients command — resolve email addresses to contact information.
///
/// Can optionally retrieve free/busy schedule data for resolved recipients.
///
/// Reference: MS-ASCMD section 2.2.1.15
library;

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Type of resolved recipient.
enum ResolvedRecipientType {
  /// Resolved from the Global Address List.
  gal(1),

  /// Resolved from personal contacts.
  contact(2);

  final int value;
  const ResolvedRecipientType(this.value);

  static ResolvedRecipientType fromValue(int value) =>
      ResolvedRecipientType.values.firstWhere((e) => e.value == value,
          orElse: () => ResolvedRecipientType.gal);
}

/// A resolved recipient.
class EasResolvedRecipient {
  final String displayName;
  final String emailAddress;
  final ResolvedRecipientType type;

  /// Merged free/busy string (characters: 0=free, 1=tentative, 2=busy, 3=OOF, 4=no data).
  final String? mergedFreeBusy;

  /// S/MIME certificates (DER-encoded).
  final List<String> certificates;

  const EasResolvedRecipient({
    required this.displayName,
    required this.emailAddress,
    this.type = ResolvedRecipientType.gal,
    this.mergedFreeBusy,
    this.certificates = const [],
  });

  @override
  String toString() => 'EasResolvedRecipient($displayName <$emailAddress>)';
}

/// Result for a single recipient resolution request.
class ResolveRecipientsResponse {
  /// The address that was queried.
  final String to;

  /// Resolution status.
  final int status;

  /// Resolved recipients (may be multiple for ambiguous addresses).
  final List<EasResolvedRecipient> recipients;

  bool get isSuccess => status == 1;

  const ResolveRecipientsResponse({
    required this.to,
    required this.status,
    this.recipients = const [],
  });
}

class ResolveRecipientsCommand
    extends EasCommand<List<ResolveRecipientsResponse>> {
  final List<String> recipients;

  /// Maximum number of ambiguous recipients to return per address.
  final int maxAmbiguousRecipients;

  /// Start time for availability (free/busy) request. Both must be set for availability.
  final DateTime? availabilityStartTime;

  /// End time for availability (free/busy) request.
  final DateTime? availabilityEndTime;

  /// Certificate retrieval mode: 1=none, 2=full, 3=mini.
  final int? certificateRetrieval;

  /// Max length per recipient address.
  static const int maxRecipientLength = 1024;

  ResolveRecipientsCommand({
    required this.recipients,
    this.maxAmbiguousRecipients = 20,
    this.availabilityStartTime,
    this.availabilityEndTime,
    this.certificateRetrieval,
  }) {
    if (recipients.isEmpty) {
      throw ArgumentError.value(
        recipients.length,
        'recipients',
        'Must have at least one recipient',
      );
    }
    for (final r in recipients) {
      if (r.isEmpty || r.length > maxRecipientLength) {
        throw ArgumentError.value(
          r.length,
          'recipients',
          'Each recipient must be 1-$maxRecipientLength characters',
        );
      }
    }
  }

  @override
  String get commandName => 'ResolveRecipients';

  @override
  WbxmlDocument buildRequest() {
    final optionChildren = <WbxmlElement>[
      WbxmlElement.withText(
        namespace: 'ResolveRecipients',
        tag: 'MaxAmbiguousRecipients',
        text: maxAmbiguousRecipients.toString(),
        codePageIndex: 10,
      ),
    ];

    // Availability
    if (availabilityStartTime != null && availabilityEndTime != null) {
      optionChildren.add(WbxmlElement(
        namespace: 'ResolveRecipients',
        tag: 'Availability',
        codePageIndex: 10,
        children: [
          WbxmlElement.withText(
            namespace: 'ResolveRecipients',
            tag: 'StartTime',
            text: availabilityStartTime!.toUtc().toIso8601String(),
            codePageIndex: 10,
          ),
          WbxmlElement.withText(
            namespace: 'ResolveRecipients',
            tag: 'EndTime',
            text: availabilityEndTime!.toUtc().toIso8601String(),
            codePageIndex: 10,
          ),
        ],
      ));
    }

    // Certificate retrieval
    if (certificateRetrieval != null) {
      optionChildren.add(WbxmlElement.withText(
        namespace: 'ResolveRecipients',
        tag: 'CertificateRetrieval',
        text: certificateRetrieval.toString(),
        codePageIndex: 10,
      ));
    }

    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'ResolveRecipients',
        tag: 'ResolveRecipients',
        codePageIndex: 10,
        children: [
          WbxmlElement(
            namespace: 'ResolveRecipients',
            tag: 'Options',
            codePageIndex: 10,
            children: optionChildren,
          ),
          ...recipients.map(
            (r) => WbxmlElement.withText(
              namespace: 'ResolveRecipients',
              tag: 'To',
              text: r,
              codePageIndex: 10,
            ),
          ),
        ],
      ),
    );
  }

  @override
  List<ResolveRecipientsResponse> parseResponse(WbxmlDocument response) {
    final root = response.root;
    return root
        .findChildren('ResolveRecipients', 'Response')
        .map((resp) {
          final to = resp.childText('ResolveRecipients', 'To') ?? '';
          final status =
              int.tryParse(resp.childText('ResolveRecipients', 'Status') ?? '') ??
                  0;
          final resolved = resp
              .findChildren('ResolveRecipients', 'Recipient')
              .map((r) {
                final typeVal = int.tryParse(
                      r.childText('ResolveRecipients', 'Type') ?? '',
                    ) ??
                    1;

                // Availability
                String? mergedFreeBusy;
                final availEl =
                    r.findChild('ResolveRecipients', 'Availability');
                if (availEl != null) {
                  mergedFreeBusy = availEl.childText(
                      'ResolveRecipients', 'MergedFreeBusy');
                }

                // Certificates
                final certs = <String>[];
                final certsEl =
                    r.findChild('ResolveRecipients', 'Certificates');
                if (certsEl != null) {
                  for (final cert in certsEl.findChildren(
                      'ResolveRecipients', 'Certificate')) {
                    if (cert.text != null && cert.text!.isNotEmpty) {
                      certs.add(cert.text!);
                    }
                  }
                }

                return EasResolvedRecipient(
                  displayName:
                      r.childText('ResolveRecipients', 'DisplayName') ?? '',
                  emailAddress:
                      r.childText('ResolveRecipients', 'EmailAddress') ?? '',
                  type: ResolvedRecipientType.fromValue(typeVal),
                  mergedFreeBusy: mergedFreeBusy,
                  certificates: certs,
                );
              })
              .toList();

          return ResolveRecipientsResponse(
            to: to,
            status: status,
            recipients: resolved,
          );
        })
        .toList();
  }
}
