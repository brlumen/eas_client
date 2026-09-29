/// Registry of all EAS WBXML code pages.
///
/// Provides lookup by page index or namespace name.
library;

import 'code_page.dart';
import 'air_sync.dart';
import 'contacts.dart';
import 'email.dart';
import 'notes.dart';
import 'contacts2.dart';
import 'calendar.dart';
import 'move.dart';
import 'item_estimate.dart';
import 'folder_hierarchy.dart';
import 'meeting_response.dart';
import 'tasks.dart';
import 'resolve_recipients.dart';
import 'validate_cert.dart';
import 'ping.dart';
import 'provision.dart';
import 'search.dart';
import 'gal.dart';
import 'air_sync_base.dart';
import 'settings.dart';
import 'item_operations.dart';
import 'compose_mail.dart';
import 'document_library.dart';
import 'email2.dart';
import 'find.dart';
import 'rights_management.dart';

class CodePageRegistry {
  static final CodePageRegistry instance = CodePageRegistry._();

  CodePageRegistry._();

  final Map<int, CodePage> _byIndex = {
    0: AirSyncCodePage.instance,
    1: ContactsCodePage.instance,
    2: EmailCodePage.instance,
    4: CalendarCodePage.instance,
    5: MoveCodePage.instance,
    6: ItemEstimateCodePage.instance,
    7: FolderHierarchyCodePage.instance,
    8: MeetingResponseCodePage.instance,
    9: TasksCodePage.instance,
    10: ResolveRecipientsCodePage.instance,
    11: ValidateCertCodePage.instance,
    12: Contacts2CodePage.instance,
    13: PingCodePage.instance,
    14: ProvisionCodePage.instance,
    15: SearchCodePage.instance,
    16: GalCodePage.instance,
    17: AirSyncBaseCodePage.instance,
    18: SettingsCodePage.instance,
    19: DocumentLibraryCodePage.instance,
    20: ItemOperationsCodePage.instance,
    21: ComposeMailCodePage.instance,
    22: Email2CodePage.instance,
    23: NotesCodePage.instance,
    24: RightsManagementCodePage.instance,
    25: FindCodePage.instance,
  };

  late final Map<String, CodePage> _byNamespace = {
    for (final cp in _byIndex.values) cp.namespace: cp,
  };

  /// Get code page by index. Returns null if not found.
  CodePage? getByIndex(int index) => _byIndex[index];

  /// Get code page by namespace name. Returns null if not found.
  CodePage? getByNamespace(String namespace) => _byNamespace[namespace];

  /// All registered code pages.
  Iterable<CodePage> get pages => _byIndex.values;

  /// Register a custom code page.
  void register(CodePage page) {
    _byIndex[page.pageIndex] = page;
    _byNamespace[page.namespace] = page;
  }
}
