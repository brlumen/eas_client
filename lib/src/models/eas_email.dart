/// EAS email model (MS-ASEMAIL: Email, Email2, AirSyncBase and
/// RightsManagement elements).
library;

import 'dart:typed_data';

import '../wbxml/wbxml_document.dart';
import 'eas_attachment.dart';
import 'eas_body.dart';
import 'eas_location.dart';
import 'eas_recurrence.dart';
import 'eas_rights_management_license.dart';
import 'wbxml_helpers.dart';

/// Email importance level.
enum EmailImportance {
  low(0),
  normal(1),
  high(2);

  final int value;
  const EmailImportance(this.value);

  static EmailImportance fromValue(int value) {
    return EmailImportance.values.firstWhere(
      (e) => e.value == value,
      orElse: () => EmailImportance.normal,
    );
  }
}

/// Follow-up flag of a message (MS-ASEMAIL 2.2.2.34 `Flag`).
class EasFlag {
  /// 0=cleared, 1=complete, 2=active.
  final int status;

  /// Flag action text (e.g. "Follow up").
  final String? flagType;

  /// Time the flag was set to complete.
  final DateTime? completeTime;

  // Tasks namespace children.
  final String? subject;
  final DateTime? dateCompleted;
  final DateTime? startDate;
  final DateTime? dueDate;
  final DateTime? utcStartDate;
  final DateTime? utcDueDate;
  final bool? reminderSet;
  final DateTime? reminderTime;
  final DateTime? ordinalDate;
  final String? subOrdinalDate;

  const EasFlag({
    this.status = 0,
    this.flagType,
    this.completeTime,
    this.subject,
    this.dateCompleted,
    this.startDate,
    this.dueDate,
    this.utcStartDate,
    this.utcDueDate,
    this.reminderSet,
    this.reminderTime,
    this.ordinalDate,
    this.subOrdinalDate,
  });

  factory EasFlag.fromElement(WbxmlElement el) => EasFlag(
    status: el.integer('Email', 'Status') ?? 0,
    flagType: el.str('Email', 'FlagType'),
    completeTime: el.date('Email', 'CompleteTime'),
    subject: el.str('Tasks', 'Subject'),
    dateCompleted: el.date('Tasks', 'DateCompleted'),
    startDate: el.date('Tasks', 'StartDate'),
    dueDate: el.date('Tasks', 'DueDate'),
    utcStartDate: el.date('Tasks', 'UtcStartDate'),
    utcDueDate: el.date('Tasks', 'UtcDueDate'),
    reminderSet: el.boolean('Tasks', 'ReminderSet'),
    reminderTime: el.date('Tasks', 'ReminderTime'),
    ordinalDate: el.date('Tasks', 'OrdinalDate'),
    subOrdinalDate: el.str('Tasks', 'SubOrdinalDate'),
  );

  /// `email:Flag` element. A cleared flag (status 0 with no other fields)
  /// produces an empty `Flag`, which clears the flag on the server.
  WbxmlElement toElement() {
    final c = <WbxmlElement>[]
      ..addText('Tasks', 'Subject', subject)
      ..addText('Email', 'Status', status == 0 ? null : status)
      ..addText('Email', 'FlagType', flagType)
      ..addDate('Tasks', 'DateCompleted', dateCompleted)
      ..addDate('Email', 'CompleteTime', completeTime)
      ..addDate('Tasks', 'StartDate', startDate)
      ..addDate('Tasks', 'DueDate', dueDate)
      ..addDate('Tasks', 'UtcStartDate', utcStartDate)
      ..addDate('Tasks', 'UtcDueDate', utcDueDate)
      ..addText('Tasks', 'ReminderSet', reminderSet)
      ..addDate('Tasks', 'ReminderTime', reminderTime)
      ..addDate('Tasks', 'OrdinalDate', ordinalDate)
      ..addText('Tasks', 'SubOrdinalDate', subOrdinalDate);
    return containerEl('Email', 'Flag', c);
  }
}

/// Recipient a meeting request was forwarded to
/// (`ComposeMail:Forwardee`).
class EasForwardee {
  final String email;
  final String? name;

  const EasForwardee({required this.email, this.name});
}

/// Meeting request details of a message (MS-ASEMAIL 2.2.2.48).
class EasMeetingRequest {
  final bool allDayEvent;
  final DateTime? startTime;
  final DateTime? dtStamp;
  final DateTime? endTime;

  /// 0=single, 1=recurring master, 2=single instance of recurring,
  /// 3=exception to recurring, 4=orphan instance.
  final int? instanceType;

  /// Location (EAS ≤14.1 `email:Location`; for 16.x the display name of
  /// [locationDetails]).
  final String? location;

  /// Structured location (EAS 16.x `airsyncbase:Location`).
  final EasLocation? locationDetails;
  final String? organizer;
  final DateTime? recurrenceId;
  final int? reminder;
  final bool? responseRequested;
  final List<EasRecurrence> recurrences;
  final int? sensitivity;
  final int? busyStatus;

  /// Base64 TIME_ZONE_INFORMATION.
  final String? timeZone;
  final String? globalObjId;
  final bool? disallowNewTimeProposal;

  /// 0=silent update, 1=initial request, 2=full update, 3=informational
  /// update, 4=outdated, 5=delegator's copy, 6=delegated.
  final int? meetingMessageType;

  /// Calendar UID (EAS 16.x).
  final String? uid;

  /// Proposed new time of a counter-proposal (EAS 16.x).
  final DateTime? proposedStartTime;
  final DateTime? proposedEndTime;

  final List<EasForwardee> forwardees;

  const EasMeetingRequest({
    this.allDayEvent = false,
    this.startTime,
    this.dtStamp,
    this.endTime,
    this.instanceType,
    this.location,
    this.locationDetails,
    this.organizer,
    this.recurrenceId,
    this.reminder,
    this.responseRequested,
    this.recurrences = const [],
    this.sensitivity,
    this.busyStatus,
    this.timeZone,
    this.globalObjId,
    this.disallowNewTimeProposal,
    this.meetingMessageType,
    this.uid,
    this.proposedStartTime,
    this.proposedEndTime,
    this.forwardees = const [],
  });

  factory EasMeetingRequest.fromElement(WbxmlElement el) {
    const ns = 'Email';
    final locationDetails = EasLocation.of(el);
    return EasMeetingRequest(
      allDayEvent: el.boolean(ns, 'AllDayEvent') ?? false,
      startTime: el.date(ns, 'StartTime'),
      dtStamp: el.date(ns, 'DtStamp'),
      endTime: el.date(ns, 'EndTime'),
      instanceType: el.integer(ns, 'InstanceType'),
      location: el.str(ns, 'Location') ?? locationDetails?.displayName,
      locationDetails: locationDetails,
      organizer: el.str(ns, 'Organizer'),
      recurrenceId: el.date(ns, 'RecurrenceId'),
      reminder: el.integer(ns, 'Reminder'),
      responseRequested: el.boolean(ns, 'ResponseRequested'),
      recurrences:
          el
              .findChild(ns, 'Recurrences')
              ?.findChildren(ns, 'Recurrence')
              .map((r) => EasRecurrence.fromElement(r, ns))
              .toList() ??
          const [],
      sensitivity: el.integer(ns, 'Sensitivity'),
      busyStatus: el.integer(ns, 'BusyStatus'),
      timeZone: el.str(ns, 'TimeZone'),
      globalObjId: el.str(ns, 'GlobalObjId'),
      disallowNewTimeProposal: el.boolean(ns, 'DisallowNewTimeProposal'),
      meetingMessageType: el.integer('Email2', 'MeetingMessageType'),
      uid: el.str('Calendar', 'UID'),
      proposedStartTime: el.date('MeetingResponse', 'ProposedStartTime'),
      proposedEndTime: el.date('MeetingResponse', 'ProposedEndTime'),
      forwardees:
          el
              .findChild('ComposeMail', 'Forwardees')
              ?.findChildren('ComposeMail', 'Forwardee')
              .map(
                (f) => EasForwardee(
                  email: f.str('ComposeMail', 'Email') ?? '',
                  name: f.str('ComposeMail', 'Name'),
                ),
              )
              .toList() ??
          const [],
    );
  }
}

class EasEmail {
  /// Server-assigned ID.
  final String serverId;

  /// Subject line.
  final String subject;

  /// From address.
  final String from;

  /// To recipients.
  final String to;

  /// CC recipients.
  final String? cc;

  /// BCC recipients (`email2:Bcc`, EAS 16.x drafts).
  final String? bcc;

  /// Display name in To field.
  final String? displayTo;

  /// Date received.
  final DateTime? dateReceived;

  /// Read status.
  final bool read;

  /// Importance level.
  final EmailImportance importance;

  /// Message class (e.g., 'IPM.Note', 'IPM.Note.Mobile.SMS').
  final String? messageClass;

  /// Body content.
  final String? body;

  /// Body type (1=plain, 2=HTML, 3=RTF, 4=MIME).
  final int bodyType;

  /// Whether body is truncated.
  final bool bodyTruncated;

  /// Estimated body size.
  final int? estimatedBodySize;

  /// Full `airsyncbase:Body` (incl. Preview), if present.
  final EasBody? bodyDetails;

  /// `airsyncbase:BodyPart` (conversation body part, EAS 14.1+).
  final EasBodyPart? bodyPart;

  /// Native body type on the server (`airsyncbase:NativeBodyType`).
  final int? nativeBodyType;

  /// Thread topic.
  final String? threadTopic;

  /// Reply-to address.
  final String? replyTo;

  /// Attachments.
  final List<EasAttachment> attachments;

  /// Conversation ID (`email2:ConversationId`; opaque bytes are
  /// base64-encoded).
  final String? conversationId;

  /// Conversation index (`email2:ConversationIndex`, raw bytes).
  final Uint8List? conversationIndex;

  /// Flag status (0=cleared, 1=complete, 2=active).
  final int flagStatus;

  /// Full follow-up flag, if present.
  final EasFlag? flag;

  /// Whether this is a draft.
  final bool isDraft;

  /// Content class (e.g., 'urn:content-classes:message').
  final String? contentClass;

  /// Internet code page ID.
  final int? internetCPID;

  /// Categories.
  final List<String> categories;

  /// Last verb executed (1=ReplyToSender, 2=ReplyToAll, 3=Forward).
  final int? lastVerbExecuted;

  /// Time of last verb execution.
  final DateTime? lastVerbExecutionTime;

  /// Whether email was received as BCC.
  final bool? receivedAsBcc;

  /// Sensitivity: 0=normal, 1=personal, 2=private, 3=confidential.
  final int? sensitivity;

  /// Meeting request details (meeting invitation messages).
  final EasMeetingRequest? meetingRequest;

  /// Sender (when sent on behalf of [from]).
  final String? sender;

  /// Account the message belongs to (`email2:AccountId`).
  final String? accountId;

  /// Voice-mail caller ID (`email2:UmCallerID`).
  final String? umCallerId;

  /// Voice-mail user notes (`email2:UmUserNotes`).
  final String? umUserNotes;

  /// IRM license of a protected message (MS-ASRM).
  final EasRightsManagementLicense? rightsManagementLicense;

  /// EAS 2.5 MIME content (`email:MIMEData`).
  final String? mimeData;

  /// EAS 2.5 MIME size (`email:MIMESize`).
  final int? mimeSize;

  /// EAS 2.5 MIME truncation flag (`email:MIMETruncated`).
  final bool? mimeTruncated;

  const EasEmail({
    required this.serverId,
    this.subject = '',
    this.from = '',
    this.to = '',
    this.cc,
    this.bcc,
    this.displayTo,
    this.dateReceived,
    this.read = false,
    this.importance = EmailImportance.normal,
    this.messageClass,
    this.body,
    this.bodyType = 1,
    this.bodyTruncated = false,
    this.estimatedBodySize,
    this.bodyDetails,
    this.bodyPart,
    this.nativeBodyType,
    this.threadTopic,
    this.replyTo,
    this.attachments = const [],
    this.conversationId,
    this.conversationIndex,
    this.flagStatus = 0,
    this.flag,
    this.isDraft = false,
    this.contentClass,
    this.internetCPID,
    this.categories = const [],
    this.lastVerbExecuted,
    this.lastVerbExecutionTime,
    this.receivedAsBcc,
    this.sensitivity,
    this.meetingRequest,
    this.sender,
    this.accountId,
    this.umCallerId,
    this.umUserNotes,
    this.rightsManagementLicense,
    this.mimeData,
    this.mimeSize,
    this.mimeTruncated,
  });

  /// Parse an email (or SMS) from `ApplicationData` / `Properties`.
  factory EasEmail.fromApplicationData(String serverId, WbxmlElement data) {
    final bodyDetails = EasBody.of(data);
    final bodyPartEl = data.findChild('AirSyncBase', 'BodyPart');
    final flagEl = data.findChild('Email', 'Flag');
    final flag = flagEl == null ? null : EasFlag.fromElement(flagEl);
    final meetingEl = data.findChild('Email', 'MeetingRequest');
    return EasEmail(
      serverId: serverId,
      subject: data.str('Email', 'Subject') ?? '',
      from: data.str('Email', 'From') ?? '',
      to: data.str('Email', 'To') ?? '',
      cc: data.str('Email', 'Cc'),
      bcc: data.str('Email2', 'Bcc'),
      displayTo: data.str('Email', 'DisplayTo'),
      dateReceived: data.date('Email', 'DateReceived'),
      read: data.boolean('Email', 'Read') ?? false,
      importance: EmailImportance.fromValue(
        data.integer('Email', 'Importance') ?? 1,
      ),
      messageClass: data.str('Email', 'MessageClass'),
      body: bodyDetails?.data ?? data.str('Email', 'Body'),
      bodyType: bodyDetails?.type ?? 1,
      bodyTruncated:
          bodyDetails?.truncated ??
          data.boolean('Email', 'BodyTruncated') ??
          false,
      estimatedBodySize:
          bodyDetails?.estimatedDataSize ?? data.integer('Email', 'BodySize'),
      bodyDetails: bodyDetails,
      bodyPart: bodyPartEl == null ? null : EasBodyPart.fromElement(bodyPartEl),
      nativeBodyType: data.integer('AirSyncBase', 'NativeBodyType'),
      threadTopic: data.str('Email', 'ThreadTopic'),
      replyTo: data.str('Email', 'ReplyTo'),
      attachments: EasAttachment.listOf(data),
      conversationId: data.idString('Email2', 'ConversationId'),
      conversationIndex: data.bytes('Email2', 'ConversationIndex'),
      flagStatus: flag?.status ?? 0,
      flag: flag,
      isDraft: data.boolean('Email2', 'IsDraft') ?? false,
      contentClass: data.str('Email', 'ContentClass'),
      internetCPID: data.integer('Email', 'InternetCPID'),
      categories: data.list('Email', 'Categories', 'Category') ?? const [],
      lastVerbExecuted: data.integer('Email2', 'LastVerbExecuted'),
      lastVerbExecutionTime: data.date('Email2', 'LastVerbExecutionTime'),
      receivedAsBcc: data.boolean('Email2', 'ReceivedAsBcc'),
      sensitivity: data.integer('Email', 'Sensitivity'),
      meetingRequest: meetingEl == null
          ? null
          : EasMeetingRequest.fromElement(meetingEl),
      sender: data.str('Email2', 'Sender'),
      accountId: data.str('Email2', 'AccountId'),
      umCallerId: data.str('Email2', 'UmCallerID'),
      umUserNotes: data.str('Email2', 'UmUserNotes'),
      rightsManagementLicense: EasRightsManagementLicense.of(data),
      mimeData: data.str('Email', 'MIMEData'),
      mimeSize: data.integer('Email', 'MIMESize'),
      mimeTruncated: data.boolean('Email', 'MIMETruncated'),
    );
  }

  /// Whether this is an SMS message (`IPM.Note.Mobile.SMS`).
  bool get isSms => messageClass?.startsWith('IPM.Note.Mobile.SMS') ?? false;

  @override
  String toString() => 'EasEmail($serverId)';
}
