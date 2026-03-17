import 'package:eas_client/eas_client.dart';
import 'package:test/test.dart';

void main() {
  group('Sync write operations', () {
    late WbxmlEncoder encoder;
    late WbxmlDecoder decoder;

    setUp(() {
      encoder = WbxmlEncoder();
      decoder = WbxmlDecoder();
    });

    test('SyncCommand with Add generates Commands element', () {
      final appData = EmailSerializer.serializeReadFlag(true);
      final cmd = SyncCommand(
        syncKey: '123',
        collectionId: '5',
        clientCommands: [
          SyncAddItem(clientId: 'c1', applicationData: appData),
        ],
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final collection = decoded.root
          .findChild('AirSync', 'Collections')!
          .findChild('AirSync', 'Collection')!;

      // GetChanges should be '0' when commands present
      expect(collection.childText('AirSync', 'GetChanges'), equals('0'));

      final commands = collection.findChild('AirSync', 'Commands');
      expect(commands, isNotNull);

      final add = commands!.findChild('AirSync', 'Add');
      expect(add, isNotNull);
      expect(add!.childText('AirSync', 'ClientId'), equals('c1'));

      final ad = add.findChild('AirSync', 'ApplicationData');
      expect(ad, isNotNull);
    });

    test('SyncCommand with Change generates correct WBXML', () {
      final appData = EmailSerializer.serializeReadFlag(false);
      final cmd = SyncCommand(
        syncKey: '456',
        collectionId: '5',
        clientCommands: [
          SyncChangeItem(serverId: 's1', applicationData: appData),
        ],
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final commands = decoded.root
          .findChild('AirSync', 'Collections')!
          .findChild('AirSync', 'Collection')!
          .findChild('AirSync', 'Commands')!;

      final change = commands.findChild('AirSync', 'Change');
      expect(change, isNotNull);
      expect(change!.childText('AirSync', 'ServerId'), equals('s1'));
    });

    test('SyncCommand with Delete generates correct WBXML', () {
      final cmd = SyncCommand(
        syncKey: '789',
        collectionId: '5',
        clientCommands: [
          SyncDeleteItem(serverId: 'd1'),
          SyncDeleteItem(serverId: 'd2'),
        ],
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final commands = decoded.root
          .findChild('AirSync', 'Collections')!
          .findChild('AirSync', 'Collection')!
          .findChild('AirSync', 'Commands')!;

      final deletes = commands.findChildren('AirSync', 'Delete').toList();
      expect(deletes, hasLength(2));
      expect(deletes[0].childText('AirSync', 'ServerId'), equals('d1'));
      expect(deletes[1].childText('AirSync', 'ServerId'), equals('d2'));
    });

    test('SyncCommand with Conflict option', () {
      final cmd = SyncCommand(
        syncKey: '100',
        collectionId: '5',
        conflict: 1,
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final options = decoded.root
          .findChild('AirSync', 'Collections')!
          .findChild('AirSync', 'Collection')!
          .findChild('AirSync', 'Options')!;

      expect(options.childText('AirSync', 'Conflict'), equals('1'));
    });

    test('SyncCommand with MIMESupport option', () {
      final cmd = SyncCommand(
        syncKey: '100',
        collectionId: '5',
        mimeSupport: 2,
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final options = decoded.root
          .findChild('AirSync', 'Collections')!
          .findChild('AirSync', 'Collection')!
          .findChild('AirSync', 'Options')!;

      expect(options.childText('AirSync', 'MIMESupport'), equals('2'));
    });

    test('SyncCommand with Class element', () {
      final cmd = SyncCommand(
        syncKey: '100',
        collectionId: '5',
        className: 'Calendar',
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final collection = decoded.root
          .findChild('AirSync', 'Collections')!
          .findChild('AirSync', 'Collection')!;

      expect(collection.childText('AirSync', 'Class'), equals('Calendar'));
    });

    test('parseResponse parses Responses for Add', () {
      final responseDoc = WbxmlDocument(
        root: WbxmlElement(
          namespace: 'AirSync',
          tag: 'Sync',
          codePageIndex: 0,
          children: [
            WbxmlElement(
              namespace: 'AirSync',
              tag: 'Collections',
              codePageIndex: 0,
              children: [
                WbxmlElement(
                  namespace: 'AirSync',
                  tag: 'Collection',
                  codePageIndex: 0,
                  children: [
                    _text('AirSync', 'Status', '1', 0),
                    _text('AirSync', 'SyncKey', '200', 0),
                    WbxmlElement(
                      namespace: 'AirSync',
                      tag: 'Responses',
                      codePageIndex: 0,
                      children: [
                        WbxmlElement(
                          namespace: 'AirSync',
                          tag: 'Add',
                          codePageIndex: 0,
                          children: [
                            _text('AirSync', 'ClientId', 'c1', 0),
                            _text('AirSync', 'ServerId', 's99', 0),
                            _text('AirSync', 'Status', '1', 0),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      final cmd = SyncCommand(syncKey: '199', collectionId: '5');
      final bytes = encoder.encode(responseDoc);
      final decoded = decoder.decode(bytes);
      final result = cmd.parseResponse(decoded);

      expect(result.status, equals(1));
      expect(result.syncKey, equals('200'));
      expect(result.addResponses, hasLength(1));
      expect(result.addResponses.first.clientId, equals('c1'));
      expect(result.addResponses.first.serverId, equals('s99'));
      expect(result.addResponses.first.isSuccess, isTrue);
    });

    test('parseResponse parses Responses for Change and Delete', () {
      final responseDoc = WbxmlDocument(
        root: WbxmlElement(
          namespace: 'AirSync',
          tag: 'Sync',
          codePageIndex: 0,
          children: [
            WbxmlElement(
              namespace: 'AirSync',
              tag: 'Collections',
              codePageIndex: 0,
              children: [
                WbxmlElement(
                  namespace: 'AirSync',
                  tag: 'Collection',
                  codePageIndex: 0,
                  children: [
                    _text('AirSync', 'Status', '1', 0),
                    _text('AirSync', 'SyncKey', '201', 0),
                    WbxmlElement(
                      namespace: 'AirSync',
                      tag: 'Responses',
                      codePageIndex: 0,
                      children: [
                        WbxmlElement(
                          namespace: 'AirSync',
                          tag: 'Change',
                          codePageIndex: 0,
                          children: [
                            _text('AirSync', 'ServerId', 's1', 0),
                            _text('AirSync', 'Status', '1', 0),
                          ],
                        ),
                        WbxmlElement(
                          namespace: 'AirSync',
                          tag: 'Delete',
                          codePageIndex: 0,
                          children: [
                            _text('AirSync', 'ServerId', 's2', 0),
                            _text('AirSync', 'Status', '1', 0),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      final cmd = SyncCommand(syncKey: '200', collectionId: '5');
      final bytes = encoder.encode(responseDoc);
      final decoded = decoder.decode(bytes);
      final result = cmd.parseResponse(decoded);

      expect(result.changeResponses, hasLength(1));
      expect(result.changeResponses.first.serverId, equals('s1'));
      expect(result.changeResponses.first.isSuccess, isTrue);
      expect(result.deleteResponses, hasLength(1));
      expect(result.deleteResponses.first.serverId, equals('s2'));
    });

    test('SyncCommand initial sync (syncKey=0) has no Commands', () {
      final cmd = SyncCommand(
        syncKey: '0',
        collectionId: '5',
        clientCommands: [SyncDeleteItem(serverId: 'x')],
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final collection = decoded.root
          .findChild('AirSync', 'Collections')!
          .findChild('AirSync', 'Collection')!;

      // SyncKey=0 should not have Commands
      expect(collection.findChild('AirSync', 'Commands'), isNull);
      expect(collection.findChild('AirSync', 'Options'), isNull);
    });
  });
}

WbxmlElement _text(String ns, String tag, String text, int cp) {
  return WbxmlElement.withText(
    namespace: ns,
    tag: tag,
    text: text,
    codePageIndex: cp,
  );
}
