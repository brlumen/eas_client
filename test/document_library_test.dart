import 'dart:convert';

import 'package:eas_client/eas_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final _encoder = WbxmlEncoder();
final _decoder = WbxmlDecoder();

WbxmlElement _roundTrip(WbxmlDocument doc) =>
    _decoder.decode(_encoder.encode(doc)).root;

WbxmlElement _io(String tag, {String? text, List<WbxmlElement>? c}) =>
    WbxmlElement(
      namespace: 'ItemOperations',
      tag: tag,
      codePageIndex: 20,
      text: text,
      children: c,
    );

WbxmlElement _dl(String tag, String text) => WbxmlElement.withText(
  namespace: 'DocumentLibrary',
  tag: tag,
  text: text,
  codePageIndex: 19,
);

const _unc = r'\\srv\share\doc.txt';

void main() {
  group('validateDocumentLinkId', () {
    for (final ok in [
      r'\\srv',
      r'\\srv\share',
      r'\\srv\share\',
      r'\\srv\share\dir\file name.docx',
      'http://sp.example.com/sites/a/doc.docx',
      'HTTPS://sp.example.com/Shared%20Documents/',
    ]) {
      test('accepts $ok', () => validateDocumentLinkId(ok));
    }

    for (final bad in [
      '',
      'relative/path',
      r'\single\backslash',
      r'\\',
      r'\\?\C:\secret',
      r'\\.\pipe\x',
      r'\\srv\share\..\other',
      r'\\srv\share\.\x',
      r'\\srv\\share',
      'file:///etc/passwd',
      'ftp://srv/file',
      'javascript:alert(1)',
      'https:///nohost',
      'https://user:pass@sp.example.com/doc',
      'https://sp.example.com/a\nb',
      '\\\\srv\\share\u0000',
      'https://sp.example.com/${'a' * 1100}',
    ]) {
      test(
        'rejects ${jsonEncode(bad.length > 40 ? bad.substring(0, 40) : bad)}',
        () {
          expect(() => validateDocumentLinkId(bad), throwsArgumentError);
        },
      );
    }

    test('error message does not leak the value or credentials', () {
      try {
        validateDocumentLinkId('https://alice:hunter2@sp.example.com/x');
        fail('expected ArgumentError');
      } on ArgumentError catch (e) {
        expect(e.toString(), isNot(contains('hunter2')));
        expect(e.toString(), isNot(contains('alice')));
      }
    });

    test('1024-byte limit counts UTF-8 bytes', () {
      final base = r'\\s\';
      validateDocumentLinkId(base + 'a' * (1024 - base.length));
      expect(
        () => validateDocumentLinkId(base + 'é' * 511),
        throwsArgumentError,
      );
    });
  });

  group('ItemOperations Fetch (DocumentLibrary)', () {
    test('request: Store, LinkId, Range/UserName/Password only', () {
      final cmd = FetchDocumentCommand(
        linkId: _unc,
        userName: r'dom\u',
        password: 'topsecret',
        rangeStart: 0,
        rangeEnd: 1023,
        acceptMultiPart: true,
      );
      expect(cmd.acceptMultiPart, isTrue);
      expect(cmd.linkId, _unc);
      final fetch = _roundTrip(
        cmd.buildRequest(),
      ).findChild('ItemOperations', 'Fetch')!;
      expect(fetch.childText('ItemOperations', 'Store'), 'DocumentLibrary');
      expect(fetch.childText('DocumentLibrary', 'LinkId'), _unc);
      final opts = fetch.findChild('ItemOperations', 'Options')!;
      expect(opts.childText('ItemOperations', 'Range'), '0-1023');
      expect(opts.childText('ItemOperations', 'UserName'), r'dom\u');
      expect(opts.childText('ItemOperations', 'Password'), 'topsecret');
      expect(opts.children, hasLength(3));
      expect(cmd.toString(), isNot(contains('topsecret')));
      expect(
        ItemFetchOptions(userName: 'u', password: 'topsecret').toString(),
        isNot(contains('topsecret')),
      );
    });

    test('invalid LinkId rejected on construction', () {
      expect(
        () => FetchDocumentCommand(linkId: 'file:///etc/passwd'),
        throwsArgumentError,
      );
      expect(() => ItemFetch.document('ftp://x/y'), throwsArgumentError);
    });

    test('Schema / body preferences / IRM are not valid for documents', () {
      expect(
        () => ItemFetch.document(
          _unc,
          options: ItemFetchOptions(
            schema: const [EasSchemaProperty('Email', 'Subject')],
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => ItemFetch.document(
          _unc,
          options: ItemFetchOptions(
            bodyPreferences: [EasBodyPreference(type: 1)],
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () =>
            ItemFetch.document(_unc, options: ItemFetchOptions(mimeSupport: 2)),
        throwsArgumentError,
      );
      expect(
        () => ItemFetch.document(
          _unc,
          options: ItemFetchOptions(rightsManagementSupport: true),
        ),
        throwsArgumentError,
      );
    });

    test('password requires userName; length limits', () {
      expect(() => ItemFetchOptions(password: 'p'), throwsArgumentError);
      expect(() => ItemFetchOptions(userName: 'u' * 101), throwsArgumentError);
      ItemFetchOptions(userName: 'u', password: 'p' * 256);
      expect(
        () => ItemFetchOptions(userName: 'u', password: 'p' * 257),
        throwsArgumentError,
      );
      expect(
        () => ItemFetchOptions(rangeStart: 5, rangeEnd: 4),
        throwsArgumentError,
      );
    });

    test('several documents in one request', () {
      final root = _roundTrip(
        ItemOperationsCommand([
          ItemFetch.document(_unc),
          ItemFetch.document('https://sp.example.com/a.docx'),
        ]).buildRequest(),
      );
      final fetches = root.findChildren('ItemOperations', 'Fetch');
      expect(fetches, hasLength(2));
      expect(
        fetches.last.childText('DocumentLibrary', 'LinkId'),
        'https://sp.example.com/a.docx',
      );
    });

    test('response: LinkId, inline Data, Range, Total, Version', () {
      final doc = _decoder.decode(
        _encoder.encode(
          WbxmlDocument(
            root: _io(
              'ItemOperations',
              c: [
                _io('Status', text: '1'),
                _io(
                  'Response',
                  c: [
                    _io(
                      'Fetch',
                      c: [
                        _io('Status', text: '1'),
                        _dl('LinkId', _unc),
                        _io(
                          'Properties',
                          c: [
                            _io('Range', text: '0-4'),
                            _io('Total', text: '13'),
                            _io(
                              'Data',
                              text: base64.encode(utf8.encode('Hello')),
                            ),
                            _io('Version', text: '2009-11-11T19:15:45.177Z'),
                          ],
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
      final r = FetchDocumentCommand(linkId: _unc).parseResponse(doc);
      expect(r.isSuccess, isTrue);
      expect(r.linkId, _unc);
      expect(utf8.decode(r.data!), 'Hello');
      expect(r.range, '0-4');
      expect(r.byteRange, (start: 0, end: 4));
      expect(r.total, 13);
      expect(r.version, DateTime.utc(2009, 11, 11, 19, 15, 45, 177));
    });

    test('document library status codes', () {
      for (final (code, status) in [
        (4, ItemOperationsStatus.badUri),
        (5, ItemOperationsStatus.accessDenied),
        (6, ItemOperationsStatus.notFound),
        (7, ItemOperationsStatus.connectionFailed),
        (8, ItemOperationsStatus.invalidRange),
        (10, ItemOperationsStatus.emptyFile),
        (12, ItemOperationsStatus.ioFailure),
        (18, ItemOperationsStatus.credentialsRequired),
      ]) {
        expect(ItemOperationsResult(status: code).statusInfo, status);
      }
    });

    test('byteRange is null for missing or malformed range', () {
      expect(const ItemOperationsResult(status: 1).byteRange, isNull);
      expect(
        const ItemOperationsResult(status: 1, range: 'abc').byteRange,
        isNull,
      );
    });
  });

  group('Search (DocumentLibrary)', () {
    test('only LinkId EqualTo query and Range/credentials options', () {
      expect(
        () => StoreSearchCommand(
          store: 'DocumentLibrary',
          query: const SearchFreeText('x'),
        ),
        throwsArgumentError,
      );
      expect(
        () => StoreSearchCommand(
          store: 'DocumentLibrary',
          query: SearchLinkIdEqualTo(_unc),
          options: SearchOptions(deepTraversal: true),
        ),
        throwsArgumentError,
      );
      expect(
        () => StoreSearchCommand(
          store: 'Mailbox',
          query: SearchAnd([SearchLinkIdEqualTo(_unc)]),
        ),
        throwsArgumentError,
      );
      final store = _roundTrip(
        StoreSearchCommand(
          store: 'DocumentLibrary',
          query: SearchLinkIdEqualTo(_unc),
          options: SearchOptions(rangeStart: 0, rangeEnd: 999),
        ).buildRequest(),
      ).findChild('Search', 'Store')!;
      expect(
        store
            .findChild('Search', 'Query')!
            .findChild('Search', 'EqualTo')!
            .childText('Search', 'Value'),
        _unc,
      );
    });

    test('invalid LinkId and credentials rules', () {
      expect(() => SearchLinkIdEqualTo('file:///x'), throwsArgumentError);
      expect(
        () => DocumentLibrarySearchCommand(linkId: 'smb://srv/share'),
        throwsArgumentError,
      );
      expect(
        () => DocumentLibrarySearchCommand(linkId: _unc, password: 'p'),
        throwsArgumentError,
      );
      expect(
        () => DocumentLibrarySearchCommand(
          linkId: _unc,
          userName: 'u',
          password: 'p' * 101,
        ),
        throwsArgumentError,
      );
      expect(
        () => DocumentLibrarySearchCommand(linkId: _unc, rangeEnd: 1000),
        throwsArgumentError,
      );
    });

    test('status codes', () {
      for (final (code, status) in [
        (4, SearchStatus.badLink),
        (5, SearchStatus.accessDenied),
        (6, SearchStatus.notFound),
        (7, SearchStatus.connectionFailed),
        (14, SearchStatus.credentialsRequired),
      ]) {
        expect(DocumentLibrarySearchResult(status: code).statusInfo, status);
      }
    });

    test('item without LinkId parses with null linkId', () {
      final props = WbxmlElement(
        namespace: 'Search',
        tag: 'Properties',
        codePageIndex: 15,
        children: [_dl('DisplayName', 'd\$'), _dl('IsFolder', '1')],
      );
      final item = EasDocumentLibraryItem.fromWbxml(props);
      expect(item.linkId, isNull);
      expect(item.isFolder, isTrue);
      expect(item.isHidden, isFalse);
      expect(item.contentLength, isNull);
    });
  });

  group('EasClient facade', () {
    EasClient client(String version, List<http.Request> seen) => EasClient(
      server: 'mail.example.com',
      credentials: BasicCredentials(username: 'user', password: 'secret'),
      deviceId: 'dev1',
      protocolVersion: version,
      httpClient: MockClient((req) async {
        seen.add(req);
        return http.Response.bytes(
          _encoder.encode(
            WbxmlDocument(
              root: _io(
                'ItemOperations',
                c: [
                  _io('Status', text: '1'),
                  _io(
                    'Response',
                    c: [
                      for (final id in [_unc, 'https://sp.example.com/b'])
                        _io(
                          'Fetch',
                          c: [
                            _io('Status', text: '1'),
                            _dl('LinkId', id),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          200,
        );
      }),
    );

    test('document library is rejected for EAS 2.5', () async {
      final seen = <http.Request>[];
      final c = client('2.5', seen);
      await expectLater(c.fetchDocument(_unc), throwsUnsupportedError);
      await expectLater(c.searchDocumentLibrary(_unc), throwsUnsupportedError);
      await expectLater(c.fetchDocuments([_unc]), throwsUnsupportedError);
      expect(seen, isEmpty);
    });

    test('fetchDocuments batches all LinkIds in one request', () async {
      final seen = <http.Request>[];
      final results = await client(
        '12.1',
        seen,
      ).fetchDocuments([_unc, 'https://sp.example.com/b']);
      expect(seen, hasLength(1));
      final fetches = _decoder
          .decode(seen.single.bodyBytes)
          .root
          .findChildren('ItemOperations', 'Fetch');
      expect(fetches, hasLength(2));
      expect(results.map((r) => r.linkId), [_unc, 'https://sp.example.com/b']);
    });
  });
}
