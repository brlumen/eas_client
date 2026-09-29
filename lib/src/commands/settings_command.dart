/// Settings command — get/set Out-of-Office, device password, device
/// information, user information and IRM templates.
///
/// Reference: MS-ASCMD section 2.2.1.18, MS-ASRM
library;

import '../models/eas_device_information.dart';
import '../models/wbxml_helpers.dart' show isoDateTime;
import '../wbxml/wbxml_document.dart';
import 'eas_command.dart';
import 'wbxml_builders.dart';

const _ns = 'Settings';
const _rm = 'RightsManagement';

/// Settings status codes (MS-ASCMD 2.2.3.177.15). Values 100-255 are
/// property-specific.
enum SettingsStatus {
  success(1, 'Success'),
  protocolError(2, 'Protocol error'),
  accessDenied(3, 'Access denied'),
  serverUnavailable(4, 'Server unavailable'),
  invalidArguments(5, 'Invalid arguments'),
  conflictingArguments(6, 'Conflicting arguments'),
  deniedByPolicy(7, 'Denied by policy');

  final int code;
  final String description;

  const SettingsStatus(this.code, this.description);

  static SettingsStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

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

  static OofState fromValue(int value) => OofState.values.firstWhere(
    (e) => e.value == value,
    orElse: () => OofState.disabled,
  );
}

/// OOF message for a specific audience (`OofMessage`).
class OofMessage {
  /// Whether auto-reply is enabled for this audience.
  final bool enabled;

  /// Reply message text.
  final String? replyMessage;

  /// Format of [replyMessage]: 'Text' or 'HTML'.
  final String? bodyType;

  const OofMessage({this.enabled = false, this.replyMessage, this.bodyType});
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

  static const _audiences = [
    'AppliesToInternal',
    'AppliesToExternalKnown',
    'AppliesToExternalUnknown',
  ];

  List<OofMessage?> get _messages => [
    internalMessage,
    externalKnownMessage,
    externalUnknownMessage,
  ];

  /// Children of the Oof `Set` element.
  List<WbxmlElement> toSetChildren() => [
    xText(_ns, 'OofState', state.value),
    if (startTime != null) xText(_ns, 'StartTime', isoDateTime(startTime!)),
    if (endTime != null) xText(_ns, 'EndTime', isoDateTime(endTime!)),
    for (var i = 0; i < _audiences.length; i++)
      if (_messages[i] case final m?)
        xEl(_ns, 'OofMessage', [
          xEl(_ns, _audiences[i]),
          xText(_ns, 'Enabled', m.enabled ? '1' : '0'),
          if (m.replyMessage != null)
            xText(_ns, 'ReplyMessage', m.replyMessage!),
          if (m.bodyType != null) xText(_ns, 'BodyType', m.bodyType!),
        ]),
  ];

  /// Parse the Oof `Get` response element.
  factory EasOofSettings.fromGet(WbxmlElement get) {
    final messages = <String, OofMessage>{};
    for (final m in get.findChildren(_ns, 'OofMessage')) {
      final message = OofMessage(
        enabled: m.childText(_ns, 'Enabled') == '1',
        replyMessage: m.childText(_ns, 'ReplyMessage'),
        bodyType: m.childText(_ns, 'BodyType'),
      );
      for (final audience in _audiences) {
        if (m.findChild(_ns, audience) != null) messages[audience] = message;
      }
    }
    return EasOofSettings(
      state: OofState.fromValue(
        int.tryParse(get.childText(_ns, 'OofState') ?? '') ?? 0,
      ),
      startTime: DateTime.tryParse(get.childText(_ns, 'StartTime') ?? ''),
      endTime: DateTime.tryParse(get.childText(_ns, 'EndTime') ?? ''),
      internalMessage: messages[_audiences[0]],
      externalKnownMessage: messages[_audiences[1]],
      externalUnknownMessage: messages[_audiences[2]],
    );
  }
}

/// A mail account of the user (`Account`, EAS 14.1+).
class EasAccount {
  final String? accountId;
  final String? accountName;
  final String? userDisplayName;

  /// Whether sending from this account is disabled.
  final bool sendDisabled;
  final List<String> smtpAddresses;
  final String? primarySmtpAddress;

  const EasAccount({
    this.accountId,
    this.accountName,
    this.userDisplayName,
    this.sendDisabled = false,
    this.smtpAddresses = const [],
    this.primarySmtpAddress,
  });

  @override
  String toString() => 'EasAccount(...)';
}

/// User information from the server.
class EasUserInfo {
  /// Display name (of the primary account, if any).
  final String? displayName;

  /// Primary SMTP address (or the first SMTP address).
  final String? emailAddress;

  /// All SMTP addresses (`EmailAddresses/SMTPAddress`).
  final List<String> smtpAddresses;

  /// `EmailAddresses/PrimarySmtpAddress`.
  final String? primarySmtpAddress;

  /// Accounts (`Accounts/Account`, EAS 14.1+).
  final List<EasAccount> accounts;

  const EasUserInfo({
    this.displayName,
    this.emailAddress,
    this.smtpAddresses = const [],
    this.primarySmtpAddress,
    this.accounts = const [],
  });

  static List<String> _smtp(WbxmlElement? addresses) => [
    ...?addresses
        ?.findChildren(_ns, 'SMTPAddress')
        .map((a) => a.text ?? '')
        .where((t) => t.isNotEmpty),
  ];

  /// Parse the UserInformation `Get` response element.
  factory EasUserInfo.fromGet(WbxmlElement get) {
    final addresses = get.findChild(_ns, 'EmailAddresses');
    final accounts = [
      for (final a
          in get.findChild(_ns, 'Accounts')?.findChildren(_ns, 'Account') ??
              <WbxmlElement>[])
        EasAccount(
          accountId: a.childText(_ns, 'AccountId'),
          accountName: a.childText(_ns, 'AccountName'),
          userDisplayName: a.childText(_ns, 'UserDisplayName'),
          sendDisabled: const {
            '1',
            'true',
          }.contains(a.childText(_ns, 'SendDisabled')?.toLowerCase()),
          smtpAddresses: _smtp(a.findChild(_ns, 'EmailAddresses')),
          primarySmtpAddress: a
              .findChild(_ns, 'EmailAddresses')
              ?.childText(_ns, 'PrimarySmtpAddress'),
        ),
    ];
    final smtp = _smtp(addresses);
    final primary =
        addresses?.childText(_ns, 'PrimarySmtpAddress') ??
        accounts.firstOrNull?.primarySmtpAddress;
    return EasUserInfo(
      displayName:
          get.childText(_ns, 'UserDisplayName') ??
          accounts.firstOrNull?.userDisplayName,
      emailAddress:
          primary ??
          smtp.firstOrNull ??
          accounts.firstOrNull?.smtpAddresses.firstOrNull,
      smtpAddresses: smtp,
      primarySmtpAddress: primary,
      accounts: accounts,
    );
  }

  @override
  String toString() => 'EasUserInfo(accounts: ${accounts.length})';
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

/// Parsed Settings response. Each `*Status` is the status of the
/// corresponding sub-command (null if absent from the response).
class SettingsResponse {
  /// Overall `Settings/Status`.
  final int status;
  final int? oofStatus;
  final EasOofSettings? oof;
  final int? devicePasswordStatus;
  final int? deviceInformationStatus;
  final int? userInformationStatus;
  final EasUserInfo? userInfo;
  final int? rightsManagementStatus;
  final List<EasRightsManagementTemplate> rightsManagementTemplates;

  const SettingsResponse({
    required this.status,
    this.oofStatus,
    this.oof,
    this.devicePasswordStatus,
    this.deviceInformationStatus,
    this.userInformationStatus,
    this.userInfo,
    this.rightsManagementStatus,
    this.rightsManagementTemplates = const [],
  });

  bool get isSuccess => status == 1;

  factory SettingsResponse.parse(WbxmlDocument response) {
    final root = response.root;
    int? sub(WbxmlElement? el) =>
        el == null ? null : int.tryParse(el.childText(_ns, 'Status') ?? '');

    final oofEl = root.findChild(_ns, 'Oof');
    final oofGet = oofEl?.findChild(_ns, 'Get');
    final userEl = root.findChild(_ns, 'UserInformation');
    final userGet = userEl?.findChild(_ns, 'Get');
    final rmEl = root.findChild(_ns, 'RightsManagementInformation');
    final templatesEl = rmEl
        ?.findChild(_ns, 'Get')
        ?.findChild(_rm, 'RightsManagementTemplates');

    return SettingsResponse(
      status: xStatus(root, _ns),
      oofStatus: sub(oofEl),
      oof: oofGet == null ? null : EasOofSettings.fromGet(oofGet),
      devicePasswordStatus: sub(root.findChild(_ns, 'DevicePassword')),
      deviceInformationStatus: EasDeviceInformation.statusOf(root),
      userInformationStatus: sub(userEl),
      userInfo: userGet == null ? null : EasUserInfo.fromGet(userGet),
      rightsManagementStatus: sub(rmEl),
      rightsManagementTemplates: [
        for (final t
            in templatesEl?.findChildren(_rm, 'RightsManagementTemplate') ??
                <WbxmlElement>[])
          EasRightsManagementTemplate(
            id: t.childText(_rm, 'TemplateID'),
            name: t.childText(_rm, 'TemplateName'),
            description: t.childText(_rm, 'TemplateDescription'),
          ),
      ],
    );
  }
}

/// Settings command with any combination of sub-commands.
///
/// Oof is either Get ([getOof]) or Set ([setOof]). The device password is
/// kept private and never exposed via fields or `toString()`.
class SettingsCommand extends EasCommand<SettingsResponse> {
  final bool getRightsManagementInformation;

  /// Oof Get with the requested reply format ('Text' or 'HTML').
  final String? getOofBodyType;
  final EasOofSettings? setOof;
  final String? _devicePassword;
  final EasDeviceInformation? deviceInformation;
  final bool getUserInformation;

  /// Max device password length (MS-ASCMD 6.38).
  static const maxPasswordLength = 255;

  SettingsCommand({
    this.getRightsManagementInformation = false,
    this.getOofBodyType,
    this.setOof,
    String? devicePassword,
    this.deviceInformation,
    this.getUserInformation = false,
  }) : _devicePassword = devicePassword {
    if (getOofBodyType != null && setOof != null) {
      throw ArgumentError('Oof is either Get or Set');
    }
    if (getOofBodyType != null && getOofBodyType!.isEmpty) {
      throw ArgumentError.value(getOofBodyType, 'getOofBodyType');
    }
    if (devicePassword != null) {
      checkLength(
        devicePassword,
        maxPasswordLength,
        'devicePassword',
        allowEmpty: true,
      );
    }
    if (!getRightsManagementInformation &&
        getOofBodyType == null &&
        setOof == null &&
        devicePassword == null &&
        deviceInformation == null &&
        !getUserInformation) {
      throw ArgumentError('No Settings sub-command specified');
    }
  }

  @override
  String get commandName => 'Settings';

  @override
  WbxmlDocument buildRequest() => WbxmlDocument(
    root: xEl(_ns, 'Settings', [
      if (getRightsManagementInformation)
        xEl(_ns, 'RightsManagementInformation', [xEl(_ns, 'Get')]),
      if (getOofBodyType != null)
        xEl(_ns, 'Oof', [
          xEl(_ns, 'Get', [xText(_ns, 'BodyType', getOofBodyType!)]),
        ]),
      if (setOof != null)
        xEl(_ns, 'Oof', [xEl(_ns, 'Set', setOof!.toSetChildren())]),
      if (_devicePassword != null)
        xEl(_ns, 'DevicePassword', [
          xEl(_ns, 'Set', [xText(_ns, 'Password', _devicePassword)]),
        ]),
      if (deviceInformation != null) deviceInformation!.toElement(),
      if (getUserInformation) xEl(_ns, 'UserInformation', [xEl(_ns, 'Get')]),
    ]),
  );

  @override
  SettingsResponse parseResponse(WbxmlDocument response) =>
      SettingsResponse.parse(response);

  @override
  String toString() => 'SettingsCommand(...)';
}

/// Combined settings response (OOF + user information).
class EasSettings {
  final int status;
  final EasOofSettings? oof;
  final EasUserInfo? userInfo;

  bool get isSuccess => status == 1;

  const EasSettings({required this.status, this.oof, this.userInfo});
}

/// Status of a sub-command: its own status if present, else the overall
/// one.
int _subStatus(int? sub, int overall) => sub ?? overall;

/// Get current settings (OOF + user info).
class SettingsGetCommand extends EasCommand<EasSettings> {
  /// Requested OOF reply format ('Text' or 'HTML').
  final String oofBodyType;

  SettingsGetCommand({this.oofBodyType = 'Text'});

  late final _inner = SettingsCommand(
    getOofBodyType: oofBodyType,
    getUserInformation: true,
  );

  @override
  String get commandName => 'Settings';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  @override
  EasSettings parseResponse(WbxmlDocument response) {
    final r = SettingsResponse.parse(response);
    return EasSettings(status: r.status, oof: r.oof, userInfo: r.userInfo);
  }
}

/// Set Out-of-Office state and reply messages. Returns the Oof status.
class SettingsSetOofCommand extends EasCommand<int> {
  final EasOofSettings oof;

  SettingsSetOofCommand({required this.oof});

  late final _inner = SettingsCommand(setOof: oof);

  @override
  String get commandName => 'Settings';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  @override
  int parseResponse(WbxmlDocument response) {
    final r = SettingsResponse.parse(response);
    return _subStatus(r.oofStatus, r.status);
  }
}

/// Send device information to the server. Returns the DeviceInformation
/// status.
class SettingsSendDeviceInfoCommand extends EasCommand<int> {
  final EasDeviceInformation deviceInformation;

  SettingsSendDeviceInfoCommand.info(this.deviceInformation);

  factory SettingsSendDeviceInfoCommand({
    String? model,
    String? imei,
    String? friendlyName,
    String? os,
    String? osLanguage,
    String? phoneNumber,
    String? userAgent,
    bool? enableOutboundSms,
    String? mobileOperator,
  }) => SettingsSendDeviceInfoCommand.info(
    EasDeviceInformation(
      model: model,
      imei: imei,
      friendlyName: friendlyName,
      os: os,
      osLanguage: osLanguage,
      phoneNumber: phoneNumber,
      userAgent: userAgent,
      enableOutboundSms: enableOutboundSms,
      mobileOperator: mobileOperator,
    ),
  );

  late final _inner = SettingsCommand(deviceInformation: deviceInformation);

  @override
  String get commandName => 'Settings';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  @override
  int parseResponse(WbxmlDocument response) {
    final r = SettingsResponse.parse(response);
    return _subStatus(r.deviceInformationStatus, r.status);
  }
}

/// Get RightsManagement information (IRM templates, EAS 14.1+).
class SettingsGetRightsManagementCommand
    extends EasCommand<EasRightsManagementInfo> {
  late final _inner = SettingsCommand(getRightsManagementInformation: true);

  @override
  String get commandName => 'Settings';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  @override
  EasRightsManagementInfo parseResponse(WbxmlDocument response) {
    final r = SettingsResponse.parse(response);
    return EasRightsManagementInfo(
      status: _subStatus(r.rightsManagementStatus, r.status),
      templates: r.rightsManagementTemplates,
    );
  }
}

/// Set the device password (recovery password stored on the server).
/// Returns the DevicePassword status (7 = password recovery disabled).
///
/// The password is kept private and never exposed via fields or
/// `toString()`.
class SettingsSetDevicePasswordCommand extends EasCommand<int> {
  final SettingsCommand _inner;

  SettingsSetDevicePasswordCommand({required String password})
    : _inner = SettingsCommand(devicePassword: password);

  @override
  String get commandName => 'Settings';

  @override
  WbxmlDocument buildRequest() => _inner.buildRequest();

  @override
  int parseResponse(WbxmlDocument response) {
    final r = SettingsResponse.parse(response);
    return _subStatus(r.devicePasswordStatus, r.status);
  }

  @override
  String toString() => 'SettingsSetDevicePasswordCommand(...)';
}
