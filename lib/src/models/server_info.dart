/// Server capabilities discovered via OPTIONS command.
library;

class ServerInfo {
  /// Supported EAS protocol versions (e.g., ['2.5', '12.0', '14.1', '16.1']).
  final List<String> supportedVersions;

  /// Supported EAS commands (e.g., ['Sync', 'FolderSync', 'Provision']).
  final List<String> supportedCommands;

  const ServerInfo({
    required this.supportedVersions,
    required this.supportedCommands,
  });

  /// Whether the server supports a specific protocol version.
  bool supportsVersion(String version) =>
      supportedVersions.contains(version);

  @override
  String toString() =>
      'ServerInfo(versions: $supportedVersions, commands: $supportedCommands)';
}
