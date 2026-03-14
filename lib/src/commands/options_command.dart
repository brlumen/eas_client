/// OPTIONS command — discovers server capabilities.
///
/// Reference: MS-ASHTTP section 2.2.4
library;

import '../models/server_info.dart';
import '../transport/eas_http_client.dart';

class OptionsCommand {
  /// Execute OPTIONS to discover server capabilities.
  Future<ServerInfo> execute(EasHttpClient client) async {
    final response = await client.sendOptions();

    if (!response.isSuccess) {
      throw Exception(
        'OPTIONS failed with HTTP ${response.statusCode}',
      );
    }

    final versions =
        response.headers['ms-asprotocolversions']?.split(',') ?? [];
    final commands =
        response.headers['ms-asprotocolcommands']?.split(',') ?? [];

    return ServerInfo(
      supportedVersions:
          versions.map((v) => v.trim()).where((v) => v.isNotEmpty).toList(),
      supportedCommands:
          commands.map((c) => c.trim()).where((c) => c.isNotEmpty).toList(),
    );
  }
}
