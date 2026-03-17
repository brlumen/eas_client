/// EAS note model (sticky note / IPM.StickyNote).
library;

/// EAS note.
class EasNote {
  /// Server-assigned ID.
  final String serverId;

  /// Note subject/title.
  final String subject;

  /// Note body.
  final String? body;

  /// Last modified date (UTC).
  final DateTime? lastModifiedDate;

  /// Whether the note is read.
  final bool isRead;

  /// Categories.
  final List<String> categories;

  const EasNote({
    required this.serverId,
    this.subject = '',
    this.body,
    this.lastModifiedDate,
    this.isRead = false,
    this.categories = const [],
  });

  @override
  String toString() => 'EasNote($serverId, subject: $subject)';
}
