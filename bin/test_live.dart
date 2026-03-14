import 'dart:io';

import 'package:eas_client/eas_client.dart';

void main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    print('''
eas_client test_live — interactive test of the EAS package with a real server.

Usage:
  dart run bin/test_live.dart [--help]

The script prompts for email and password, then automatically discovers
the EAS server via Autodiscover. If discovery fails, it will prompt
for the server address manually.

Operations:
  1. AUTODISCOVER — find server by email
  2. OPTIONS      — check connectivity, get protocol versions
  3. PROVISION    — negotiate security policies
  4. FOLDERSYNC   — get folder list
  5. SYNC INBOX   — sync inbox (first 5 emails)
  6. SEND MAIL    — send a test email (interactive)

Requirements:
  - Exchange Server with ActiveSync enabled (on-premise or z-push)
  - Credentials with EAS access (Basic Auth)
  - For Exchange Online (Microsoft 365) Basic Auth is disabled —
    use an on-premise server or z-push for testing
''');
    exit(0);
  }

  stdout.write('Email: ');
  final email = stdin.readLineSync()?.trim() ?? '';
  if (email.isEmpty || !email.contains('@')) {
    print('Valid email is required');
    exit(1);
  }

  stdout.write('Password: ');
  stdin.echoMode = false;
  final password = stdin.readLineSync()?.trim() ?? '';
  stdin.echoMode = true;
  print('');
  if (password.isEmpty) {
    print('Password is required');
    exit(1);
  }

  // Autodiscover → fallback to manual
  final deviceId = DeviceIdGenerator.generate();
  EasClient client;
  print('\n=== AUTODISCOVER ===');
  print('Searching EAS server for $email...');
  print('DeviceId: $deviceId');
  try {
    client = await EasClient.autodiscover(
      email: email,
      password: password,
      deviceId: deviceId,
    );
    print('Found server: ${client.httpClient.server}');
  } on AutodiscoverException catch (e) {
    print('Autodiscover failed: ${e.message}');
    for (final url in e.triedUrls) {
      print('  tried: $url');
    }

    stdout.write('\nServer (manual): ');
    final server = stdin.readLineSync()?.trim() ?? '';
    if (server.isEmpty) {
      print('Server is required');
      exit(1);
    }

    client = EasClient(
      server: server,
      credentials: BasicCredentials(
        username: email,
        password: password,
      ),
      deviceId: deviceId,
    );
  }

  try {
    // 1. OPTIONS
    print('\n=== OPTIONS ===');
    final info = await client.discoverCapabilities();
    print('Versions: ${info.supportedVersions}');
    print('Commands: ${info.supportedCommands}');

    // 2. Provision
    print('\n=== PROVISION ===');
    final policy = await client.provision();
    if (policy != null) {
      print('PolicyKey: ${policy.policyKey}');
      print('DevicePasswordEnabled: ${policy.devicePasswordEnabled}');
      print('RequireDeviceEncryption: ${policy.requireDeviceEncryption}');
    } else {
      print('Server does not require provisioning');
    }

    // 3. FolderSync
    print('\n=== FOLDER SYNC ===');
    final folders = await client.syncFolders();
    for (final f in folders.addedFolders) {
      print('  ${f.displayName} (${f.type.name}) [${f.serverId}]');
    }

    // 4. Sync inbox
    final inbox = folders.addedFolders
        .where((f) => f.type == EasFolderType.defaultInbox)
        .firstOrNull;

    if (inbox != null) {
      print('\n=== SYNC INBOX: ${inbox.displayName} ===');
      final emails = await client.fullSync(
        inbox.serverId,
        bodyTruncationSize: 256,
      );
      for (final e in emails.take(5)) {
        print('  ${e.subject} | ${e.from} | ${e.dateReceived}');
      }
      print('Total: ${emails.length} emails');
    } else {
      print('\nInbox not found');
    }

    // 5. Send mail
    print('\n=== SEND MAIL ===');
    stdout.write('To (email): ');
    final to = stdin.readLineSync()?.trim() ?? '';
    if (to.isNotEmpty && to.contains('@')) {
      stdout.write('Subject: ');
      final subject = stdin.readLineSync()?.trim() ?? 'Test from eas_client';
      stdout.write('Body: ');
      final body = stdin.readLineSync()?.trim() ?? '';

      final safeTo = _sanitizeMimeHeader(to);
      final safeSubject = _sanitizeMimeHeader(subject);

      final mime = 'From: $email\r\n'
          'To: $safeTo\r\n'
          'Subject: $safeSubject\r\n'
          'MIME-Version: 1.0\r\n'
          'Content-Type: text/plain; charset=utf-8\r\n'
          '\r\n'
          '$body';

      final clientId = DateTime.now().millisecondsSinceEpoch.toString();
      await client.sendMail(clientId: clientId, mimeContent: mime);
      print('Sent!');
    } else {
      print('Skipped (empty or invalid email)');
    }

    print('\nDone!');
  } catch (e) {
    print('Error: $e');
    exit(1);
  } finally {
    client.dispose();
  }
}

/// Strip CR/LF to prevent MIME header injection.
String _sanitizeMimeHeader(String value) {
  return value.replaceAll(RegExp(r'[\r\n]'), '');
}
