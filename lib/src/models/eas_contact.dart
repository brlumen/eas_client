/// EAS contact model (MS-ASCNTC: Contacts and Contacts2 namespaces).
library;

import '../wbxml/wbxml_document.dart';
import 'eas_body.dart';
import 'wbxml_helpers.dart';

/// EAS contact (address book entry).
class EasContact {
  /// Server-assigned ID.
  final String serverId;

  /// Display/sort name (FileAs).
  final String? fileAs;

  /// First name.
  final String? firstName;

  /// Middle name.
  final String? middleName;

  /// Last name.
  final String? lastName;

  /// Nickname (`contacts2:NickName`).
  final String? nickName;

  /// Primary email address.
  final String? email1;

  /// Secondary email address.
  final String? email2;

  /// Tertiary email address.
  final String? email3;

  /// Mobile phone number.
  final String? mobilePhone;

  /// Business phone number.
  final String? businessPhone;

  /// Second business phone number.
  final String? business2Phone;

  /// Home phone number.
  final String? homePhone;

  /// Second home phone number.
  final String? home2Phone;

  /// Business fax number.
  final String? businessFax;

  /// Home fax number.
  final String? homeFax;

  /// Car phone number.
  final String? carPhone;

  /// Pager number.
  final String? pager;

  /// Radio phone number.
  final String? radioPhone;

  /// Assistant name.
  final String? assistantName;

  /// Assistant phone number.
  final String? assistantPhone;

  /// Company name.
  final String? companyName;

  /// Department.
  final String? department;

  /// Job title.
  final String? jobTitle;

  /// Business address.
  final String? businessAddressStreet;
  final String? businessAddressCity;
  final String? businessAddressState;
  final String? businessAddressPostalCode;
  final String? businessAddressCountry;

  /// Home address.
  final String? homeAddressStreet;
  final String? homeAddressCity;
  final String? homeAddressState;
  final String? homeAddressPostalCode;
  final String? homeAddressCountry;

  /// Other address.
  final String? otherAddressStreet;
  final String? otherAddressCity;
  final String? otherAddressState;
  final String? otherAddressPostalCode;
  final String? otherAddressCountry;

  /// Birthday.
  final DateTime? birthday;

  /// Wedding anniversary.
  final DateTime? anniversary;

  /// Spouse name.
  final String? spouse;

  /// Children names.
  final List<String> children;

  /// Notes/body.
  final String? body;

  /// Full `airsyncbase:Body`, if present.
  final EasBody? bodyDetails;

  /// Native body type on the server.
  final int? nativeBodyType;

  /// Web page URL.
  final String? webPage;

  /// Office location.
  final String? officeLocation;

  /// Phonetic (Yomi) names.
  final String? yomiCompanyName;
  final String? yomiFirstName;
  final String? yomiLastName;

  /// Categories.
  final List<String> categories;

  /// Alias (server-only, GAL/recipient info).
  final String? alias;

  /// Weighted rank (server-only, recipient information cache).
  final int? weightedRank;

  // ─── Contacts2 (CP 12) fields ────────────────────────────────────────────

  /// IM address.
  final String? imAddress;

  /// Secondary IM address.
  final String? imAddress2;

  /// Tertiary IM address.
  final String? imAddress3;

  /// Company main phone.
  final String? companyMainPhone;

  /// Account name.
  final String? accountName;

  /// MMS address.
  final String? mms;

  /// Customer ID.
  final String? customerId;

  /// Government ID.
  final String? governmentId;

  /// Manager name.
  final String? managerName;

  // ─── Additional Contacts (CP 1) fields ───────────────────────────────────

  /// Title (Mr., Ms., Dr., etc.).
  final String? title;

  /// Name suffix (Jr., Sr., III, etc.).
  final String? suffix;

  /// Picture (base64-encoded).
  final String? picture;

  const EasContact({
    required this.serverId,
    this.fileAs,
    this.firstName,
    this.middleName,
    this.lastName,
    this.nickName,
    this.email1,
    this.email2,
    this.email3,
    this.mobilePhone,
    this.businessPhone,
    this.business2Phone,
    this.homePhone,
    this.home2Phone,
    this.businessFax,
    this.homeFax,
    this.carPhone,
    this.pager,
    this.radioPhone,
    this.assistantName,
    this.assistantPhone,
    this.companyName,
    this.department,
    this.jobTitle,
    this.businessAddressStreet,
    this.businessAddressCity,
    this.businessAddressState,
    this.businessAddressPostalCode,
    this.businessAddressCountry,
    this.homeAddressStreet,
    this.homeAddressCity,
    this.homeAddressState,
    this.homeAddressPostalCode,
    this.homeAddressCountry,
    this.otherAddressStreet,
    this.otherAddressCity,
    this.otherAddressState,
    this.otherAddressPostalCode,
    this.otherAddressCountry,
    this.birthday,
    this.anniversary,
    this.spouse,
    this.children = const [],
    this.body,
    this.bodyDetails,
    this.nativeBodyType,
    this.webPage,
    this.officeLocation,
    this.yomiCompanyName,
    this.yomiFirstName,
    this.yomiLastName,
    this.categories = const [],
    this.alias,
    this.weightedRank,
    this.imAddress,
    this.imAddress2,
    this.imAddress3,
    this.companyMainPhone,
    this.accountName,
    this.mms,
    this.customerId,
    this.governmentId,
    this.managerName,
    this.title,
    this.suffix,
    this.picture,
  });

  /// Parse a contact from `ApplicationData` / `Properties`.
  factory EasContact.fromApplicationData(String serverId, WbxmlElement data) {
    String? c(String tag) => data.str('Contacts', tag);
    String? c2(String tag) => data.str('Contacts2', tag);
    final bodyDetails = EasBody.anyOf(data, 'Contacts');
    return EasContact(
      serverId: serverId,
      fileAs: c('FileAs'),
      firstName: c('FirstName'),
      middleName: c('MiddleName'),
      lastName: c('LastName'),
      nickName: c2('NickName') ?? c('NickName'),
      email1: c('Email1Address'),
      email2: c('Email2Address'),
      email3: c('Email3Address'),
      mobilePhone: c('MobilePhoneNumber'),
      businessPhone: c('BusinessPhoneNumber'),
      business2Phone: c('Business2PhoneNumber'),
      homePhone: c('HomePhoneNumber'),
      home2Phone: c('Home2PhoneNumber'),
      businessFax: c('BusinessFaxNumber'),
      homeFax: c('HomeFaxNumber'),
      carPhone: c('CarPhoneNumber'),
      pager: c('PagerNumber'),
      radioPhone: c('RadioPhoneNumber'),
      assistantName: c('AssistantName'),
      assistantPhone: c('AssistantPhoneNumber'),
      companyName: c('CompanyName'),
      department: c('Department'),
      jobTitle: c('JobTitle'),
      businessAddressStreet: c('BusinessAddressStreet'),
      businessAddressCity: c('BusinessAddressCity'),
      businessAddressState: c('BusinessAddressState'),
      businessAddressPostalCode: c('BusinessAddressPostalCode'),
      businessAddressCountry: c('BusinessAddressCountry'),
      homeAddressStreet: c('HomeAddressStreet'),
      homeAddressCity: c('HomeAddressCity'),
      homeAddressState: c('HomeAddressState'),
      homeAddressPostalCode: c('HomeAddressPostalCode'),
      homeAddressCountry: c('HomeAddressCountry'),
      otherAddressStreet: c('OtherAddressStreet'),
      otherAddressCity: c('OtherAddressCity'),
      otherAddressState: c('OtherAddressState'),
      otherAddressPostalCode: c('OtherAddressPostalCode'),
      otherAddressCountry: c('OtherAddressCountry'),
      birthday: data.date('Contacts', 'Birthday'),
      anniversary: data.date('Contacts', 'Anniversary'),
      spouse: c('Spouse'),
      children: data.list('Contacts', 'Children', 'Child') ?? const [],
      body: bodyDetails?.data,
      bodyDetails: bodyDetails,
      nativeBodyType: data.integer('AirSyncBase', 'NativeBodyType'),
      webPage: c('WebPage'),
      officeLocation: c('OfficeLocation'),
      yomiCompanyName: c('YomiCompanyName'),
      yomiFirstName: c('YomiFirstName'),
      yomiLastName: c('YomiLastName'),
      categories: data.list('Contacts', 'Categories', 'Category') ?? const [],
      alias: c('Alias'),
      weightedRank: data.integer('Contacts', 'WeightedRank'),
      imAddress: c2('IMAddress'),
      imAddress2: c2('IMAddress2'),
      imAddress3: c2('IMAddress3'),
      companyMainPhone: c2('CompanyMainPhone'),
      accountName: c2('AccountName'),
      mms: c2('MMS'),
      customerId: c2('CustomerId'),
      governmentId: c2('GovernmentId'),
      managerName: c2('ManagerName'),
      title: c('Title'),
      suffix: c('Suffix'),
      picture: c('Picture'),
    );
  }

  /// Full display name derived from first+last or fileAs.
  String get displayName {
    if (fileAs != null && fileAs!.isNotEmpty) return fileAs!;
    final parts = [
      firstName,
      lastName,
    ].whereType<String>().where((s) => s.isNotEmpty);
    return parts.join(' ');
  }

  @override
  String toString() => 'EasContact($serverId)';
}
