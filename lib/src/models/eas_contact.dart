/// EAS contact model.
library;

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

  /// Nickname.
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

  /// Home phone number.
  final String? homePhone;

  /// Business fax number.
  final String? businessFax;

  /// Company name.
  final String? companyName;

  /// Department.
  final String? department;

  /// Job title.
  final String? jobTitle;

  /// Business street address.
  final String? businessAddressStreet;

  /// Business city.
  final String? businessAddressCity;

  /// Business postal code.
  final String? businessAddressPostalCode;

  /// Business country.
  final String? businessAddressCountry;

  /// Home street address.
  final String? homeAddressStreet;

  /// Home city.
  final String? homeAddressCity;

  /// Home postal code.
  final String? homeAddressPostalCode;

  /// Home country.
  final String? homeAddressCountry;

  /// Birthday.
  final DateTime? birthday;

  /// Wedding anniversary.
  final DateTime? anniversary;

  /// Notes/body.
  final String? body;

  /// Web page URL.
  final String? webPage;

  /// Office location.
  final String? officeLocation;

  /// Categories.
  final List<String> categories;

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
    this.homePhone,
    this.businessFax,
    this.companyName,
    this.department,
    this.jobTitle,
    this.businessAddressStreet,
    this.businessAddressCity,
    this.businessAddressPostalCode,
    this.businessAddressCountry,
    this.homeAddressStreet,
    this.homeAddressCity,
    this.homeAddressPostalCode,
    this.homeAddressCountry,
    this.birthday,
    this.anniversary,
    this.body,
    this.webPage,
    this.officeLocation,
    this.categories = const [],
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

  /// Full display name derived from first+last or fileAs.
  String get displayName {
    if (fileAs != null && fileAs!.isNotEmpty) return fileAs!;
    final parts = [firstName, lastName].whereType<String>().where((s) => s.isNotEmpty);
    return parts.join(' ');
  }

  @override
  String toString() =>
      'EasContact($serverId, name: $displayName, email: $email1)';
}
