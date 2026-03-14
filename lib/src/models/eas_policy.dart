/// EAS provisioning policy model.
///
/// Status values defined in MS-ASPROV specification.
library;

/// Status of the Provision element in server response.
///
/// Reference: [MS-ASPROV] section 2.2.2.54.2
enum ProvisionStatus {
  /// 1 — Success.
  success(1),

  /// 2 — Protocol error.
  protocolError(2),

  /// 3 — General server error.
  serverError(3);

  final int code;
  const ProvisionStatus(this.code);

  static ProvisionStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Status of the Policy element in server response.
///
/// Reference: [MS-ASPROV] section 2.2.2.54.1
enum PolicyStatus {
  /// 1 — Success.
  success(1),

  /// 2 — No policy for this client.
  noPolicyForClient(2),

  /// 3 — Unknown PolicyType value.
  unknownPolicyType(3),

  /// 4 — Policy data on server is corrupted.
  policyDataCorrupted(4),

  /// 5 — Client is acknowledging the wrong policy key.
  wrongPolicyKey(5);

  final int code;
  const PolicyStatus(this.code);

  static PolicyStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Status sent by client in Policy acknowledgement request.
///
/// Reference: [MS-ASPROV] section 2.2.2.54.1
enum PolicyAckStatus {
  /// 1 — Success.
  success(1),

  /// 2 — Partial success (at least PIN was enabled).
  partialSuccess(2),

  /// 3 — Client did not apply the policy at all.
  notApplied(3),

  /// 4 — Client claims to have been provisioned by a third party.
  thirdPartyProvisioned(4);

  final int code;
  const PolicyAckStatus(this.code);
}

/// Security policies from EASProvisionDoc.
///
/// Reference: MS-ASPROV section 2.2.2.28
class EasPolicy {
  final String policyKey;
  final String policyType;
  final PolicyStatus status;

  // Password policies
  final bool devicePasswordEnabled;
  final int minDevicePasswordLength;
  final bool alphanumericPasswordRequired;
  final bool allowSimplePassword;
  final int minDevicePasswordComplexCharacters;
  final int devicePasswordExpiration;
  final int devicePasswordHistory;
  final int maxDevicePasswordFailedAttempts;
  final int maxInactivityTimeLock;

  // Encryption
  final bool requireDeviceEncryption;
  final bool requireStorageCardEncryption;

  // Features
  final bool allowCamera;
  final bool allowBrowser;
  final bool allowConsumerEmail;
  final bool allowDesktopSync;
  final bool allowHTMLEmail;
  final bool allowInternetSharing;
  final bool allowIrDA;
  final bool allowPOPIMAPEmail;
  final bool allowRemoteDesktop;
  final bool allowTextMessaging;
  final bool allowWiFi;
  final bool allowBluetooth;
  final bool allowStorageCard;
  final bool allowUnsignedApplications;
  final bool allowUnsignedInstallationPackages;
  final bool attachmentsEnabled;
  final bool passwordRecoveryEnabled;
  final bool requireManualSyncWhenRoaming;

  // S/MIME
  final bool requireSignedSMIMEMessages;
  final bool requireEncryptedSMIMEMessages;
  final bool allowSMIMESoftCerts;

  // Size limits
  final int maxAttachmentSize;
  final int maxEmailBodyTruncationSize;
  final int maxEmailHTMLBodyTruncationSize;

  const EasPolicy({
    required this.policyKey,
    this.policyType = 'MS-EAS-Provisioning-WBXML',
    this.status = PolicyStatus.success,
    this.devicePasswordEnabled = false,
    this.minDevicePasswordLength = 0,
    this.alphanumericPasswordRequired = false,
    this.allowSimplePassword = true,
    this.minDevicePasswordComplexCharacters = 1,
    this.devicePasswordExpiration = 0,
    this.devicePasswordHistory = 0,
    this.maxDevicePasswordFailedAttempts = 0,
    this.maxInactivityTimeLock = 0,
    this.requireDeviceEncryption = false,
    this.requireStorageCardEncryption = false,
    this.allowCamera = true,
    this.allowBrowser = true,
    this.allowConsumerEmail = true,
    this.allowDesktopSync = true,
    this.allowHTMLEmail = true,
    this.allowInternetSharing = true,
    this.allowIrDA = true,
    this.allowPOPIMAPEmail = true,
    this.allowRemoteDesktop = true,
    this.allowTextMessaging = true,
    this.allowWiFi = true,
    this.allowBluetooth = true,
    this.allowStorageCard = true,
    this.allowUnsignedApplications = true,
    this.allowUnsignedInstallationPackages = true,
    this.attachmentsEnabled = true,
    this.passwordRecoveryEnabled = false,
    this.requireManualSyncWhenRoaming = false,
    this.requireSignedSMIMEMessages = false,
    this.requireEncryptedSMIMEMessages = false,
    this.allowSMIMESoftCerts = true,
    this.maxAttachmentSize = 0,
    this.maxEmailBodyTruncationSize = 0,
    this.maxEmailHTMLBodyTruncationSize = 0,
  });

  @override
  String toString() => 'EasPolicy(key: ***, status: ${status.name})';
}
