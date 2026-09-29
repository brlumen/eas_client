/// Global EAS status codes shared by all commands.
///
/// Returned in the top-level `Status` element of a command response.
/// Codes below 101 are command-specific and are not covered here.
///
/// Reference: MS-ASCMD section 2.2.2 (Common Status Codes)
library;

/// Common status codes 101–184 (MS-ASCMD 2.2.2).
enum EasGlobalStatus {
  invalidContent(101, 'Invalid content'),
  invalidWbxml(102, 'Invalid WBXML'),
  invalidXml(103, 'Invalid XML'),
  invalidDateTime(104, 'Invalid DateTime value'),
  invalidCombinationOfIds(105, 'Invalid combination of IDs'),
  invalidIds(106, 'Invalid IDs'),
  invalidMime(107, 'Invalid MIME'),
  deviceIdMissingOrInvalid(108, 'DeviceId missing or invalid'),
  deviceTypeMissingOrInvalid(109, 'DeviceType missing or invalid'),
  serverError(110, 'Server error'),
  serverErrorRetryLater(111, 'Server error, retry later'),
  activeDirectoryAccessDenied(112, 'Active Directory access denied'),
  mailboxQuotaExceeded(113, 'Mailbox quota exceeded'),
  mailboxServerOffline(114, 'Mailbox server offline'),
  sendQuotaExceeded(115, 'Send quota exceeded'),
  messageRecipientUnresolved(116, 'Message recipient unresolved'),
  messageReplyNotAllowed(117, 'Message reply not allowed'),
  messagePreviouslySent(118, 'Message previously sent'),
  messageHasNoRecipient(119, 'Message has no recipient'),
  mailSubmissionFailed(120, 'Mail submission failed'),
  messageReplyFailed(121, 'Message reply failed'),
  attachmentIsTooLarge(122, 'Attachment is too large'),
  userHasNoMailbox(123, 'User has no mailbox'),
  userCannotBeAnonymous(124, 'User cannot be anonymous'),
  userPrincipalCouldNotBeFound(125, 'User principal could not be found'),
  userDisabledForSync(126, 'User disabled for sync'),
  userOnNewMailboxCannotSync(127, 'User on new mailbox cannot sync'),
  userOnLegacyMailboxCannotSync(128, 'User on legacy mailbox cannot sync'),
  deviceIsBlockedForThisUser(129, 'Device is blocked for this user'),
  accessDenied(130, 'Access denied'),
  accountDisabled(131, 'Account disabled'),
  syncStateNotFound(132, 'Sync state not found'),
  syncStateLocked(133, 'Sync state locked'),
  syncStateCorrupt(134, 'Sync state corrupt'),
  syncStateAlreadyExists(135, 'Sync state already exists'),
  syncStateVersionInvalid(136, 'Sync state version invalid'),
  commandNotSupported(137, 'Command not supported'),
  versionNotSupported(138, 'Version not supported'),
  deviceNotFullyProvisionable(139, 'Device not fully provisionable'),
  remoteWipeRequested(140, 'Remote wipe requested'),
  legacyDeviceOnStrictPolicy(141, 'Legacy device on strict policy'),
  deviceNotProvisioned(142, 'Device not provisioned'),
  policyRefresh(143, 'Policy refresh'),
  invalidPolicyKey(144, 'Invalid policy key'),
  externallyManagedDevicesNotAllowed(
    145,
    'Externally managed devices not allowed',
  ),
  noRecurrenceInCalendar(146, 'No recurrence in calendar'),
  unexpectedItemClass(147, 'Unexpected item class'),
  remoteServerHasNoSsl(148, 'Remote server has no SSL'),
  invalidStoredRequest(149, 'Invalid stored request'),
  itemNotFound(150, 'Item not found'),
  tooManyFolders(151, 'Too many folders'),
  noFoldersFound(152, 'No folders found'),
  itemsLostAfterMove(153, 'Items lost after move'),
  failureInMoveOperation(154, 'Failure in move operation'),
  moveCommandDisallowedForNonPersistentMoveAction(
    155,
    'Move disallowed for non-persistent move action',
  ),
  moveCommandInvalidDestinationFolder(
    156,
    'Move command invalid destination folder',
  ),
  availabilityTooManyRecipients(160, 'Availability: too many recipients'),
  availabilityDlLimitReached(161, 'Availability: DL limit reached'),
  availabilityTransientFailure(162, 'Availability: transient failure'),
  availabilityFailure(163, 'Availability: failure'),
  bodyPartPreferenceTypeNotSupported(
    164,
    'Body part preference type not supported',
  ),
  deviceInformationRequired(165, 'Device information required'),
  invalidAccountId(166, 'Invalid account ID'),
  accountSendDisabled(167, 'Account send disabled'),
  irmFeatureDisabled(168, 'IRM feature disabled'),
  irmTransientError(169, 'IRM transient error'),
  irmPermanentError(170, 'IRM permanent error'),
  irmInvalidTemplateId(171, 'IRM invalid template ID'),
  irmOperationNotPermitted(172, 'IRM operation not permitted'),
  noPicture(173, 'No picture'),
  pictureTooLarge(174, 'Picture too large'),
  pictureLimitReached(175, 'Picture limit reached'),
  bodyPartConversationTooLarge(176, 'Body part conversation too large'),
  maximumDevicesReached(177, 'Maximum devices reached'),
  invalidMimeBodyCombination(178, 'Invalid MIME body combination'),
  invalidSmartForwardParameters(179, 'Invalid SmartForward parameters'),
  invalidRecipients(183, 'Invalid recipients'),
  oneOrMoreExceptionsFailed(184, 'One or more exceptions failed');

  final int code;
  final String description;

  const EasGlobalStatus(this.code, this.description);

  /// Lowest global status code; smaller codes are command-specific.
  static const int minCode = 101;

  /// Whether the client must re-run Provision (142, 143, 144) —
  /// equivalent to HTTP 449.
  bool get requiresProvisioning =>
      this == deviceNotProvisioned ||
      this == policyRefresh ||
      this == invalidPolicyKey;

  static EasGlobalStatus? fromCode(int code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}
