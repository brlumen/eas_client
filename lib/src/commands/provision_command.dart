/// Provision command — security policy negotiation.
///
/// Implements the two-phase provisioning flow:
/// 1. Request policies from server
/// 2. Acknowledge policies and receive PolicyKey
///
/// Status values (MS-ASPROV):
/// - Provision Status: 1=Success, 2=Protocol error, 3=Server error
/// - Policy Status: 1=Success, 2=No policy, 3=Unknown type, 4=Corrupted, 5=Wrong key
///
/// Reference: MS-ASPROV
library;

import 'package:meta/meta.dart';

import '../models/eas_policy.dart';
import '../transport/eas_http_client.dart';
import '../wbxml/wbxml_codec.dart';
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Result of a Provision command.
class ProvisionResult {
  final ProvisionStatus status;
  final EasPolicy? policy;

  const ProvisionResult({required this.status, this.policy});
}

class ProvisionCommand {
  final WbxmlEncoder _encoder = WbxmlEncoder();
  final WbxmlDecoder _decoder = WbxmlDecoder();

  /// Status sent to server during policy acknowledgement (phase 2).
  ///
  /// Per MS-ASPROV 2.2.2.54.1, the client SHOULD report the actual
  /// policy application status. Required — the consumer must explicitly
  /// indicate whether policies have been applied.
  final PolicyAckStatus policyAckStatus;

  ProvisionCommand({
    required this.policyAckStatus,
  });

  /// Execute the full two-phase provisioning flow.
  ///
  /// Returns the [EasPolicy] with parsed security policies and PolicyKey,
  /// or `null` if provisioning is not required/supported.
  /// Also sets [EasHttpClient.policyKey] for subsequent commands.
  ///
  /// Handles:
  /// - Provision Status 2 (protocol error) — server doesn't support provisioning
  /// - Policy Status 2 (no policy for client) — no policies to enforce
  Future<EasPolicy?> execute(EasHttpClient client) async {
    // Phase 1: Request policies
    final phase1Result = await _sendProvision(client);

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
    final phase2Result = await _sendProvisionAck(client, tempPolicyKey);

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

    final finalPolicy = phase2Result.policy;
    if (finalPolicy != null) {
      switch (finalPolicy.status) {
        case PolicyStatus.success:
          break;
        case PolicyStatus.noPolicyForClient:
          return null;
        case PolicyStatus.unknownPolicyType:
          throw EasCommandException(
            command: 'Provision',
            easStatus: finalPolicy.status.code,
            message: 'Server does not recognize PolicyType',
          );
        case PolicyStatus.policyDataCorrupted:
          throw EasCommandException(
            command: 'Provision',
            easStatus: finalPolicy.status.code,
            message: 'Policy data on server is corrupted',
          );
        case PolicyStatus.wrongPolicyKey:
          throw EasCommandException(
            command: 'Provision',
            easStatus: finalPolicy.status.code,
            message: 'Client acknowledged wrong policy key',
          );
      }
    }

    final finalPolicyKey = finalPolicy?.policyKey;
    if (finalPolicyKey == null || finalPolicyKey.isEmpty) {
      throw EasCommandException(
        command: 'Provision',
        message: 'No PolicyKey in phase 2 response',
      );
    }

    client.policyKey = finalPolicyKey;
    return finalPolicy;
  }

  /// Phase 1: Request policies.
  Future<ProvisionResult> _sendProvision(EasHttpClient client) async {
    final doc = WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Provision',
        tag: 'Provision',
        codePageIndex: 14,
        children: [
          // DeviceInformation MUST precede Policies per MS-ASPROV for EAS >= 14.1
          WbxmlElement(
            namespace: 'Settings',
            tag: 'DeviceInformation',
            codePageIndex: 18,
            children: [
              WbxmlElement(
                namespace: 'Settings',
                tag: 'Set',
                codePageIndex: 18,
                children: [
                  WbxmlElement.withText(
                    namespace: 'Settings',
                    tag: 'Model',
                    text: 'FlutterEAS',
                    codePageIndex: 18,
                  ),
                  WbxmlElement.withText(
                    namespace: 'Settings',
                    tag: 'OS',
                    text: 'Dart',
                    codePageIndex: 18,
                  ),
                  WbxmlElement.withText(
                    namespace: 'Settings',
                    tag: 'UserAgent',
                    text: 'FlutterEAS/1.0',
                    codePageIndex: 18,
                  ),
                ],
              ),
            ],
          ),
          WbxmlElement(
            namespace: 'Provision',
            tag: 'Policies',
            codePageIndex: 14,
            children: [
              WbxmlElement(
                namespace: 'Provision',
                tag: 'Policy',
                codePageIndex: 14,
                children: [
                  WbxmlElement.withText(
                    namespace: 'Provision',
                    tag: 'PolicyType',
                    text: 'MS-EAS-Provisioning-WBXML',
                    codePageIndex: 14,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return _sendAndParse(client, doc);
  }

  /// Phase 2: Acknowledge policies.
  Future<ProvisionResult> _sendProvisionAck(
    EasHttpClient client,
    String policyKey,
  ) async {
    final doc = WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Provision',
        tag: 'Provision',
        codePageIndex: 14,
        children: [
          WbxmlElement(
            namespace: 'Provision',
            tag: 'Policies',
            codePageIndex: 14,
            children: [
              WbxmlElement(
                namespace: 'Provision',
                tag: 'Policy',
                codePageIndex: 14,
                children: [
                  WbxmlElement.withText(
                    namespace: 'Provision',
                    tag: 'PolicyType',
                    text: 'MS-EAS-Provisioning-WBXML',
                    codePageIndex: 14,
                  ),
                  WbxmlElement.withText(
                    namespace: 'Provision',
                    tag: 'PolicyKey',
                    text: policyKey,
                    codePageIndex: 14,
                  ),
                  WbxmlElement.withText(
                    namespace: 'Provision',
                    tag: 'Status',
                    text: '${policyAckStatus.code}',
                    codePageIndex: 14,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return _sendAndParse(client, doc);
  }

  Future<ProvisionResult> _sendAndParse(
    EasHttpClient client,
    WbxmlDocument request,
  ) async {
    final bytes = _encoder.encode(request);
    final response = await client.sendCommand('Provision', bytes);

    if (!response.isSuccess) {
      throw EasCommandException(
        command: 'Provision',
        statusCode: response.statusCode,
        message: 'HTTP error ${response.statusCode}',
      );
    }

    final doc = _decoder.decode(response.body);
    return parseResponse(doc);
  }

  @visibleForTesting
  ProvisionResult parseResponse(WbxmlDocument doc) {
    final root = doc.root;
    final statusCode =
        int.tryParse(root.childText('Provision', 'Status') ?? '') ?? 0;
    // Unknown codes (e.g. non-standard server extensions like Z-Push status 111)
    // are treated as protocolError → caller returns null (no provisioning needed).
    final status =
        ProvisionStatus.fromCode(statusCode) ?? ProvisionStatus.protocolError;

    final policies = root.findChild('Provision', 'Policies');
    if (policies == null) {
      return ProvisionResult(status: status);
    }

    final policy = policies.findChild('Provision', 'Policy');
    if (policy == null) {
      return ProvisionResult(status: status);
    }

    final policyKey = policy.childText('Provision', 'PolicyKey') ?? '';
    final policyStatusCode =
        int.tryParse(policy.childText('Provision', 'Status') ?? '') ?? 0;
    final policyStatus =
        PolicyStatus.fromCode(policyStatusCode) ?? PolicyStatus.success;

    // Parse EASProvisionDoc from Data element (MS-ASPROV 2.2.2.28)
    final data = policy.findChild('Provision', 'Data');
    final provDoc = data?.findChild('Provision', 'EASProvisionDoc');

    return ProvisionResult(
      status: status,
      policy: _buildPolicy(policyKey, policyStatus, provDoc),
    );
  }

  EasPolicy _buildPolicy(
    String policyKey,
    PolicyStatus policyStatus,
    WbxmlElement? doc,
  ) {
    if (doc == null) {
      return EasPolicy(policyKey: policyKey, status: policyStatus);
    }

    return EasPolicy(
      policyKey: policyKey,
      status: policyStatus,
      devicePasswordEnabled: _bool(doc, 'DevicePasswordEnabled'),
      minDevicePasswordLength: _int(doc, 'MinDevicePasswordLength'),
      alphanumericPasswordRequired:
          _bool(doc, 'AlphanumericDevicePasswordRequired'),
      allowSimplePassword: _bool(doc, 'AllowSimpleDevicePassword', true),
      minDevicePasswordComplexCharacters:
          _int(doc, 'MinDevicePasswordComplexCharacters', 1),
      devicePasswordExpiration: _int(doc, 'DevicePasswordExpiration'),
      devicePasswordHistory: _int(doc, 'DevicePasswordHistory'),
      maxDevicePasswordFailedAttempts:
          _int(doc, 'MaxDevicePasswordFailedAttempts'),
      maxInactivityTimeLock: _int(doc, 'MaxInactivityTimeDeviceLock'),
      requireDeviceEncryption: _bool(doc, 'RequireDeviceEncryption'),
      requireStorageCardEncryption:
          _bool(doc, 'RequireStorageCardEncryption'),
      allowCamera: _bool(doc, 'AllowCamera', true),
      allowBrowser: _bool(doc, 'AllowBrowser', true),
      allowConsumerEmail: _bool(doc, 'AllowConsumerEmail', true),
      allowDesktopSync: _bool(doc, 'AllowDesktopSync', true),
      allowHTMLEmail: _bool(doc, 'AllowHTMLEmail', true),
      allowInternetSharing: _bool(doc, 'AllowInternetSharing', true),
      allowIrDA: _bool(doc, 'AllowIrDA', true),
      allowPOPIMAPEmail: _bool(doc, 'AllowPOPIMAPEmail', true),
      allowRemoteDesktop: _bool(doc, 'AllowRemoteDesktop', true),
      allowTextMessaging: _bool(doc, 'AllowTextMessaging', true),
      allowWiFi: _bool(doc, 'AllowWiFi', true),
      allowBluetooth: _bool(doc, 'AllowBluetooth', true),
      allowStorageCard: _bool(doc, 'AllowStorageCard', true),
      allowUnsignedApplications:
          _bool(doc, 'AllowUnsignedApplications', true),
      allowUnsignedInstallationPackages:
          _bool(doc, 'AllowUnsignedInstallationPackages', true),
      attachmentsEnabled: _bool(doc, 'AttachmentsEnabled', true),
      passwordRecoveryEnabled: _bool(doc, 'PasswordRecoveryEnabled'),
      requireManualSyncWhenRoaming:
          _bool(doc, 'RequireManualSyncWhenRoaming'),
      requireSignedSMIMEMessages:
          _bool(doc, 'RequireSignedSMIMEMessages'),
      requireEncryptedSMIMEMessages:
          _bool(doc, 'RequireEncryptedSMIMEMessages'),
      allowSMIMESoftCerts: _bool(doc, 'AllowSMIMESoftCerts', true),
      maxAttachmentSize: _int(doc, 'MaxAttachmentSize'),
      maxEmailBodyTruncationSize:
          _int(doc, 'MaxEmailBodyTruncationSize'),
      maxEmailHTMLBodyTruncationSize:
          _int(doc, 'MaxEmailHTMLBodyTruncationSize'),
    );
  }

  /// Read boolean field from EASProvisionDoc. EAS uses '1'/'0'.
  static bool _bool(WbxmlElement doc, String tag, [bool defaultValue = false]) {
    final text = doc.childText('Provision', tag);
    if (text == null) return defaultValue;
    return text == '1';
  }

  /// Read integer field from EASProvisionDoc.
  static int _int(WbxmlElement doc, String tag, [int defaultValue = 0]) {
    final text = doc.childText('Provision', tag);
    if (text == null) return defaultValue;
    return int.tryParse(text) ?? defaultValue;
  }
}
