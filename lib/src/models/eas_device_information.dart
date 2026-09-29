/// Device properties sent with Settings `DeviceInformation` and in the
/// initial Provision request (MS-ASCMD 2.2.3.45, MS-ASPROV 2.2.2.53).
library;

import '../wbxml/wbxml_document.dart';
import 'wbxml_helpers.dart';

/// Client device information (`settings:DeviceInformation/Set`).
///
/// [imei] and [phoneNumber] are personal data and are never included in
/// `toString()`.
class EasDeviceInformation {
  final String? model;
  final String? imei;
  final String? friendlyName;
  final String? os;
  final String? osLanguage;
  final String? phoneNumber;
  final String? userAgent;

  /// Whether the device sends SMS through the server (EAS 14.0+).
  final bool? enableOutboundSms;

  /// Mobile operator name (EAS 14.0+).
  final String? mobileOperator;

  /// Max length of each value (MS-ASCMD 6.38 DeviceInformationStringType).
  static const maxLength = 1024;

  EasDeviceInformation({
    this.model,
    this.imei,
    this.friendlyName,
    this.os,
    this.osLanguage,
    this.phoneNumber,
    this.userAgent,
    this.enableOutboundSms,
    this.mobileOperator,
  }) {
    for (final v in [
      model,
      imei,
      friendlyName,
      os,
      osLanguage,
      phoneNumber,
      userAgent,
      mobileOperator,
    ]) {
      if (v != null && v.length > maxLength) {
        throw ArgumentError.value(
          v.length,
          'deviceInformation',
          'Each value must be at most $maxLength characters',
        );
      }
    }
  }

  /// `settings:DeviceInformation` element with a `Set` child.
  WbxmlElement toElement() {
    const ns = 'Settings';
    WbxmlElement t(String tag, String v) => WbxmlElement.withText(
      namespace: ns,
      tag: tag,
      text: v,
      codePageIndex: 18,
    );
    WbxmlElement c(String tag, List<WbxmlElement> ch) =>
        WbxmlElement(namespace: ns, tag: tag, codePageIndex: 18, children: ch);
    return c('DeviceInformation', [
      c('Set', [
        if (model != null) t('Model', model!),
        if (imei != null) t('IMEI', imei!),
        if (friendlyName != null) t('FriendlyName', friendlyName!),
        if (os != null) t('OS', os!),
        if (osLanguage != null) t('OSLanguage', osLanguage!),
        if (phoneNumber != null) t('PhoneNumber', phoneNumber!),
        if (userAgent != null) t('UserAgent', userAgent!),
        if (enableOutboundSms != null)
          t('EnableOutboundSMS', enableOutboundSms! ? '1' : '0'),
        if (mobileOperator != null) t('MobileOperator', mobileOperator!),
      ]),
    ]);
  }

  /// Status of a `DeviceInformation` response element, if present.
  static int? statusOf(WbxmlElement parent) => parent
      .findChild('Settings', 'DeviceInformation')
      ?.integer('Settings', 'Status');

  @override
  String toString() => 'EasDeviceInformation(model: $model, os: $os)';
}
