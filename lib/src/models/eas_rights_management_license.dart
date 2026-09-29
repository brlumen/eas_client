/// IRM license of a protected message (MS-ASRM 2.2.2.14
/// RightsManagementLicense).
library;

import '../wbxml/wbxml_document.dart';
import 'wbxml_helpers.dart';

/// Rights granted to the user on an IRM-protected message.
class EasRightsManagementLicense {
  final DateTime? contentExpiryDate;
  final String? contentOwner;
  final bool editAllowed;
  final bool exportAllowed;
  final bool extractAllowed;
  final bool forwardAllowed;
  final bool modifyRecipientsAllowed;

  /// Whether the current user is the owner of the license.
  final bool owner;
  final bool printAllowed;
  final bool programmaticAccessAllowed;
  final bool replyAllAllowed;
  final bool replyAllowed;
  final String? templateDescription;
  final String? templateId;
  final String? templateName;

  const EasRightsManagementLicense({
    this.contentExpiryDate,
    this.contentOwner,
    this.editAllowed = false,
    this.exportAllowed = false,
    this.extractAllowed = false,
    this.forwardAllowed = false,
    this.modifyRecipientsAllowed = false,
    this.owner = false,
    this.printAllowed = false,
    this.programmaticAccessAllowed = false,
    this.replyAllAllowed = false,
    this.replyAllowed = false,
    this.templateDescription,
    this.templateId,
    this.templateName,
  });

  factory EasRightsManagementLicense.fromElement(WbxmlElement el) {
    const ns = 'RightsManagement';
    bool b(String tag) => el.boolean(ns, tag) ?? false;
    return EasRightsManagementLicense(
      contentExpiryDate: el.date(ns, 'ContentExpiryDate'),
      contentOwner: el.str(ns, 'ContentOwner'),
      editAllowed: b('EditAllowed'),
      exportAllowed: b('ExportAllowed'),
      extractAllowed: b('ExtractAllowed'),
      forwardAllowed: b('ForwardAllowed'),
      modifyRecipientsAllowed: b('ModifyRecipientsAllowed'),
      owner: b('Owner'),
      printAllowed: b('PrintAllowed'),
      programmaticAccessAllowed: b('ProgrammaticAccessAllowed'),
      replyAllAllowed: b('ReplyAllAllowed'),
      replyAllowed: b('ReplyAllowed'),
      templateDescription: el.str(ns, 'TemplateDescription'),
      templateId: el.str(ns, 'TemplateID'),
      templateName: el.str(ns, 'TemplateName'),
    );
  }

  /// `rm:RightsManagementLicense` of [parent], or `null`.
  static EasRightsManagementLicense? of(WbxmlElement parent) {
    final el = parent.findChild('RightsManagement', 'RightsManagementLicense');
    return el == null ? null : EasRightsManagementLicense.fromElement(el);
  }

  @override
  String toString() => 'EasRightsManagementLicense($templateName)';
}
