import 'dart:typed_data';

import 'package:eas_client/eas_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _pages = {
  'AirSync': 0,
  'Email': 2,
  'Calendar': 4,
  'FolderHierarchy': 7,
  'AirSyncBase': 17,
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

WbxmlDocument _roundTrip(WbxmlDocument doc) =>
    WbxmlDecoder().decode(WbxmlEncoder().encode(doc));

EasClient _client(Future<http.Response> Function(http.Request) handler) =>
    EasClient(
      server: 'mail.example.com',
      credentials: BasicCredentials(username: 'user', password: 'secret'),
      deviceId: 'dev1',
      httpClient: MockClient(handler),
    );

WbxmlElement _collectionResponse(
  String id,
  String key, {
  String status = '1',
  List<WbxmlElement> extra = const [],
}) => _as('Collection', [
  _as('SyncKey', key),
  _as('CollectionId', id),
  _as('Status', status),
  ...extra,
]);

Uint8List _syncResponse(List<WbxmlElement> collections) =>
    _encode(_as('Sync', [_as('Collections', collections)]));

void main() {
  group('MultiSyncCommand request', () {
    test('builds one Collection per folder with its own SyncKey', () {
      final cmd = MultiSyncCommand(
        collections: const [
          SyncCollection(syncKey: 'k1', collectionId: '5'),
          SyncCollection(
            syncKey: '0',
            collectionId: '6',
            contentType: SyncContentType.calendar,
          ),
        ],
      );
      final root = _roundTrip(cmd.buildRequest()).root;
      final cols = root
          .findChild('AirSync', 'Collections')!
          .findChildren('AirSync', 'Collection');
      expect(cols, hasLength(2));
      expect(cols[0].childText('AirSync', 'SyncKey'), 'k1');
      expect(cols[0].childText('AirSync', 'GetChanges'), '1');
      expect(cols[1].childText('AirSync', 'SyncKey'), '0');
      expect(cols[1].childText('AirSync', 'CollectionId'), '6');
      expect(cols[1].findChild('AirSync', 'Options'), isNull);
      expect(root.findChild('AirSync', 'Partial'), isNull);
    });

    test('partial request adds <Partial/> and may omit Collections', () {
      final root = _roundTrip(
        MultiSyncCommand(collections: const [], partial: true).buildRequest(),
      ).root;
      expect(root.findChild('AirSync', 'Partial'), isNotNull);
      expect(root.findChild('AirSync', 'Collections'), isNull);
    });

    test('Fetch client command', () {
      final cmd = SyncCommand(
        syncKey: 'k',
        collectionId: '5',
        clientCommands: const [SyncFetchItem(serverId: '5:1')],
      );
      final commands = _roundTrip(cmd.buildRequest()).root
          .findChild('AirSync', 'Collections')!
          .findChild('AirSync', 'Collection')!
          .findChild('AirSync', 'Commands')!;
      expect(
        commands
            .findChild('AirSync', 'Fetch')!
            .childText('AirSync', 'ServerId'),
        '5:1',
      );
    });
  });

  group('MultiSyncCommand response', () {
    final cmd = MultiSyncCommand(
      collections: const [
        SyncCollection(syncKey: 'a0', collectionId: 'mail'),
        SyncCollection(
          syncKey: 'c0',
          collectionId: 'cal',
          contentType: SyncContentType.calendar,
        ),
      ],
    );

    test('parses every collection with its own type, key and status', () {
      final doc = WbxmlDecoder().decode(
        _syncResponse([
          _collectionResponse(
            'mail',
            'a1',
            extra: [
              _as('Commands', [
                _as('Add', [
                  _as('ServerId', 'mail:1'),
                  _as('ApplicationData', [_el('Email', 'Subject', 'Hi')]),
                ]),
                _as('Delete', [_as('ServerId', 'mail:2')]),
                _as('SoftDelete', [_as('ServerId', 'mail:3')]),
              ]),
            ],
          ),
          _collectionResponse(
            'cal',
            'c1',
            extra: [
              _as('Commands', [
                _as('Add', [
                  _as('ServerId', 'cal:1'),
                  _as('ApplicationData', [_el('Calendar', 'Subject', 'Mtg')]),
                ]),
              ]),
              _as('MoreAvailable'),
            ],
          ),
        ]),
      );
      final result = cmd.parseResponse(doc);

      expect(result.status, 1);
      expect(result.collections, hasLength(2));
      final mail = result.collection('mail')!;
      expect(mail.syncKey, 'a1');
      expect(mail.addedEmails.single.subject, 'Hi');
      expect(mail.deletedIds, ['mail:2']);
      expect(mail.softDeletedIds, ['mail:3']);
      final cal = result.collection('cal')!;
      expect(cal.syncKey, 'c1');
      expect(cal.addedCalendarEvents.single.subject, 'Mtg');
      expect(cal.addedEmails, isEmpty);
      expect(cal.moreAvailable, isTrue);
    });

    test('Status 12 and 13 getters', () {
      final col = cmd.parseResponse(
        WbxmlDecoder().decode(
          _syncResponse([_collectionResponse('mail', 'a0', status: '12')]),
        ),
      );
      expect(col.collection('mail')!.needsFolderSync, isTrue);
      expect(col.needsFolderSync, isTrue);

      final top = cmd.parseResponse(
        WbxmlDecoder().decode(_encode(_as('Sync', [_as('Status', '13')]))),
      );
      expect(top.needsFullRequest, isTrue);
      expect(top.collections, isEmpty);
    });

    test('parses Fetch responses and attachment FileReferences', () {
      final doc = WbxmlDecoder().decode(
        _syncResponse([
          _collectionResponse(
            'mail',
            'a1',
            extra: [
              _as('Responses', [
                _as('Fetch', [
                  _as('ServerId', 'mail:9'),
                  _as('Status', '1'),
                  _as('ApplicationData', [_el('Email', 'Subject', 'Fetched')]),
                ]),
                _as('Fetch', [_as('ServerId', 'mail:8'), _as('Status', '8')]),
                _as('Add', [
                  _as('ClientId', 'd1'),
                  _as('ServerId', 'mail:10'),
                  _as('Status', '1'),
                  _as('ApplicationData', [
                    _el('AirSyncBase', 'Attachments', [
                      _el('AirSyncBase', 'Attachment', [
                        _el('AirSyncBase', 'ClientId', 'att1'),
                        _el('AirSyncBase', 'FileReference', 'ref-1'),
                      ]),
                    ]),
                  ]),
                ]),
              ]),
            ],
          ),
        ]),
      );
      final mail = cmd.parseResponse(doc).collection('mail')!;
      expect(mail.fetchResponses, hasLength(2));
      expect((mail.fetchResponses[0].item as EasEmail).subject, 'Fetched');
      expect(mail.fetchResponses[1].isSuccess, isFalse);
      expect(mail.fetchResponses[1].item, isNull);
      expect(mail.addResponses.single.serverId, 'mail:10');
      expect(mail.addResponses.single.attachmentFileReferences, {
        'att1': 'ref-1',
      });
    });
  });

  group('SyncCommand backward compatibility', () {
    test('selects its collection from a multi-collection response', () {
      final cmd = SyncCommand(syncKey: 'k0', collectionId: 'b');
      final result = cmd.parseResponse(
        WbxmlDecoder().decode(
          _syncResponse([
            _collectionResponse('a', 'x1'),
            _collectionResponse('b', 'k1'),
          ]),
        ),
      );
      expect(result.collectionId, 'b');
      expect(result.syncKey, 'k1');
    });

    test('missing Collections keeps the request key', () {
      final result = SyncCommand(
        syncKey: 'k0',
        collectionId: 'b',
      ).parseResponse(WbxmlDecoder().decode(_encode(_as('Sync', []))));
      expect(result.status, 1);
      expect(result.syncKey, 'k0');
    });
  });

  group('HTTP behaviour', () {
    test('HTTP 200 with empty body means no changes', () async {
      var call = 0;
      final client = _client((req) async {
        call++;
        if (call == 1) {
          return http.Response.bytes(
            _syncResponse([_collectionResponse('5', 'k1')]),
            200,
          );
        }
        return http.Response.bytes(Uint8List(0), 200);
      });
      await client.syncFolder('5');
      final result = await client.syncFolder('5');
      expect(result.status, 1);
      expect(result.syncKey, 'k1');
      expect(result.addedEmails, isEmpty);
    });

    test('empty request sends no body; empty reply → noChanges', () async {
      final bodies = <int>[];
      final client = _client((req) async {
        bodies.add(req.bodyBytes.length);
        return http.Response.bytes(Uint8List(0), 200);
      });
      final result = await client.syncMultipleFolders(const [
        SyncCollection(collectionId: '5'),
      ], emptyRequest: true);
      expect(bodies, [0]);
      expect(result.isEmpty, isTrue);
    });

    test('empty request falls back to full request on Status 13', () async {
      final bodies = <int>[];
      final client = _client((req) async {
        bodies.add(req.bodyBytes.length);
        if (req.bodyBytes.isEmpty) {
          return http.Response.bytes(
            _encode(_as('Sync', [_as('Status', '13')])),
            200,
          );
        }
        return http.Response.bytes(
          _syncResponse([
            _collectionResponse('5', 'k1'),
            _collectionResponse('6', 'k2', status: '3'),
          ]),
          200,
        );
      });
      final result = await client.syncMultipleFolders(const [
        SyncCollection(collectionId: '5'),
        SyncCollection(collectionId: '6'),
      ], emptyRequest: true);
      expect(bodies, hasLength(2));
      expect(bodies[1], greaterThan(0));
      expect(result.collections, hasLength(2));
      expect(result.collection('6')!.needsReset, isTrue);
    });

    test('FolderSync Status 9 resets the key and re-syncs once', () async {
      final keys = <String?>[];
      var call = 0;
      final client = _client((req) async {
        call++;
        final sent = WbxmlDecoder()
            .decode(req.bodyBytes)
            .root
            .childText('FolderHierarchy', 'SyncKey');
        keys.add(sent);
        final status = call == 2 ? '9' : '1';
        return http.Response.bytes(
          _encode(
            _el('FolderHierarchy', 'FolderSync', [
              _el('FolderHierarchy', 'Status', status),
              if (status == '1') _el('FolderHierarchy', 'SyncKey', 'f$call'),
            ]),
          ),
          200,
        );
      });
      await client.syncFolders(); // key → f1
      final result = await client.syncFolders(); // 9 → reset → f3
      expect(keys, ['0', 'f1', '0']);
      expect(result.isSuccess, isTrue);
      expect(result.syncKey, 'f3');
    });
  });

  group('FolderSyncResult', () {
    test('needsReset on Status 9', () {
      expect(
        const FolderSyncResult(status: 9, syncKey: '1').needsReset,
        isTrue,
      );
      expect(const FolderSyncResult(status: 1, syncKey: '1').isSuccess, isTrue);
    });
  });

  group('EmailSerializer.serializeDraft', () {
    test('emits draft fields, attachments Add/Delete and Send', () {
      final content = Uint8List.fromList([1, 2, 3, 4]);
      final appData = EmailSerializer.serializeDraft(
        const EasEmail(
          serverId: '',
          to: 'a@example.com',
          cc: 'b@example.com',
          bcc: 'c@example.com',
          subject: 'Draft',
          from: 'ignored@example.com',
          body: 'Hello',
          importance: EmailImportance.high,
        ),
        addAttachments: [
          EasAttachmentAdd(
            clientId: 'att1',
            displayName: 'file.bin',
            content: content,
            contentType: 'application/octet-stream',
            contentId: 'cid1',
            isInline: true,
          ),
        ],
        deleteAttachments: ['ref-old'],
      );

      final root = _roundTrip(WbxmlDocument(root: appData)).root;
      expect(root.childText('Email', 'To'), 'a@example.com');
      expect(root.childText('Email', 'Cc'), 'b@example.com');
      expect(root.childText('Email2', 'Bcc'), 'c@example.com');
      expect(root.childText('Email', 'Subject'), 'Draft');
      expect(root.childText('Email', 'Importance'), '2');
      expect(root.findChild('Email', 'From'), isNull);
      expect(root.findChild('Email', 'Read'), isNull);
      expect(
        root.findChild('AirSyncBase', 'Body')!.childText('AirSyncBase', 'Data'),
        'Hello',
      );
      // email2:Send is a sibling of ApplicationData (SyncChangeItem.send).
      expect(root.findChild('Email2', 'Send'), isNull);

      final atts = root.findChild('AirSyncBase', 'Attachments')!;
      final add = atts.findChild('AirSyncBase', 'Add')!;
      expect(add.childText('AirSyncBase', 'ClientId'), 'att1');
      expect(add.findChild('AirSyncBase', 'Content')!.opaque, content);
      expect(add.childText('AirSyncBase', 'Method'), '1');
      expect(add.childText('AirSyncBase', 'DisplayName'), 'file.bin');
      expect(
        add.childText('AirSyncBase', 'ContentType'),
        'application/octet-stream',
      );
      expect(add.childText('AirSyncBase', 'ContentId'), 'cid1');
      expect(add.childText('AirSyncBase', 'IsInline'), '1');
      expect(
        atts
            .findChild('AirSyncBase', 'Delete')!
            .childText('AirSyncBase', 'FileReference'),
        'ref-old',
      );
    });

    test('minimal draft has no attachments and no Send', () {
      final root = EmailSerializer.serializeDraft(const EasEmail(serverId: ''));
      expect(root.findChild('AirSyncBase', 'Attachments'), isNull);
      expect(root.findChild('Email2', 'Send'), isNull);
      expect(root.childText('Email', 'Importance'), '1');
    });
  });
}
