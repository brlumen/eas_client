/// Settings command — get/set device and user settings (OOF, device info).
///
/// Reference: MS-ASCMD section 2.2.1.20
library;

import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';

/// Out-of-Office state.
enum OofState {
  /// OOF is disabled.
  disabled(0),

  /// OOF is globally enabled (no time limit).
  global(1),

  /// OOF is enabled for a specific time range.
  timeBased(2);

  final int value;
  const OofState(this.value);

  static OofState fromValue(int value) =>
      OofState.values.firstWhere((e) => e.value == value,
          orElse: () => OofState.disabled);
}

/// OOF message for a specific audience.
class OofMessage {
  /// Whether auto-reply is enabled for this audience.
  final bool enabled;

  /// Reply message text.
  final String? replyMessage;

  const OofMessage({this.enabled = false, this.replyMessage});
}

/// Out-of-Office settings.
class EasOofSettings {
  final OofState state;
  final DateTime? startTime;
  final DateTime? endTime;

  /// Reply to internal senders.
  final OofMessage? internalMessage;

  /// Reply to known external senders.
  final OofMessage? externalKnownMessage;

  /// Reply to unknown external senders.
  final OofMessage? externalUnknownMessage;

  const EasOofSettings({
    this.state = OofState.disabled,
    this.startTime,
    this.endTime,
    this.internalMessage,
    this.externalKnownMessage,
    this.externalUnknownMessage,
  });
}

/// User information from the server.
class EasUserInfo {
  /// Display name.
  final String? displayName;

  /// Primary SMTP address.
  final String? emailAddress;

  const EasUserInfo({this.displayName, this.emailAddress});
}

/// Combined settings response.
class EasSettings {
  final int status;
  final EasOofSettings? oof;
  final EasUserInfo? userInfo;

  bool get isSuccess => status == 1;

  const EasSettings({required this.status, this.oof, this.userInfo});
}

/// Get current settings (OOF + user info).
class SettingsGetCommand extends EasCommand<EasSettings> {
  @override
  String get commandName => 'Settings';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Settings',
        tag: 'Settings',
        codePageIndex: 18,
        children: [
          WbxmlElement(
            namespace: 'Settings',
            tag: 'Oof',
            codePageIndex: 18,
            children: [
              WbxmlElement(
                namespace: 'Settings',
                tag: 'Get',
                codePageIndex: 18,
                children: [
                  WbxmlElement.withText(
                    namespace: 'Settings',
                    tag: 'BodyType',
                    text: 'Text',
                    codePageIndex: 18,
                  ),
                ],
              ),
            ],
          ),
          WbxmlElement(
            namespace: 'Settings',
            tag: 'UserInformation',
            codePageIndex: 18,
            children: [
              WbxmlElement(
                namespace: 'Settings',
                tag: 'Get',
                codePageIndex: 18,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  EasSettings parseResponse(WbxmlDocument response) {
    final root = response.root;
    final status =
        int.tryParse(root.childText('Settings', 'Status') ?? '') ?? 0;

    // Parse OOF
    EasOofSettings? oof;
    final oofEl = root.findChild('Settings', 'Oof');
    if (oofEl != null) {
      final getEl = oofEl.findChild('Settings', 'Get');
      if (getEl != null) {
        final stateVal =
            int.tryParse(getEl.childText('Settings', 'OofState') ?? '') ?? 0;
        final startStr = getEl.childText('Settings', 'StartTime');
        final endStr = getEl.childText('Settings', 'EndTime');

        OofMessage? parseOofMessage(WbxmlElement? el) {
          if (el == null) return null;
          final enabled = el.childText('Settings', 'Enabled') == '1';
          final msg = el.childText('Settings', 'ReplyMessage');
          return OofMessage(enabled: enabled, replyMessage: msg);
        }

        oof = EasOofSettings(
          state: OofState.fromValue(stateVal),
          startTime: startStr != null ? DateTime.tryParse(startStr) : null,
          endTime: endStr != null ? DateTime.tryParse(endStr) : null,
          internalMessage:
              parseOofMessage(getEl.findChild('Settings', 'AppliesToInternal')),
          externalKnownMessage: parseOofMessage(
              getEl.findChild('Settings', 'AppliesToExternalKnown')),
          externalUnknownMessage: parseOofMessage(
              getEl.findChild('Settings', 'AppliesToExternalUnknown')),
        );
      }
    }

    // Parse UserInformation
    EasUserInfo? userInfo;
    final userEl = root.findChild('Settings', 'UserInformation');
    if (userEl != null) {
      final getEl = userEl.findChild('Settings', 'Get');
      if (getEl != null) {
        final emailsEl = getEl.findChild('Settings', 'EmailAddresses');
        final email = emailsEl?.childText('Settings', 'SMTPAddress') ??
            emailsEl?.childText('Settings', 'PrimarySmtpAddress');
        final displayName = getEl.childText('Settings', 'UserDisplayName');
        userInfo = EasUserInfo(
          displayName: displayName,
          emailAddress: email,
        );
      }
    }

    return EasSettings(status: status, oof: oof, userInfo: userInfo);
  }
}

/// Set Out-of-Office state and reply message.
class SettingsSetOofCommand extends EasCommand<int> {
  final EasOofSettings oof;

  SettingsSetOofCommand({required this.oof});

  @override
  String get commandName => 'Settings';

  WbxmlElement _buildOofMessage(String tag, OofMessage msg) {
    return WbxmlElement(
      namespace: 'Settings',
      tag: tag,
      codePageIndex: 18,
      children: [
        WbxmlElement.withText(
          namespace: 'Settings',
          tag: 'Enabled',
          text: msg.enabled ? '1' : '0',
          codePageIndex: 18,
        ),
        if (msg.replyMessage != null)
          WbxmlElement.withText(
            namespace: 'Settings',
            tag: 'ReplyMessage',
            text: msg.replyMessage!,
            codePageIndex: 18,
          ),
      ],
    );
  }

  @override
  WbxmlDocument buildRequest() {
    final setChildren = <WbxmlElement>[
      WbxmlElement.withText(
        namespace: 'Settings',
        tag: 'OofState',
        text: oof.state.value.toString(),
        codePageIndex: 18,
      ),
      if (oof.startTime != null)
        WbxmlElement.withText(
          namespace: 'Settings',
          tag: 'StartTime',
          text: oof.startTime!.toUtc().toIso8601String(),
          codePageIndex: 18,
        ),
      if (oof.endTime != null)
        WbxmlElement.withText(
          namespace: 'Settings',
          tag: 'EndTime',
          text: oof.endTime!.toUtc().toIso8601String(),
          codePageIndex: 18,
        ),
      if (oof.internalMessage != null)
        _buildOofMessage('AppliesToInternal', oof.internalMessage!),
      if (oof.externalKnownMessage != null)
        _buildOofMessage('AppliesToExternalKnown', oof.externalKnownMessage!),
      if (oof.externalUnknownMessage != null)
        _buildOofMessage(
            'AppliesToExternalUnknown', oof.externalUnknownMessage!),
    ];

    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Settings',
        tag: 'Settings',
        codePageIndex: 18,
        children: [
          WbxmlElement(
            namespace: 'Settings',
            tag: 'Oof',
            codePageIndex: 18,
            children: [
              WbxmlElement(
                namespace: 'Settings',
                tag: 'Set',
                codePageIndex: 18,
                children: setChildren,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  int parseResponse(WbxmlDocument response) {
    final root = response.root;
    return int.tryParse(root.childText('Settings', 'Status') ?? '') ?? 0;
  }
}

/// Send device information to the server.
class SettingsSendDeviceInfoCommand extends EasCommand<int> {
  final String model;
  final String friendlyName;
  final String os;
  final String? osLanguage;
  final String? phoneNumber;

  SettingsSendDeviceInfoCommand({
    required this.model,
    required this.friendlyName,
    required this.os,
    this.osLanguage,
    this.phoneNumber,
  });

  @override
  String get commandName => 'Settings';

  @override
  WbxmlDocument buildRequest() {
    final deviceChildren = <WbxmlElement>[
      WbxmlElement.withText(
        namespace: 'Settings',
        tag: 'Model',
        text: model,
        codePageIndex: 18,
      ),
      WbxmlElement.withText(
        namespace: 'Settings',
        tag: 'FriendlyName',
        text: friendlyName,
        codePageIndex: 18,
      ),
      WbxmlElement.withText(
        namespace: 'Settings',
        tag: 'OS',
        text: os,
        codePageIndex: 18,
      ),
      if (osLanguage != null)
        WbxmlElement.withText(
          namespace: 'Settings',
          tag: 'OSLanguage',
          text: osLanguage!,
          codePageIndex: 18,
        ),
      if (phoneNumber != null)
        WbxmlElement.withText(
          namespace: 'Settings',
          tag: 'PhoneNumber',
          text: phoneNumber!,
          codePageIndex: 18,
        ),
    ];

    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Settings',
        tag: 'Settings',
        codePageIndex: 18,
        children: [
          WbxmlElement(
            namespace: 'Settings',
            tag: 'DeviceInformation',
            codePageIndex: 18,
            children: [
              WbxmlElement(
                namespace: 'Settings',
                tag: 'Set',
                codePageIndex: 18,
                children: deviceChildren,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  int parseResponse(WbxmlDocument response) {
    final root = response.root;
    return int.tryParse(root.childText('Settings', 'Status') ?? '') ?? 0;
  }
}

/// IRM template from RightsManagement.
class EasRightsManagementTemplate {
  final String? id;
  final String? name;
  final String? description;

  const EasRightsManagementTemplate({this.id, this.name, this.description});
}

/// Rights management info response.
class EasRightsManagementInfo {
  final int status;
  final List<EasRightsManagementTemplate> templates;

  const EasRightsManagementInfo({
    required this.status,
    this.templates = const [],
  });
}

/// Get RightsManagement information (IRM templates).
class SettingsGetRightsManagementCommand
    extends EasCommand<EasRightsManagementInfo> {
  @override
  String get commandName => 'Settings';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Settings',
        tag: 'Settings',
        codePageIndex: 18,
        children: [
          WbxmlElement(
            namespace: 'Settings',
            tag: 'RightsManagementInformation',
            codePageIndex: 18,
            children: [
              WbxmlElement(
                namespace: 'Settings',
                tag: 'Get',
                codePageIndex: 18,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  EasRightsManagementInfo parseResponse(WbxmlDocument response) {
    final root = response.root;
    final status =
        int.tryParse(root.childText('Settings', 'Status') ?? '') ?? 0;

    final rmEl = root.findChild('Settings', 'RightsManagementInformation');
    if (rmEl == null) return EasRightsManagementInfo(status: status);

    final getEl = rmEl.findChild('Settings', 'Get');
    if (getEl == null) return EasRightsManagementInfo(status: status);

    final templates = getEl
        .findChildren('RightsManagement', 'RightsManagementTemplate')
        .map((t) => EasRightsManagementTemplate(
              id: t.childText('RightsManagement', 'TemplateID'),
              name: t.childText('RightsManagement', 'TemplateName'),
              description:
                  t.childText('RightsManagement', 'TemplateDescription'),
            ))
        .toList();

    return EasRightsManagementInfo(status: status, templates: templates);
  }
}

/// Enable/set device password.
class SettingsSetDevicePasswordCommand extends EasCommand<int> {
  final String password;

  SettingsSetDevicePasswordCommand({required this.password});

  @override
  String get commandName => 'Settings';

  @override
  WbxmlDocument buildRequest() {
    return WbxmlDocument(
      root: WbxmlElement(
        namespace: 'Settings',
        tag: 'Settings',
        codePageIndex: 18,
        children: [
          WbxmlElement(
            namespace: 'Settings',
            tag: 'DevicePassword',
            codePageIndex: 18,
            children: [
              WbxmlElement(
                namespace: 'Settings',
                tag: 'Set',
                codePageIndex: 18,
                children: [
                  WbxmlElement.withText(
                    namespace: 'Settings',
                    tag: 'Password',
                    text: password,
                    codePageIndex: 18,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  int parseResponse(WbxmlDocument response) {
    final root = response.root;
    return int.tryParse(root.childText('Settings', 'Status') ?? '') ?? 0;
  }
}
