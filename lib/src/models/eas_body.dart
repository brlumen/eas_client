/// AirSyncBase body models (MS-ASAIRS 2.2.2.9 Body, 2.2.2.10 BodyPart).
library;

import '../wbxml/wbxml_document.dart';
import 'wbxml_helpers.dart';

/// Item body (`airsyncbase:Body`).
class EasBody {
  /// Body type: 1=plain text, 2=HTML, 3=RTF, 4=MIME.
  final int type;

  /// Body content (possibly truncated).
  final String? data;

  /// Estimated size of the full body in bytes.
  final int? estimatedDataSize;

  /// Whether [data] is truncated.
  final bool truncated;

  /// Plain-text preview (EAS 14.0+).
  final String? preview;

  /// ItemOperations multipart part index (`itemoperations:Part`).
  final int? part;

  const EasBody({
    this.type = 1,
    this.data,
    this.estimatedDataSize,
    this.truncated = false,
    this.preview,
    this.part,
  });

  /// Parse an `airsyncbase:Body` element.
  factory EasBody.fromElement(WbxmlElement el) => EasBody(
    type: el.integer('AirSyncBase', 'Type') ?? 1,
    data: el.str('AirSyncBase', 'Data'),
    estimatedDataSize: el.integer('AirSyncBase', 'EstimatedDataSize'),
    truncated: el.boolean('AirSyncBase', 'Truncated') ?? false,
    preview: el.str('AirSyncBase', 'Preview'),
    part: el.integer('ItemOperations', 'Part'),
  );

  /// `airsyncbase:Body` of [parent], or `null`.
  static EasBody? of(WbxmlElement parent) {
    final el = parent.findChild('AirSyncBase', 'Body');
    return el == null ? null : EasBody.fromElement(el);
  }

  /// EAS 2.5 body of [parent] in namespace [ns] (`Body`, `BodySize`,
  /// `BodyTruncated` of Calendar/Contacts/Tasks/Email), or `null`.
  static EasBody? legacyOf(WbxmlElement parent, String ns) {
    final data = parent.str(ns, 'Body');
    final truncated = parent.boolean(ns, 'BodyTruncated');
    if (data == null && truncated == null) return null;
    return EasBody(
      data: data,
      estimatedDataSize: parent.integer(ns, 'BodySize'),
      truncated: truncated ?? false,
    );
  }

  /// `airsyncbase:Body` of [parent], falling back to the EAS 2.5 body in
  /// namespace [ns].
  static EasBody? anyOf(WbxmlElement parent, String ns) =>
      of(parent) ?? legacyOf(parent, ns);

  /// Request element (Type + Data only are client-writable).
  static WbxmlElement toElement(String data, {int type = 1}) =>
      containerEl('AirSyncBase', 'Body', [
        textEl('AirSyncBase', 'Type', '$type'),
        textEl('AirSyncBase', 'Data', data),
      ]);

  @override
  String toString() => 'EasBody(type: $type, truncated: $truncated)';
}

/// Message part body (`airsyncbase:BodyPart`, EAS 14.1+).
class EasBodyPart {
  /// 1 = success, 176 = too many conversation messages.
  final int status;
  final int type;
  final int? estimatedDataSize;
  final bool truncated;
  final String? data;
  final String? preview;

  const EasBodyPart({
    required this.status,
    this.type = 2,
    this.estimatedDataSize,
    this.truncated = false,
    this.data,
    this.preview,
  });

  factory EasBodyPart.fromElement(WbxmlElement el) => EasBodyPart(
    status: el.integer('AirSyncBase', 'Status') ?? 1,
    type: el.integer('AirSyncBase', 'Type') ?? 2,
    estimatedDataSize: el.integer('AirSyncBase', 'EstimatedDataSize'),
    truncated: el.boolean('AirSyncBase', 'Truncated') ?? false,
    data: el.str('AirSyncBase', 'Data'),
    preview: el.str('AirSyncBase', 'Preview'),
  );

  @override
  String toString() => 'EasBodyPart(status: $status, type: $type)';
}

/// Body/BodyPart preference for Sync/ItemOperations/Search Options
/// (MS-ASAIRS 2.2.2.11 / 2.2.2.12).
class EasBodyPreference {
  /// Body type: 1=plain, 2=HTML, 3=RTF, 4=MIME.
  final int type;

  /// Truncation size in bytes.
  final int? truncationSize;

  /// Return the body only if it fits into [truncationSize].
  final bool? allOrNone;

  /// Preview length in characters (0-255, EAS 14.0+).
  final int? preview;

  const EasBodyPreference({
    required this.type,
    this.truncationSize,
    this.allOrNone,
    this.preview,
  });

  WbxmlElement _toElement(String tag) => containerEl('AirSyncBase', tag, [
    textEl('AirSyncBase', 'Type', '$type'),
    if (truncationSize != null)
      textEl('AirSyncBase', 'TruncationSize', '$truncationSize'),
    if (allOrNone != null)
      textEl('AirSyncBase', 'AllOrNone', allOrNone! ? '1' : '0'),
    if (preview != null) textEl('AirSyncBase', 'Preview', '$preview'),
  ]);

  /// `airsyncbase:BodyPreference` element.
  WbxmlElement toBodyPreference() => _toElement('BodyPreference');

  /// `airsyncbase:BodyPartPreference` element.
  WbxmlElement toBodyPartPreference() => _toElement('BodyPartPreference');
}
