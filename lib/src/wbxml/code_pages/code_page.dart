/// Abstract code page for WBXML tag-to-token mapping.
///
/// Each EAS namespace (AirSync, Email, FolderHierarchy, etc.) has its own
/// code page with a unique index and tag mappings.
library;

abstract class CodePage {
  /// Code page index (0-24).
  int get pageIndex;

  /// Namespace name (e.g., 'AirSync', 'FolderHierarchy').
  String get namespace;

  /// Map from token byte (0x05-0x3F) to tag name.
  Map<int, String> get tokenToTag;

  /// Map from tag name to token byte.
  Map<String, int> get tagToToken;
}
