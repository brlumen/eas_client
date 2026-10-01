import 'dart:convert';
import 'dart:typed_data';

import 'package:eas_client/eas_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final _encoder = WbxmlEncoder();
final _decoder = WbxmlDecoder();

/// Encode → decode round-trip of a command request.
WbxmlElement _roundTrip(WbxmlDocument doc) =>
    _decoder.decode(_encoder.encode(doc)).root;

final _mime = utf8.encode('To: a@example.com\r\nSubject: Hi\r\n\r\nBody');

/// Build a multipart body from [parts] (little-endian layout).
Uint8List _multipart(List<List<int>> parts) {
  final header = ByteData(4 + parts.length * 8)
    ..setInt32(0, parts.length, Endian.little);
  var offset = header.lengthInBytes;
  for (var i = 0; i < parts.length; i++) {
    header
      ..setInt32(4 + i * 8, offset, Endian.little)
      ..setInt32(8 + i * 8, parts[i].length, Endian.little);
    offset += parts[i].length;
  }
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    for (final p in parts) ...p,
  ]);
}

Uint8List _rawHeader(List<int> ints) {
  final b = ByteData(ints.length * 4);
  for (var i = 0; i < ints.length; i++) {
    b.setInt32(i * 4, ints[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

WbxmlElement _io(String tag, {String? text, List<WbxmlElement>? children}) =>
    WbxmlElement(
      namespace: 'ItemOperations',
      tag: tag,
      codePageIndex: 20,
      text: text,
      children: children,
    );

WbxmlDocument _fetchResponse(List<WbxmlElement> properties) => WbxmlDocument(
  root: _io(
    'ItemOperations',
    children: [
      _io('Status', text: '1'),
      _io(
        'Response',
        children: [
          _io(
            'Fetch',
            children: [
              _io('Status', text: '1'),
              _io('Properties', children: properties),
            ],
          ),
        ],
      ),
    ],
  ),
);

void main() {
  group('SmartReply / SmartForward', () {
    test('FolderId/ItemId source with InstanceId, ReplaceMime, TemplateID', () {
      final root = _roundTrip(
        SmartReplyCommand(
          clientId: 'c1',
          serverId: '5:10',
          collectionId: '5',
          instanceId: DateTime.utc(2026, 3, 20, 22, 40),
          mimeContent: _mime,
          replaceMime: true,
          templateId: 'tpl-1',
        ).buildRequest(),
      );

      expect(root.tag, 'SmartReply');
      expect(root.children.map((e) => e.tag).toList(), [
        'ClientId',
        'Source',
        'SaveInSentItems',
        'ReplaceMime',
        'Mime',
        'TemplateID',
      ]);
      final source = root.findChild('ComposeMail', 'Source')!;
      expect(source.childText('ComposeMail', 'FolderId'), '5');
      expect(source.childText('ComposeMail', 'ItemId'), '5:10');
      expect(
        source.childText('ComposeMail', 'InstanceId'),
        '2026-03-20T22:40:00.000Z',
      );
      expect(root.childText('RightsManagement', 'TemplateID'), 'tpl-1');
      expect(root.findChild('ComposeMail', 'Mime')!.opaque, _mime);
    });

    test('LongId source, no optional elements', () {
      final root = _roundTrip(
        SmartReplyCommand(
          clientId: 'c1',
          longId: 'RgAAAA',
          mimeContent: _mime,
          saveInSentItems: false,
        ).buildRequest(),
      );

      final source = root.findChild('ComposeMail', 'Source')!;
      expect(source.children.map((e) => e.tag), ['LongId']);
      expect(source.childText('ComposeMail', 'LongId'), 'RgAAAA');
      expect(root.findChild('ComposeMail', 'SaveInSentItems'), isNull);
      expect(root.findChild('ComposeMail', 'ReplaceMime'), isNull);
      expect(root.findChild('RightsManagement', 'TemplateID'), isNull);
    });

    test('rejects missing, partial or ambiguous source', () {
      expect(
        () => SmartReplyCommand(clientId: 'c', mimeContent: _mime),
        throwsArgumentError,
      );
      expect(
        () =>
            SmartReplyCommand(clientId: 'c', serverId: '1', mimeContent: _mime),
        throwsArgumentError,
      );
      expect(
        () => SmartForwardCommand(
          clientId: 'c',
          serverId: '1',
          collectionId: '2',
          longId: 'x',
          mimeContent: _mime,
        ),
        throwsArgumentError,
      );
    });

    test('still rejects MIME header injection', () {
      expect(
        () => SmartForwardCommand(
          clientId: 'c',
          longId: 'x',
          mimeContent: utf8.encode('Subject: a\nBcc: evil@x\r\n\r\nb'),
        ),
        throwsArgumentError,
      );
    });

    test('SmartForward Forwardees', () {
      final root = _roundTrip(
        SmartForwardCommand.meeting(
          clientId: 'c1',
          serverId: '1',
          collectionId: '2',
          forwardees: const [
            Forwardee(email: 'a@example.com', name: 'A'),
            Forwardee(email: 'b@example.com'),
          ],
        ).buildRequest(),
      );

      expect(root.tag, 'SmartForward');
      expect(root.children.last.tag, 'Forwardees');
      final list = root
          .findChild('ComposeMail', 'Forwardees')!
          .findChildren('ComposeMail', 'Forwardee');
      expect(list, hasLength(2));
      expect(list[0].childText('ComposeMail', 'Name'), 'A');
      expect(list[0].childText('ComposeMail', 'Email'), 'a@example.com');
      expect(list[1].findChild('ComposeMail', 'Name'), isNull);
    });

    test('SendMail TemplateID', () {
      final root = _roundTrip(
        SendMailCommand(
          clientId: 'c',
          mimeContent: _mime,
          templateId: 't',
        ).buildRequest(),
      );
      expect(root.children.map((e) => e.tag), [
        'ClientId',
        'SaveInSentItems',
        'Mime',
        'TemplateID',
      ]);
    });
  });

  group('MeetingResponse 16.x', () {
    test('LongId, InstanceId and SendResponse with proposed time', () {
      final root = _roundTrip(
        MeetingResponseCommand.single(
          longId: 'L1',
          response: MeetingResponseStatus.tentative,
          instanceId: DateTime.utc(2026, 1, 2, 10),
          sendResponse: MeetingSendResponse(
            body: 'Can we move it?',
            proposedStartTime: DateTime.utc(2026, 1, 2, 12),
            proposedEndTime: DateTime.utc(2026, 1, 2, 13),
          ),
        ).buildRequest(),
      );

      final req = root.findChild('MeetingResponse', 'Request')!;
      expect(req.childText('MeetingResponse', 'UserResponse'), '2');
      expect(req.childText('Search', 'LongId'), 'L1');
      expect(req.findChild('MeetingResponse', 'CollectionId'), isNull);
      expect(req.findChild('MeetingResponse', 'RequestId'), isNull);
      expect(
        req.childText('MeetingResponse', 'InstanceId'),
        '2026-01-02T10:00:00.000Z',
      );
      final send = req.findChild('MeetingResponse', 'SendResponse')!;
      final body = send.findChild('AirSyncBase', 'Body')!;
      expect(body.childText('AirSyncBase', 'Type'), '1');
      expect(body.childText('AirSyncBase', 'Data'), 'Can we move it?');
      expect(
        send.childText('MeetingResponse', 'ProposedStartTime'),
        '20260102T120000Z',
      );
      expect(
        send.childText('MeetingResponse', 'ProposedEndTime'),
        '20260102T130000Z',
      );
      expect(send.children.map((e) => e.tag), [
        'Body',
        'ProposedStartTime',
        'ProposedEndTime',
      ]);
    });

    test('classic request keeps CollectionId/RequestId, no SendResponse', () {
      final req = _roundTrip(
        MeetingResponseCommand.single(
          requestId: 'r1',
          collectionId: 'c1',
          response: MeetingResponseStatus.accepted,
        ).buildRequest(),
      ).findChild('MeetingResponse', 'Request')!;
      expect(req.children.map((e) => e.tag), [
        'UserResponse',
        'CollectionId',
        'RequestId',
      ]);
    });

    test('empty SendResponse is emitted', () {
      final req = _roundTrip(
        MeetingResponseCommand.single(
          requestId: 'r1',
          collectionId: 'c1',
          response: MeetingResponseStatus.accepted,
          sendResponse: const MeetingSendResponse(),
        ).buildRequest(),
      ).findChild('MeetingResponse', 'Request')!;
      expect(req.findChild('MeetingResponse', 'SendResponse'), isNotNull);
    });

    test('validation', () {
      expect(
        () => MeetingResponseCommand.single(
          response: MeetingResponseStatus.accepted,
        ),
        throwsArgumentError,
      );
      expect(
        () => MeetingResponseCommand.single(
          longId: 'L',
          response: MeetingResponseStatus.accepted,
          sendResponse: MeetingSendResponse(
            proposedStartTime: DateTime.utc(2026),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('ItemOperations Move', () {
    final convId = Uint8List.fromList([0xFF, 0x68, 0x02, 0x20]);

    test('buildRequest with MoveAlways', () {
      final move = _roundTrip(
        MoveConversationCommand(
          conversationId: convId,
          dstFolderId: '7',
          moveAlways: true,
        ).buildRequest(),
      ).findChild('ItemOperations', 'Move')!;
      expect(
        move.findChild('ItemOperations', 'ConversationId')!.opaque,
        convId,
      );
      expect(move.childText('ItemOperations', 'DstFldId'), '7');
      expect(
        move
            .findChild('ItemOperations', 'Options')!
            .findChild('ItemOperations', 'MoveAlways'),
        isNotNull,
      );
    });

    test('no Options without MoveAlways', () {
      final move = _roundTrip(
        MoveConversationCommand(
          conversationId: convId,
          dstFolderId: '7',
          moveAlways: false,
        ).buildRequest(),
      ).findChild('ItemOperations', 'Move')!;
      expect(move.findChild('ItemOperations', 'Options'), isNull);
    });

    test('parseResponse', () {
      final doc = _decoder.decode(
        _encoder.encode(
          WbxmlDocument(
            root: _io(
              'ItemOperations',
              children: [
                _io('Status', text: '1'),
                _io(
                  'Response',
                  children: [
                    _io(
                      'Move',
                      children: [
                        _io('Status', text: '1'),
                        WbxmlElement(
                          namespace: 'ItemOperations',
                          tag: 'ConversationId',
                          codePageIndex: 20,
                          opaque: convId,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      final result = MoveConversationCommand(
        conversationId: convId,
        dstFolderId: '7',
      ).parseResponse(doc);
      expect(result.isSuccess, isTrue);
      expect(result.conversationId, convId);
    });
  });

  group('ItemOperations Fetch', () {
    test('by LongId', () {
      final fetch = _roundTrip(
        FetchByLongIdCommand(longId: 'L1', bodyType: 1).buildRequest(),
      ).findChild('ItemOperations', 'Fetch')!;
      expect(fetch.childText('ItemOperations', 'Store'), 'Mailbox');
      expect(fetch.childText('Search', 'LongId'), 'L1');
      expect(fetch.findChild('AirSync', 'ServerId'), isNull);
    });

    test('DocumentLibrary by LinkId with credentials', () {
      final cmd = FetchDocumentCommand(
        linkId: r'\\srv\share\a.txt',
        userName: 'dom\\u',
        password: 'p@ss',
      );
      final fetch = _roundTrip(
        cmd.buildRequest(),
      ).findChild('ItemOperations', 'Fetch')!;
      expect(fetch.childText('ItemOperations', 'Store'), 'DocumentLibrary');
      expect(
        fetch.childText('DocumentLibrary', 'LinkId'),
        r'\\srv\share\a.txt',
      );
      final options = fetch.findChild('ItemOperations', 'Options')!;
      expect(options.childText('ItemOperations', 'UserName'), 'dom\\u');
      expect(options.childText('ItemOperations', 'Password'), 'p@ss');
      expect(cmd.toString(), isNot(contains('p@ss')));
    });

    test('DocumentLibrary without credentials has no Options', () {
      final fetch = _roundTrip(
        FetchDocumentCommand(linkId: 'https://sp.example.com/d').buildRequest(),
      ).findChild('ItemOperations', 'Fetch')!;
      expect(fetch.findChild('ItemOperations', 'Options'), isNull);
    });

    test('multipart header only when requested', () {
      expect(FetchAttachmentCommand(fileReference: 'f').acceptMultiPart, false);
      expect(
        FetchAttachmentCommand(
          fileReference: 'f',
          acceptMultiPart: true,
        ).acceptMultiPart,
        true,
      );
    });

    test('Part reference in a non-multipart response is rejected', () {
      final doc = _fetchResponse([_io('Part', text: '1')]);
      expect(
        () => FetchAttachmentCommand(fileReference: 'f').parseResponse(doc),
        throwsA(isA<EasCommandException>()),
      );
    });

    test('multipart end-to-end via EasHttpClient', () async {
      final payload = List<int>.generate(300, (i) => i % 256);
      final wbxml = _encoder.encode(_fetchResponse([_io('Part', text: '1')]));
      http.BaseRequest? sent;
      final client = EasHttpClient(
        server: 'mail.example.com',
        credentials: BasicCredentials(username: 'u', password: 'p'),
        deviceId: 'dev1',
        httpClient: MockClient((req) async {
          sent = req;
          return http.Response.bytes(
            _multipart([wbxml, payload]),
            200,
            headers: {'content-type': easMultipartContentType},
          );
        }),
      );

      final result = await FetchAttachmentCommand(
        fileReference: 'f',
        acceptMultiPart: true,
      ).execute(client);

      expect(sent!.headers['MS-ASAcceptMultiPart'], 'T');
      expect(result.status, 1);
      expect(result.data, payload);
    });

    test('inline Body Part is decoded as UTF-8 text', () {
      final wbxml = _encoder.encode(
        _fetchResponse([
          WbxmlElement(
            namespace: 'AirSyncBase',
            tag: 'Body',
            codePageIndex: 17,
            children: [
              WbxmlElement.withText(
                namespace: 'AirSyncBase',
                tag: 'Type',
                text: '1',
                codePageIndex: 17,
              ),
              _io('Part', text: '1'),
            ],
          ),
        ]),
      );
      final result = FetchEmailBodyCommand(serverId: '1', collectionId: '2')
          .parseHttpResponse(
            EasResponse(
              statusCode: 200,
              headers: {'content-type': easMultipartContentType},
              body: _multipart([wbxml, utf8.encode('héllo')]),
            ),
          );
      expect(result.body, 'héllo');
      expect(result.bodyType, 1);
    });
  });

  group('EasMultipartResponse', () {
    test('parses parts', () {
      final mp = EasMultipartResponse.parse(
        _multipart([
          [1, 2],
          [],
          [3, 4, 5],
        ]),
      );
      expect(mp.parts, hasLength(3));
      expect(mp.parts[0], [1, 2]);
      expect(mp.parts[1], isEmpty);
      expect(mp.partAt('2'), [3, 4, 5]);
    });

    test('isMultipart', () {
      expect(EasMultipartResponse.isMultipart(easMultipartContentType), isTrue);
      expect(
        EasMultipartResponse.isMultipart(
          'Application/Vnd.MS-Sync.Multipart; charset=x',
        ),
        isTrue,
      );
      expect(
        EasMultipartResponse.isMultipart('application/vnd.ms-sync.wbxml'),
        isFalse,
      );
      expect(EasMultipartResponse.isMultipart(null), isFalse);
    });

    test('partAt rejects invalid references', () {
      final mp = EasMultipartResponse.parse(
        _multipart([
          [1],
          [2],
        ]),
      );
      for (final ref in [null, '', 'x', '0', '2', '-1']) {
        expect(
          () => mp.partAt(ref),
          throwsA(isA<EasMultipartException>()),
          reason: 'ref=$ref',
        );
      }
    });

    void expectMalformed(Uint8List body, {int? maxPartSize}) => expect(
      () => maxPartSize == null
          ? EasMultipartResponse.parse(body)
          : EasMultipartResponse.parse(body, maxPartSize: maxPartSize),
      throwsA(isA<EasMultipartException>()),
    );

    test('rejects too-short body', () {
      expectMalformed(Uint8List(0));
      expectMalformed(Uint8List.fromList([1, 0, 0]));
    });

    test('rejects invalid part count', () {
      expectMalformed(_rawHeader([0]));
      expectMalformed(_rawHeader([-1]));
      // Count claims more descriptors than the body can hold.
      expectMalformed(_rawHeader([0x7FFFFFFF, 12, 0]));
      expectMalformed(_rawHeader([2, 20, 0]));
    });

    test('rejects out-of-bounds and negative offsets/lengths', () {
      // offset + length beyond body
      expectMalformed(_rawHeader([1, 12, 100]));
      // offset inside the header
      expectMalformed(
        Uint8List.fromList([
          ..._rawHeader([1, 0, 4]),
          9,
        ]),
      );
      // negative length
      expectMalformed(
        Uint8List.fromList([
          ..._rawHeader([1, 12, -1]),
          9,
        ]),
      );
      // negative offset
      expectMalformed(
        Uint8List.fromList([
          ..._rawHeader([1, -4, 1]),
          9,
        ]),
      );
      // offset + length overflow attempt
      expectMalformed(
        Uint8List.fromList([
          ..._rawHeader([1, 12, 0x7FFFFFFF]),
          9,
        ]),
      );
    });

    test('rejects oversized part', () {
      expectMalformed(_multipart([List.filled(10, 0)]), maxPartSize: 9);
      expect(
        EasMultipartResponse.parse(
          _multipart([List.filled(10, 0)]),
          maxPartSize: 10,
        ).parts.single,
        hasLength(10),
      );
    });

    test('toString does not leak content', () {
      expect(
        EasMultipartException('Invalid part reference').toString(),
        'EasMultipartException: Invalid part reference',
      );
    });
  });

  group('Search DocumentLibrary', () {
    test('buildRequest', () {
      final store = _roundTrip(
        DocumentLibrarySearchCommand(
          linkId: r'\\srv\share',
          rangeEnd: 9,
          userName: 'u',
          password: 'secret',
        ).buildRequest(),
      ).findChild('Search', 'Store')!;
      expect(store.childText('Search', 'Name'), 'DocumentLibrary');
      final eq = store
          .findChild('Search', 'Query')!
          .findChild('Search', 'EqualTo')!;
      expect(eq.findChild('DocumentLibrary', 'LinkId'), isNotNull);
      expect(eq.childText('Search', 'Value'), r'\\srv\share');
      final options = store.findChild('Search', 'Options')!;
      expect(options.childText('Search', 'Range'), '0-9');
      expect(options.childText('Search', 'UserName'), 'u');
      expect(options.childText('Search', 'Password'), 'secret');
    });

    test('parseResponse', () {
      WbxmlElement s(String tag, {String? text, List<WbxmlElement>? c}) =>
          WbxmlElement(
            namespace: 'Search',
            tag: tag,
            codePageIndex: 15,
            text: text,
            children: c,
          );
      WbxmlElement d(String tag, String text) => WbxmlElement.withText(
        namespace: 'DocumentLibrary',
        tag: tag,
        text: text,
        codePageIndex: 19,
      );

      final doc = _decoder.decode(
        _encoder.encode(
          WbxmlDocument(
            root: s(
              'Search',
              c: [
                s('Status', text: '1'),
                s(
                  'Response',
                  c: [
                    s(
                      'Store',
                      c: [
                        s('Status', text: '1'),
                        s(
                          'Result',
                          c: [
                            s(
                              'Properties',
                              c: [
                                d('LinkId', r'\\srv\share\doc.txt'),
                                d('DisplayName', 'doc.txt'),
                                d('IsFolder', '0'),
                                d('CreationDate', '2026-01-01T10:00:00.000Z'),
                                d(
                                  'LastModifiedDate',
                                  '2026-02-01T10:00:00.000Z',
                                ),
                                d('IsHidden', '1'),
                                d('ContentLength', '1234'),
                                d('ContentType', 'text/plain'),
                              ],
                            ),
                          ],
                        ),
                        s(
                          'Result',
                          c: [
                            s(
                              'Properties',
                              c: [
                                d('LinkId', r'\\srv\share\dir'),
                                d('IsFolder', '1'),
                              ],
                            ),
                          ],
                        ),
                        s('Range', text: '0-1'),
                        s('Total', text: '2'),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      final result = DocumentLibrarySearchCommand(
        linkId: 'https://sp.example.com/share',
      ).parseResponse(doc);
      expect(result.status, 1);
      expect(result.total, 2);
      expect(result.items, hasLength(2));
      final file = result.items.first;
      expect(file.linkId, r'\\srv\share\doc.txt');
      expect(file.displayName, 'doc.txt');
      expect(file.isFolder, isFalse);
      expect(file.creationDate, DateTime.utc(2026, 1, 1, 10));
      expect(file.lastModifiedDate, DateTime.utc(2026, 2, 1, 10));
      expect(file.isHidden, isTrue);
      expect(file.contentLength, 1234);
      expect(file.contentType, 'text/plain');
      expect(file.toString(), isNot(contains('doc.txt')));
      expect(result.items.last.isFolder, isTrue);
    });
  });
}
