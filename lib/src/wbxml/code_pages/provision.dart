/// Code Page 14: Provision namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.15
library;

import 'code_page.dart';

class ProvisionCodePage extends CodePage {
  static final ProvisionCodePage instance = ProvisionCodePage._();

  ProvisionCodePage._();

  @override
  int get pageIndex => 14;

  @override
  String get namespace => 'Provision';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Provision',
        0x06: 'Policies',
        0x07: 'Policy',
        0x08: 'PolicyType',
        0x09: 'PolicyKey',
        0x0A: 'Data',
        0x0B: 'Status',
        0x0C: 'RemoteWipe',
        0x0D: 'EASProvisionDoc',
        0x0E: 'DevicePasswordEnabled',
        0x0F: 'AlphanumericDevicePasswordRequired',
        0x10: 'RequireStorageCardEncryption',
        0x11: 'PasswordRecoveryEnabled',
        0x13: 'AttachmentsEnabled',
        0x14: 'MinDevicePasswordLength',
        0x15: 'MaxInactivityTimeDeviceLock',
        0x16: 'MaxDevicePasswordFailedAttempts',
        0x17: 'MaxAttachmentSize',
        0x18: 'AllowSimpleDevicePassword',
        0x19: 'DevicePasswordExpiration',
        0x1A: 'DevicePasswordHistory',
        0x1B: 'AllowStorageCard',
        0x1C: 'AllowCamera',
        0x1D: 'RequireDeviceEncryption',
        0x1E: 'AllowUnsignedApplications',
        0x1F: 'AllowUnsignedInstallationPackages',
        0x20: 'MinDevicePasswordComplexCharacters',
        0x21: 'AllowWiFi',
        0x22: 'AllowTextMessaging',
        0x23: 'AllowPOPIMAPEmail',
        0x24: 'AllowBluetooth',
        0x25: 'AllowIrDA',
        0x26: 'RequireManualSyncWhenRoaming',
        0x27: 'AllowDesktopSync',
        0x28: 'MaxCalendarAgeFilter',
        0x29: 'AllowHTMLEmail',
        0x2A: 'MaxEmailAgeFilter',
        0x2B: 'MaxEmailBodyTruncationSize',
        0x2C: 'MaxEmailHTMLBodyTruncationSize',
        0x2D: 'RequireSignedSMIMEMessages',
        0x2E: 'RequireEncryptedSMIMEMessages',
        0x2F: 'RequireSignedSMIMEAlgorithm',
        0x30: 'RequireEncryptionSMIMEAlgorithm',
        0x31: 'AllowSMIMEEncryptionAlgorithmNegotiation',
        0x32: 'AllowSMIMESoftCerts',
        0x33: 'AllowBrowser',
        0x34: 'AllowConsumerEmail',
        0x35: 'AllowRemoteDesktop',
        0x36: 'AllowInternetSharing',
        0x37: 'UnapprovedInROMApplicationList',
        0x38: 'ApplicationName',
        0x39: 'ApprovedApplicationList',
        0x3A: 'Hash',
        0x3B: 'AccountOnlyRemoteWipe',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
