import 'dart:typed_data';

import 'package:eas_client/eas_client.dart';

void main() async {
  // --- WBXML codec example ---
  wbxmlExample();

  // --- EAS client example (requires a real Exchange server) ---
  // Uncomment to run: await easClientExample();
}

/// Demonstrates WBXML encoding and decoding.
void wbxmlExample() {
  final doc = WbxmlDocument(
    root: WbxmlElement(
      namespace: 'FolderHierarchy',
      tag: 'FolderSync',
      codePageIndex: 7,
      children: [
        WbxmlElement.withText(
          namespace: 'FolderHierarchy',
          tag: 'SyncKey',
          text: '0',
          codePageIndex: 7,
        ),
      ],
    ),
  );

  final encoder = WbxmlEncoder();
  final Uint8List bytes = encoder.encode(doc);
  print('Encoded ${bytes.length} bytes');

  final decoder = WbxmlDecoder();
  final decoded = decoder.decode(bytes);
  print('Decoded: ${decoded.root.tag}');
  print('SyncKey: ${decoded.root.childText('FolderHierarchy', 'SyncKey')}');
}

/// Demonstrates full EAS client workflow.
/// Requires a real Exchange server with ActiveSync enabled.
Future<void> easClientExample() async {
  final deviceId = DeviceIdGenerator.generate(); // persist this!
  final client = EasClient(
    server: 'mail.example.com',
    credentials: BasicCredentials(
      username: 'user@example.com',
      password: 'password',
    ),
    deviceId: deviceId,
  );

  try {
    // 1. Discover capabilities
    final info = await client.discoverCapabilities();
    print('Supported versions: ${info.supportedVersions}');

    // 2. Provision (required before any other command)
    await client.provision();

    // 3. Get folder list
    final folders = await client.syncFolders();
    for (final f in folders.addedFolders) {
      print('Folder: ${f.displayName} (${f.type.name})');
    }

    // 4. Sync inbox emails
    final inboxId = folders.addedFolders
        .firstWhere((f) => f.type == EasFolderType.defaultInbox)
        .serverId;
    final emails = await client.fullSync(inboxId);
    for (final email in emails) {
      print('Email: ${email.subject} from ${email.from}');
    }

    // 5. Send email
    await client.sendMail(
      clientId: 'unique-id-123',
      mimeContent: 'From: user@example.com\r\n'
          'To: recipient@example.com\r\n'
          'Subject: Test\r\n'
          '\r\n'
          'Hello from eas_client!',
    );
  } finally {
    client.dispose();
  }
}
