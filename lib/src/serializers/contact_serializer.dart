/// Serializes EasContact to WBXML ApplicationData for Sync Add/Change.
library;

import '../models/eas_contact.dart';
import '../wbxml/wbxml_document.dart';

/// Serializer for contact items (Sync Add/Change).
class ContactSerializer {
  const ContactSerializer._();

  /// Serialize contact for Sync Add/Change ApplicationData.
  static WbxmlElement serialize(EasContact contact) {
    final children = <WbxmlElement>[];

    void addField(String tag, String? value, {int cp = 1}) {
      if (value != null && value.isNotEmpty) {
        children.add(WbxmlElement.withText(
          namespace: cp == 1 ? 'Contacts' : 'Contacts2',
          tag: tag,
          text: value,
          codePageIndex: cp,
        ));
      }
    }

    // Contacts (CP 1) fields
    addField('FileAs', contact.fileAs);
    addField('FirstName', contact.firstName);
    addField('MiddleName', contact.middleName);
    addField('LastName', contact.lastName);
    addField('NickName', contact.nickName);
    addField('Email1Address', contact.email1);
    addField('Email2Address', contact.email2);
    addField('Email3Address', contact.email3);
    addField('MobilePhoneNumber', contact.mobilePhone);
    addField('BusinessPhoneNumber', contact.businessPhone);
    addField('HomePhoneNumber', contact.homePhone);
    addField('BusinessFaxNumber', contact.businessFax);
    addField('CompanyName', contact.companyName);
    addField('Department', contact.department);
    addField('JobTitle', contact.jobTitle);
    addField('Title', contact.title);
    addField('Suffix', contact.suffix);
    addField('WebPage', contact.webPage);
    addField('OfficeLocation', contact.officeLocation);

    // Business address
    addField('BusinessAddressStreet', contact.businessAddressStreet);
    addField('BusinessAddressCity', contact.businessAddressCity);
    addField('BusinessAddressPostalCode', contact.businessAddressPostalCode);
    addField('BusinessAddressCountry', contact.businessAddressCountry);

    // Home address
    addField('HomeAddressStreet', contact.homeAddressStreet);
    addField('HomeAddressCity', contact.homeAddressCity);
    addField('HomeAddressPostalCode', contact.homeAddressPostalCode);
    addField('HomeAddressCountry', contact.homeAddressCountry);

    // Dates
    if (contact.birthday != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Contacts',
        tag: 'Birthday',
        text: contact.birthday!.toUtc().toIso8601String(),
        codePageIndex: 1,
      ));
    }

    if (contact.anniversary != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Contacts',
        tag: 'Anniversary',
        text: contact.anniversary!.toUtc().toIso8601String(),
        codePageIndex: 1,
      ));
    }

    // Picture (base64)
    if (contact.picture != null) {
      children.add(WbxmlElement.withText(
        namespace: 'Contacts',
        tag: 'Picture',
        text: contact.picture!,
        codePageIndex: 1,
      ));
    }

    // Contacts2 (CP 12) fields
    addField('IMAddress', contact.imAddress, cp: 12);
    addField('IMAddress2', contact.imAddress2, cp: 12);
    addField('IMAddress3', contact.imAddress3, cp: 12);
    addField('CompanyMainPhone', contact.companyMainPhone, cp: 12);
    addField('AccountName', contact.accountName, cp: 12);
    addField('MMS', contact.mms, cp: 12);
    addField('CustomerId', contact.customerId, cp: 12);
    addField('GovernmentId', contact.governmentId, cp: 12);
    addField('ManagerName', contact.managerName, cp: 12);

    // Categories
    if (contact.categories.isNotEmpty) {
      children.add(WbxmlElement(
        namespace: 'Contacts',
        tag: 'Categories',
        codePageIndex: 1,
        children: contact.categories
            .map((c) => WbxmlElement.withText(
                  namespace: 'Contacts',
                  tag: 'Category',
                  text: c,
                  codePageIndex: 1,
                ))
            .toList(),
      ));
    }

    // Body
    if (contact.body != null) {
      children.add(WbxmlElement(
        namespace: 'AirSyncBase',
        tag: 'Body',
        codePageIndex: 17,
        children: [
          WbxmlElement.withText(
            namespace: 'AirSyncBase',
            tag: 'Type',
            text: '1',
            codePageIndex: 17,
          ),
          WbxmlElement.withText(
            namespace: 'AirSyncBase',
            tag: 'Data',
            text: contact.body!,
            codePageIndex: 17,
          ),
        ],
      ));
    }

    return WbxmlElement(
      namespace: 'AirSync',
      tag: 'ApplicationData',
      codePageIndex: 0,
      children: children,
    );
  }
}
