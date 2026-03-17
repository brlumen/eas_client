import 'package:eas_client/eas_client.dart';
import 'package:test/test.dart';

/// Helper: build a Provision response WbxmlDocument with EASProvisionDoc.
WbxmlDocument _buildProvisionResponse({
  String provisionStatus = '1',
  String policyStatus = '1',
  String policyKey = 'test-key-123',
  List<WbxmlElement>? provDocChildren,
}) {
  final policyChildren = <WbxmlElement>[
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
      text: policyStatus,
      codePageIndex: 14,
    ),
  ];

  if (provDocChildren != null) {
    policyChildren.add(WbxmlElement(
      namespace: 'Provision',
      tag: 'Data',
      codePageIndex: 14,
      children: [
        WbxmlElement(
          namespace: 'Provision',
          tag: 'EASProvisionDoc',
          codePageIndex: 14,
          children: provDocChildren,
        ),
      ],
    ));
  }

  return WbxmlDocument(
    root: WbxmlElement(
      namespace: 'Provision',
      tag: 'Provision',
      codePageIndex: 14,
      children: [
        WbxmlElement.withText(
          namespace: 'Provision',
          tag: 'Status',
          text: provisionStatus,
          codePageIndex: 14,
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
              children: policyChildren,
            ),
          ],
        ),
      ],
    ),
  );
}

WbxmlElement _provField(String tag, String value) {
  return WbxmlElement.withText(
    namespace: 'Provision',
    tag: tag,
    text: value,
    codePageIndex: 14,
  );
}

void main() {
  group('Provision policy parsing', () {
    late ProvisionCommand command;

    setUp(() {
      command = ProvisionCommand(policyAckStatus: PolicyAckStatus.success);
    });

    test('parses full EASProvisionDoc', () {
      final doc = _buildProvisionResponse(
        provDocChildren: [
          _provField('DevicePasswordEnabled', '1'),
          _provField('MinDevicePasswordLength', '8'),
          _provField('AlphanumericDevicePasswordRequired', '1'),
          _provField('AllowSimpleDevicePassword', '0'),
          _provField('MinDevicePasswordComplexCharacters', '3'),
          _provField('DevicePasswordExpiration', '90'),
          _provField('DevicePasswordHistory', '5'),
          _provField('MaxDevicePasswordFailedAttempts', '10'),
          _provField('MaxInactivityTimeDeviceLock', '300'),
          _provField('RequireDeviceEncryption', '1'),
          _provField('RequireStorageCardEncryption', '1'),
          _provField('AllowCamera', '0'),
          _provField('AllowBrowser', '0'),
          _provField('AllowConsumerEmail', '0'),
          _provField('AllowDesktopSync', '0'),
          _provField('AllowHTMLEmail', '0'),
          _provField('AllowInternetSharing', '0'),
          _provField('AllowIrDA', '0'),
          _provField('AllowPOPIMAPEmail', '0'),
          _provField('AllowRemoteDesktop', '0'),
          _provField('AllowTextMessaging', '0'),
          _provField('AllowWiFi', '0'),
          _provField('AllowBluetooth', '0'),
          _provField('AllowStorageCard', '0'),
          _provField('AllowUnsignedApplications', '0'),
          _provField('AllowUnsignedInstallationPackages', '0'),
          _provField('AttachmentsEnabled', '0'),
          _provField('PasswordRecoveryEnabled', '1'),
          _provField('RequireManualSyncWhenRoaming', '1'),
          _provField('MaxAttachmentSize', '5242880'),
        ],
      );

      final result = command.parseResponse(doc);
      final policy = result.policy!;

      expect(policy.policyKey, equals('test-key-123'));
      expect(policy.status, equals(PolicyStatus.success));

      // Password policies
      expect(policy.devicePasswordEnabled, isTrue);
      expect(policy.minDevicePasswordLength, equals(8));
      expect(policy.alphanumericPasswordRequired, isTrue);
      expect(policy.allowSimplePassword, isFalse);
      expect(policy.minDevicePasswordComplexCharacters, equals(3));
      expect(policy.devicePasswordExpiration, equals(90));
      expect(policy.devicePasswordHistory, equals(5));
      expect(policy.maxDevicePasswordFailedAttempts, equals(10));
      expect(policy.maxInactivityTimeLock, equals(300));

      // Encryption
      expect(policy.requireDeviceEncryption, isTrue);
      expect(policy.requireStorageCardEncryption, isTrue);

      // All "Allow" fields set to false
      expect(policy.allowCamera, isFalse);
      expect(policy.allowBrowser, isFalse);
      expect(policy.allowConsumerEmail, isFalse);
      expect(policy.allowDesktopSync, isFalse);
      expect(policy.allowHTMLEmail, isFalse);
      expect(policy.allowInternetSharing, isFalse);
      expect(policy.allowIrDA, isFalse);
      expect(policy.allowPOPIMAPEmail, isFalse);
      expect(policy.allowRemoteDesktop, isFalse);
      expect(policy.allowTextMessaging, isFalse);
      expect(policy.allowWiFi, isFalse);
      expect(policy.allowBluetooth, isFalse);
      expect(policy.allowStorageCard, isFalse);
      expect(policy.allowUnsignedApplications, isFalse);
      expect(policy.allowUnsignedInstallationPackages, isFalse);
      expect(policy.attachmentsEnabled, isFalse);
      expect(policy.passwordRecoveryEnabled, isTrue);
      expect(policy.requireManualSyncWhenRoaming, isTrue);

      // Size limits
      expect(policy.maxAttachmentSize, equals(5242880));
    });

    test('returns defaults when no EASProvisionDoc', () {
      final doc = _buildProvisionResponse(provDocChildren: null);

      final result = command.parseResponse(doc);
      final policy = result.policy!;

      expect(policy.policyKey, equals('test-key-123'));
      expect(policy.devicePasswordEnabled, isFalse);
      expect(policy.minDevicePasswordLength, equals(0));
      expect(policy.allowSimplePassword, isTrue);
      expect(policy.allowCamera, isTrue);
      expect(policy.allowBrowser, isTrue);
      expect(policy.requireDeviceEncryption, isFalse);
      expect(policy.attachmentsEnabled, isTrue);
      expect(policy.maxAttachmentSize, equals(0));
    });

    test('partial doc fills specified fields, rest are defaults', () {
      final doc = _buildProvisionResponse(
        provDocChildren: [
          _provField('DevicePasswordEnabled', '1'),
          _provField('MinDevicePasswordLength', '6'),
          _provField('AllowCamera', '0'),
        ],
      );

      final result = command.parseResponse(doc);
      final policy = result.policy!;

      // Specified fields
      expect(policy.devicePasswordEnabled, isTrue);
      expect(policy.minDevicePasswordLength, equals(6));
      expect(policy.allowCamera, isFalse);

      // Defaults for unspecified
      expect(policy.alphanumericPasswordRequired, isFalse);
      expect(policy.allowSimplePassword, isTrue);
      expect(policy.allowBrowser, isTrue);
      expect(policy.requireDeviceEncryption, isFalse);
      expect(policy.maxAttachmentSize, equals(0));
    });

    test('WBXML round-trip preserves EASProvisionDoc fields', () {
      final doc = _buildProvisionResponse(
        provDocChildren: [
          _provField('DevicePasswordEnabled', '1'),
          _provField('RequireDeviceEncryption', '1'),
          _provField('MaxInactivityTimeDeviceLock', '600'),
        ],
      );

      // Encode → decode round-trip
      final encoder = WbxmlEncoder();
      final decoder = WbxmlDecoder();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final result = command.parseResponse(decoded);
      final policy = result.policy!;

      expect(policy.devicePasswordEnabled, isTrue);
      expect(policy.requireDeviceEncryption, isTrue);
      expect(policy.maxInactivityTimeLock, equals(600));
      expect(policy.allowCamera, isTrue); // default
    });
  });
}
