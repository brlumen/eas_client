/// Dart implementation of Microsoft Exchange ActiveSync (EAS) protocol client.
///
/// Provides WBXML codec, HTTP transport, and EAS command implementations
/// for synchronizing email, contacts, calendar, tasks, and notes with
/// Exchange servers.
library;

// WBXML codec
export 'src/wbxml/wbxml_codec.dart';
export 'src/wbxml/wbxml_constants.dart';
export 'src/wbxml/wbxml_document.dart';
export 'src/wbxml/code_pages/code_page.dart';
export 'src/wbxml/code_pages/code_page_registry.dart';

// Transport
export 'src/transport/eas_credentials.dart';
export 'src/transport/eas_http_client.dart';
export 'src/transport/device_id_generator.dart';
export 'src/transport/autodiscover.dart';

// Commands
export 'src/commands/eas_command.dart';
export 'src/commands/options_command.dart';
export 'src/commands/provision_command.dart';
export 'src/commands/folder_sync_command.dart';
export 'src/commands/folder_management_command.dart';
export 'src/commands/sync_command.dart';
export 'src/commands/ping_command.dart';
export 'src/commands/item_operations_command.dart';
export 'src/commands/send_mail_command.dart';
export 'src/commands/smart_reply_command.dart';
export 'src/commands/smart_forward_command.dart';
export 'src/commands/move_items_command.dart';
export 'src/commands/search_command.dart';
export 'src/commands/meeting_response_command.dart';
export 'src/commands/get_item_estimate_command.dart';
export 'src/commands/settings_command.dart';
export 'src/commands/resolve_recipients_command.dart';
export 'src/commands/validate_cert_command.dart';

// Commands (new)
export 'src/commands/find_command.dart';

// Models
export 'src/models/server_info.dart';
export 'src/models/eas_policy.dart';
export 'src/models/eas_folder.dart';
export 'src/models/eas_email.dart';
export 'src/models/eas_attachment.dart';
export 'src/models/eas_calendar_event.dart';
export 'src/models/eas_task.dart';
export 'src/models/eas_contact.dart';
export 'src/models/eas_note.dart';
export 'src/models/eas_recurrence.dart';
export 'src/models/eas_exception.dart';
export 'src/models/sync_state.dart';

// Serializers
export 'src/serializers/email_serializer.dart';
export 'src/serializers/calendar_serializer.dart';
export 'src/serializers/task_serializer.dart';
export 'src/serializers/contact_serializer.dart';
export 'src/serializers/note_serializer.dart';

// Client
export 'src/client/eas_client.dart';
