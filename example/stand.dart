// Test stand: probes an Exchange ActiveSync server for behaviour a push
// design depends on and prints a report.
//
//   dart run example/stand.dart --server mail.example.com[:port] \
//       --user alice --password secret [--domain CORP] [--device-id Stand1]
//
// Experiments:
//   (a) does a Sync / FolderSync from the same DeviceId complete a pending
//       Ping (heartbeat 300 s, issued 5 s after the Ping)?
//   (b) with Body Type 4 (MIME, MIMESupport 2), are airsyncbase:Attachments
//       (FileReference) returned too?
//   (c) folder list with types; Junk candidates
//   (d) maximum accepted heartbeat (Ping with 3540 s; status 5 = limit)
//   (e) bytes the server sends on an idle TLS connection right after the
//       handshake (e.g. TLS 1.3 NewSessionTicket), seen at the TCP level
//
// Raw Pings run over a TLS socket relayed through a local TCP pipe, so
// the stand sees the encrypted bytes exactly as a tunneling proxy would.
// The stand talks to a real mailbox: it only reads, but it re-initializes
// the Inbox sync state of its DeviceId.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:eas_client/eas_client.dart';

Future<void> main(List<String> argv) async {
  final args = _parseArgs(argv);
  final server = args['server'];
  final user = args['user'];
  final password = args['password'];
  if (server == null || user == null || password == null) {
    stderr.writeln(
      'Usage: dart run example/stand.dart --server HOST[:PORT] --user USER '
      '--password PASS [--domain DOMAIN] [--device-id ID]',
    );
    exitCode = 64;
    return;
  }
  final domain = args['domain'];
  final deviceId = args['device-id'] ?? 'EasClientStand1';
  final client = EasClient(
    server: server,
    credentials: BasicCredentials(
      username: domain == null ? user : '$domain\\$user',
      password: password,
    ),
    deviceId: deviceId,
    deviceType: 'EasClientStand',
  );
  final report = _Report();
  try {
    await _run(client, server, report);
  } catch (e, st) {
    report.line('FATAL: $e\n$st');
  } finally {
    client.dispose();
    stdout.writeln(report);
  }
}

Map<String, String> _parseArgs(List<String> argv) {
  final out = <String, String>{};
  for (var i = 0; i < argv.length; i++) {
    final a = argv[i];
    if (!a.startsWith('--')) continue;
    final eq = a.indexOf('=');
    if (eq > 0) {
      out[a.substring(2, eq)] = a.substring(eq + 1);
    } else if (i + 1 < argv.length) {
      out[a.substring(2)] = argv[++i];
    }
  }
  return out;
}

class _Report {
  final _buf = StringBuffer('\n========== EAS stand report ==========\n');

  void section(String title) => _buf.write('\n--- $title ---\n');
  void line(String text) {
    _buf.writeln(text);
    stderr.writeln('[stand] $text'); // progress while running
  }

  @override
  String toString() => _buf.toString();
}

Future<void> _run(EasClient client, String server, _Report r) async {
  r.section('Setup');
  final info = await client.discoverCapabilities();
  final version = ['16.1', '16.0', '14.1', '14.0'].firstWhere(
    info.supportedVersions.contains,
    orElse: () => client.httpClient.protocolVersion,
  );
  client.httpClient.protocolVersion = version;
  r.line(
    'Server versions: ${info.supportedVersions.join(', ')}; using $version',
  );
  r.line('MS-Server-ActiveSync: ${client.httpClient.serverVersion}');

  final policy = await client.provision(
    policyAckStatus: PolicyAckStatus.success,
  );
  r.line(
    'Provision: policyKey=${client.httpClient.policyKey} '
    '(policy ${policy == null ? 'not required' : 'received'})',
  );

  final folders = await client.syncFolders();
  final all = folders.addedFolders;
  final inbox = all.firstWhere((f) => f.type == EasFolderType.defaultInbox);

  _folders(all, r);
  await _mimeAttachments(client, inbox, r);
  for (final interfering in ['Sync', 'FolderSync']) {
    await _pingCancellation(client, server, inbox, interfering, r);
  }
  await _maxHeartbeat(client, server, inbox, r);
  await _tlsIdleBytes(client, server, inbox, r);
}

// ─── (c) Folders ──────────────────────────────────────────────────────────

final _junkName = RegExp(
  r'junk|spam|bulk|нежелательн|спам',
  caseSensitive: false,
);

void _folders(List<EasFolder> folders, _Report r) {
  r.section('(c) Folders');
  for (final f in folders) {
    final junk =
        (f.type == EasFolderType.userMail ||
                f.type == EasFolderType.userGeneric) &&
            _junkName.hasMatch(f.displayName)
        ? '   <== Junk candidate'
        : '';
    r.line(
      '${f.serverId.padRight(6)} parent=${f.parentId.padRight(4)} '
      'type=${f.type.value.toString().padLeft(2)} ${f.type.name.padRight(20)} '
      '"${f.displayName}"$junk',
    );
  }
  final candidates = folders.where((f) => _junkName.hasMatch(f.displayName));
  r.line(
    'Junk candidates: '
    '${candidates.isEmpty ? 'none' : candidates.map((f) => '"${f.displayName}" (id ${f.serverId}, type ${f.type.value})').join(', ')}',
  );
}

// ─── (b) MIME body + Attachments ──────────────────────────────────────────

Future<void> _mimeAttachments(
  EasClient client,
  EasFolder inbox,
  _Report r,
) async {
  r.section('(b) Body Type 4 (MIME) + airsyncbase:Attachments');
  final options = [
    SyncOptions(
      bodyPreferences: const [
        EasBodyPreference(type: 4, truncationSize: 512 * 1024),
      ],
      mimeSupport: 2,
    ),
  ];
  final version = client.httpClient.protocolVersion;
  final initial = await client.execute(
    SyncCommand(syncKey: '0', collectionId: inbox.serverId),
  );
  final result = await client.execute(
    SyncCommand(
      syncKey: initial.syncKey,
      collectionId: inbox.serverId,
      windowSize: 25,
      options: options,
      protocolVersion: version,
    ),
  );
  await client.syncStateStore.setSyncKey(inbox.serverId, result.syncKey);

  final emails = result.addedEmails;
  var withMime = 0, withAttachments = 0, mimeOnlyAttachments = 0;
  for (final e in emails) {
    final mime = e.mime;
    final mimeHasAttachment =
        mime != null &&
        RegExp(
          r'Content-Disposition:\s*attachment',
          caseSensitive: false,
        ).hasMatch(String.fromCharCodes(mime));
    if (mime != null) withMime++;
    if (e.attachments.isNotEmpty) withAttachments++;
    if (mimeHasAttachment && e.attachments.isEmpty) mimeOnlyAttachments++;
    if (e.attachments.isNotEmpty || mimeHasAttachment) {
      r.line(
        '  "${e.subject}": body type ${e.bodyDetails?.type}, '
        'MIME ${mime?.length ?? 0} B (truncated ${e.bodyTruncated}), '
        'Attachments ${e.attachments.length}'
        '${e.attachments.isEmpty ? '' : ' first FileReference=${e.attachments.first.fileReference}'}'
        ', MIME has attachment part: $mimeHasAttachment',
      );
    }
  }
  r.line(
    'Messages: ${emails.length}; with MIME body: $withMime; '
    'with Attachments list: $withAttachments; '
    'attachment only inside MIME (no Attachments element): $mimeOnlyAttachments',
  );
  if (withAttachments + mimeOnlyAttachments == 0) {
    r.line(
      'INCONCLUSIVE: no message with attachments among the newest '
      '${emails.length}; send one to the Inbox and rerun.',
    );
  } else {
    r.line(
      'ANSWER (b): Attachments with Type 4 '
      '${withAttachments > 0 ? 'ARE returned' : 'are NOT returned'}.',
    );
  }
}

// ─── (a) Ping cancellation ────────────────────────────────────────────────

Future<void> _pingCancellation(
  EasClient client,
  String server,
  EasFolder inbox,
  String interfering,
  _Report r,
) async {
  r.section('(a) Pending Ping vs $interfering from the same DeviceId');
  final ping = PingCommand(
    folders: [PingFolder(id: inbox.serverId)],
    heartbeatInterval: 300,
  );
  final tunnel = await _Tunnel.open(server);
  try {
    tunnel.send(client.buildRawRequest(ping));
    final pingSent = tunnel.clock.elapsed;
    final early = await tunnel.readResponse(const Duration(seconds: 5));
    if (early != null) {
      r.line(
        'Ping answered before the interfering command: '
        '${_describePing(client, ping, early)}',
      );
      return;
    }

    final started = tunnel.clock.elapsed;
    if (interfering == 'Sync') {
      final s = await client.syncFolder(inbox.serverId, windowSize: 1);
      r.line('Sync done: status ${s.status}');
    } else {
      final f = await client.syncFolders();
      r.line('FolderSync done: status ${f.status}');
    }
    final commandDone = tunnel.clock.elapsed;

    final response = await tunnel.readResponse(const Duration(seconds: 60));
    final at = tunnel.clock.elapsed;
    if (response == null) {
      r.line(
        'ANSWER (a/$interfering): Ping NOT completed '
        '(still pending ${_s(at - started)} after the $interfering).',
      );
    } else {
      r.line(
        'ANSWER (a/$interfering): Ping completed ${_s(at - pingSent)} after '
        'it was sent, ${_s(at - started)} after the $interfering started '
        '(${_s(at - commandDone)} after it finished): '
        '${_describePing(client, ping, response)}',
      );
    }
  } finally {
    await tunnel.close();
  }
}

String _describePing(EasClient client, PingCommand ping, Uint8List raw) {
  try {
    final result = client.parseRawHttpResponse(ping, raw);
    return 'status ${result.status.value} (${result.status.name})'
        '${result.changedFolderIds.isEmpty ? '' : ', folders ${result.changedFolderIds}'}'
        '${result.suggestedHeartbeat == null ? '' : ', heartbeat ${result.suggestedHeartbeat}'}';
  } catch (e) {
    return 'error $e';
  }
}

// ─── (d) Maximum heartbeat ────────────────────────────────────────────────

Future<void> _maxHeartbeat(
  EasClient client,
  String server,
  EasFolder inbox,
  _Report r,
) async {
  r.section('(d) Maximum heartbeat');
  final ping = PingCommand(
    folders: [PingFolder(id: inbox.serverId)],
    heartbeatInterval: PingCommand.maxHeartbeat,
  );
  final tunnel = await _Tunnel.open(server);
  try {
    tunnel.send(client.buildRawRequest(ping));
    final response = await tunnel.readResponse(const Duration(seconds: 15));
    if (response == null) {
      r.line(
        'ANSWER (d): heartbeat ${PingCommand.maxHeartbeat} s accepted '
        '(Ping held for 15 s without an answer).',
      );
      return;
    }
    final result = client.parseRawHttpResponse(ping, response);
    if (result.status == PingStatus.invalidHeartbeat) {
      r.line(
        'ANSWER (d): ${PingCommand.maxHeartbeat} s rejected (status 5); '
        'server maximum = ${result.suggestedHeartbeat} s.',
      );
    } else {
      r.line(
        'Ping answered within 15 s with status ${result.status.value} '
        '(${result.status.name}) — rerun (d) when the mailbox is idle.',
      );
    }
  } catch (e) {
    r.line('(d) failed: $e');
  } finally {
    await tunnel.close();
  }
}

// ─── (e) TLS bytes on an idle connection ──────────────────────────────────

Future<void> _tlsIdleBytes(
  EasClient client,
  String server,
  EasFolder inbox,
  _Report r,
) async {
  r.section('(e) Server bytes after the TLS handshake');
  const window = Duration(seconds: 3);
  final tunnel = await _Tunnel.open(server);
  try {
    final handshake = tunnel.handshakeDone;
    r.line(
      'TLS handshake done at ${_s(handshake)} '
      '(${tunnel.upstreamChunks.length} server chunks during handshake)',
    );

    // 1) Idle: nothing sent after the handshake.
    final idleFrom = tunnel.upstreamChunks.length;
    await Future<void>.delayed(window);
    _chunks(
      r,
      'Idle ${window.inSeconds} s after handshake',
      tunnel.upstreamChunks.sublist(idleFrom),
      handshake,
    );

    // 2) Right after sending a Ping (as a tunnel handoff does).
    final ping = PingCommand(
      folders: [PingFolder(id: inbox.serverId)],
      heartbeatInterval: 300,
    );
    final sentFrom = tunnel.upstreamChunks.length;
    tunnel.send(client.buildRawRequest(ping));
    final sentAt = tunnel.clock.elapsed;
    final response = await tunnel.readResponse(window);
    _chunks(
      r,
      'First ${window.inSeconds} s after sending a Ping',
      tunnel.upstreamChunks.sublist(sentFrom),
      sentAt,
    );
    r.line(
      response == null
          ? 'No HTTP response within ${window.inSeconds} s (Ping pending).'
          : 'HTTP response within ${window.inSeconds} s: '
                '${_describePing(client, ping, response)}',
    );
    r.line(
      'ANSWER (e): a tunnel must ignore server bytes that arrive without an '
      'HTTP response (see chunks above) — typically the TLS 1.3 '
      'NewSessionTicket records right after the handshake/first request.',
    );
  } finally {
    await tunnel.close();
  }
}

void _chunks(
  _Report r,
  String title,
  List<(Duration, Uint8List)> chunks,
  Duration from,
) {
  if (chunks.isEmpty) {
    r.line('$title: no bytes from the server.');
    return;
  }
  r.line('$title: ${chunks.length} chunk(s):');
  for (final (at, bytes) in chunks) {
    r.line(
      '  +${_s(at - from)}: ${bytes.length} B, TLS records '
      '${_tlsRecords(bytes)}',
    );
  }
}

/// TLS record headers (content type / length) found in [bytes]; a chunk
/// boundary may split a record, so this is best-effort.
String _tlsRecords(Uint8List bytes) {
  final out = <String>[];
  var i = 0;
  while (i + 5 <= bytes.length) {
    final type = bytes[i];
    final length = (bytes[i + 3] << 8) | bytes[i + 4];
    final name = switch (type) {
      20 => 'ChangeCipherSpec',
      21 => 'Alert',
      22 => 'Handshake',
      23 => 'ApplicationData',
      _ => '?$type',
    };
    out.add('$name($length)');
    i += 5 + length;
  }
  return out.isEmpty ? '[partial]' : out.join(' ');
}

String _s(Duration d) => '${(d.inMilliseconds / 1000).toStringAsFixed(2)}s';

// ─── TLS over a local relay ───────────────────────────────────────────────

/// A TLS connection to the EAS server whose encrypted traffic passes
/// through a local TCP relay, recording when the server sends bytes.
class _Tunnel {
  final Stopwatch clock;
  final Socket _upstream;
  final ServerSocket _relay;
  final Socket _relayPeer;
  final SecureSocket _tls;

  /// Encrypted chunks from the server with their arrival time.
  final List<(Duration, Uint8List)> upstreamChunks;

  /// When the TLS handshake completed.
  final Duration handshakeDone;

  final _plain = BytesBuilder();
  var _closed = false;
  var _signal = Completer<void>();

  _Tunnel._(
    this.clock,
    this._upstream,
    this._relay,
    this._relayPeer,
    this._tls,
    this.upstreamChunks,
    this.handshakeDone,
  ) {
    _tls.listen(
      (data) {
        _plain.add(data);
        _notify();
      },
      onDone: () {
        _closed = true;
        _notify();
      },
      onError: (Object _) {
        _closed = true;
        _notify();
      },
    );
  }

  static Future<_Tunnel> open(String server) async {
    final uri = Uri.parse('https://$server');
    final clock = Stopwatch()..start();
    final chunks = <(Duration, Uint8List)>[];
    final upstream = await Socket.connect(
      uri.host,
      uri.port,
      timeout: const Duration(seconds: 15),
    );
    final relay = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final peerFuture = relay.first;
    final local = await Socket.connect(relay.address, relay.port);
    final peer = await peerFuture;
    upstream.listen(
      (data) {
        chunks.add((clock.elapsed, data));
        peer.add(data);
      },
      onDone: () => peer.destroy(),
      onError: (Object _) => peer.destroy(),
    );
    peer.listen(
      upstream.add,
      onDone: () => upstream.destroy(),
      onError: (Object _) => upstream.destroy(),
    );
    final tls = await SecureSocket.secure(local, host: uri.host);
    return _Tunnel._(clock, upstream, relay, peer, tls, chunks, clock.elapsed);
  }

  void _notify() {
    if (!_signal.isCompleted) _signal.complete();
  }

  void send(Uint8List bytes) => _tls.add(bytes);

  /// Bytes of the first complete HTTP response, or `null` if none arrived
  /// within [timeout].
  Future<Uint8List?> readResponse(Duration timeout) async {
    final deadline = clock.elapsed + timeout;
    while (true) {
      final bytes = _plain.toBytes();
      RawHttpParseResult? parsed;
      try {
        parsed = EasRawHttpParser.tryParse(bytes, endOfStream: _closed);
      } on FormatException {
        return null; // connection closed mid-response
      }
      if (parsed != null) return bytes.sublist(0, parsed.length);
      if (_closed) return null;
      final left = deadline - clock.elapsed;
      if (left <= Duration.zero) return null;
      _signal = Completer<void>();
      await _signal.future.timeout(left, onTimeout: () {});
    }
  }

  Future<void> close() async {
    _tls.destroy();
    _relayPeer.destroy();
    _upstream.destroy();
    await _relay.close();
  }
}
