/// Provision command — security policy negotiation.
///
/// Implements the two-phase provisioning flow:
/// 1. Request policies from server (with `settings:DeviceInformation` for
///    protocol 14.1+)
/// 2. Acknowledge policies and receive the final PolicyKey
///
/// Status values (MS-ASPROV):
/// - Provision Status: 1=Success, 2=Protocol error, 3=Server error
/// - Policy Status: 1=Success, 2=No policy, 3=Unknown type, 4=Corrupted,
///   5=Wrong key
///
/// Policies are returned, not enforced.
///
/// Reference: MS-ASPROV
library;

import 'package:meta/meta.dart';

import '../models/eas_device_information.dart';
import '../models/eas_policy.dart';
import '../models/eas_provision_doc.dart';
import '../models/wbxml_helpers.dart' show protocolVersionValue;
import '../transport/eas_http_client.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'Provision';

/// `PolicyType` for protocol 12.0+ (WBXML `EASProvisionDoc`).
const easProvisioningWbxml = 'MS-EAS-Provisioning-WBXML';

/// `PolicyType` for protocol 2.5 (XML document in `Data`).
const wapProvisioningXml = 'MS-WAP-Provisioning-XML';

class ProvisionResult {
  final ProvisionStatus status;
  final EasPolicy? policy;

  final RemoteWipeType? remoteWipe;

  /// Status of `settings:DeviceInformation` (14.1+), if returned.
  final int? deviceInformationStatus;

  const ProvisionResult({
    required this.status,
    this.policy,
    this.remoteWipe,
    this.deviceInformationStatus,
  });
}

/// Two-phase provisioning.
///
/// [deviceInformation] is sent in the initial request for protocol 14.1+
/// (MS-ASPROV 2.2.2.53: it MUST contain at least `Model`); when omitted a
/// minimal one (`Model` + the client's User-Agent) is sent. It is never
/// sent for 2.5-14.0.
class ProvisionCommand {
  final PolicyAckStatus policyAckStatus;
  final EasDeviceInformation? deviceInformation;

  ProvisionCommand({required this.policyAckStatus, this.deviceInformation}) {
    if (deviceInformation != null && deviceInformation!.model == null) {
      throw ArgumentError.value(
        null,
        'deviceInformation.model',
        'Model is required (MS-ASPROV 2.2.2.53)',
      );
    }
  }

  /// `PolicyType` for [protocolVersion].
  static String policyTypeFor(String protocolVersion) =>
      protocolVersionValue(protocolVersion) < 120
      ? wapProvisioningXml
      : easProvisioningWbxml;

  /// Whether `settings:DeviceInformation` is sent (14.1+).
  static bool sendsDeviceInformation(String protocolVersion) =>
      protocolVersionValue(protocolVersion) >= 141;

  Future<EasPolicy?> execute(EasHttpClient client) async {
    final version = client.protocolVersion;
    final policyType = policyTypeFor(version);

    // Phase 1: Request policies
    final phase1Result = await _send(
      client,
      buildInitialRequest(
        policyType,
        sendsDeviceInformation(version)
            ? deviceInformation ??
                  EasDeviceInformation(
                    model: 'EasClient',
                    userAgent: client.userAgent,
                  )
            : null,
      ),
    );

    switch (phase1Result.status) {
      case ProvisionStatus.success:
        break; // continue to phase 2
      case ProvisionStatus.protocolError:
        // Server doesn't support or require provisioning
        return null;
      case ProvisionStatus.serverError:
        throw EasCommandException(
          command: 'Provision',
          easStatus: phase1Result.status.code,
          message: 'General server error during provisioning',
        );
    }

    final policy = phase1Result.policy;

    // Check Policy-level status
    if (policy != null && policy.status == PolicyStatus.noPolicyForClient) {
      return null;
    }

    final tempPolicyKey = policy?.policyKey;
    if (tempPolicyKey == null || tempPolicyKey.isEmpty) {
      throw EasCommandException(
        command: 'Provision',
        message: 'No PolicyKey in phase 1 response',
      );
    }

    // Phase 2: Acknowledge policies
    client.policyKey = tempPolicyKey;
    final phase2Result = await _send(
      client,
      buildAcknowledgement(policyType, tempPolicyKey, policyAckStatus),
    );

    switch (phase2Result.status) {
      case ProvisionStatus.success:
        break;
      case ProvisionStatus.protocolError:
        return null;
      case ProvisionStatus.serverError:
        throw EasCommandException(
          command: 'Provision',
          easStatus: phase2Result.status.code,
          message: 'General server error during provision acknowledgement',
        );
    }

    final ackPolicy = phase2Result.policy;
    if (ackPolicy != null) {
      switch (ackPolicy.status) {
        case PolicyStatus.success:
          break;
        case PolicyStatus.noPolicyForClient:
          return null;
        case PolicyStatus.unknownPolicyType:
          throw EasCommandException(
            command: 'Provision',
            easStatus: ackPolicy.status.code,
            message: 'Server does not recognize PolicyType',
          );
        case PolicyStatus.policyDataCorrupted:
          throw EasCommandException(
            command: 'Provision',
            easStatus: ackPolicy.status.code,
            message: 'Policy data on server is corrupted',
          );
        case PolicyStatus.wrongPolicyKey:
          throw EasCommandException(
            command: 'Provision',
            easStatus: ackPolicy.status.code,
            message: 'Client acknowledged wrong policy key',
          );
      }
    }

    final finalPolicyKey = ackPolicy?.policyKey;
    if ((finalPolicyKey == null || finalPolicyKey.isEmpty) &&
        policyAckStatus != PolicyAckStatus.success) {
      throw EasPolicyNotAcceptedException(ackStatus: policyAckStatus);
    }
    if (finalPolicyKey == null || finalPolicyKey.isEmpty) {
      throw EasCommandException(
        command: 'Provision',
        message: 'No PolicyKey in phase 2 response',
      );
    }

    client.policyKey = finalPolicyKey;
    // The acknowledgement carries no policy data: return the phase 1
    // policies with the final key.
    return _withKey(policy, finalPolicyKey, ackPolicy!.status);
  }

  static EasPolicy _withKey(EasPolicy? p, String key, PolicyStatus status) {
    final d = p ?? EasPolicy(policyKey: key);
    return EasPolicy(
      policyKey: key,
      policyType: d.policyType,
      status: status,
      devicePasswordEnabled: d.devicePasswordEnabled,
      minDevicePasswordLength: d.minDevicePasswordLength,
      alphanumericPasswordRequired: d.alphanumericPasswordRequired,
      allowSimplePassword: d.allowSimplePassword,
      minDevicePasswordComplexCharacters: d.minDevicePasswordComplexCharacters,
      devicePasswordExpiration: d.devicePasswordExpiration,
      devicePasswordHistory: d.devicePasswordHistory,
      maxDevicePasswordFailedAttempts: d.maxDevicePasswordFailedAttempts,
      maxInactivityTimeLock: d.maxInactivityTimeLock,
      requireDeviceEncryption: d.requireDeviceEncryption,
      requireStorageCardEncryption: d.requireStorageCardEncryption,
      allowCamera: d.allowCamera,
      allowBrowser: d.allowBrowser,
      allowConsumerEmail: d.allowConsumerEmail,
      allowDesktopSync: d.allowDesktopSync,
      allowHTMLEmail: d.allowHTMLEmail,
      allowInternetSharing: d.allowInternetSharing,
      allowIrDA: d.allowIrDA,
      allowPOPIMAPEmail: d.allowPOPIMAPEmail,
      allowRemoteDesktop: d.allowRemoteDesktop,
      allowTextMessaging: d.allowTextMessaging,
      allowWiFi: d.allowWiFi,
      allowBluetooth: d.allowBluetooth,
      allowStorageCard: d.allowStorageCard,
      allowUnsignedApplications: d.allowUnsignedApplications,
      allowUnsignedInstallationPackages: d.allowUnsignedInstallationPackages,
      attachmentsEnabled: d.attachmentsEnabled,
      passwordRecoveryEnabled: d.passwordRecoveryEnabled,
      requireManualSyncWhenRoaming: d.requireManualSyncWhenRoaming,
      requireSignedSMIMEMessages: d.requireSignedSMIMEMessages,
      requireEncryptedSMIMEMessages: d.requireEncryptedSMIMEMessages,
      allowSMIMESoftCerts: d.allowSMIMESoftCerts,
      maxAttachmentSize: d.maxAttachmentSize,
      maxEmailBodyTruncationSize: d.maxEmailBodyTruncationSize,
      maxEmailHTMLBodyTruncationSize: d.maxEmailHTMLBodyTruncationSize,
      provisionDoc: d.provisionDoc,
    );
  }

  /// Initial request: `DeviceInformation?`, `Policies/Policy/PolicyType`.
  @visibleForTesting
  static WbxmlDocument buildInitialRequest(
    String policyType,
    EasDeviceInformation? deviceInformation,
  ) => WbxmlDocument(
    root: xEl(_ns, 'Provision', [
      ?deviceInformation?.toElement(),
      xEl(_ns, 'Policies', [
        xEl(_ns, 'Policy', [xText(_ns, 'PolicyType', policyType)]),
      ]),
    ]),
  );

  /// Acknowledgement: `Policies/Policy/(PolicyType, PolicyKey, Status)`.
  @visibleForTesting
  static WbxmlDocument buildAcknowledgement(
    String policyType,
    String policyKey,
    PolicyAckStatus status,
  ) => WbxmlDocument(
    root: xEl(_ns, 'Provision', [
      xEl(_ns, 'Policies', [
        xEl(_ns, 'Policy', [
          xText(_ns, 'PolicyType', policyType),
          xText(_ns, 'PolicyKey', policyKey),
          xText(_ns, 'Status', status.code),
        ]),
      ]),
    ]),
  );

  Future<ProvisionResult> _send(
    EasHttpClient client,
    WbxmlDocument request,
  ) async {
    final result = await _ProvisionPhase(request, this).execute(client);
    if (result.remoteWipe != null) {
      throw EasRemoteWipeException(
        command: 'Provision',
        type: result.remoteWipe,
      );
    }
    return result;
  }

  @visibleForTesting
  ProvisionResult parseResponse(WbxmlDocument doc) {
    final root = doc.root;
    final statusCode = int.tryParse(root.childText(_ns, 'Status') ?? '') ?? 0;
    // Unknown codes (e.g. non-standard server extensions like Z-Push status
    // 111) are treated as protocolError → no provisioning needed.
    final status =
        ProvisionStatus.fromCode(statusCode) ?? ProvisionStatus.protocolError;
    final remoteWipe = parseRemoteWipe(root);
    final deviceInfoStatus = EasDeviceInformation.statusOf(root);

    final policy = root.findChild(_ns, 'Policies')?.findChild(_ns, 'Policy');
    if (policy == null) {
      return ProvisionResult(
        status: status,
        remoteWipe: remoteWipe,
        deviceInformationStatus: deviceInfoStatus,
      );
    }

    final policyKey = policy.childText(_ns, 'PolicyKey') ?? '';
    final policyStatusCode =
        int.tryParse(policy.childText(_ns, 'Status') ?? '') ?? 0;
    final policyStatus =
        PolicyStatus.fromCode(policyStatusCode) ?? PolicyStatus.success;
    final policyType = policy.childText(_ns, 'PolicyType');

    // EASProvisionDoc (MS-ASPROV 2.2.2.28) or, for 2.5, an XML string.
    final data = policy.findChild(_ns, 'Data');
    final provDoc = data?.findChild(_ns, 'EASProvisionDoc');
    final wapXml = provDoc == null ? data?.text : null;

    return ProvisionResult(
      status: status,
      policy: _buildPolicy(
        policyKey,
        policyType,
        policyStatus,
        provDoc,
        wapXml,
      ),
      remoteWipe: remoteWipe,
      deviceInformationStatus: deviceInfoStatus,
    );
  }

  static RemoteWipeType? parseRemoteWipe(WbxmlElement root) {
    if (root.findChild(_ns, 'RemoteWipe') != null) {
      return RemoteWipeType.full;
    }
    if (root.findChild(_ns, 'AccountOnlyRemoteWipe') != null) {
      return RemoteWipeType.accountOnly;
    }
    return null;
  }

  EasPolicy _buildPolicy(
    String policyKey,
    String? policyType,
    PolicyStatus policyStatus,
    WbxmlElement? docEl,
    String? wapXml,
  ) {
    final type = policyType ?? easProvisioningWbxml;
    if (docEl == null) {
      return EasPolicy(
        policyKey: policyKey,
        policyType: type,
        status: policyStatus,
        provisionDoc: wapXml == null
            ? null
            : EasProvisionDoc(wapProvisioningXml: wapXml),
      );
    }

    final doc = EasProvisionDoc.fromElement(docEl);
    bool b(String tag, [bool def = false]) => doc.boolean(tag) ?? def;
    int i(String tag, [int def = 0]) => doc.integer(tag) ?? def;

    return EasPolicy(
      policyKey: policyKey,
      policyType: type,
      status: policyStatus,
      devicePasswordEnabled: b('DevicePasswordEnabled'),
      minDevicePasswordLength: i('MinDevicePasswordLength'),
      alphanumericPasswordRequired: b('AlphanumericDevicePasswordRequired'),
      allowSimplePassword: b('AllowSimpleDevicePassword', true),
      minDevicePasswordComplexCharacters: i(
        'MinDevicePasswordComplexCharacters',
        1,
      ),
      devicePasswordExpiration: i('DevicePasswordExpiration'),
      devicePasswordHistory: i('DevicePasswordHistory'),
      maxDevicePasswordFailedAttempts: i('MaxDevicePasswordFailedAttempts'),
      maxInactivityTimeLock: i('MaxInactivityTimeDeviceLock'),
      requireDeviceEncryption: b('RequireDeviceEncryption'),
      requireStorageCardEncryption: b('RequireStorageCardEncryption'),
      allowCamera: b('AllowCamera', true),
      allowBrowser: b('AllowBrowser', true),
      allowConsumerEmail: b('AllowConsumerEmail', true),
      allowDesktopSync: b('AllowDesktopSync', true),
      allowHTMLEmail: b('AllowHTMLEmail', true),
      allowInternetSharing: b('AllowInternetSharing', true),
      allowIrDA: b('AllowIrDA', true),
      allowPOPIMAPEmail: b('AllowPOPIMAPEmail', true),
      allowRemoteDesktop: b('AllowRemoteDesktop', true),
      allowTextMessaging: b('AllowTextMessaging', true),
      allowWiFi: b('AllowWiFi', true),
      // 0 = disabled, 1 = hands-free only, 2 = allowed (see
      // EasProvisionDoc.allowBluetooth for the exact mode).
      allowBluetooth: (doc.integer('AllowBluetooth') ?? 2) != 0,
      allowStorageCard: b('AllowStorageCard', true),
      allowUnsignedApplications: b('AllowUnsignedApplications', true),
      allowUnsignedInstallationPackages: b(
        'AllowUnsignedInstallationPackages',
        true,
      ),
      attachmentsEnabled: b('AttachmentsEnabled', true),
      passwordRecoveryEnabled: b('PasswordRecoveryEnabled'),
      requireManualSyncWhenRoaming: b('RequireManualSyncWhenRoaming'),
      requireSignedSMIMEMessages: b('RequireSignedSMIMEMessages'),
      requireEncryptedSMIMEMessages: b('RequireEncryptedSMIMEMessages'),
      allowSMIMESoftCerts: b('AllowSMIMESoftCerts', true),
      maxAttachmentSize: i('MaxAttachmentSize'),
      maxEmailBodyTruncationSize: i('MaxEmailBodyTruncationSize'),
      maxEmailHTMLBodyTruncationSize: i('MaxEmailHTMLBodyTruncationSize'),
      provisionDoc: doc,
    );
  }
}

/// One Provision round-trip; reuses [EasCommand]'s HTTP status mapping.
class _ProvisionPhase extends EasCommand<ProvisionResult> {
  final WbxmlDocument request;
  final ProvisionCommand owner;

  _ProvisionPhase(this.request, this.owner);

  @override
  String get commandName => 'Provision';

  @override
  WbxmlDocument buildRequest() => request;

  @override
  ProvisionResult parseResponse(WbxmlDocument response) =>
      owner.parseResponse(response);
}

class RemoteWipeAckCommand extends EasCommand<ProvisionStatus> {
  final RemoteWipeType type;
  final RemoteWipeAckStatus status;

  RemoteWipeAckCommand({required this.type, required this.status});

  @override
  String get commandName => 'Provision';

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'Provision', [
      xEl(
        _ns,
        switch (type) {
          RemoteWipeType.full => 'RemoteWipe',
          RemoteWipeType.accountOnly => 'AccountOnlyRemoteWipe',
        },
        [xText(_ns, 'Status', status.code)],
      ),
    ]),
  );

  @override
  ProvisionStatus parseResponse(WbxmlDocument response) {
    final code = int.tryParse(response.root.childText(_ns, 'Status') ?? '');
    return ProvisionStatus.fromCode(code ?? 0) ?? ProvisionStatus.protocolError;
  }
}
