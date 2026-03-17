/// Code Page 17: AirSyncBase namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.18
library;

import 'code_page.dart';

class AirSyncBaseCodePage extends CodePage {
  static final AirSyncBaseCodePage instance = AirSyncBaseCodePage._();

  AirSyncBaseCodePage._();

  @override
  int get pageIndex => 17;

  @override
  String get namespace => 'AirSyncBase';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'BodyPreference',
        0x06: 'Type',
        0x07: 'TruncationSize',
        0x08: 'AllOrNone',
        0x0A: 'Body',
        0x0B: 'Data',
        0x0C: 'EstimatedDataSize',
        0x0D: 'Truncated',
        0x0E: 'Attachments',
        0x0F: 'Attachment',
        0x10: 'DisplayName',
        0x11: 'FileReference',
        0x12: 'Method',
        0x13: 'ContentId',
        0x14: 'ContentLocation',
        0x15: 'IsInline',
        0x16: 'NativeBodyType',
        0x17: 'ContentType',
        0x18: 'Preview',
        0x19: 'BodyPartPreference',
        0x1A: 'BodyPart',
        0x1B: 'Status',
        0x1C: 'Add',
        0x1D: 'Delete',
        0x1E: 'ClientId',
        0x1F: 'Content',
        0x20: 'Location',
        0x21: 'Annotation',
        0x22: 'Street',
        0x23: 'City',
        0x24: 'State',
        0x25: 'Country',
        0x26: 'PostalCode',
        0x27: 'Latitude',
        0x28: 'Longitude',
        0x29: 'Accuracy',
        0x2A: 'Altitude',
        0x2B: 'AltitudeAccuracy',
        0x2C: 'LocationUri',
        0x2D: 'InstanceId',
        0x2E: 'Picture',
        0x2F: 'MaxSize',
        0x30: 'MaxPictures',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
