/// Serializes EasContact to WBXML ApplicationData for Sync Add/Change.
///
/// Reference: MS-ASCNTC 2.2.2; writable elements per MS-ASCMD 6.45.
/// `Alias` and `WeightedRank` are server-only and never sent.
library;

import '../models/eas_body.dart';
import '../models/eas_contact.dart';
import '../models/wbxml_helpers.dart';
import '../wbxml/wbxml_document.dart';

/// Serializer for contact items (Sync Add/Change).
class ContactSerializer {
  const ContactSerializer._();

  /// Serialize contact for Sync Add/Change ApplicationData.
  static WbxmlElement serialize(
    EasContact contact, {
    String protocolVersion = '16.1',
  }) {
    final v = protocolVersionValue(protocolVersion);
    const n = 'Contacts';
    const n2 = 'Contacts2';
    final c = <WbxmlElement>[]
      ..addDate(n, 'Anniversary', contact.anniversary)
      ..addText(n, 'AssistantName', contact.assistantName)
      ..addText(n, 'AssistantPhoneNumber', contact.assistantPhone)
      ..addDate(n, 'Birthday', contact.birthday)
      ..addText(n, 'Business2PhoneNumber', contact.business2Phone)
      ..addText(n, 'BusinessAddressCity', contact.businessAddressCity)
      ..addText(n, 'BusinessAddressCountry', contact.businessAddressCountry)
      ..addText(
        n,
        'BusinessAddressPostalCode',
        contact.businessAddressPostalCode,
      )
      ..addText(n, 'BusinessAddressState', contact.businessAddressState)
      ..addText(n, 'BusinessAddressStreet', contact.businessAddressStreet)
      ..addText(n, 'BusinessFaxNumber', contact.businessFax)
      ..addText(n, 'BusinessPhoneNumber', contact.businessPhone)
      ..addText(n, 'CarPhoneNumber', contact.carPhone)
      ..addList(n, 'Categories', 'Category', contact.categories)
      ..addList(n, 'Children', 'Child', contact.children)
      ..addText(n, 'CompanyName', contact.companyName)
      ..addText(n, 'Department', contact.department)
      ..addText(n, 'Email1Address', contact.email1)
      ..addText(n, 'Email2Address', contact.email2)
      ..addText(n, 'Email3Address', contact.email3)
      ..addText(n, 'FileAs', contact.fileAs)
      ..addText(n, 'FirstName', contact.firstName)
      ..addText(n, 'Home2PhoneNumber', contact.home2Phone)
      ..addText(n, 'HomeAddressCity', contact.homeAddressCity)
      ..addText(n, 'HomeAddressCountry', contact.homeAddressCountry)
      ..addText(n, 'HomeAddressPostalCode', contact.homeAddressPostalCode)
      ..addText(n, 'HomeAddressState', contact.homeAddressState)
      ..addText(n, 'HomeAddressStreet', contact.homeAddressStreet)
      ..addText(n, 'HomeFaxNumber', contact.homeFax)
      ..addText(n, 'HomePhoneNumber', contact.homePhone)
      ..addText(n, 'JobTitle', contact.jobTitle)
      ..addText(n, 'LastName', contact.lastName)
      ..addText(n, 'MiddleName', contact.middleName)
      ..addText(n, 'MobilePhoneNumber', contact.mobilePhone)
      ..addText(n, 'OfficeLocation', contact.officeLocation)
      ..addText(n, 'OtherAddressCity', contact.otherAddressCity)
      ..addText(n, 'OtherAddressCountry', contact.otherAddressCountry)
      ..addText(n, 'OtherAddressPostalCode', contact.otherAddressPostalCode)
      ..addText(n, 'OtherAddressState', contact.otherAddressState)
      ..addText(n, 'OtherAddressStreet', contact.otherAddressStreet)
      ..addText(n, 'PagerNumber', contact.pager)
      ..addText(n, 'RadioPhoneNumber', contact.radioPhone)
      ..addText(n, 'Spouse', contact.spouse)
      ..addText(n, 'Suffix', contact.suffix)
      ..addText(n, 'Title', contact.title)
      ..addText(n, 'WebPage', contact.webPage)
      ..addText(n, 'YomiCompanyName', contact.yomiCompanyName)
      ..addText(n, 'YomiFirstName', contact.yomiFirstName)
      ..addText(n, 'YomiLastName', contact.yomiLastName)
      ..addText(n, 'Picture', contact.picture)
      // Contacts2 (CP 12)
      ..addText(n2, 'CustomerId', contact.customerId)
      ..addText(n2, 'GovernmentId', contact.governmentId)
      ..addText(n2, 'IMAddress', contact.imAddress)
      ..addText(n2, 'IMAddress2', contact.imAddress2)
      ..addText(n2, 'IMAddress3', contact.imAddress3)
      ..addText(n2, 'ManagerName', contact.managerName)
      ..addText(n2, 'CompanyMainPhone', contact.companyMainPhone)
      ..addText(n2, 'AccountName', contact.accountName)
      ..addText(n2, 'NickName', contact.nickName)
      ..addText(n2, 'MMS', contact.mms);
    if (contact.body case final body?) {
      if (v < 120) {
        c.addText(n, 'Body', body);
      } else {
        c.add(EasBody.toElement(body, type: contact.bodyDetails?.type ?? 1));
      }
    }
    return applicationData(c);
  }
}
