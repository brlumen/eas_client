import 'package:eas_client/eas_client.dart';
import 'package:test/test.dart';

void main() {
  late WbxmlEncoder encoder;
  late WbxmlDecoder decoder;

  setUp(() {
    encoder = WbxmlEncoder();
    decoder = WbxmlDecoder();
  });

  group('Calendar recurrence parsing', () {
    test('parses recurrence from Sync response', () {
      final syncResponse = _buildSyncResponse(
        contentChildren: [
          _addCommand('s1', _calendarAppData(
            subject: 'Weekly standup',
            startTime: '2026-03-16T10:00:00Z',
            endTime: '2026-03-16T10:30:00Z',
            recurrence: WbxmlElement(
              namespace: 'Calendar',
              tag: 'Recurrence',
              codePageIndex: 4,
              children: [
                _text('Calendar', 'Type', '1', 4), // weekly
                _text('Calendar', 'Interval', '1', 4),
                _text('Calendar', 'DayOfWeek', '2', 4), // Monday
                _text('Calendar', 'Occurrences', '52', 4),
              ],
            ),
          )),
        ],
      );

      final cmd = SyncCommand(
        syncKey: '1',
        collectionId: '10',
        contentType: SyncContentType.calendar,
      );
      final bytes = encoder.encode(syncResponse);
      final decoded = decoder.decode(bytes);
      final result = cmd.parseResponse(decoded);

      expect(result.addedCalendarEvents, hasLength(1));
      final event = result.addedCalendarEvents.first;
      expect(event.subject, equals('Weekly standup'));
      expect(event.recurrence, isNotNull);
      expect(event.recurrence!.type, equals(1));
      expect(event.recurrence!.interval, equals(1));
      expect(event.recurrence!.dayOfWeek, equals(2));
      expect(event.recurrence!.occurrences, equals(52));
    });

    test('parses exceptions from Sync response', () {
      final syncResponse = _buildSyncResponse(
        contentChildren: [
          _addCommand('s2', _calendarAppDataWithExceptions()),
        ],
      );

      final cmd = SyncCommand(
        syncKey: '1',
        collectionId: '10',
        contentType: SyncContentType.calendar,
      );
      final bytes = encoder.encode(syncResponse);
      final decoded = decoder.decode(bytes);
      final result = cmd.parseResponse(decoded);

      expect(result.addedCalendarEvents, hasLength(1));
      final event = result.addedCalendarEvents.first;
      expect(event.exceptions, hasLength(1));
      expect(event.exceptions.first.deleted, isTrue);
      expect(event.exceptions.first.exceptionStartTime, isNotNull);
    });

    test('parses new calendar fields', () {
      final syncResponse = _buildSyncResponse(
        contentChildren: [
          _addCommand('s3', WbxmlElement(
            namespace: 'AirSync',
            tag: 'ApplicationData',
            codePageIndex: 0,
            children: [
              _text('Calendar', 'Subject', 'Meeting', 4),
              _text('Calendar', 'Timezone', 'dGVzdA==', 4),
              _text('Calendar', 'DtStamp', '2026-03-16T08:00:00Z', 4),
              _text('Calendar', 'ResponseType', '3', 4),
              _text('Calendar', 'DisallowNewTimeProposal', '1', 4),
              _text('Calendar', 'OnlineMeetingConfLink', 'https://teams.test/meet', 4),
            ],
          )),
        ],
      );

      final cmd = SyncCommand(
        syncKey: '1',
        collectionId: '10',
        contentType: SyncContentType.calendar,
      );
      final bytes = encoder.encode(syncResponse);
      final decoded = decoder.decode(bytes);
      final result = cmd.parseResponse(decoded);

      final event = result.addedCalendarEvents.first;
      expect(event.timezone, equals('dGVzdA=='));
      expect(event.dtStamp, isNotNull);
      expect(event.responseType, equals(3));
      expect(event.disallowNewTimeProposal, isTrue);
      expect(event.onlineMeetingConfLink, equals('https://teams.test/meet'));
    });
  });

  group('Email extended fields parsing', () {
    test('parses categories, contentClass, sensitivity', () {
      final syncResponse = _buildSyncResponse(
        contentChildren: [
          _addCommand('e1', WbxmlElement(
            namespace: 'AirSync',
            tag: 'ApplicationData',
            codePageIndex: 0,
            children: [
              _text('Email', 'Subject', 'Test', 2),
              _text('Email', 'ContentClass', 'urn:content-classes:message', 2),
              _text('Email', 'Sensitivity', '2', 2),
              _text('Email', 'InternetCPID', '65001', 2),
              WbxmlElement(
                namespace: 'Email',
                tag: 'Categories',
                codePageIndex: 2,
                children: [
                  _text('Email', 'Category', 'Work', 2),
                  _text('Email', 'Category', 'Important', 2),
                ],
              ),
              _text('Email2', 'LastVerbExecuted', '2', 22),
              _text('Email2', 'ReceivedAsBcc', '1', 22),
            ],
          )),
        ],
      );

      final cmd = SyncCommand(
        syncKey: '1',
        collectionId: '5',
        contentType: SyncContentType.email,
      );
      final bytes = encoder.encode(syncResponse);
      final decoded = decoder.decode(bytes);
      final result = cmd.parseResponse(decoded);

      final email = result.addedEmails.first;
      expect(email.contentClass, equals('urn:content-classes:message'));
      expect(email.sensitivity, equals(2));
      expect(email.internetCPID, equals(65001));
      expect(email.categories, equals(['Work', 'Important']));
      expect(email.lastVerbExecuted, equals(2));
      expect(email.receivedAsBcc, isTrue);
    });
  });

  group('Contact Contacts2 fields parsing', () {
    test('parses Contacts2 fields', () {
      final syncResponse = _buildSyncResponse(
        contentChildren: [
          _addCommand('c1', WbxmlElement(
            namespace: 'AirSync',
            tag: 'ApplicationData',
            codePageIndex: 0,
            children: [
              _text('Contacts', 'FirstName', 'John', 1),
              _text('Contacts', 'LastName', 'Doe', 1),
              _text('Contacts', 'Title', 'Mr.', 1),
              _text('Contacts', 'Suffix', 'Jr.', 1),
              _text('Contacts', 'Picture', 'base64data', 1),
              _text('Contacts2', 'IMAddress', 'john@im.test', 12),
              _text('Contacts2', 'CompanyMainPhone', '+1234567890', 12),
              _text('Contacts2', 'ManagerName', 'Jane Boss', 12),
              _text('Contacts2', 'CustomerId', 'CUST-001', 12),
            ],
          )),
        ],
      );

      final cmd = SyncCommand(
        syncKey: '1',
        collectionId: '7',
        contentType: SyncContentType.contact,
      );
      final bytes = encoder.encode(syncResponse);
      final decoded = decoder.decode(bytes);
      final result = cmd.parseResponse(decoded);

      final contact = result.addedContacts.first;
      expect(contact.firstName, equals('John'));
      expect(contact.lastName, equals('Doe'));
      expect(contact.title, equals('Mr.'));
      expect(contact.suffix, equals('Jr.'));
      expect(contact.picture, equals('base64data'));
      expect(contact.imAddress, equals('john@im.test'));
      expect(contact.companyMainPhone, equals('+1234567890'));
      expect(contact.managerName, equals('Jane Boss'));
      expect(contact.customerId, equals('CUST-001'));
    });
  });

  group('Task recurrence parsing', () {
    test('parses task with recurrence', () {
      final syncResponse = _buildSyncResponse(
        contentChildren: [
          _addCommand('t1', WbxmlElement(
            namespace: 'AirSync',
            tag: 'ApplicationData',
            codePageIndex: 0,
            children: [
              _text('Tasks', 'Subject', 'Weekly report', 9),
              _text('Tasks', 'Complete', '0', 9),
              _text('Tasks', 'OrdinalDate', '2026-03-16', 9),
              WbxmlElement(
                namespace: 'Tasks',
                tag: 'Recurrence',
                codePageIndex: 9,
                children: [
                  _text('Tasks', 'Type', '1', 9),
                  _text('Tasks', 'Interval', '1', 9),
                  _text('Tasks', 'DayOfWeek', '32', 9),
                ],
              ),
            ],
          )),
        ],
      );

      final cmd = SyncCommand(
        syncKey: '1',
        collectionId: '8',
        contentType: SyncContentType.task,
      );
      final bytes = encoder.encode(syncResponse);
      final decoded = decoder.decode(bytes);
      final result = cmd.parseResponse(decoded);

      final task = result.addedTasks.first;
      expect(task.subject, equals('Weekly report'));
      expect(task.ordinalDate, equals('2026-03-16'));
      expect(task.recurrence, isNotNull);
      expect(task.recurrence!.type, equals(1));
      expect(task.recurrence!.dayOfWeek, equals(32));
    });
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────

WbxmlElement _text(String ns, String tag, String text, int cp) {
  return WbxmlElement.withText(
    namespace: ns,
    tag: tag,
    text: text,
    codePageIndex: cp,
  );
}

WbxmlElement _addCommand(String serverId, WbxmlElement appData) {
  return WbxmlElement(
    namespace: 'AirSync',
    tag: 'Add',
    codePageIndex: 0,
    children: [
      _text('AirSync', 'ServerId', serverId, 0),
      appData,
    ],
  );
}

WbxmlDocument _buildSyncResponse({
  required List<WbxmlElement> contentChildren,
  String status = '1',
  String syncKey = '2',
}) {
  return WbxmlDocument(
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
                _text('AirSync', 'Status', status, 0),
                _text('AirSync', 'SyncKey', syncKey, 0),
                WbxmlElement(
                  namespace: 'AirSync',
                  tag: 'Commands',
                  codePageIndex: 0,
                  children: contentChildren,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

WbxmlElement _calendarAppData({
  required String subject,
  required String startTime,
  required String endTime,
  WbxmlElement? recurrence,
}) {
  return WbxmlElement(
    namespace: 'AirSync',
    tag: 'ApplicationData',
    codePageIndex: 0,
    children: [
      _text('Calendar', 'Subject', subject, 4),
      _text('Calendar', 'StartTime', startTime, 4),
      _text('Calendar', 'EndTime', endTime, 4),
      if (recurrence != null) recurrence,
    ],
  );
}

WbxmlElement _calendarAppDataWithExceptions() {
  return WbxmlElement(
    namespace: 'AirSync',
    tag: 'ApplicationData',
    codePageIndex: 0,
    children: [
      _text('Calendar', 'Subject', 'Recurring', 4),
      WbxmlElement(
        namespace: 'Calendar',
        tag: 'Exceptions',
        codePageIndex: 4,
        children: [
          WbxmlElement(
            namespace: 'Calendar',
            tag: 'Exception',
            codePageIndex: 4,
            children: [
              _text('Calendar', 'ExceptionStartTime', '2026-03-23T10:00:00Z', 4),
              _text('Calendar', 'Deleted', '1', 4),
            ],
          ),
        ],
      ),
    ],
  );
}
