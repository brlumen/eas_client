/// Code Page 18: Settings namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.19
library;

import 'code_page.dart';

class SettingsCodePage extends CodePage {
  static final SettingsCodePage instance = SettingsCodePage._();

  SettingsCodePage._();

  @override
  int get pageIndex => 18;

  @override
  String get namespace => 'Settings';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'Settings',
        0x06: 'Status',
        0x07: 'Get',
        0x08: 'Set',
        0x09: 'Oof',
        0x0A: 'OofState',
        0x0B: 'StartTime',
        0x0C: 'EndTime',
        0x0D: 'OofMessage',
        0x0E: 'AppliesToInternal',
        0x0F: 'AppliesToExternalKnown',
        0x10: 'AppliesToExternalUnknown',
        0x11: 'Enabled',
        0x12: 'ReplyMessage',
        0x13: 'BodyType',
        0x14: 'DevicePassword',
        0x15: 'Password',
        0x16: 'DeviceInformation',
        0x17: 'Model',
        0x18: 'IMEI',
        0x19: 'FriendlyName',
        0x1A: 'OS',
        0x1B: 'OSLanguage',
        0x1C: 'PhoneNumber',
        0x1D: 'UserInformation',
        0x1E: 'EmailAddresses',
        0x1F: 'SMTPAddress',
        0x20: 'UserAgent',
        0x21: 'EnableOutboundSMS',
        0x22: 'MobileOperator',
        0x23: 'PrimarySmtpAddress',
        0x24: 'Accounts',
        0x25: 'Account',
        0x26: 'AccountId',
        0x27: 'AccountName',
        0x28: 'UserDisplayName',
        0x29: 'SendDisabled',
        0x2B: 'RightsManagementInformation',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
