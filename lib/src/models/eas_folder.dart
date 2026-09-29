/// EAS folder model.
library;

/// Folder types as defined by MS-ASCMD section 2.2.3.170.3.
enum EasFolderType {
  userGeneric(1),
  defaultInbox(2),
  defaultDrafts(3),
  defaultDeletedItems(4),
  defaultSentItems(5),
  defaultOutbox(6),
  defaultTasks(7),
  defaultCalendar(8),
  defaultContacts(9),
  defaultNotes(10),
  defaultJournal(11),
  userMail(12),
  userCalendar(13),
  userContacts(14),
  userTasks(15),
  userJournal(16),
  userNotes(17),
  unknown(18),
  recipientInfoCache(19);

  final int value;
  const EasFolderType(this.value);

  static EasFolderType fromValue(int value) {
    return EasFolderType.values.firstWhere(
      (t) => t.value == value,
      orElse: () => EasFolderType.unknown,
    );
  }
}

class EasFolder {
  /// Server-assigned folder ID.
  final String serverId;

  /// Parent folder ID ('0' for root level).
  final String parentId;

  /// Display name of the folder.
  final String displayName;

  /// Folder type.
  final EasFolderType type;

  const EasFolder({
    required this.serverId,
    required this.parentId,
    required this.displayName,
    required this.type,
  });

  /// Whether this is a mail folder.
  bool get isMailFolder =>
      type == EasFolderType.defaultInbox ||
      type == EasFolderType.defaultDrafts ||
      type == EasFolderType.defaultDeletedItems ||
      type == EasFolderType.defaultSentItems ||
      type == EasFolderType.defaultOutbox ||
      type == EasFolderType.userMail;

  @override
  String toString() =>
      'EasFolder($displayName, type: ${type.name}, id: $serverId)';
}
