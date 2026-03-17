/// Code Page 24: RightsManagement namespace.
///
/// Reference: MS-ASWBXML section 2.2.2.24
library;

import 'code_page.dart';

class RightsManagementCodePage extends CodePage {
  static final RightsManagementCodePage instance =
      RightsManagementCodePage._();

  RightsManagementCodePage._();

  @override
  int get pageIndex => 24;

  @override
  String get namespace => 'RightsManagement';

  @override
  Map<int, String> get tokenToTag => const {
        0x05: 'RightsManagementSupport',
        0x06: 'RightsManagementTemplates',
        0x07: 'RightsManagementTemplate',
        0x08: 'RightsManagementLicense',
        0x09: 'EditAllowed',
        0x0A: 'ReplyAllowed',
        0x0B: 'ReplyAllAllowed',
        0x0C: 'ForwardAllowed',
        0x0D: 'ModifyRecipientsAllowed',
        0x0E: 'ExtractAllowed',
        0x0F: 'PrintAllowed',
        0x10: 'ExportAllowed',
        0x11: 'ProgrammaticAccessAllowed',
        0x12: 'Owner',
        0x13: 'ContentExpiryDate',
        0x14: 'TemplateID',
        0x15: 'TemplateName',
        0x16: 'TemplateDescription',
        0x17: 'ContentOwner',
        0x18: 'RemoveRightsManagementDistribution',
      };

  @override
  late final Map<String, int> tagToToken = {
    for (final e in tokenToTag.entries) e.value: e.key,
  };
}
