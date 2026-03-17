import 'dart:io';
import 'dart:math';

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
  1.  AUTODISCOVER   — find server by email
  2.  OPTIONS        — check connectivity, get protocol versions
  3.  PROVISION      — negotiate security policies
  4.  SETTINGS       — get OOF state and user info
  5.  FOLDERSYNC     — get folder list
  6.  SYNC INBOX     — sync inbox (first 5 emails)
  7.  FETCH BODY     — fetch full body of first email
  8.  GET ESTIMATE   — estimate inbox item count
  9.  SYNC CALENDAR  — sync calendar events
  10. SYNC TASKS     — sync tasks
  11. SYNC CONTACTS  — sync contacts
  12. SEND MAIL      — send a test email (interactive)
  13. SMART REPLY    — reply to first inbox email (interactive)
  14. MEETING RESP.  — respond to first calendar meeting (interactive)

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
      final error = e.errors[url];
      print('  tried: $url${error != null ? ' → $error' : ''}');
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
    final policy = await client.provision(
      policyAckStatus: PolicyAckStatus.notApplied,
    );
    if (policy != null) {
      print('PolicyKey: ${policy.policyKey}');
      print('DevicePasswordEnabled: ${policy.devicePasswordEnabled}');
      print('RequireDeviceEncryption: ${policy.requireDeviceEncryption}');
    } else {
      print('Server does not require provisioning');
    }

    // 3. Settings
    print('\n=== SETTINGS ===');
    try {
      final settings = await client.getSettings();
      if (settings.oof != null) {
        print('OOF state: ${settings.oof!.state.name}');
        final internal = settings.oof!.internalMessage;
        if (internal != null && internal.enabled) {
          print('OOF reply (internal): ${internal.replyMessage ?? "(empty)"}');
        }
      }
      if (settings.userInfo != null) {
        print('User: ${settings.userInfo!.displayName} '
            '<${settings.userInfo!.emailAddress}>');
      }
    } catch (e) {
      print('Settings not supported: $e');
    }

    // 4. FolderSync
    print('\n=== FOLDER SYNC ===');
    final folders = await client.syncFolders();
    for (final f in folders.addedFolders) {
      print('  ${f.displayName} (${f.type.name}) [${f.serverId}]');
    }

    // 5. Sync inbox
    final inbox = folders.addedFolders
        .where((f) => f.type == EasFolderType.defaultInbox)
        .firstOrNull;

    List<EasEmail> emails = [];
    if (inbox != null) {
      print('\n=== SYNC INBOX: ${inbox.displayName} ===');
      emails = await client.fullSync(
        inbox.serverId,
        bodyTruncationSize: 256,
        filterType: SyncFilterType.oneWeek,
      );
      for (final e in emails.take(5)) {
        print('  ${e.subject} | ${e.from} | ${e.dateReceived}');
      }
      print('Total: ${emails.length} emails');
    } else {
      print('\nInbox not found');
    }

    // 6. Fetch body of first email
    if (inbox != null && emails.isNotEmpty) {
      print('\n=== FETCH BODY ===');
      try {
        final first = emails.first;
        final bodyResult =
            await client.fetchEmailBody(first.serverId, inbox.serverId);
        final body = bodyResult.body ?? '';
        final preview = body.substring(0, min(200, body.length));
        print('Subject: ${first.subject}');
        print('Body preview: $preview${body.length > 200 ? "..." : ""}');
      } catch (e) {
        print('FetchBody failed: $e');
      }
    }

    // 7. GetItemEstimate for inbox
    if (inbox != null) {
      print('\n=== GET ITEM ESTIMATE ===');
      try {
        final count = await client.getItemEstimate(inbox.serverId);
        print('Inbox estimate: $count items');
      } catch (e) {
        print('GetItemEstimate not supported: $e');
      }
    }

    // 8. Sync calendar
    final calendarFolder = folders.addedFolders
        .where((f) =>
            f.type == EasFolderType.defaultCalendar ||
            f.type == EasFolderType.userCalendar)
        .firstOrNull;

    List<EasCalendarEvent> events = [];
    if (calendarFolder != null) {
      print('\n=== SYNC CALENDAR: ${calendarFolder.displayName} ===');
      try {
        events = await client.fullSyncCalendar(
          calendarFolder.serverId,
          bodyTruncationSize: 128,
        );
        for (final e in events.take(5)) {
          print('  ${e.subject} | ${e.startTime} → ${e.endTime}'
              '${e.location != null ? " @ ${e.location}" : ""}');
        }
        print('Total: ${events.length} events');
      } catch (e) {
        print('Calendar sync failed: $e');
      }
    } else {
      print('\nCalendar folder not found');
    }

    // 9. Sync tasks
    final tasksFolder = folders.addedFolders
        .where((f) =>
            f.type == EasFolderType.defaultTasks ||
            f.type == EasFolderType.userTasks)
        .firstOrNull;

    if (tasksFolder != null) {
      print('\n=== SYNC TASKS: ${tasksFolder.displayName} ===');
      try {
        final tasks = await client.fullSyncTasks(tasksFolder.serverId);
        for (final t in tasks.take(5)) {
          print('  [${t.complete ? "x" : " "}] ${t.subject}'
              '${t.dueDate != null ? " due ${t.dueDate!.toLocal().toIso8601String().substring(0, 10)}" : ""}');
        }
        print('Total: ${tasks.length} tasks');
      } catch (e) {
        print('Tasks sync failed: $e');
      }
    } else {
      print('\nTasks folder not found');
    }

    // 10. Sync contacts
    final contactsFolder = folders.addedFolders
        .where((f) =>
            f.type == EasFolderType.defaultContacts ||
            f.type == EasFolderType.userContacts)
        .firstOrNull;

    if (contactsFolder != null) {
      print('\n=== SYNC CONTACTS: ${contactsFolder.displayName} ===');
      try {
        final contacts =
            await client.fullSyncContacts(contactsFolder.serverId);
        for (final c in contacts.take(5)) {
          print('  ${c.displayName}'
              '${c.email1 != null ? " <${c.email1}>" : ""}'
              '${c.mobilePhone != null ? " ${c.mobilePhone}" : ""}');
        }
        print('Total: ${contacts.length} contacts');
      } catch (e) {
        print('Contacts sync failed: $e');
      }
    } else {
      print('\nContacts folder not found');
    }

    // 11. Send mail
    print('\n=== SEND MAIL ===');
    stdout.write('To (email, Enter to skip): ');
    final to = stdin.readLineSync()?.trim() ?? '';
    if (to.isNotEmpty && to.contains('@')) {
      stdout.write('Subject: ');
      final subject =
          stdin.readLineSync()?.trim() ?? 'Test from eas_client';
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
      try {
        await client.sendMail(clientId: clientId, mimeContent: mime);
        print('Sent!');
      } catch (e) {
        print('SendMail failed: $e');
      }
    } else {
      print('Skipped');
    }

    // 12. SmartReply
    if (inbox != null && emails.isNotEmpty) {
      print('\n=== SMART REPLY ===');
      stdout.write(
          'Reply to "${emails.first.subject}"? [y/N]: ');
      final doReply =
          stdin.readLineSync()?.trim().toLowerCase() == 'y';
      if (doReply) {
        stdout.write('Reply body: ');
        final replyBody = stdin.readLineSync()?.trim() ?? '';
        final mime = 'From: $email\r\n'
            'To: ${_sanitizeMimeHeader(emails.first.from)}\r\n'
            'Subject: Re: ${_sanitizeMimeHeader(emails.first.subject)}\r\n'
            'MIME-Version: 1.0\r\n'
            'Content-Type: text/plain; charset=utf-8\r\n'
            '\r\n'
            '$replyBody';
        try {
          await client.smartReply(
            clientId: DateTime.now().millisecondsSinceEpoch.toString(),
            serverId: emails.first.serverId,
            collectionId: inbox.serverId,
            mimeContent: mime,
          );
          print('Reply sent!');
        } catch (e) {
          print('SmartReply failed: $e');
        }
      } else {
        print('Skipped');
      }
    }

    // 13. MeetingResponse
    final meetingEvents = events
        .where((e) =>
            e.meetingStatus != 0 && e.serverId.isNotEmpty)
        .toList();
    if (calendarFolder != null && meetingEvents.isNotEmpty) {
      print('\n=== MEETING RESPONSE ===');
      final first = meetingEvents.first;
      stdout.write(
          'Respond to meeting "${first.subject}"? [a=accept/t=tentative/d=decline/Enter=skip]: ');
      final resp = stdin.readLineSync()?.trim().toLowerCase() ?? '';
      MeetingResponseStatus? status;
      if (resp == 'a') status = MeetingResponseStatus.accepted;
      if (resp == 't') status = MeetingResponseStatus.tentative;
      if (resp == 'd') status = MeetingResponseStatus.declined;
      if (status != null) {
        try {
          final results = await client.respondToMeeting(
            requestId: first.serverId,
            collectionId: calendarFolder.serverId,
            response: status,
          );
          final r = results.firstOrNull;
          print(r != null && r.isSuccess
              ? 'Response sent! CalendarId: ${r.calendarId}'
              : 'Failed (status ${r?.status})');
        } catch (e) {
          print('MeetingResponse failed: $e');
        }
      } else {
        print('Skipped');
      }
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
