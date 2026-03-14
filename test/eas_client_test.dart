import 'package:eas_client/eas_client.dart';
import 'package:test/test.dart';

void main() {
  group('WBXML round-trip', () {
    late WbxmlEncoder encoder;
    late WbxmlDecoder decoder;

    setUp(() {
      encoder = WbxmlEncoder();
      decoder = WbxmlDecoder();
    });

    test('encode and decode simple element', () {
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

      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      expect(decoded.root.namespace, equals('FolderHierarchy'));
      expect(decoded.root.tag, equals('FolderSync'));
      expect(
        decoded.root.childText('FolderHierarchy', 'SyncKey'),
        equals('0'),
      );
    });

    test('encode and decode with namespace switching', () {
      final doc = WbxmlDocument(
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
                    WbxmlElement.withText(
                      namespace: 'AirSync',
                      tag: 'SyncKey',
                      text: '1234',
                      codePageIndex: 0,
                    ),
                    WbxmlElement.withText(
                      namespace: 'AirSync',
                      tag: 'CollectionId',
                      text: '5',
                      codePageIndex: 0,
                    ),
                    WbxmlElement(
                      namespace: 'AirSync',
                      tag: 'Options',
                      codePageIndex: 0,
                      children: [
                        WbxmlElement(
                          namespace: 'AirSyncBase',
                          tag: 'BodyPreference',
                          codePageIndex: 17,
                          children: [
                            WbxmlElement.withText(
                              namespace: 'AirSyncBase',
                              tag: 'Type',
                              text: '2',
                              codePageIndex: 17,
                            ),
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

      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      expect(decoded.root.namespace, equals('AirSync'));
      expect(decoded.root.tag, equals('Sync'));

      final collections =
          decoded.root.findChild('AirSync', 'Collections');
      expect(collections, isNotNull);

      final collection = collections!.findChild('AirSync', 'Collection');
      expect(collection, isNotNull);
      expect(collection!.childText('AirSync', 'SyncKey'), equals('1234'));

      final options = collection.findChild('AirSync', 'Options');
      expect(options, isNotNull);

      final bodyPref =
          options!.findChild('AirSyncBase', 'BodyPreference');
      expect(bodyPref, isNotNull);
      expect(bodyPref!.childText('AirSyncBase', 'Type'), equals('2'));
    });

    test('encode and decode empty element', () {
      final doc = WbxmlDocument(
        root: WbxmlElement(
          namespace: 'AirSync',
          tag: 'Sync',
          codePageIndex: 0,
        ),
      );

      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      expect(decoded.root.tag, equals('Sync'));
      expect(decoded.root.children, isEmpty);
      expect(decoded.root.text, isNull);
    });
  });

  group('CodePageRegistry', () {
    test('lookup by index', () {
      final registry = CodePageRegistry.instance;
      final airSync = registry.getByIndex(0);
      expect(airSync, isNotNull);
      expect(airSync!.namespace, equals('AirSync'));
    });

    test('lookup by namespace', () {
      final registry = CodePageRegistry.instance;
      final fh = registry.getByNamespace('FolderHierarchy');
      expect(fh, isNotNull);
      expect(fh!.pageIndex, equals(7));
    });

    test('all EAS code pages registered', () {
      final registry = CodePageRegistry.instance;
      expect(registry.getByIndex(0), isNotNull); // AirSync
      expect(registry.getByIndex(1), isNotNull); // Contacts
      expect(registry.getByIndex(2), isNotNull); // Email
      expect(registry.getByIndex(4), isNotNull); // Calendar
      expect(registry.getByIndex(5), isNotNull); // Move
      expect(registry.getByIndex(7), isNotNull); // FolderHierarchy
      expect(registry.getByIndex(14), isNotNull); // Provision
      expect(registry.getByIndex(17), isNotNull); // AirSyncBase
    });
  });

  group('mb_u_int32', () {
    test('encode and decode zero', () {
      _testMbUint32RoundTrip(0);
    });

    test('encode and decode small value', () {
      _testMbUint32RoundTrip(42);
    });

    test('encode and decode 127 (max single byte)', () {
      _testMbUint32RoundTrip(127);
    });

    test('encode and decode 128 (two bytes)', () {
      _testMbUint32RoundTrip(128);
    });

    test('encode and decode large value', () {
      _testMbUint32RoundTrip(16384);
    });
  });
}

/// Helper to test mb_u_int32 round-trip via a simple WBXML document.
void _testMbUint32RoundTrip(int value) {
  final text = value.toString();
  final doc = WbxmlDocument(
    root: WbxmlElement.withText(
      namespace: 'AirSync',
      tag: 'Status',
      text: text,
      codePageIndex: 0,
    ),
  );

  final bytes = WbxmlEncoder().encode(doc);
  final decoded = WbxmlDecoder().decode(bytes);
  expect(decoded.root.text, equals(text));
}
