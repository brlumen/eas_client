/// ResolveRecipients command — resolve recipients to GAL entries or
/// contacts, optionally with S/MIME certificates, free/busy data and
/// contact photos.
///
/// Reference: MS-ASCMD sections 2.2.1.15, 6.31, 6.32
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/wbxml_helpers.dart' show isoDateTime;
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'ResolveRecipients';

/// Type of resolved recipient (`Type`).
enum ResolvedRecipientType {
  /// Resolved from the Global Address List.
  gal(1),

  /// Resolved from personal contacts.
  contact(2);

  final int value;
  const ResolvedRecipientType(this.value);

  static ResolvedRecipientType fromValue(int value) => ResolvedRecipientType
      .values
      .firstWhere((e) => e.value == value, orElse: () => gal);
}

/// `CertificateRetrieval` option.
enum CertificateRetrieval {
  /// Do not retrieve certificates.
  none(1),

  /// Retrieve full certificates (`Certificate`).
  full(2),

  /// Retrieve mini certificates (`MiniCertificate`).
  mini(3);

  final int value;
  const CertificateRetrieval(this.value);
}

/// ResolveRecipients status codes (MS-ASCMD 2.2.3.177.12): top-level,
/// `Response`, `Availability`, `Certificates` and `Picture` scopes.
enum ResolveRecipientsStatus {
  success(1, 'Success'),
  ambiguous(2, 'Ambiguous recipient; suggestions returned'),
  ambiguousPartial(3, 'Ambiguous recipient; partial list of suggestions'),
  notFound(4, 'Recipient did not resolve'),
  protocolError(5, 'Protocol error: invalid parameter or range exceeded'),
  serverError(6, 'Server error; retry the request'),
  noValidCertificate(7, 'Recipient has no valid S/MIME certificate'),
  certificateLimit(8, 'Global certificate limit reached'),
  tooManyRecipients(160, 'Too many exactly matched recipients for free/busy'),
  distributionGroupTooLarge(161, 'Distribution group has too many members'),
  freeBusyTemporaryFailure(162, 'Free/busy temporarily unavailable'),
  freeBusyUnavailable(163, 'Free/busy data unavailable for the recipient'),
  noPhoto(173, 'The user has no contact photo'),
  photoTooLarge(174, 'The contact photo exceeds MaxSize'),
  tooManyPhotos(175, 'The number of photos exceeds MaxPictures');

  final int code;
  final String description;

  const ResolveRecipientsStatus(this.code, this.description);

  static ResolveRecipientsStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Free/busy data of a recipient (`Availability`, EAS 14.0+).
class RecipientAvailability {
  final int status;

  /// One character per interval: 0 = free, 1 = tentative, 2 = busy,
  /// 3 = OOF, 4 = no data.
  final String? mergedFreeBusy;

  const RecipientAvailability({required this.status, this.mergedFreeBusy});

  bool get isSuccess => status == 1;
  ResolveRecipientsStatus? get statusInfo =>
      ResolveRecipientsStatus.fromCode(status);
}

/// S/MIME certificates of a recipient (`Certificates`).
class RecipientCertificates {
  final int status;

  /// Number of valid certificates (`CertificateCount`).
  final int? certificateCount;

  /// Number of recipients in a distribution list (`RecipientCount`).
  final int? recipientCount;

  /// DER-encoded certificates (base64 `Certificate` values decoded).
  final List<Uint8List> certificates;

  /// Mini certificate (base64 `MiniCertificate` decoded).
  final Uint8List? miniCertificate;

  const RecipientCertificates({
    required this.status,
    this.certificateCount,
    this.recipientCount,
    this.certificates = const [],
    this.miniCertificate,
  });

  bool get isSuccess => status == 1;
  ResolveRecipientsStatus? get statusInfo =>
      ResolveRecipientsStatus.fromCode(status);
}

/// Contact photo of a recipient (`Picture`, EAS 14.1+).
class RecipientPicture {
  final int status;
  final Uint8List? data;

  const RecipientPicture({required this.status, this.data});

  bool get isSuccess => status == 1;
  ResolveRecipientsStatus? get statusInfo =>
      ResolveRecipientsStatus.fromCode(status);
}

/// A resolved recipient (`Recipient`).
class EasResolvedRecipient {
  final String displayName;
  final String emailAddress;
  final ResolvedRecipientType type;
  final RecipientAvailability? availability;
  final RecipientCertificates? certificateInfo;

  /// Contact photos (the schema allows several).
  final List<RecipientPicture> pictures;

  const EasResolvedRecipient({
    required this.displayName,
    required this.emailAddress,
    this.type = ResolvedRecipientType.gal,
    this.availability,
    this.certificateInfo,
    this.pictures = const [],
  });

  /// Shortcut for [RecipientAvailability.mergedFreeBusy].
  String? get mergedFreeBusy => availability?.mergedFreeBusy;

  /// Shortcut for [RecipientCertificates.certificates].
  List<Uint8List> get certificates => certificateInfo?.certificates ?? const [];

  /// First contact photo, if any.
  RecipientPicture? get picture => pictures.firstOrNull;

  @override
  String toString() => 'EasResolvedRecipient(type: ${type.name})';
}

/// Result for a single `To` of the request (`Response`).
class ResolveRecipientsResponse {
  /// The queried recipient.
  final String to;

  /// Resolution status (1-4) or the top-level status when the whole
  /// request failed.
  final int status;

  /// Number of recipients returned (`RecipientCount`).
  final int? recipientCount;

  /// Resolved recipients (several for ambiguous names).
  final List<EasResolvedRecipient> recipients;

  bool get isSuccess => status == 1;
  ResolveRecipientsStatus? get statusInfo =>
      ResolveRecipientsStatus.fromCode(status);

  const ResolveRecipientsResponse({
    required this.to,
    required this.status,
    this.recipientCount,
    this.recipients = const [],
  });
}

/// Resolve up to 100 recipients.
class ResolveRecipientsCommand
    extends EasCommand<List<ResolveRecipientsResponse>> {
  final List<String> recipients;

  /// `CertificateRetrieval` (null = omitted, server default none).
  final CertificateRetrieval? certificateRetrieval;

  /// `MaxCertificates` (0-9999).
  final int? maxCertificates;

  /// `MaxAmbiguousRecipients` (0-9999).
  final int? maxAmbiguousRecipients;

  /// Free/busy window (`Availability`, EAS 14.0+); end time is optional.
  final DateTime? availabilityStartTime;
  final DateTime? availabilityEndTime;

  /// Request contact photos (`Picture`, EAS 14.1+).
  final bool picture;

  /// `Picture/MaxSize` in bytes.
  final int? pictureMaxSize;

  /// `Picture/MaxPictures`.
  final int? maxPictures;

  /// Max `To` length and count (MS-ASCMD 6.31).
  static const int maxRecipientLength = 256;
  static const int maxRecipients = 100;

  ResolveRecipientsCommand({
    required this.recipients,
    this.certificateRetrieval,
    this.maxCertificates,
    this.maxAmbiguousRecipients,
    this.availabilityStartTime,
    this.availabilityEndTime,
    this.picture = false,
    this.pictureMaxSize,
    this.maxPictures,
  }) {
    if (recipients.isEmpty || recipients.length > maxRecipients) {
      throw ArgumentError.value(
        recipients.length,
        'recipients',
        'Must have 1-$maxRecipients recipients',
      );
    }
    for (final r in recipients) {
      checkLength(r, maxRecipientLength, 'recipients');
    }
    _check(maxCertificates, 'maxCertificates');
    _check(maxAmbiguousRecipients, 'maxAmbiguousRecipients');
    if (availabilityEndTime != null && availabilityStartTime == null) {
      throw ArgumentError('availabilityEndTime requires availabilityStartTime');
    }
    if ((pictureMaxSize != null || maxPictures != null) && !picture) {
      throw ArgumentError('pictureMaxSize/maxPictures require picture');
    }
  }

  static void _check(int? value, String name) {
    if (value != null && (value < 0 || value > 9999)) {
      throw ArgumentError.value(value, name, 'Must be 0-9999');
    }
  }

  @override
  String get commandName => 'ResolveRecipients';

  @override
  WbxmlDocument buildRequest() {
    final start = availabilityStartTime;
    final end = availabilityEndTime;
    final options = [
      if (certificateRetrieval != null)
        xText(_ns, 'CertificateRetrieval', certificateRetrieval!.value),
      if (maxCertificates != null)
        xText(_ns, 'MaxCertificates', maxCertificates!),
      if (maxAmbiguousRecipients != null)
        xText(_ns, 'MaxAmbiguousRecipients', maxAmbiguousRecipients!),
      if (start != null)
        xEl(_ns, 'Availability', [
          xText(_ns, 'StartTime', isoDateTime(start)),
          if (end != null) xText(_ns, 'EndTime', isoDateTime(end)),
        ]),
      if (picture)
        xEl(_ns, 'Picture', [
          if (pictureMaxSize != null) xText(_ns, 'MaxSize', pictureMaxSize!),
          if (maxPictures != null) xText(_ns, 'MaxPictures', maxPictures!),
        ]),
    ];
    return WbxmlDocument(
      root: xEl(_ns, 'ResolveRecipients', [
        for (final r in recipients) xText(_ns, 'To', r),
        if (options.isNotEmpty) xEl(_ns, 'Options', options),
      ]),
    );
  }

  @override
  List<ResolveRecipientsResponse> parseResponse(WbxmlDocument response) {
    final root = response.root;
    final responses = root.findChildren(_ns, 'Response');
    if (responses.isEmpty && root.findChild(_ns, 'Status') != null) {
      // Whole-request failure (e.g. 5 = protocol error, 6 = server error).
      final status = xStatus(root, _ns);
      return [
        for (final to in recipients)
          ResolveRecipientsResponse(to: to, status: status),
      ];
    }
    return [
      for (final resp in responses)
        ResolveRecipientsResponse(
          to: resp.childText(_ns, 'To') ?? '',
          status: xStatus(resp, _ns),
          recipientCount: _int(resp, 'RecipientCount'),
          recipients: [
            for (final r in resp.findChildren(_ns, 'Recipient')) _recipient(r),
          ],
        ),
    ];
  }

  static int? _int(WbxmlElement el, String tag) =>
      int.tryParse(el.childText(_ns, tag) ?? '');

  static EasResolvedRecipient _recipient(WbxmlElement r) {
    final avail = r.findChild(_ns, 'Availability');
    final certs = r.findChild(_ns, 'Certificates');
    return EasResolvedRecipient(
      displayName: r.childText(_ns, 'DisplayName') ?? '',
      emailAddress: r.childText(_ns, 'EmailAddress') ?? '',
      type: ResolvedRecipientType.fromValue(_int(r, 'Type') ?? 1),
      availability: avail == null
          ? null
          : RecipientAvailability(
              status: xStatus(avail, _ns),
              mergedFreeBusy: avail.childText(_ns, 'MergedFreeBusy'),
            ),
      certificateInfo: certs == null
          ? null
          : RecipientCertificates(
              status: xStatus(certs, _ns),
              certificateCount: _int(certs, 'CertificateCount'),
              recipientCount: _int(certs, 'RecipientCount'),
              certificates: [
                for (final c in certs.findChildren(_ns, 'Certificate'))
                  ?_binary(c),
              ],
              miniCertificate: switch (certs.findChild(
                _ns,
                'MiniCertificate',
              )) {
                final m? => _binary(m),
                null => null,
              },
            ),
      pictures: [
        for (final p in r.findChildren(_ns, 'Picture'))
          RecipientPicture(
            status: xStatus(p, _ns),
            data: switch (p.findChild(_ns, 'Data')) {
              final d? => _binary(d),
              null => null,
            },
          ),
      ],
    );
  }

  /// Opaque content, or base64 text decoded (null if empty/invalid).
  static Uint8List? _binary(WbxmlElement el) {
    if (el.opaque case final o? when o.isNotEmpty) return o;
    final text = el.text?.replaceAll(RegExp(r'\s'), '');
    if (text == null || text.isEmpty) return null;
    try {
      return base64.decode(text);
    } on FormatException {
      return null;
    }
  }
}
