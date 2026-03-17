import 'package:eas_client/eas_client.dart';
import 'package:test/test.dart';

void main() {
  late WbxmlEncoder encoder;
  late WbxmlDecoder decoder;

  setUp(() {
    encoder = WbxmlEncoder();
    decoder = WbxmlDecoder();
  });

  group('Ping with Class per folder', () {
    test('generates correct WBXML with different classes', () {
      final cmd = PingCommand(
        folders: [
          PingFolder(id: '1', className: 'Email'),
          PingFolder(id: '2', className: 'Calendar'),
          PingFolder(id: '3', className: 'Tasks'),
        ],
        heartbeatInterval: 120,
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final folders = decoded.root.findChild('Ping', 'Folders')!;
      final folderList = folders.findChildren('Ping', 'Folder').toList();

      expect(folderList, hasLength(3));
      expect(folderList[0].childText('Ping', 'Id'), equals('1'));
      expect(folderList[0].childText('Ping', 'Class'), equals('Email'));
      expect(folderList[1].childText('Ping', 'Id'), equals('2'));
      expect(folderList[1].childText('Ping', 'Class'), equals('Calendar'));
      expect(folderList[2].childText('Ping', 'Id'), equals('3'));
      expect(folderList[2].childText('Ping', 'Class'), equals('Tasks'));
    });

    test('PingCommand.fromIds defaults to Email class', () {
      final cmd = PingCommand.fromIds(folderIds: ['a', 'b']);

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final folderList = decoded.root
          .findChild('Ping', 'Folders')!
          .findChildren('Ping', 'Folder')
          .toList();

      expect(folderList[0].childText('Ping', 'Class'), equals('Email'));
      expect(folderList[1].childText('Ping', 'Class'), equals('Email'));
    });
  });

  group('GetItemEstimate with FilterType and Class', () {
    test('generates Options with Class and FilterType', () {
      final cmd = GetItemEstimateCommand.single(
        collectionId: '5',
        syncKey: '100',
        filterType: 3,
        className: 'Email',
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final collection = decoded.root
          .findChild('GetItemEstimate', 'Collections')!
          .findChild('GetItemEstimate', 'Collection')!;

      final options = collection.findChild('GetItemEstimate', 'Options');
      expect(options, isNotNull);
      expect(options!.childText('AirSync', 'Class'), equals('Email'));
      expect(options.childText('AirSync', 'FilterType'), equals('3'));
    });

    test('no Options when filterType and className are null', () {
      final cmd = GetItemEstimateCommand.single(
        collectionId: '5',
        syncKey: '100',
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final collection = decoded.root
          .findChild('GetItemEstimate', 'Collections')!
          .findChild('GetItemEstimate', 'Collection')!;

      expect(collection.findChild('GetItemEstimate', 'Options'), isNull);
    });
  });

  group('GAL Search', () {
    test('generates correct Store=GAL request', () {
      final cmd = GalSearchCommand(query: 'john', rangeEnd: 19);

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final store = decoded.root.findChild('Search', 'Store')!;
      expect(store.childText('Search', 'Name'), equals('GAL'));

      final query = store.findChild('Search', 'Query')!;
      expect(query.childText('Search', 'FreeText'), equals('john'));

      final options = store.findChild('Search', 'Options')!;
      expect(options.childText('Search', 'Range'), equals('0-19'));
    });

    test('parses GAL response', () {
      final responseDoc = WbxmlDocument(
        root: WbxmlElement(
          namespace: 'Search',
          tag: 'Search',
          codePageIndex: 15,
          children: [
            _text('Search', 'Status', '1', 15),
            WbxmlElement(
              namespace: 'Search',
              tag: 'Response',
              codePageIndex: 15,
              children: [
                WbxmlElement(
                  namespace: 'Search',
                  tag: 'Store',
                  codePageIndex: 15,
                  children: [
                    _text('Search', 'Total', '2', 15),
                    WbxmlElement(
                      namespace: 'Search',
                      tag: 'Result',
                      codePageIndex: 15,
                      children: [
                        WbxmlElement(
                          namespace: 'Search',
                          tag: 'Properties',
                          codePageIndex: 15,
                          children: [
                            _text('GAL', 'DisplayName', 'John Doe', 16),
                            _text('GAL', 'EmailAddress', 'john@test.com', 16),
                            _text('GAL', 'Company', 'Acme', 16),
                            _text('GAL', 'Title', 'Engineer', 16),
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

      final cmd = GalSearchCommand(query: 'john');
      final bytes = encoder.encode(responseDoc);
      final decoded = decoder.decode(bytes);
      final result = cmd.parseResponse(decoded);

      expect(result.status, equals(1));
      expect(result.total, equals(2));
      expect(result.entries, hasLength(1));
      expect(result.entries.first.displayName, equals('John Doe'));
      expect(result.entries.first.emailAddress, equals('john@test.com'));
      expect(result.entries.first.company, equals('Acme'));
      expect(result.entries.first.title, equals('Engineer'));
    });
  });

  group('Find command', () {
    test('generates correct GAL Find request', () {
      final cmd = FindCommand(
        query: 'smith',
        rangeEnd: 49,
        requestPicture: true,
        maxPictureSize: 5120,
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      expect(decoded.root.childText('Find', 'SearchId'), equals('GAL'));

      final exec = decoded.root.findChild('Find', 'ExecuteSearch')!;
      final criterion = exec.findChild('Find', 'GALSearchCriterion')!;
      expect(criterion.childText('Find', 'Query'), equals('smith'));

      final options = exec.findChild('Find', 'Options')!;
      expect(options.childText('Find', 'Range'), equals('0-49'));
      expect(options.findChild('AirSyncBase', 'Picture'), isNotNull);
    });

    test('parses Find response', () {
      final responseDoc = WbxmlDocument(
        root: WbxmlElement(
          namespace: 'Find',
          tag: 'Find',
          codePageIndex: 25,
          children: [
            _text('Find', 'Status', '1', 25),
            WbxmlElement(
              namespace: 'Find',
              tag: 'Response',
              codePageIndex: 25,
              children: [
                _text('Find', 'Total', '1', 25),
                WbxmlElement(
                  namespace: 'Find',
                  tag: 'Result',
                  codePageIndex: 25,
                  children: [
                    WbxmlElement(
                      namespace: 'Find',
                      tag: 'Properties',
                      codePageIndex: 25,
                      children: [
                        _text('GAL', 'DisplayName', 'Alice Smith', 16),
                        _text('GAL', 'EmailAddress', 'alice@test.com', 16),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      final cmd = FindCommand(query: 'alice');
      final bytes = encoder.encode(responseDoc);
      final decoded = decoder.decode(bytes);
      final result = cmd.parseResponse(decoded);

      expect(result.status, equals(1));
      expect(result.total, equals(1));
      expect(result.entries, hasLength(1));
      expect(result.entries.first.displayName, equals('Alice Smith'));
      expect(result.entries.first.emailAddress, equals('alice@test.com'));
    });
  });

  group('Notes Code Page 23', () {
    test('Notes registered at CP 23, not CP 3', () {
      final registry = CodePageRegistry.instance;
      final notesCp = registry.getByNamespace('Notes');
      expect(notesCp, isNotNull);
      expect(notesCp!.pageIndex, equals(23));

      // CP 3 should be unregistered (AirNotify deprecated)
      expect(registry.getByIndex(3), isNull);
    });

    test('Notes WBXML round-trip at CP 23', () {
      final doc = WbxmlDocument(
        root: WbxmlElement(
          namespace: 'AirSync',
          tag: 'Sync',
          codePageIndex: 0,
          children: [
            WbxmlElement.withText(
              namespace: 'Notes',
              tag: 'Subject',
              text: 'Test note',
              codePageIndex: 23,
            ),
          ],
        ),
      );

      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);
      expect(decoded.root.childText('Notes', 'Subject'), equals('Test note'));
    });
  });

  group('Contacts2 Code Page 12', () {
    test('Contacts2 registered at CP 12', () {
      final registry = CodePageRegistry.instance;
      final cp = registry.getByIndex(12);
      expect(cp, isNotNull);
      expect(cp!.namespace, equals('Contacts2'));
    });

    test('Contacts2 WBXML round-trip', () {
      final doc = WbxmlDocument(
        root: WbxmlElement(
          namespace: 'AirSync',
          tag: 'Sync',
          codePageIndex: 0,
          children: [
            WbxmlElement.withText(
              namespace: 'Contacts2',
              tag: 'IMAddress',
              text: 'user@im.test',
              codePageIndex: 12,
            ),
          ],
        ),
      );

      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);
      expect(decoded.root.childText('Contacts2', 'IMAddress'),
          equals('user@im.test'));
    });
  });

  group('New Code Pages registration', () {
    test('all 26 code pages registered', () {
      final registry = CodePageRegistry.instance;
      final expected = {
        0: 'AirSync',
        1: 'Contacts',
        2: 'Email',
        4: 'Calendar',
        5: 'Move',
        6: 'GetItemEstimate',
        7: 'FolderHierarchy',
        8: 'MeetingResponse',
        9: 'Tasks',
        10: 'ResolveRecipients',
        11: 'ValidateCert',
        12: 'Contacts2',
        13: 'Ping',
        14: 'Provision',
        15: 'Search',
        16: 'GAL',
        17: 'AirSyncBase',
        18: 'Settings',
        19: 'DocumentLibrary',
        20: 'ItemOperations',
        21: 'ComposeMail',
        22: 'Email2',
        23: 'Notes',
        24: 'RightsManagement',
        25: 'Find',
      };

      for (final entry in expected.entries) {
        final cp = registry.getByIndex(entry.key);
        expect(cp, isNotNull,
            reason: 'Code page ${entry.key} (${entry.value}) not found');
        expect(cp!.namespace, equals(entry.value),
            reason: 'CP ${entry.key} namespace mismatch');
      }
    });
  });

  group('Serializers', () {
    test('EmailSerializer.serializeReadFlag', () {
      final appData = EmailSerializer.serializeReadFlag(true);
      final doc = WbxmlDocument(root: appData);
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      expect(decoded.root.childText('Email', 'Read'), equals('1'));
    });

    test('EmailSerializer.serializeFlag', () {
      final appData = EmailSerializer.serializeFlag(2);
      final doc = WbxmlDocument(root: appData);
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final flag = decoded.root.findChild('Email', 'Flag')!;
      expect(flag.childText('Email', 'Status'), equals('2'));
    });

    test('CalendarSerializer round-trip', () {
      final event = EasCalendarEvent(
        serverId: '',
        subject: 'Meeting',
        startTime: DateTime.utc(2026, 3, 16, 10),
        endTime: DateTime.utc(2026, 3, 16, 11),
        location: 'Room A',
        allDayEvent: false,
        busyStatus: 2,
        sensitivity: 0,
        meetingStatus: 1,
        attendees: [
          EasAttendee(email: 'bob@test.com', name: 'Bob'),
        ],
        categories: ['Work'],
        recurrence: EasRecurrence(type: 1, interval: 1, dayOfWeek: 2),
      );

      final appData = CalendarSerializer.serialize(event);
      final doc = WbxmlDocument(root: appData);
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      expect(decoded.root.childText('Calendar', 'Subject'), equals('Meeting'));
      expect(decoded.root.childText('Calendar', 'Location'), equals('Room A'));
      expect(decoded.root.childText('Calendar', 'MeetingStatus'), equals('1'));

      final attendees = decoded.root.findChild('Calendar', 'Attendees')!;
      final att = attendees.findChild('Calendar', 'Attendee')!;
      expect(att.childText('Calendar', 'Email'), equals('bob@test.com'));

      final rec = decoded.root.findChild('Calendar', 'Recurrence')!;
      expect(rec.childText('Calendar', 'Type'), equals('1'));
      expect(rec.childText('Calendar', 'DayOfWeek'), equals('2'));
    });

    test('ContactSerializer with Contacts2 fields round-trip', () {
      final contact = EasContact(
        serverId: '',
        firstName: 'Jane',
        lastName: 'Doe',
        email1: 'jane@test.com',
        imAddress: 'jane@im.test',
        companyMainPhone: '+1555000',
        managerName: 'Boss',
      );

      final appData = ContactSerializer.serialize(contact);
      final doc = WbxmlDocument(root: appData);
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      expect(decoded.root.childText('Contacts', 'FirstName'), equals('Jane'));
      expect(decoded.root.childText('Contacts', 'Email1Address'),
          equals('jane@test.com'));
      expect(decoded.root.childText('Contacts2', 'IMAddress'),
          equals('jane@im.test'));
      expect(decoded.root.childText('Contacts2', 'CompanyMainPhone'),
          equals('+1555000'));
    });

    test('TaskSerializer round-trip', () {
      final task = EasTask(
        serverId: '',
        subject: 'Do stuff',
        complete: false,
        importance: 2,
        dueDate: DateTime.utc(2026, 3, 20),
        categories: ['Personal'],
      );

      final appData = TaskSerializer.serialize(task);
      final doc = WbxmlDocument(root: appData);
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      expect(decoded.root.childText('Tasks', 'Subject'), equals('Do stuff'));
      expect(decoded.root.childText('Tasks', 'Complete'), equals('0'));
      expect(decoded.root.childText('Tasks', 'Importance'), equals('2'));
    });

    test('NoteSerializer round-trip', () {
      final note = EasNote(
        serverId: '',
        subject: 'My note',
        body: 'Content here',
        categories: ['Ideas'],
      );

      final appData = NoteSerializer.serialize(note);
      final doc = WbxmlDocument(root: appData);
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      expect(decoded.root.childText('Notes', 'Subject'), equals('My note'));
      expect(decoded.root.childText('Notes', 'MessageClass'),
          equals('IPM.StickyNote'));

      final body = decoded.root.findChild('AirSyncBase', 'Body')!;
      expect(body.childText('AirSyncBase', 'Data'), equals('Content here'));
    });
  });

  group('Search customization', () {
    test('Search with custom bodyType and truncation', () {
      final cmd = SearchCommand(
        query: 'test',
        bodyType: 1,
        bodyTruncationSize: 256,
        rebuildResults: true,
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final store = decoded.root.findChild('Search', 'Store')!;
      final options = store.findChild('Search', 'Options')!;
      final bodyPref = options.findChild('AirSyncBase', 'BodyPreference')!;

      expect(bodyPref.childText('AirSyncBase', 'Type'), equals('1'));
      expect(
          bodyPref.childText('AirSyncBase', 'TruncationSize'), equals('256'));
      expect(options.findChild('Search', 'RebuildResults'), isNotNull);
    });
  });

  group('ResolveRecipients availability', () {
    test('generates Availability in Options', () {
      final cmd = ResolveRecipientsCommand(
        recipients: ['test@example.com'],
        availabilityStartTime: DateTime.utc(2026, 3, 16),
        availabilityEndTime: DateTime.utc(2026, 3, 17),
        certificateRetrieval: 2,
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final options =
          decoded.root.findChild('ResolveRecipients', 'Options')!;
      final avail = options.findChild('ResolveRecipients', 'Availability')!;
      expect(avail.childText('ResolveRecipients', 'StartTime'), isNotNull);
      expect(avail.childText('ResolveRecipients', 'EndTime'), isNotNull);
      expect(options.childText('ResolveRecipients', 'CertificateRetrieval'),
          equals('2'));
    });

    test('parses mergedFreeBusy in response', () {
      final responseDoc = WbxmlDocument(
        root: WbxmlElement(
          namespace: 'ResolveRecipients',
          tag: 'ResolveRecipients',
          codePageIndex: 10,
          children: [
            WbxmlElement(
              namespace: 'ResolveRecipients',
              tag: 'Response',
              codePageIndex: 10,
              children: [
                _text('ResolveRecipients', 'To', 'user@test.com', 10),
                _text('ResolveRecipients', 'Status', '1', 10),
                WbxmlElement(
                  namespace: 'ResolveRecipients',
                  tag: 'Recipient',
                  codePageIndex: 10,
                  children: [
                    _text('ResolveRecipients', 'Type', '1', 10),
                    _text('ResolveRecipients', 'DisplayName', 'User', 10),
                    _text('ResolveRecipients', 'EmailAddress',
                        'user@test.com', 10),
                    WbxmlElement(
                      namespace: 'ResolveRecipients',
                      tag: 'Availability',
                      codePageIndex: 10,
                      children: [
                        _text('ResolveRecipients', 'MergedFreeBusy',
                            '0022001100', 10),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );

      final cmd = ResolveRecipientsCommand(recipients: ['user@test.com']);
      final bytes = encoder.encode(responseDoc);
      final decoded = decoder.decode(bytes);
      final results = cmd.parseResponse(decoded);

      expect(results, hasLength(1));
      expect(results.first.recipients, hasLength(1));
      expect(results.first.recipients.first.mergedFreeBusy,
          equals('0022001100'));
    });
  });

  group('BatchFetchEmailBodies', () {
    test('generates multiple Fetch elements', () {
      final cmd = BatchFetchEmailBodiesCommand(
        items: [
          (serverId: 's1', collectionId: '5'),
          (serverId: 's2', collectionId: '5'),
        ],
      );

      final doc = cmd.buildRequest();
      final bytes = encoder.encode(doc);
      final decoded = decoder.decode(bytes);

      final fetches =
          decoded.root.findChildren('ItemOperations', 'Fetch').toList();
      expect(fetches, hasLength(2));
      expect(fetches[0].childText('AirSync', 'ServerId'), equals('s1'));
      expect(fetches[1].childText('AirSync', 'ServerId'), equals('s2'));
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
