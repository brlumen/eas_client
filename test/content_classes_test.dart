import 'dart:convert';
import 'dart:typed_data';

import 'package:eas_client/eas_client.dart';
import 'package:test/test.dart';

const _pages = {
  'AirSync': 0,
  'Contacts': 1,
  'Email': 2,
  'Calendar': 4,
  'MeetingResponse': 8,
  'Tasks': 9,
  'Contacts2': 12,
  'AirSyncBase': 17,
  'ComposeMail': 21,
  'Email2': 22,
  'Notes': 23,
  'RightsManagement': 24,
};

/// `_e('Ns:Tag', 'text' | [children] | Uint8List | null)`.
WbxmlElement _e(String qname, [Object? content]) {
  final [ns, tag] = qname.split(':');
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
    Uint8List bytes => WbxmlElement(
      namespace: ns,
      tag: tag,
      codePageIndex: page,
      opaque: bytes,
    ),
    _ => WbxmlElement(namespace: ns, tag: tag, codePageIndex: page),
  };
}

WbxmlElement _rt(WbxmlElement root) => WbxmlDecoder()
    .decode(WbxmlEncoder().encode(WbxmlDocument(root: root)))
    .root;

WbxmlDocument _syncResponse(
  List<WbxmlElement> commands, {
  List<WbxmlElement> responses = const [],
  String collectionId = '1',
}) => WbxmlDocument(
  root: _rt(
    _e('AirSync:Sync', [
      _e('AirSync:Collections', [
        _e('AirSync:Collection', [
          _e('AirSync:SyncKey', '2'),
          _e('AirSync:CollectionId', collectionId),
          _e('AirSync:Status', '1'),
          if (commands.isNotEmpty) _e('AirSync:Commands', commands),
          if (responses.isNotEmpty) _e('AirSync:Responses', responses),
        ]),
      ]),
    ]),
  ),
);

WbxmlElement _add(String serverId, List<WbxmlElement> data, {String? cls}) =>
    _e('AirSync:Add', [
      _e('AirSync:ServerId', serverId),
      if (cls != null) _e('AirSync:Class', cls),
      _e('AirSync:ApplicationData', data),
    ]);

WbxmlElement _collection(WbxmlDocument doc) => doc.root
    .findChild('AirSync', 'Collections')!
    .findChild('AirSync', 'Collection')!;

WbxmlElement _request(EasCommand<Object?> cmd) => _rt(cmd.buildRequest().root);

void main() {
  group('Email parsing (MS-ASEMAIL, MS-ASRM)', () {
    test('parses every Email/Email2/AirSyncBase/RM element', () {
      final convId = Uint8List.fromList([1, 2, 3, 250]);
      final doc = _syncResponse([
        _add('m1', [
          _e('Email:To', 'a@x.com'),
          _e('Email:Cc', 'b@x.com'),
          _e('Email:From', 'c@x.com'),
          _e('Email:Subject', 'Hi'),
          _e('Email:ReplyTo', 'r@x.com'),
          _e('Email:DateReceived', '2026-01-02T03:04:05.000Z'),
          _e('Email:DisplayTo', 'A'),
          _e('Email:ThreadTopic', 'Topic'),
          _e('Email:Importance', '2'),
          _e('Email:Read', '1'),
          _e('Email:MessageClass', 'IPM.Note'),
          _e('Email:InternetCPID', '65001'),
          _e('Email:ContentClass', 'urn:content-classes:message'),
          _e('Email:Categories', [_e('Email:Category', 'Red')]),
          _e('Email:Flag', [
            _e('Tasks:Subject', 'Follow'),
            _e('Email:Status', '2'),
            _e('Email:FlagType', 'Follow up'),
            _e('Tasks:StartDate', '2026-01-03T00:00:00.000Z'),
            _e('Tasks:UtcStartDate', '2026-01-03T00:00:00.000Z'),
            _e('Tasks:DueDate', '2026-01-04T00:00:00.000Z'),
            _e('Tasks:UtcDueDate', '2026-01-04T00:00:00.000Z'),
            _e('Tasks:ReminderSet', '1'),
            _e('Tasks:ReminderTime', '2026-01-03T09:00:00.000Z'),
            _e('Tasks:OrdinalDate', '2026-01-01T00:00:00.000Z'),
            _e('Tasks:SubOrdinalDate', '5'),
          ]),
          _e('AirSyncBase:Body', [
            _e('AirSyncBase:Type', '2'),
            _e('AirSyncBase:EstimatedDataSize', '1000'),
            _e('AirSyncBase:Truncated', '1'),
            _e('AirSyncBase:Data', '<p>x</p>'),
            _e('AirSyncBase:Preview', 'x'),
          ]),
          _e('AirSyncBase:BodyPart', [
            _e('AirSyncBase:Status', '1'),
            _e('AirSyncBase:Type', '2'),
            _e('AirSyncBase:EstimatedDataSize', '10'),
            _e('AirSyncBase:Data', 'part'),
            _e('AirSyncBase:Preview', 'p'),
          ]),
          _e('AirSyncBase:NativeBodyType', '2'),
          _e('AirSyncBase:Attachments', [
            _e('AirSyncBase:Attachment', [
              _e('AirSyncBase:DisplayName', 'v.wav'),
              _e('AirSyncBase:FileReference', 'ref1'),
              _e('AirSyncBase:Method', '1'),
              _e('AirSyncBase:EstimatedDataSize', '4096'),
              _e('AirSyncBase:ContentId', 'cid'),
              _e('AirSyncBase:ContentLocation', 'loc'),
              _e('AirSyncBase:IsInline', '1'),
              _e('Email2:UmAttDuration', '12'),
              _e('Email2:UmAttOrder', '1'),
            ]),
          ]),
          _e('Email2:UmCallerID', '+100'),
          _e('Email2:UmUserNotes', 'note'),
          _e('Email2:ConversationId', convId),
          _e('Email2:ConversationIndex', Uint8List.fromList([9, 9])),
          _e('Email2:LastVerbExecuted', '2'),
          _e('Email2:LastVerbExecutionTime', '2026-01-05T00:00:00.000Z'),
          _e('Email2:ReceivedAsBcc', '1'),
          _e('Email2:Sender', 's@x.com'),
          _e('Email2:AccountId', 'acc'),
          _e('Email2:IsDraft', '0'),
          _e('Email2:Bcc', 'd@x.com'),
          _e('RightsManagement:RightsManagementLicense', [
            _e('RightsManagement:EditAllowed', '1'),
            _e('RightsManagement:ReplyAllowed', '1'),
            _e('RightsManagement:ReplyAllAllowed', '0'),
            _e('RightsManagement:ForwardAllowed', '1'),
            _e('RightsManagement:ModifyRecipientsAllowed', '0'),
            _e('RightsManagement:ExtractAllowed', '1'),
            _e('RightsManagement:PrintAllowed', '1'),
            _e('RightsManagement:ExportAllowed', '0'),
            _e('RightsManagement:ProgrammaticAccessAllowed', '1'),
            _e('RightsManagement:Owner', '1'),
            _e(
              'RightsManagement:ContentExpiryDate',
              '2027-01-01T00:00:00.000Z',
            ),
            _e('RightsManagement:TemplateID', 'tid'),
            _e('RightsManagement:TemplateName', 'Do Not Forward'),
            _e('RightsManagement:TemplateDescription', 'desc'),
            _e('RightsManagement:ContentOwner', 'o@x.com'),
          ]),
        ]),
      ]);
      final r = SyncCommand(syncKey: '1', collectionId: '1').parseResponse(doc);
      final m = r.addedEmails.single;

      expect(m.to, 'a@x.com');
      expect(m.cc, 'b@x.com');
      expect(m.bcc, 'd@x.com');
      expect(m.replyTo, 'r@x.com');
      expect(m.dateReceived, DateTime.utc(2026, 1, 2, 3, 4, 5));
      expect(m.importance, EmailImportance.high);
      expect(m.read, isTrue);
      expect(m.internetCPID, 65001);
      expect(m.categories, ['Red']);
      expect(m.flagStatus, 2);
      expect(m.flag!.flagType, 'Follow up');
      expect(m.flag!.subject, 'Follow');
      expect(m.flag!.utcDueDate, DateTime.utc(2026, 1, 4));
      expect(m.flag!.reminderSet, isTrue);
      expect(m.flag!.subOrdinalDate, '5');
      expect(m.body, '<p>x</p>');
      expect(m.bodyType, 2);
      expect(m.bodyTruncated, isTrue);
      expect(m.estimatedBodySize, 1000);
      expect(m.bodyDetails!.preview, 'x');
      expect(m.bodyPart!.data, 'part');
      expect(m.bodyPart!.preview, 'p');
      expect(m.nativeBodyType, 2);
      final att = m.attachments.single;
      expect(att.estimatedSize, 4096);
      expect(att.contentLocation, 'loc');
      expect(att.isInline, isTrue);
      expect(att.umAttDuration, 12);
      expect(att.umAttOrder, 1);
      expect(m.umCallerId, '+100');
      expect(m.umUserNotes, 'note');
      expect(m.conversationId, base64.encode(convId));
      expect(m.conversationIndex, [9, 9]);
      expect(m.lastVerbExecuted, 2);
      expect(m.receivedAsBcc, isTrue);
      expect(m.sender, 's@x.com');
      expect(m.accountId, 'acc');
      expect(m.isDraft, isFalse);

      final rm = m.rightsManagementLicense!;
      expect(rm.editAllowed, isTrue);
      expect(rm.replyAllAllowed, isFalse);
      expect(rm.forwardAllowed, isTrue);
      expect(rm.exportAllowed, isFalse);
      expect(rm.programmaticAccessAllowed, isTrue);
      expect(rm.owner, isTrue);
      expect(rm.contentExpiryDate, DateTime.utc(2027));
      expect(rm.templateId, 'tid');
      expect(rm.templateName, 'Do Not Forward');
      expect(rm.templateDescription, 'desc');
      expect(rm.contentOwner, 'o@x.com');
    });

    test('parses MeetingRequest incl. 16.x Location, UID, proposals', () {
      final data = _e('AirSync:ApplicationData', [
        _e('Email:MeetingRequest', [
          _e('Email:AllDayEvent', '0'),
          _e('Email:StartTime', '2026-02-01T10:00:00.000Z'),
          _e('Email:DtStamp', '2026-01-01T10:00:00.000Z'),
          _e('Email:EndTime', '2026-02-01T11:00:00.000Z'),
          _e('Email:InstanceType', '1'),
          _e('Email:Location', 'Room'),
          _e('AirSyncBase:Location', [
            _e('AirSyncBase:DisplayName', 'Room'),
            _e('AirSyncBase:Latitude', '55.75'),
          ]),
          _e('Email:Organizer', 'o@x.com'),
          _e('Email:RecurrenceId', '2026-02-01T10:00:00.000Z'),
          _e('Email:Reminder', '15'),
          _e('Email:ResponseRequested', '1'),
          _e('Email:Recurrences', [
            _e('Email:Recurrence', [
              _e('Email:Type', '1'),
              _e('Email:Interval', '2'),
              _e('Email:DayOfWeek', '2'),
              _e('Email2:CalendarType', '1'),
              _e('Email2:IsLeapMonth', '0'),
              _e('Email2:FirstDayOfWeek', '1'),
            ]),
          ]),
          _e('Email:Sensitivity', '0'),
          _e('Email:BusyStatus', '2'),
          _e('Email:TimeZone', 'tz'),
          _e('Email:GlobalObjId', 'goid'),
          _e('Email:DisallowNewTimeProposal', '1'),
          _e('Email2:MeetingMessageType', '1'),
          _e('Calendar:UID', 'uid-1'),
          _e('MeetingResponse:ProposedStartTime', '2026-02-01T12:00:00.000Z'),
          _e('MeetingResponse:ProposedEndTime', '2026-02-01T13:00:00.000Z'),
          _e('ComposeMail:Forwardees', [
            _e('ComposeMail:Forwardee', [
              _e('ComposeMail:Name', 'F'),
              _e('ComposeMail:Email', 'f@x.com'),
            ]),
          ]),
        ]),
      ]);
      final mr = EasEmail.fromApplicationData('m', data).meetingRequest!;
      expect(mr.startTime, DateTime.utc(2026, 2, 1, 10));
      expect(mr.instanceType, 1);
      expect(mr.location, 'Room');
      expect(mr.locationDetails!.latitude, 55.75);
      expect(mr.organizer, 'o@x.com');
      expect(mr.reminder, 15);
      expect(mr.responseRequested, isTrue);
      expect(mr.recurrences.single.interval, 2);
      expect(mr.recurrences.single.calendarType, 1);
      expect(mr.recurrences.single.firstDayOfWeek, 1);
      expect(mr.timeZone, 'tz');
      expect(mr.globalObjId, 'goid');
      expect(mr.disallowNewTimeProposal, isTrue);
      expect(mr.meetingMessageType, 1);
      expect(mr.uid, 'uid-1');
      expect(mr.proposedStartTime, DateTime.utc(2026, 2, 1, 12));
      expect(mr.proposedEndTime, DateTime.utc(2026, 2, 1, 13));
      expect(mr.forwardees.single.email, 'f@x.com');
      expect(mr.forwardees.single.name, 'F');
    });

    test('EAS 2.5 body and attachments fall back to Email namespace', () {
      final data = _e('AirSync:ApplicationData', [
        _e('Email:Body', 'plain'),
        _e('Email:BodySize', '5'),
        _e('Email:BodyTruncated', '0'),
        _e('Email:Attachments', [
          _e('Email:Attachment', [
            _e('Email:AttName', 'a.txt'),
            _e('Email:AttSize', '3'),
            _e('Email:AttMethod', '1'),
            _e('Email:Att0id', 'oid'),
          ]),
        ]),
        _e('Email:MIMEData', 'MIME'),
        _e('Email:MIMESize', '4'),
        _e('Email:MIMETruncated', '0'),
      ]);
      final m = EasEmail.fromApplicationData('m', data);
      expect(m.body, 'plain');
      expect(m.estimatedBodySize, 5);
      expect(m.attachments.single.fileReference, 'a.txt');
      expect(m.attachments.single.estimatedSize, 3);
      expect(m.attachments.single.attOid, 'oid');
      expect(m.mimeData, 'MIME'.codeUnits);
      expect(m.mime, 'MIME'.codeUnits);
      expect(m.mimeSize, 4);
      expect(m.mimeTruncated, isFalse);
    });

    test('SMS items (Class SMS) are routed to addedSms', () {
      final doc = _syncResponse([
        _add('s1', [
          _e('Email:To', '+1'),
          _e('Email:MessageClass', 'IPM.Note.Mobile.SMS'),
        ], cls: 'SMS'),
        _add('e1', [_e('Email:Subject', 'mail')]),
      ]);
      final r = SyncCommand(syncKey: '1', collectionId: '1').parseResponse(doc);
      expect(r.addedSms.single.serverId, 's1');
      expect(r.addedSms.single.isSms, isTrue);
      expect(r.addedEmails.single.serverId, 'e1');
    });
  });

  group('Email serialization', () {
    test('serializeChange writes only Read/Flag/Categories', () {
      final data = _rt(
        EmailSerializer.serializeChange(
          read: true,
          flag: EasFlag(
            status: 2,
            flagType: 'Follow up',
            startDate: DateTime.utc(2026),
            dueDate: DateTime.utc(2026, 1, 2),
            utcStartDate: DateTime.utc(2026),
            utcDueDate: DateTime.utc(2026, 1, 2),
          ),
          categories: const ['A'],
        ),
      );
      expect(data.children.map((e) => e.tag), ['Read', 'Flag', 'Categories']);
      final flag = data.findChild('Email', 'Flag')!;
      expect(flag.childText('Email', 'Status'), '2');
      expect(flag.childText('Email', 'FlagType'), 'Follow up');
      expect(flag.childText('Tasks', 'UtcDueDate'), '2026-01-02T00:00:00.000Z');
    });

    test('cleared flag is an empty Flag element', () {
      final data = _rt(
        EmailSerializer.serializeChange(flag: const EasFlag(status: 0)),
      );
      expect(data.findChild('Email', 'Flag')!.children, isEmpty);
    });

    test('serializeSms emits To/From/DateReceived/Importance/Read/Body', () {
      final data = _rt(
        EmailSerializer.serializeSms(
          EasEmail(
            serverId: '',
            to: '+1',
            from: '+2',
            dateReceived: DateTime.utc(2026, 1, 1),
            read: true,
            body: 'hi',
          ),
        ),
      );
      expect(data.children.map((e) => e.tag), [
        'To',
        'From',
        'DateReceived',
        'Importance',
        'Read',
        'Body',
      ]);
      expect(
        data.findChild('AirSyncBase', 'Body')!.childText('AirSyncBase', 'Type'),
        '1',
      );
    });

    test('draft Send is a sibling of ApplicationData (16.x only)', () {
      final change = SyncChangeItem(
        serverId: 'd1',
        applicationData: EmailSerializer.serializeDraft(
          const EasEmail(serverId: '', subject: 's'),
        ),
        send: true,
      );
      for (final (version, hasSend) in [('16.1', true), ('14.1', false)]) {
        final cmd = SyncCommand(
          syncKey: '1',
          collectionId: '1',
          clientCommands: [change],
          protocolVersion: version,
        );
        final el = _collection(
          WbxmlDocument(root: _request(cmd)),
        ).findChild('AirSync', 'Commands')!.findChild('AirSync', 'Change')!;
        expect(el.children.map((e) => e.tag), [
          'ServerId',
          'ApplicationData',
          if (hasSend) 'Send',
        ]);
      }
    });

    test('attachment Content is WBXML opaque data', () {
      final bytes = Uint8List.fromList(List.generate(300, (i) => i % 256));
      final atts = _rt(
        AttachmentSerializer.serialize(
          add: [
            EasAttachmentAdd(
              clientId: 'c1',
              displayName: 'f.bin',
              content: bytes,
              contentLocation: 'loc',
            ),
          ],
          delete: const ['ref'],
        )!,
      );
      final add = atts.findChild('AirSyncBase', 'Add')!;
      final content = add.findChild('AirSyncBase', 'Content')!;
      expect(content.opaque, bytes);
      expect(content.text, isNull);
      expect(add.childText('AirSyncBase', 'ContentLocation'), 'loc');
      expect(
        atts
            .findChild('AirSyncBase', 'Delete')!
            .childText('AirSyncBase', 'FileReference'),
        'ref',
      );
      expect(AttachmentSerializer.serialize(), isNull);
    });
  });

  group('Calendar (MS-ASCAL)', () {
    final event = EasCalendarEvent(
      serverId: '',
      subject: 'Meet',
      startTime: DateTime.utc(2026, 3, 1, 9),
      endTime: DateTime.utc(2026, 3, 1, 10),
      location: 'Room 1',
      uid: 'uid',
      clientUid: 'cuid',
      dtStamp: DateTime.utc(2026),
      organizerName: 'Org',
      organizerEmail: 'org@x.com',
      responseType: 3,
      responseRequested: true,
      disallowNewTimeProposal: true,
      timezone: 'tz',
      reminder: 10,
      meetingStatus: 1,
      body: 'b',
      attendees: const [
        EasAttendee(
          email: 'a@x.com',
          name: 'A',
          status: AttendeeStatus.accepted,
          type: AttendeeType.optional,
        ),
      ],
      recurrence: EasRecurrence(
        type: 1,
        dayOfWeek: 2,
        until: DateTime.utc(2026, 6, 1, 9),
        calendarType: 1,
        firstDayOfWeek: 1,
      ),
      exceptions: [
        EasCalendarException(
          exceptionStartTime: DateTime.utc(2026, 3, 8, 9),
          subject: 'Moved',
          startTime: DateTime.utc(2026, 3, 8, 11),
          location: 'Room 2',
          categories: const ['X'],
          attendees: const [EasAttendee(email: 'b@x.com', name: 'B')],
        ),
        EasCalendarException(
          exceptionStartTime: DateTime.utc(2026, 3, 15, 9),
          deleted: true,
        ),
      ],
    );

    test('16.1 serializer follows 16.x request rules', () {
      final bytes = Uint8List.fromList([7, 7]);
      final d = _rt(
        CalendarSerializer.serialize(
          event,
          addAttachments: [
            EasAttachmentAdd(clientId: 'a1', displayName: 'x', content: bytes),
          ],
          deleteAttachments: const ['old'],
        ),
      );
      for (final tag in [
        'UID',
        'DtStamp',
        'OrganizerName',
        'OrganizerEmail',
        'ResponseType',
        'Location',
        'AppointmentReplyTime',
      ]) {
        expect(d.findChild('Calendar', tag), isNull, reason: tag);
      }
      expect(d.childText('Calendar', 'ClientUid'), 'cuid');
      expect(d.childText('Calendar', 'StartTime'), '20260301T090000Z');
      expect(
        d
            .findChild('AirSyncBase', 'Location')!
            .childText('AirSyncBase', 'DisplayName'),
        'Room 1',
      );
      expect(d.childText('Calendar', 'ResponseRequested'), '1');
      expect(d.childText('Calendar', 'DisallowNewTimeProposal'), '1');
      final att = d
          .findChild('Calendar', 'Attendees')!
          .findChild('Calendar', 'Attendee')!;
      expect(att.findChild('Calendar', 'AttendeeStatus'), isNull);
      expect(att.childText('Calendar', 'AttendeeType'), '2');
      final rec = d.findChild('Calendar', 'Recurrence')!;
      expect(rec.childText('Calendar', 'Until'), '20260601T090000Z');
      expect(rec.childText('Calendar', 'CalendarType'), '1');
      expect(rec.childText('Calendar', 'FirstDayOfWeek'), '1');

      final exs = d
          .findChild('Calendar', 'Exceptions')!
          .findChildren('Calendar', 'Exception');
      expect(exs[0].childText('AirSyncBase', 'InstanceId'), '20260308T090000Z');
      expect(exs[0].findChild('Calendar', 'ExceptionStartTime'), isNull);
      expect(
        exs[0]
            .findChild('AirSyncBase', 'Location')!
            .childText('AirSyncBase', 'DisplayName'),
        'Room 2',
      );
      expect(exs[0].findChild('Calendar', 'Attendees'), isNotNull);
      expect(exs[1].childText('Calendar', 'Deleted'), '1');

      final atts = d.findChild('AirSyncBase', 'Attachments')!;
      expect(
        atts
            .findChild('AirSyncBase', 'Add')!
            .findChild('AirSyncBase', 'Content')!
            .opaque,
        bytes,
      );
      expect(atts.findChild('AirSyncBase', 'Delete'), isNotNull);
    });

    test('14.1 serializer uses legacy elements and no attachments', () {
      final d = _rt(
        CalendarSerializer.serialize(
          event,
          protocolVersion: '14.1',
          addAttachments: [
            EasAttachmentAdd(
              clientId: 'a1',
              displayName: 'x',
              content: Uint8List(1),
            ),
          ],
        ),
      );
      expect(d.childText('Calendar', 'UID'), 'uid');
      expect(d.childText('Calendar', 'DtStamp'), '20260101T000000Z');
      expect(d.childText('Calendar', 'OrganizerEmail'), 'org@x.com');
      expect(d.childText('Calendar', 'Location'), 'Room 1');
      expect(d.findChild('Calendar', 'ClientUid'), isNull);
      expect(d.findChild('AirSyncBase', 'Location'), isNull);
      expect(d.findChild('AirSyncBase', 'Attachments'), isNull);
      expect(d.findChild('Calendar', 'ResponseType'), isNull);
      final att = d
          .findChild('Calendar', 'Attendees')!
          .findChild('Calendar', 'Attendee')!;
      expect(att.childText('Calendar', 'AttendeeStatus'), '3');
      final ex = d
          .findChild('Calendar', 'Exceptions')!
          .findChild('Calendar', 'Exception')!;
      expect(
        ex.childText('Calendar', 'ExceptionStartTime'),
        '20260308T090000Z',
      );
      expect(ex.findChild('AirSyncBase', 'InstanceId'), isNull);
      expect(ex.childText('Calendar', 'Location'), 'Room 2');
    });

    test('12.1 omits 14.x-only elements; 2.5 uses calendar:Body', () {
      final d121 = _rt(
        CalendarSerializer.serialize(event, protocolVersion: '12.1'),
      );
      expect(d121.findChild('Calendar', 'ResponseRequested'), isNull);
      final ex = d121
          .findChild('Calendar', 'Exceptions')!
          .findChild('Calendar', 'Exception')!;
      expect(ex.findChild('Calendar', 'Attendees'), isNull);
      expect(
        d121
            .findChild('Calendar', 'Recurrence')!
            .findChild('Calendar', 'CalendarType'),
        isNull,
      );

      final d25 = _rt(
        CalendarSerializer.serialize(event, protocolVersion: '2.5'),
      );
      expect(d25.childText('Calendar', 'Body'), 'b');
      expect(d25.findChild('AirSyncBase', 'Body'), isNull);
    });

    test('occurrence Change/Delete carry InstanceId (16.x)', () {
      final instance = DateTime.utc(2026, 3, 8, 9);
      final cmd = SyncCommand(
        syncKey: '1',
        collectionId: 'cal',
        contentType: SyncContentType.calendar,
        clientCommands: [
          SyncChangeItem(
            serverId: 'e1',
            instanceId: instance,
            applicationData: CalendarSerializer.serializeOccurrence(
              EasCalendarException(
                exceptionStartTime: instance,
                subject: 'Only this one',
                endTime: DateTime.utc(2026, 3, 8, 12),
                addAttachments: [
                  EasAttachmentAdd(
                    clientId: 'x',
                    displayName: 'x',
                    content: Uint8List(2),
                  ),
                ],
              ),
            ),
          ),
          SyncDeleteItem(
            serverId: 'e1',
            instanceId: DateTime.utc(2026, 3, 15, 9),
          ),
        ],
      );
      final commands = _collection(
        WbxmlDocument(root: _request(cmd)),
      ).findChild('AirSync', 'Commands')!;
      final change = commands.findChild('AirSync', 'Change')!;
      expect(change.children.map((e) => e.tag), [
        'ServerId',
        'InstanceId',
        'ApplicationData',
      ]);
      expect(change.childText('AirSyncBase', 'InstanceId'), '20260308T090000Z');
      final data = change.findChild('AirSync', 'ApplicationData')!;
      expect(data.childText('Calendar', 'Subject'), 'Only this one');
      expect(data.childText('Calendar', 'EndTime'), '20260308T120000Z');
      expect(data.findChild('Calendar', 'StartTime'), isNull);
      expect(data.findChild('AirSyncBase', 'Attachments'), isNotNull);

      final delete = commands.findChild('AirSync', 'Delete')!;
      expect(delete.childText('AirSyncBase', 'InstanceId'), '20260315T090000Z');
    });

    test('InstanceId is not sent for protocol < 16.0', () {
      final cmd = SyncCommand(
        syncKey: '1',
        collectionId: 'cal',
        protocolVersion: '14.1',
        clientCommands: [
          SyncDeleteItem(serverId: 'e1', instanceId: DateTime.utc(2026)),
        ],
      );
      final delete = _collection(
        WbxmlDocument(root: _request(cmd)),
      ).findChild('AirSync', 'Commands')!.findChild('AirSync', 'Delete')!;
      expect(delete.findChild('AirSyncBase', 'InstanceId'), isNull);
    });

    test('parses 16.x calendar: Location, Attachments, orphan InstanceId', () {
      final doc = _syncResponse(collectionId: 'cal', [
        _add('e1', [
          _e('Calendar:Subject', 'S'),
          _e('Calendar:StartTime', '20260301T090000Z'),
          _e('Calendar:UID', 'server-uid'),
          _e('Calendar:ResponseRequested', '1'),
          _e('Calendar:AppointmentReplyTime', '20260101T000000Z'),
          _e('Calendar:ResponseType', '3'),
          _e('Calendar:OnlineMeetingConfLink', 'sip:x'),
          _e('Calendar:OnlineMeetingExternalLink', 'https://x'),
          _e('AirSyncBase:InstanceId', '20260301T090000Z'),
          _e('AirSyncBase:Location', [
            _e('AirSyncBase:DisplayName', 'Hall'),
            _e('AirSyncBase:Annotation', 'ann'),
            _e('AirSyncBase:Street', 'st'),
            _e('AirSyncBase:City', 'c'),
            _e('AirSyncBase:State', 's'),
            _e('AirSyncBase:Country', 'co'),
            _e('AirSyncBase:PostalCode', 'pc'),
            _e('AirSyncBase:Latitude', '1.5'),
            _e('AirSyncBase:Longitude', '2.5'),
            _e('AirSyncBase:Accuracy', '3'),
            _e('AirSyncBase:Altitude', '4'),
            _e('AirSyncBase:AltitudeAccuracy', '5'),
            _e('AirSyncBase:LocationUri', 'geo:1'),
          ]),
          _e('AirSyncBase:Attachments', [
            _e('AirSyncBase:Attachment', [
              _e('AirSyncBase:DisplayName', 'agenda.pdf'),
              _e('AirSyncBase:FileReference', 'fr'),
              _e('AirSyncBase:EstimatedDataSize', '10'),
            ]),
          ]),
          _e('Calendar:Attendees', [
            _e('Calendar:Attendee', [
              _e('Calendar:Email', 'a@x.com'),
              _e('Calendar:Name', 'A'),
              _e('Calendar:AttendeeStatus', '4'),
              _e('Calendar:AttendeeType', '3'),
              _e('MeetingResponse:ProposedStartTime', '20260301T100000Z'),
              _e('MeetingResponse:ProposedEndTime', '20260301T110000Z'),
            ]),
          ]),
          _e('Calendar:Exceptions', [
            _e('Calendar:Exception', [
              _e('AirSyncBase:InstanceId', '20260308T090000Z'),
              _e('Calendar:Subject', 'X'),
              _e('Calendar:MeetingStatus', '5'),
              _e('Calendar:DtStamp', '20260101T000000Z'),
              _e('Calendar:Categories', [_e('Calendar:Category', 'C')]),
              _e('Calendar:Attendees', [
                _e('Calendar:Attendee', [
                  _e('Calendar:Email', 'b@x.com'),
                  _e('Calendar:Name', 'B'),
                ]),
              ]),
              _e('Calendar:ResponseType', '2'),
              _e('Calendar:AppointmentReplyTime', '20260102T000000Z'),
              _e('Calendar:OnlineMeetingConfLink', 'sip:y'),
              _e('Calendar:OnlineMeetingExternalLink', 'https://y'),
              _e('AirSyncBase:Location', [
                _e('AirSyncBase:DisplayName', 'Other'),
              ]),
              _e('AirSyncBase:Attachments', [
                _e('AirSyncBase:Attachment', [
                  _e('AirSyncBase:FileReference', 'fr2'),
                ]),
              ]),
            ]),
          ]),
        ]),
      ]);
      final r = SyncCommand(
        syncKey: '1',
        collectionId: 'cal',
        contentType: SyncContentType.calendar,
      ).parseResponse(doc);
      final e = r.addedCalendarEvents.single;
      expect(e.uid, 'server-uid');
      expect(e.startTime, DateTime.utc(2026, 3, 1, 9));
      expect(e.responseRequested, isTrue);
      expect(e.appointmentReplyTime, DateTime.utc(2026));
      expect(e.onlineMeetingExternalLink, 'https://x');
      expect(e.instanceId, DateTime.utc(2026, 3, 1, 9));
      expect(e.location, 'Hall');
      final loc = e.locationDetails!;
      expect(
        [loc.annotation, loc.street, loc.city, loc.state],
        ['ann', 'st', 'c', 's'],
      );
      expect(
        [loc.country, loc.postalCode, loc.locationUri],
        ['co', 'pc', 'geo:1'],
      );
      expect([loc.latitude, loc.longitude, loc.accuracy], [1.5, 2.5, 3.0]);
      expect([loc.altitude, loc.altitudeAccuracy], [4.0, 5.0]);
      expect(e.attachments.single.fileReference, 'fr');
      final a = e.attendees.single;
      expect(a.status, AttendeeStatus.declined);
      expect(a.type, AttendeeType.resource);
      expect(a.proposedStartTime, DateTime.utc(2026, 3, 1, 10));
      expect(a.proposedEndTime, DateTime.utc(2026, 3, 1, 11));

      final x = e.exceptions.single;
      expect(x.instanceId, DateTime.utc(2026, 3, 8, 9));
      expect(x.exceptionStartTime, DateTime.utc(2026, 3, 8, 9));
      expect(x.meetingStatus, 5);
      expect(x.dtStamp, DateTime.utc(2026));
      expect(x.categories, ['C']);
      expect(x.attendees!.single.email, 'b@x.com');
      expect(x.responseType, 2);
      expect(x.appointmentReplyTime, DateTime.utc(2026, 1, 2));
      expect(x.onlineMeetingConfLink, 'sip:y');
      expect(x.onlineMeetingExternalLink, 'https://y');
      expect(x.location, 'Other');
      expect(x.attachments.single.fileReference, 'fr2');
    });

    test('location round-trips and empty Location clears it', () {
      const loc = EasLocation(displayName: 'D', latitude: 1.25);
      final parsed = EasLocation.fromElement(_rt(loc.toElement()));
      expect(parsed.displayName, 'D');
      expect(parsed.latitude, 1.25);
      expect(const EasLocation().toElement().children, isEmpty);
    });
  });

  group('Contacts (MS-ASCNTC)', () {
    const contact = EasContact(
      serverId: '',
      fileAs: 'Doe, J',
      firstName: 'J',
      lastName: 'Doe',
      nickName: 'JD',
      assistantName: 'As',
      assistantPhone: '1',
      business2Phone: '2',
      businessAddressState: 'BS',
      carPhone: '3',
      home2Phone: '4',
      homeAddressState: 'HS',
      homeFax: '5',
      otherAddressStreet: 'OS',
      otherAddressCity: 'OC',
      otherAddressState: 'OSt',
      otherAddressPostalCode: 'OP',
      otherAddressCountry: 'OCo',
      pager: '6',
      radioPhone: '7',
      spouse: 'Sp',
      children: ['K1', 'K2'],
      yomiCompanyName: 'YC',
      yomiFirstName: 'YF',
      yomiLastName: 'YL',
      alias: 'alias',
      weightedRank: 3,
      accountName: 'acc',
      body: 'notes',
    );

    test('serializer emits all writable fields; NickName is Contacts2', () {
      final d = _rt(ContactSerializer.serialize(contact));
      expect(d.childText('Contacts2', 'NickName'), 'JD');
      expect(d.findChild('Contacts', 'NickName'), isNull);
      expect(d.findChild('Contacts', 'Alias'), isNull);
      expect(d.findChild('Contacts', 'WeightedRank'), isNull);
      expect(
        d
            .findChild('Contacts', 'Children')!
            .findChildren('Contacts', 'Child')
            .map((e) => e.text),
        ['K1', 'K2'],
      );
      final parsed = EasContact.fromApplicationData('c', d);
      expect(parsed.assistantName, 'As');
      expect(parsed.assistantPhone, '1');
      expect(parsed.business2Phone, '2');
      expect(parsed.businessAddressState, 'BS');
      expect(parsed.carPhone, '3');
      expect(parsed.home2Phone, '4');
      expect(parsed.homeAddressState, 'HS');
      expect(parsed.homeFax, '5');
      expect(parsed.otherAddressStreet, 'OS');
      expect(parsed.otherAddressCity, 'OC');
      expect(parsed.otherAddressState, 'OSt');
      expect(parsed.otherAddressPostalCode, 'OP');
      expect(parsed.otherAddressCountry, 'OCo');
      expect(parsed.pager, '6');
      expect(parsed.radioPhone, '7');
      expect(parsed.spouse, 'Sp');
      expect(parsed.children, ['K1', 'K2']);
      expect(parsed.yomiCompanyName, 'YC');
      expect(parsed.yomiFirstName, 'YF');
      expect(parsed.yomiLastName, 'YL');
      expect(parsed.nickName, 'JD');
      expect(parsed.accountName, 'acc');
      expect(parsed.body, 'notes');
    });

    test('parses server-only Alias and WeightedRank', () {
      final d = _e('AirSync:ApplicationData', [
        _e('Contacts:Alias', 'jd'),
        _e('Contacts:WeightedRank', '9'),
      ]);
      final c = EasContact.fromApplicationData('c', d);
      expect(c.alias, 'jd');
      expect(c.weightedRank, 9);
    });
  });

  group('Tasks (MS-ASTASK)', () {
    test('recurrence children are in the Tasks namespace', () {
      final task = EasTask(
        serverId: '',
        subject: 'T',
        startDate: DateTime.utc(2026, 1, 1),
        dueDate: DateTime.utc(2026, 1, 2),
        body: 'b',
        recurrence: EasRecurrence(
          type: 0,
          start: DateTime.utc(2026, 1, 1),
          until: DateTime.utc(2026, 12, 31),
          regenerate: true,
          deadOccur: false,
          calendarType: 1,
          isLeapMonth: false,
          firstDayOfWeek: 1,
        ),
      );
      final d = _rt(TaskSerializer.serialize(task));
      expect(d.childText('Tasks', 'UtcStartDate'), '2026-01-01T00:00:00.000Z');
      expect(d.childText('Tasks', 'UtcDueDate'), '2026-01-02T00:00:00.000Z');
      expect(d.findChild('AirSyncBase', 'Body'), isNotNull);
      expect(d.findChild('Tasks', 'OrdinalDate'), isNull);
      final rec = d.findChild('Tasks', 'Recurrence')!;
      expect(rec.children.every((c) => c.namespace == 'Tasks'), isTrue);
      expect(rec.childText('Tasks', 'Start'), '2026-01-01T00:00:00.000Z');
      expect(rec.childText('Tasks', 'Regenerate'), '1');
      expect(rec.childText('Tasks', 'DeadOccur'), '0');

      final parsed = EasTask.fromApplicationData('t', d);
      expect(parsed.utcDueDate, DateTime.utc(2026, 1, 2));
      expect(parsed.body, 'b');
      expect(parsed.recurrence!.start, DateTime.utc(2026, 1, 1));
      expect(parsed.recurrence!.until, DateTime.utc(2026, 12, 31));
      expect(parsed.recurrence!.regenerate, isTrue);
      expect(parsed.recurrence!.deadOccur, isFalse);
      expect(parsed.recurrence!.firstDayOfWeek, 1);
    });
  });

  group('Notes (MS-ASNOTE)', () {
    test('round-trips MessageClass, LastModifiedDate, Body type', () {
      final d = _rt(
        NoteSerializer.serialize(
          EasNote(
            serverId: '',
            subject: 'N',
            body: '<b>x</b>',
            bodyDetails: const EasBody(type: 2),
            messageClass: 'IPM.StickyNote.Custom',
            lastModifiedDate: DateTime.utc(2026, 5, 5),
          ),
        ),
      );
      final n = EasNote.fromApplicationData('n', d);
      expect(n.messageClass, 'IPM.StickyNote.Custom');
      expect(n.lastModifiedDate, DateTime.utc(2026, 5, 5));
      expect(n.bodyDetails!.type, 2);
      expect(n.body, '<b>x</b>');
    });
  });

  group('Sync request options (MS-ASCMD 2.2.3.125.6)', () {
    test('all Options children, two Options (Email + SMS), collection', () {
      final cmd = MultiSyncCommand(
        wait: 5,
        windowSize: 100,
        collections: [
          SyncCollection(
            syncKey: '5',
            collectionId: 'inbox',
            conversationMode: true,
            options: [
              SyncOptions(
                className: 'Email',
                filterType: SyncFilterType.twoWeeks,
                bodyPreferences: [
                  EasBodyPreference(
                    type: 2,
                    truncationSize: 5120,
                    allOrNone: true,
                    preview: 100,
                  ),
                  EasBodyPreference(type: 4),
                ],
                bodyPartPreferences: [
                  EasBodyPreference(type: 2, truncationSize: 100, preview: 50),
                ],
                conflict: 1,
                mimeSupport: 2,
                mimeTruncation: 8,
                maxItems: 20,
                rightsManagementSupport: true,
              ),
              SyncOptions(
                className: 'SMS',
                filterType: SyncFilterType.oneWeek,
                bodyPreferences: [EasBodyPreference(type: 1)],
              ),
            ],
          ),
        ],
      );
      final root = _request(cmd);
      expect(root.childText('AirSync', 'Wait'), '5');
      expect(root.childText('AirSync', 'WindowSize'), '100');
      final col = _collection(WbxmlDocument(root: root));
      expect(col.childText('AirSync', 'ConversationMode'), '1');
      final opts = col.findChildren('AirSync', 'Options');
      expect(opts, hasLength(2));
      final o = opts.first;
      expect(o.childText('AirSync', 'Class'), 'Email');
      expect(o.childText('AirSync', 'FilterType'), '4');
      final bp = o.findChildren('AirSyncBase', 'BodyPreference');
      expect(bp, hasLength(2));
      expect(bp.first.childText('AirSyncBase', 'TruncationSize'), '5120');
      expect(bp.first.childText('AirSyncBase', 'AllOrNone'), '1');
      expect(bp.first.childText('AirSyncBase', 'Preview'), '100');
      final bpp = o.findChild('AirSyncBase', 'BodyPartPreference')!;
      expect(bpp.childText('AirSyncBase', 'Preview'), '50');
      expect(o.childText('AirSync', 'Conflict'), '1');
      expect(o.childText('AirSync', 'MIMESupport'), '2');
      expect(o.childText('AirSync', 'MIMETruncation'), '8');
      expect(o.childText('AirSync', 'MaxItems'), '20');
      expect(o.childText('RightsManagement', 'RightsManagementSupport'), '1');
      expect(opts.last.childText('AirSync', 'Class'), 'SMS');
    });

    test('14.0 omits BodyPartPreference and RightsManagementSupport', () {
      const opts = SyncOptions(
        className: 'Email',
        bodyPartPreferences: [EasBodyPreference(type: 2)],
        rightsManagementSupport: true,
        truncation: 4,
      );
      final o = _rt(opts.toElement(140));
      expect(o.findChild('AirSyncBase', 'BodyPartPreference'), isNull);
      expect(
        o.findChild('RightsManagement', 'RightsManagementSupport'),
        isNull,
      );
      expect(o.findChild('AirSync', 'Truncation'), isNull);
      final o25 = _rt(opts.toElement(25));
      expect(o25.childText('AirSync', 'Truncation'), '4');
      expect(o25.findChild('AirSync', 'Class'), isNull);
    });

    test('Supported (ghosting) is sent only with SyncKey 0', () {
      final initial = SyncCollection(
        collectionId: 'contacts',
        supported: const ['Contacts:FirstName', 'Contacts2:NickName'],
      ).toElement();
      final sup = _rt(initial).findChild('AirSync', 'Supported')!;
      expect(sup.children.map((e) => '${e.namespace}:${e.tag}'), [
        'Contacts:FirstName',
        'Contacts2:NickName',
      ]);
      final later = SyncCollection(
        syncKey: '3',
        collectionId: 'contacts',
        supported: const ['Contacts:FirstName'],
      ).toElement();
      expect(later.findChild('AirSync', 'Supported'), isNull);
    });

    test(
      'HeartbeatInterval, Partial and explicit GetChanges/DeletesAsMoves',
      () {
        final root = _request(
          MultiSyncCommand(
            heartbeatInterval: 600,
            partial: true,
            collections: const [
              SyncCollection(
                syncKey: '1',
                collectionId: 'x',
                getChanges: false,
                deletesAsMoves: false,
              ),
            ],
          ),
        );
        expect(root.childText('AirSync', 'HeartbeatInterval'), '600');
        expect(root.findChild('AirSync', 'Partial'), isNotNull);
        final col = _collection(WbxmlDocument(root: root));
        expect(col.childText('AirSync', 'GetChanges'), '0');
        expect(col.childText('AirSync', 'DeletesAsMoves'), '0');
      },
    );

    test('Add carries Class (SMS) before ClientId', () {
      final cmd = SyncCommand(
        syncKey: '1',
        collectionId: 'inbox',
        clientCommands: [
          SyncAddItem(
            clientId: 'c1',
            className: 'SMS',
            applicationData: EmailSerializer.serializeSms(
              const EasEmail(serverId: '', to: '+1', body: 'x'),
            ),
          ),
        ],
      );
      final add = _collection(
        WbxmlDocument(root: _request(cmd)),
      ).findChild('AirSync', 'Commands')!.findChild('AirSync', 'Add')!;
      expect(add.children.map((e) => e.tag), [
        'Class',
        'ClientId',
        'ApplicationData',
      ]);
    });

    test('FilterType 8 = incomplete tasks', () {
      expect(SyncFilterType.incompleteTasks.value, 8);
    });
  });

  group('Sync status and responses', () {
    test('every Sync status code is mapped', () {
      for (final code in [1, 3, 4, 5, 6, 7, 8, 9, 12, 13, 14, 15, 16]) {
        expect(SyncStatus.fromCode(code), isNotNull, reason: '$code');
      }
      expect(SyncStatus.fromCode(2), isNull);
      expect(SyncStatus.retry.isRetriable, isTrue);
      expect(SyncStatus.conflict.isRetriable, isFalse);
    });

    test('top-level Status 14 with Limit', () {
      final doc = WbxmlDocument(
        root: _rt(
          _e('AirSync:Sync', [
            _e('AirSync:Status', '14'),
            _e('AirSync:Limit', '59'),
          ]),
        ),
      );
      final r = MultiSyncCommand(collections: const []).parseResponse(doc);
      expect(r.invalidWaitOrHeartbeat, isTrue);
      expect(r.limit, 59);
      expect(r.syncStatus, SyncStatus.invalidWaitOrHeartbeat);
    });

    test('Responses: conflict, instance ids, Add item, Delete class', () {
      final doc = _syncResponse(
        collectionId: 'cal',
        [
          _e('AirSync:Delete', [
            _e('AirSync:ServerId', 'd1'),
            _e('AirSync:Class', 'SMS'),
          ]),
          _e('AirSync:SoftDelete', [_e('AirSync:ServerId', 'sd1')]),
        ],
        responses: [
          _e('AirSync:Add', [
            _e('AirSync:ClientId', 'c1'),
            _e('AirSync:ServerId', 's1'),
            _e('AirSync:Status', '1'),
            _e('AirSync:ApplicationData', [
              _e('Calendar:UID', 'new-uid'),
              _e('AirSyncBase:Attachments', [
                _e('AirSyncBase:Attachment', [
                  _e('AirSyncBase:ClientId', 'a1'),
                  _e('AirSyncBase:FileReference', 'fr1'),
                ]),
              ]),
            ]),
          ]),
          _e('AirSync:Change', [
            _e('AirSync:ServerId', 's2'),
            _e('AirSyncBase:InstanceId', '20260308T090000Z'),
            _e('AirSync:Status', '7'),
          ]),
          _e('AirSync:Delete', [
            _e('AirSync:ServerId', 's3'),
            _e('AirSyncBase:InstanceId', '20260315T090000Z'),
            _e('AirSync:Status', '8'),
          ]),
        ],
      );
      final r = SyncCommand(
        syncKey: '1',
        collectionId: 'cal',
        contentType: SyncContentType.calendar,
      ).parseResponse(doc);
      final add = r.addResponses.single;
      expect((add.item as EasCalendarEvent).uid, 'new-uid');
      expect(add.attachmentFileReferences, {'a1': 'fr1'});
      final change = r.changeResponses.single;
      expect(change.isConflict, isTrue);
      expect(change.syncStatus, SyncStatus.conflict);
      expect(change.instanceId, DateTime.utc(2026, 3, 8, 9));
      final del = r.deleteResponses.single;
      expect(del.syncStatus, SyncStatus.objectNotFound);
      expect(del.instanceId, DateTime.utc(2026, 3, 15, 9));
      expect(r.deletedItems.single.className, 'SMS');
      expect(r.deletedIds, ['d1']);
      expect(r.softDeletedIds, ['sd1']);
      expect(r.syncStatus, SyncStatus.success);
    });
  });

  group('Calendar request rules (MS-ASCAL 16.x)', () {
    final base = EasCalendarEvent(
      serverId: '',
      subject: 'All day',
      allDayEvent: true,
      timezone: 'tz',
      busyStatus: 4,
      startTime: DateTime.utc(2026, 3, 1),
      endTime: DateTime.utc(2026, 3, 2),
      recurrence: const EasRecurrence(type: 0),
      exceptions: [
        EasCalendarException(
          exceptionStartTime: DateTime.utc(2026, 3, 3),
          deleted: true,
        ),
      ],
    );

    test('all-day event omits Timezone only in 16.x', () {
      final d16 = _rt(CalendarSerializer.serialize(base));
      final d14 = _rt(
        CalendarSerializer.serialize(base, protocolVersion: '14.1'),
      );
      expect(d16.findChild('Calendar', 'Timezone'), isNull);
      expect(d14.childText('Calendar', 'Timezone'), 'tz');
    });

    test('BusyStatus 4 (working elsewhere) is never sent', () {
      final d = _rt(CalendarSerializer.serialize(base));
      expect(d.findChild('Calendar', 'BusyStatus'), isNull);
      final occ = _rt(
        CalendarSerializer.serializeOccurrence(
          EasCalendarException(
            exceptionStartTime: DateTime.utc(2026, 3, 3),
            busyStatus: 4,
          ),
        ),
      );
      expect(occ.findChild('Calendar', 'BusyStatus'), isNull);
    });

    test('16.x Change omits Exceptions; Add and 14.1 Change keep them', () {
      Object? ex(String v, bool change) => _rt(
        CalendarSerializer.serialize(
          base,
          protocolVersion: v,
          isChange: change,
        ),
      ).findChild('Calendar', 'Exceptions');
      expect(ex('16.1', true), isNull);
      expect(ex('16.1', false), isNotNull);
      expect(ex('14.1', true), isNotNull);
    });

    test('empty Reminder removes the reminder (16.x only)', () {
      final d16 = _rt(CalendarSerializer.serialize(base, removeReminder: true));
      final r = d16.findChild('Calendar', 'Reminder')!;
      expect(r.text, isNull);
      expect(r.children, isEmpty);
      final d14 = _rt(
        CalendarSerializer.serialize(
          base,
          protocolVersion: '14.1',
          removeReminder: true,
        ),
      );
      expect(d14.findChild('Calendar', 'Reminder'), isNull);
      final occ = _rt(
        CalendarSerializer.serializeOccurrence(
          EasCalendarException(exceptionStartTime: DateTime.utc(2026, 3, 3)),
          removeReminder: true,
        ),
      );
      expect(occ.findChild('Calendar', 'Reminder'), isNotNull);
    });
  });

  group('Sync Options version gating', () {
    const opts = SyncOptions(
      maxItems: 20,
      bodyPreferences: [
        EasBodyPreference(type: 2, truncationSize: 100, preview: 50),
      ],
    );

    test('MaxItems requires 12.0+', () {
      expect(_rt(opts.toElement(25)).findChild('AirSync', 'MaxItems'), isNull);
      expect(_rt(opts.toElement(120)).childText('AirSync', 'MaxItems'), '20');
    });

    test('BodyPreference Preview requires 14.0+', () {
      WbxmlElement pref(int v) =>
          _rt(opts.toElement(v)).findChild('AirSyncBase', 'BodyPreference')!;
      expect(pref(121).findChild('AirSyncBase', 'Preview'), isNull);
      expect(pref(121).childText('AirSyncBase', 'TruncationSize'), '100');
      expect(pref(140).childText('AirSyncBase', 'Preview'), '50');
    });
  });

  group('EAS 2.5 legacy bodies', () {
    test('Calendar/Contacts/Tasks parse Body, BodySize, BodyTruncated', () {
      final cal = EasCalendarEvent.fromApplicationData(
        'c',
        _rt(
          _e('AirSync:ApplicationData', [
            _e('Calendar:Body', 'cal body'),
            _e('Calendar:BodyTruncated', '1'),
          ]),
        ),
      );
      expect(cal.body, 'cal body');
      expect(cal.bodyDetails!.truncated, isTrue);

      final contact = EasContact.fromApplicationData(
        'p',
        _rt(
          _e('AirSync:ApplicationData', [
            _e('Contacts:Body', 'notes'),
            _e('Contacts:BodySize', '500'),
            _e('Contacts:BodyTruncated', '1'),
          ]),
        ),
      );
      expect(contact.body, 'notes');
      expect(contact.bodyDetails!.estimatedDataSize, 500);
      expect(contact.bodyDetails!.truncated, isTrue);

      final task = EasTask.fromApplicationData(
        't',
        _rt(
          _e('AirSync:ApplicationData', [
            _e('Tasks:Body', 'todo'),
            _e('Tasks:BodySize', '4'),
            _e('Tasks:BodyTruncated', '0'),
          ]),
        ),
      );
      expect(task.body, 'todo');
      expect(task.bodyDetails!.estimatedDataSize, 4);
      expect(task.bodyDetails!.truncated, isFalse);
    });
  });
}
