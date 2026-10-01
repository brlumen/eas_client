import 'dart:convert';
import 'dart:typed_data';

import 'package:eas_client/eas_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _pages = {
  'AirSync': 0,
  'Email': 2,
  'FolderHierarchy': 7,
  'Ping': 13,
  'Provision': 14,
  'AirSyncBase': 17,
  'ComposeMail': 21,
  'Email2': 22,
};

WbxmlElement _el(String ns, String tag, [Object? content]) {
  final page = _pages[ns]!;
  return switch (content) {
    String text => WbxmlElement.withText(
      namespace: ns,
      tag: tag,
      text: text,
      codePageIndex: page,
    ),
    List<WbxmlElement> children => WbxmlElement(
      namespace: ns,
      tag: tag,
      codePageIndex: page,
      children: children,
    ),
    _ => WbxmlElement(namespace: ns, tag: tag, codePageIndex: page),
  };
}

WbxmlElement _as(String tag, [Object? content]) => _el('AirSync', tag, content);

Uint8List _encode(WbxmlElement root) =>
    WbxmlEncoder().encode(WbxmlDocument(root: root));

WbxmlDocument _decode(Uint8List bytes) => WbxmlDecoder().decode(bytes);

Uint8List _syncResponse(
  String key, {
  String collectionId = '5',
  String status = '1',
  List<WbxmlElement> commands = const [],
}) => _encode(
  _as('Sync', [
    _as('Collections', [
      _as('Collection', [
        _as('SyncKey', key),
        _as('CollectionId', collectionId),
        _as('Status', status),
        if (commands.isNotEmpty) _as('Commands', commands),
      ]),
    ]),
  ]),
);

String? _requestSyncKey(http.Request r) => _decode(r.bodyBytes).root
    .findChild('AirSync', 'Collections')
    ?.findChild('AirSync', 'Collection')
    ?.childText('AirSync', 'SyncKey');

EasClient _client(
  Future<http.Response> Function(http.Request) handler, {
  EasSyncStateStore? store,
  String server = 'mail.example.com',
  bool base64Query = false,
}) => EasClient(
  server: server,
  credentials: const BasicCredentials(username: 'user', password: 'secret'),
  deviceId: 'dev1',
  useBase64QueryString: base64Query,
  httpClient: MockClient(handler),
  syncStateStore: store,
);

Uint8List _pingResponse(String status, {List<String> folders = const []}) =>
    _encode(
      _el('Ping', 'Ping', [
        _el('Ping', 'Status', status),
        if (folders.isNotEmpty)
          _el('Ping', 'Folders', [
            for (final f in folders) _el('Ping', 'Folder', f),
          ]),
      ]),
    );

Uint8List _rawResponse(
  int status,
  Uint8List body, {
  Map<String, String> headers = const {},
  bool chunked = false,
}) {
  final head = StringBuffer('HTTP/1.1 $status X\r\n');
  headers.forEach((k, v) => head.write('$k: $v\r\n'));
  if (chunked) {
    head.write('Transfer-Encoding: chunked\r\n\r\n');
    final b = BytesBuilder()..add(ascii.encode(head.toString()));
    // Two chunks + terminator.
    final mid = body.length ~/ 2;
    for (final part in [body.sublist(0, mid), body.sublist(mid)]) {
      if (part.isEmpty) continue;
      b
        ..add(ascii.encode('${part.length.toRadixString(16)};ext=1\r\n'))
        ..add(part)
        ..add(ascii.encode('\r\n'));
    }
    b.add(ascii.encode('0\r\nX-Trailer: 1\r\n\r\n'));
    return b.toBytes();
  }
  head.write('Content-Length: ${body.length}\r\n\r\n');
  return (BytesBuilder()
        ..add(ascii.encode(head.toString()))
        ..add(body))
      .toBytes();
}

/// Split a raw request into (head lines, body).
(List<String>, Uint8List) _splitRaw(Uint8List raw) {
  final text = latin1.decode(raw);
  final end = text.indexOf('\r\n\r\n');
  return (text.substring(0, end).split('\r\n'), raw.sublist(end + 4));
}

class _RecordingStore extends InMemoryEasSyncStateStore {
  final log = <String>[];

  @override
  void setSyncKey(String collectionId, String syncKey) {
    log.add('set $collectionId=$syncKey');
    super.setSyncKey(collectionId, syncKey);
  }

  @override
  void removeSyncKey(String collectionId) {
    log.add('remove $collectionId');
    super.removeSyncKey(collectionId);
  }
}

/// Async store, to check that `FutureOr` results are awaited.
class _AsyncStore implements EasSyncStateStore {
  final inner = InMemoryEasSyncStateStore();

  @override
  Future<String?> getFolderSyncKey() async => inner.getFolderSyncKey();
  @override
  Future<void> setFolderSyncKey(String k) async => inner.setFolderSyncKey(k);
  @override
  Future<String?> getSyncKey(String id) async => inner.getSyncKey(id);
  @override
  Future<void> setSyncKey(String id, String k) async => inner.setSyncKey(id, k);
  @override
  Future<void> removeSyncKey(String id) async => inner.removeSyncKey(id);
  @override
  Future<void> clear() async => inner.clear();
}

void main() {
  group('EasSyncStateStore', () {
    test('InMemoryEasSyncStateStore get/set/remove/clear', () {
      final s = InMemoryEasSyncStateStore();
      expect(s.getFolderSyncKey(), isNull);
      expect(s.getSyncKey('5'), isNull);
      s
        ..setFolderSyncKey('f1')
        ..setSyncKey('5', 'k1')
        ..setSyncKey('6', 'k2')
        ..removeSyncKey('6');
      expect(s.getFolderSyncKey(), 'f1');
      expect(s.getSyncKey('5'), 'k1');
      expect(s.getSyncKey('6'), isNull);
      s.clear();
      expect(s.getFolderSyncKey(), isNull);
      expect(s.getSyncKey('5'), isNull);
    });

    test(
      'syncFolder resumes from a persisted key and stores the new one',
      () async {
        final store = _AsyncStore();
        await store.setSyncKey('5', 'persisted');
        final sent = <String?>[];
        final client = _client((r) async {
          sent.add(_requestSyncKey(r));
          return http.Response.bytes(_syncResponse('next'), 200);
        }, store: store);

        await client.syncFolder('5');
        expect(sent, ['persisted']);
        expect(await store.getSyncKey('5'), 'next');
      },
    );

    test('Status 3 removes the key and re-syncs from 0', () async {
      final store = _RecordingStore()..setSyncKey('5', 'bad');
      store.log.clear();
      final sent = <String?>[];
      final client = _client((r) async {
        sent.add(_requestSyncKey(r));
        return http.Response.bytes(
          sent.length == 1
              ? _syncResponse('bad', status: '3')
              : _syncResponse('fresh'),
          200,
        );
      }, store: store);

      await client.syncFolder('5');
      expect(sent, ['bad', '0']);
      expect(store.log, ['remove 5', 'set 5=fresh']);
    });

    test(
      'syncFolders persists the FolderSync key; reset APIs clear the store',
      () async {
        final store = InMemoryEasSyncStateStore()..setSyncKey('5', 'k');
        final client = _client(
          (r) async => http.Response.bytes(
            _encode(
              _el('FolderHierarchy', 'FolderSync', [
                _el('FolderHierarchy', 'Status', '1'),
                _el('FolderHierarchy', 'SyncKey', 'f1'),
              ]),
            ),
            200,
          ),
          store: store,
        );

        await client.syncFolders();
        expect(store.getFolderSyncKey(), 'f1');

        await client.resetSyncState('5');
        expect(store.getSyncKey('5'), isNull);
        expect(store.getFolderSyncKey(), 'f1');

        await client.resetAllSyncStates();
        expect(store.getFolderSyncKey(), isNull);
      },
    );

    test('syncWithCommands requires a stored key', () async {
      final client = _client((r) async => http.Response('', 500));
      await expectLater(
        client.markEmailRead('5', '5:1', true),
        throwsA(isA<EasCommandException>()),
      );
    });

    test(
      'syncMultipleFolders stores keys of requested collections only',
      () async {
        final store = InMemoryEasSyncStateStore()..setSyncKey('5', 'a');
        final client = _client(
          (r) async => http.Response.bytes(
            _encode(
              _as('Sync', [
                _as('Collections', [
                  _as('Collection', [
                    _as('SyncKey', 'b'),
                    _as('CollectionId', '5'),
                    _as('Status', '1'),
                  ]),
                  _as('Collection', [
                    _as('SyncKey', 'x'),
                    _as('CollectionId', '9'),
                    _as('Status', '1'),
                  ]),
                ]),
              ]),
            ),
            200,
          ),
          store: store,
        );

        await client.syncMultipleFolders([
          const SyncCollection(collectionId: '5'),
        ]);
        expect(store.getSyncKey('5'), 'b');
        expect(store.getSyncKey('9'), isNull);
      },
    );
  });

  group('EasEmailChange (partial Sync Change)', () {
    Future<SyncResult> syncWith(List<WbxmlElement> commands) {
      final store = InMemoryEasSyncStateStore()..setSyncKey('5', 'k');
      return _client(
        (r) async =>
            http.Response.bytes(_syncResponse('k2', commands: commands), 200),
        store: store,
      ).syncFolder('5');
    }

    test('flag-only change leaves other fields null', () async {
      final r = await syncWith([
        _as('Change', [
          _as('ServerId', '5:1'),
          _as('ApplicationData', [
            _el('Email', 'Flag', [_el('Email', 'Status', '2')]),
          ]),
        ]),
      ]);

      final c = r.emailChanges.single;
      expect(c.serverId, '5:1');
      expect(c.flagStatus, 2);
      expect(c.read, isNull);
      expect(c.subject, isNull);
      expect(c.categories, isNull);
      expect(c.importance, isNull);
      expect(c.lastVerbExecuted, isNull);
      expect(r.smsChanges, isEmpty);
    });

    test('read, cleared flag, empty categories, verb and importance', () async {
      final r = await syncWith([
        _as('Change', [
          _as('ServerId', '5:2'),
          _as('ApplicationData', [
            _el('Email', 'Read', '1'),
            _el('Email', 'Flag'),
            _el('Email', 'Categories'),
            _el('Email', 'Importance', '2'),
            _el('Email2', 'LastVerbExecuted', '3'),
            _el('Email2', 'LastVerbExecutionTime', '2026-09-30T10:00:00.000Z'),
          ]),
        ]),
      ]);

      final c = r.emailChanges.single;
      expect(c.read, isTrue);
      expect(c.flag, isNotNull);
      expect(c.flagStatus, 0);
      expect(c.categories, isEmpty);
      expect(c.importance, EmailImportance.high);
      expect(c.lastVerbExecuted, 3);
      expect(c.lastVerbExecutionTime, DateTime.utc(2026, 9, 30, 10));
      expect(c.applicationData.findChild('Email', 'Read'), isNotNull);
    });

    test('SMS changes are reported separately', () async {
      final r = await syncWith([
        _as('Change', [
          _as('ServerId', '5:3'),
          _as('Class', 'SMS'),
          _as('ApplicationData', [_el('Email', 'Read', '0')]),
        ]),
      ]);
      expect(r.emailChanges, isEmpty);
      expect(r.smsChanges.single.read, isFalse);
      expect(r.smsChanges.single.isSms, isTrue);
    });

    test('deprecated changedEmails is still populated', () async {
      final r = await syncWith([
        _as('Change', [
          _as('ServerId', '5:4'),
          _as('ApplicationData', [_el('Email', 'Read', '1')]),
        ]),
      ]);
      // ignore: deprecated_member_use_from_same_package
      expect(r.changedEmails.single.serverId, '5:4');
    });
  });

  group('MIME as bytes', () {
    // windows-1251 "Привет" — not valid UTF-8.
    final cp1251 = Uint8List.fromList([0xcf, 0xf0, 0xe8, 0xe2, 0xe5, 0xf2]);
    final mime = Uint8List.fromList([
      ...ascii.encode(
        'Subject: x\r\nContent-Type: text/plain; charset=windows-1251\r\n\r\n',
      ),
      ...cp1251,
    ]);

    /// WBXML with `airsyncbase:Body` Type 4 whose Data is an inline
    /// string of [data] bytes (STR_I).
    Uint8List bodyDoc(Uint8List data) {
      final b = BytesBuilder()
        ..add([0x03, 0x01, 0x6a, 0x00]) // header, empty string table
        ..add([0x00, 17]) // SWITCH_PAGE AirSyncBase
        ..add([0x4a]) // Body (0x0A) with content
        ..add([0x46, 0x03]) // Type (0x06) + STR_I
        ..add(ascii.encode('4'))
        ..add([0x00, 0x01]) // NUL, END Type
        ..add([0x4b, 0x03]) // Data (0x0B) + STR_I
        ..add(data)
        ..add([0x00, 0x01]) // NUL, END Data
        ..add([0x01]); // END Body
      return b.toBytes();
    }

    test('decoder keeps non-UTF-8 string bytes in rawText', () {
      final root = _decode(bodyDoc(mime)).root;
      final data = root.findChild('AirSyncBase', 'Data')!;
      expect(data.rawText, mime);
      expect(data.text, isNotNull);
    });

    test('valid UTF-8 strings have no rawText', () {
      final utf = Uint8List.fromList(utf8.encode('Subject: Привет\r\n\r\nx'));
      final data = _decode(bodyDoc(utf)).root.findChild('AirSyncBase', 'Data')!;
      expect(data.rawText, isNull);
      expect(data.text, 'Subject: Привет\r\n\r\nx');
    });

    test(
      'Body type 4 exposes lossless bytes via EasBody and EasEmail.mime',
      () {
        final bodyEl = _decode(bodyDoc(mime)).root;
        final body = EasBody.fromElement(bodyEl);
        expect(body.type, 4);
        expect(body.dataBytes, mime);

        final email = EasEmail.fromApplicationData(
          '1',
          _as('ApplicationData', [bodyEl]),
        );
        expect(email.mime, mime);
        expect(email.mimeData, isNull);
      },
    );

    test('non-MIME bodies have no dataBytes', () {
      final body = EasBody.fromElement(
        _el('AirSyncBase', 'Body', [
          _el('AirSyncBase', 'Type', '2'),
          _el('AirSyncBase', 'Data', '<p>x</p>'),
        ]),
      );
      expect(body.dataBytes, isNull);
    });

    test('SendMail sends MIME bytes unchanged (WBXML and raw)', () {
      final cmd = SendMailCommand(clientId: 'c1', mimeContent: mime);
      final wbxml = _decode(cmd.encodeRequest('16.1')!).root;
      expect(wbxml.findChild('ComposeMail', 'Mime')!.opaque, mime);
      expect(cmd.encodeRequest('12.1'), mime);
    });

    test('header injection check on bytes', () {
      expect(
        () => SendMailCommand.validateMimeHeaderBytes(
          Uint8List.fromList(ascii.encode('Subject: a\nBcc: x\r\n\r\nb')),
        ),
        throwsArgumentError,
      );
      expect(
        () => SendMailCommand.validateMimeHeaderBytes(
          Uint8List.fromList(
            ascii.encode('Subject: a\r\n\r\nbody\nwith\rbare'),
          ),
        ),
        returnsNormally,
      );
    });
  });

  group('Raw HTTP', () {
    test('empty Ping: request line, headers, Content-Length 0, no body', () {
      final client = _client((r) async => http.Response('', 200))
        ..httpClient.policyKey = '123';
      final raw = client.buildRawRequest(PingCommand.empty());
      final (lines, body) = _splitRaw(raw);

      expect(
        lines.first,
        'POST /Microsoft-Server-ActiveSync?Cmd=Ping&User=user&DeviceId=dev1'
        '&DeviceType=FlutterEAS HTTP/1.1',
      );
      expect(lines[1], 'Host: mail.example.com');
      expect(lines, contains('MS-ASProtocolVersion: 16.1'));
      expect(lines, contains('X-MS-PolicyKey: 123'));
      expect(lines, contains('User-Agent: FlutterEAS/1.0'));
      expect(lines, contains('Content-Type: application/vnd.ms-sync.wbxml'));
      expect(lines, contains('Content-Length: 0'));
      expect(lines, contains('Connection: keep-alive'));
      expect(
        lines,
        contains(
          'Authorization: Basic ${base64.encode(utf8.encode('user:secret'))}',
        ),
      );
      expect(lines.any((l) => l.toLowerCase().startsWith('expect')), isFalse);
      expect(body, isEmpty);
    });

    test('Ping with body matches the WBXML sent by execute', () async {
      http.Request? sent;
      final client = _client((r) async {
        sent = r;
        return http.Response.bytes(_pingResponse('1'), 200);
      });
      final cmd = PingCommand(
        folders: const [PingFolder(id: '5')],
        heartbeatInterval: 300,
      );
      await client.execute(cmd);
      final (lines, body) = _splitRaw(client.buildRawRequest(cmd));
      expect(body, sent!.bodyBytes);
      expect(lines, contains('Content-Length: ${body.length}'));
      expect(
        lines.first,
        startsWith('POST ${sent!.url.path}?${sent!.url.query} '),
      );
    });

    test(
      'cookies from the jar are sent; raw Set-Cookie updates the jar',
      () async {
        final client = _client(
          (r) async => http.Response.bytes(
            _pingResponse('1'),
            200,
            headers: {'set-cookie': 'a=1; Path=/'},
          ),
        );
        await client.execute(PingCommand.empty());
        final (lines, _) = _splitRaw(
          client.buildRawRequest(PingCommand.empty()),
        );
        expect(lines, contains('Cookie: a=1'));

        client.parseRawHttpResponse(
          PingCommand.empty(),
          _rawResponse(200, _pingResponse('1'), headers: {'Set-Cookie': 'b=2'}),
        );
        expect(client.httpClient.cookieNames, containsAll(['a', 'b']));
      },
    );

    test('parses Content-Length and chunked Ping responses', () {
      final client = _client((r) async => http.Response('', 200));
      for (final chunked in [false, true]) {
        final result = client.parseRawHttpResponse(
          PingCommand.empty(),
          _rawResponse(
            200,
            _pingResponse('2', folders: ['5']),
            chunked: chunked,
          ),
        );
        expect(result.status, PingStatus.changesAvailable);
        expect(result.changedFolderIds, ['5']);
      }
    });

    test('HTTP 449 raw response → EasProvisioningRequiredException', () {
      final client = _client((r) async => http.Response('', 200));
      expect(
        () => client.parseRawHttpResponse(
          PingCommand.empty(),
          _rawResponse(449, Uint8List(0)),
        ),
        throwsA(
          isA<EasProvisioningRequiredException>()
              .having((e) => e.statusCode, 'status', 449)
              .having((e) => e.requiresProvisioning, 'reprov', isTrue),
        ),
      );
    });

    test('incomplete response throws FormatException', () {
      final client = _client((r) async => http.Response('', 200));
      final full = _rawResponse(200, _pingResponse('1'));
      expect(
        () => client.parseRawHttpResponse(
          PingCommand.empty(),
          full.sublist(0, full.length - 1),
        ),
        throwsFormatException,
      );
    });

    group('EasRawHttpParser.tryParse', () {
      final body = Uint8List.fromList(List.generate(40, (i) => i));

      test('null until complete, then reports consumed length', () {
        for (final chunked in [false, true]) {
          final full = _rawResponse(200, body, chunked: chunked);
          final extra = Uint8List.fromList([...full, 1, 2, 3]);
          for (var i = 0; i < full.length; i++) {
            expect(
              EasRawHttpParser.tryParse(full.sublist(0, i)),
              isNull,
              reason: 'prefix $i (chunked: $chunked)',
            );
          }
          final r = EasRawHttpParser.tryParse(extra)!;
          expect(r.length, full.length);
          expect(r.response.body, body);
          expect(r.response.statusCode, 200);
        }
      });

      test('skips 100 Continue and lower-cases/joins headers', () {
        final bytes = Uint8List.fromList([
          ...ascii.encode('HTTP/1.1 100 Continue\r\n\r\n'),
          ...ascii.encode(
            'HTTP/1.1 200 OK\r\nX-A: 1\r\nx-a: 2\r\nContent-Length: 0\r\n\r\n',
          ),
        ]);
        final r = EasRawHttpParser.tryParse(bytes)!;
        expect(r.response.statusCode, 200);
        expect(r.response.headers['x-a'], '1, 2');
        expect(r.response.body, isEmpty);
      });

      test('body without length is read to end of stream', () {
        final bytes = Uint8List.fromList([
          ...ascii.encode('HTTP/1.1 200 OK\r\n\r\n'),
          1,
          2,
        ]);
        expect(EasRawHttpParser.tryParse(bytes), isNull);
        expect(EasRawHttpParser.parse(bytes).body, [1, 2]);
      });

      test('malformed input and size limits', () {
        expect(
          () => EasRawHttpParser.tryParse(
            Uint8List.fromList(ascii.encode('garbage\r\n\r\n')),
          ),
          throwsFormatException,
        );
        expect(
          () => EasRawHttpParser.tryParse(
            _rawResponse(200, body),
            maxBodySize: 10,
          ),
          throwsA(isA<EasResponseTooLargeException>()),
        );
      });
    });

    test('header injection in credentials is rejected', () {
      final client = _client((r) async => http.Response('', 200))
        ..updateCredentials(OAuthCredentials(accessToken: 'a\r\nX-Evil: 1'));
      expect(
        () => client.buildRawRequest(PingCommand.empty()),
        throwsArgumentError,
      );
    });
  });

  group('Server host:port', () {
    for (final base64Query in [false, true]) {
      test('port is kept (base64 query: $base64Query)', () async {
        Uri? uri;
        final client = _client(
          (r) async {
            uri = r.url;
            return http.Response.bytes(_pingResponse('1'), 200);
          },
          server: 'mail.example.com:8443',
          base64Query: base64Query,
        );
        await client.execute(PingCommand.empty());
        expect(uri!.host, 'mail.example.com');
        expect(uri!.port, 8443);
        expect(uri!.path, '/Microsoft-Server-ActiveSync');
        if (base64Query) expect(uri!.query, isNot(contains('Cmd=')));

        final (lines, _) = _splitRaw(
          client.buildRawRequest(PingCommand.empty()),
        );
        expect(lines, contains('Host: mail.example.com:8443'));
      });
    }
  });

  test('updateCredentials changes Authorization of later requests', () async {
    final auth = <String?>[];
    final client = _client((r) async {
      auth.add(r.headers['Authorization']);
      return http.Response.bytes(_pingResponse('1'), 200);
    });
    await client.execute(PingCommand.empty());
    client.updateCredentials(
      const BasicCredentials(username: 'user', password: 'new'),
    );
    await client.execute(PingCommand.empty());
    expect(auth, [
      'Basic ${base64.encode(utf8.encode('user:secret'))}',
      'Basic ${base64.encode(utf8.encode('user:new'))}',
    ]);
  });

  group('Provisioning', () {
    for (final code in ['142', '143', '144']) {
      test('global status $code → EasProvisioningRequiredException', () async {
        final client = _client(
          (r) async => http.Response.bytes(_pingResponse(code), 200),
        );
        await expectLater(
          client.execute(PingCommand.empty()),
          throwsA(
            isA<EasProvisioningRequiredException>()
                .having((e) => e.easStatus, 'status', int.parse(code))
                .having((e) => e, 'compat', isA<EasCommandException>()),
          ),
        );
      });
    }

    test('HTTP 449 → EasProvisioningRequiredException', () async {
      final client = _client((r) async => http.Response('', 449));
      await expectLater(
        client.execute(PingCommand.empty()),
        throwsA(isA<EasProvisioningRequiredException>()),
      );
    });

    test(
      'reprovision acknowledges with success and stores the policy key',
      () async {
        WbxmlElement provision(String key) => _el('Provision', 'Provision', [
          _el('Provision', 'Status', '1'),
          _el('Provision', 'Policies', [
            _el('Provision', 'Policy', [
              _el('Provision', 'PolicyType', 'MS-EAS-Provisioning-WBXML'),
              _el('Provision', 'Status', '1'),
              _el('Provision', 'PolicyKey', key),
            ]),
          ]),
        ]);
        final requests = <WbxmlElement>[];
        final client = _client((r) async {
          requests.add(_decode(r.bodyBytes).root);
          return http.Response.bytes(
            _encode(provision(requests.length == 1 ? '111' : '222')),
            200,
          );
        });

        final policy = await client.reprovision();
        expect(policy?.policyKey, '222');
        expect(client.httpClient.policyKey, '222');
        final ack = requests.last
            .findChild('Provision', 'Policies')!
            .findChild('Provision', 'Policy')!;
        expect(ack.childText('Provision', 'Status'), '1');
        expect(ack.childText('Provision', 'PolicyKey'), '111');
      },
    );
  });
}
