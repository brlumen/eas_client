# eas_client

Dart implementation of the Microsoft Exchange ActiveSync (EAS) protocol client.
Supports WBXML codec, email/contacts/calendar/tasks sync, push notifications, and Autodiscover.

> **Alpha release.** The API is unstable and may change without notice.
> Use at your own risk in production environments.

## Features

- **WBXML codec** — WAP-192 encoding/decoding with 25 EAS code pages
- **Autodiscover** — automatic server discovery by email (MS-OXDISCO), incl. opt-in HTTP redirect and DNS SRV steps
- **Provisioning** — security policy negotiation (MS-ASPROV)
- **Sync** — folder and item synchronization (email, contacts, calendar, tasks, notes)
- **Ping** — push notifications via long-poll (MS-ASCMD)
- **SendMail** — send email through EAS
- **SmartReply / SmartForward** — reply/forward with server-side original body
- **MeetingResponse** — accept, tentatively accept, or decline meeting invitations
- **Search** — server-side mailbox search
- **MoveItems** — move items between folders
- **ItemOperations** — fetch full message body, attachments, and empty folders
- **FolderCreate / FolderDelete / FolderUpdate** — folder management
- **GetItemEstimate** — count items before sync
- **Settings** — get/set OOF (out-of-office), send device information
- **ResolveRecipients** — resolve email addresses to contact info
- **ValidateCert** — S/MIME certificate validation
- **Find** — GAL and mailbox search (EAS 16.1)

## Quick start

```dart
import 'package:eas_client/eas_client.dart';

// Generate a DeviceId once and persist it.
// Every request from the device MUST use the same DeviceId (MS-ASHTTP).
final deviceId = DeviceIdGenerator.generate(); // 32 hex characters

// Automatic server discovery
final client = await EasClient.autodiscover(
  email: 'user@example.com',
  password: 'password',
  // username: 'DOMAIN\user', // when the login differs from the email
  deviceId: deviceId,
);

// Or connect directly
final client = EasClient(
  server: 'mail.example.com',
  credentials: BasicCredentials(
    username: 'user@example.com',
    password: 'password',
  ),
  deviceId: deviceId,
);

// Provisioning (required before other commands).
// Report the real outcome of applying the policies; servers with
// "Allow non-provisionable devices" disabled reject anything but success.
try {
  await client.provision(policyAckStatus: PolicyAckStatus.notApplied);
} on EasPolicyNotAcceptedException {
  // Apply the policies (see "Provisioning" below), then:
  await client.provision(policyAckStatus: PolicyAckStatus.success);
}

// Get folder list
final folders = await client.syncFolders();

// Sync inbox
final inboxId = folders.addedFolders
    .firstWhere((f) => f.type == EasFolderType.defaultInbox)
    .serverId;
final emails = await client.fullSync(inboxId);

// Sync calendar
final calendarId = folders.addedFolders
    .firstWhere((f) => f.type == EasFolderType.defaultCalendar)
    .serverId;
final events = await client.fullSyncCalendar(calendarId);

// Sync tasks
final tasksId = folders.addedFolders
    .firstWhere((f) => f.type == EasFolderType.defaultTasks)
    .serverId;
final tasks = await client.fullSyncTasks(tasksId);

// Sync contacts
final contactsId = folders.addedFolders
    .firstWhere((f) => f.type == EasFolderType.defaultContacts)
    .serverId;
final contacts = await client.fullSyncContacts(contactsId);

// Get OOF status
final settings = await client.getSettings();
print(settings.oof?.state);

client.dispose();
```

### Persistent sync state

Sync keys live in an `EasSyncStateStore` (in memory by default). Pass your
own implementation to resume after a restart:

```dart
final client = EasClient(/* ... */, syncStateStore: MyDbSyncStateStore());
```

### Partial changes and MIME bytes

`SyncResult.emailChanges` holds `EasEmailChange` items with only the
properties the server sent (`read`, `flag`, `categories`, ... are `null`
when unchanged). MIME is handled as bytes: `EasEmail.mime` (Body Type 4 or
EAS 2.5 `MIMEData`) and `sendMail` / `smartReply` / `smartForward`
(`mimeContent: utf8.encode(text)`).

### Custom transport (raw HTTP/1.1)

To run a command over your own socket (e.g. a Ping kept open by a
tunneling proxy):

```dart
final ping = PingCommand(folders: [PingFolder(id: inboxId)], heartbeatInterval: 900);
socket.add(client.buildRawRequest(ping)); // full HTTP/1.1 request
// ... collect bytes until EasRawHttpParser.tryParse(bytes) != null
final result = client.parseRawHttpResponse(ping, bytes);
```

`updateCredentials()` replaces the credentials of a live client. The
`example/stand.dart` CLI probes a server for Ping/Sync interaction, MIME
attachments, folder types, heartbeat limits and post-handshake TLS bytes.

## Protocol coverage

Coverage by [MS-ASCMD](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-ascmd/) commands:

| Command | Status | Notes |
|---------|--------|-------|
| Autodiscover | ✅ | MS-OXDISCO; HTTP redirect and DNS SRV steps are opt-in — see below |
| OPTIONS | ✅ | HTTP OPTIONS, no WBXML |
| Provision | ✅ | 2-phase; policies are not enforced client-side |
| FolderSync | ✅ | |
| FolderCreate | ✅ | |
| FolderDelete | ✅ | |
| FolderUpdate | ✅ | rename / move |
| Sync (Email) | ✅ | |
| Sync (Calendar) | ✅ | |
| Sync (Tasks) | ✅ | |
| Sync (Contacts) | ✅ | |
| Sync (Notes) | ✅ | IPM.StickyNote |
| Ping | ✅ | long-poll push notifications |
| SendMail | ✅ | MIME content |
| SmartReply | ✅ | |
| SmartForward | ✅ | |
| ItemOperations — Fetch (email body) | ✅ | |
| ItemOperations — Fetch (attachment) | ✅ | |
| ItemOperations — EmptyFolderContents | ✅ | |
| MoveItems | ✅ | |
| Search | ✅ | |
| GetItemEstimate | ✅ | |
| MeetingResponse | ✅ | accept / tentative / decline |
| Settings — Get OOF | ✅ | |
| Settings — Set OOF | ✅ | |
| Settings — DeviceInformation | ✅ | |
| ResolveRecipients | ✅ | address book + GAL lookup |
| ValidateCert | ✅ | S/MIME certificate validation |
| Find | ✅ | EAS 16.1 only; GAL and mailbox (KQL) |
| GetAttachment | ❌ | deprecated; replaced by ItemOperations |

## Deviations from the Microsoft specification

### Autodiscover: unauthenticated steps are opt-in

Candidate order (MS-OXDISCO 3.1.5):

| Step | URL | Default | Parameter |
|---|---|---|---|
| 1 | `https://<domain>/autodiscover/autodiscover.xml` | on | — |
| 2 | `https://autodiscover.<domain>/autodiscover/autodiscover.xml` | on | — |
| 3 | `http://autodiscover.<domain>/...` → HTTPS redirect | off | `enableHttpRedirectStep` |
| 4 | DNS SRV `_autodiscover._tcp.<domain>` | off | `srvResolver` (`UdpDnsSrvResolver`) |
| 5 | `https://autodiscover-s.outlook.com/...` (Office 365) | on | `Autodiscover.useOffice365Fallback` |

Steps 3 and 4 rely on sources an attacker on the network can spoof
(plain HTTP, DNS). MS-OXDISCO 4.1 warns the client cannot identify the
server in that case, so the package hardens them:

- step 3 is a bare GET without credentials, body or cookies; only an HTTPS
  `Location` is used;
- hosts from steps 3 and 4 are used only after the consumer confirms them
  via `confirmRedirect` (e.g. by asking the user); without the callback
  they are rejected.

Credentials are sent only over HTTPS; redirects are followed only to HTTPS
(max 10, loops detected). If discovery fails, connect directly via the
`EasClient(server: ...)` constructor.

### DeviceId: consumer-side generation

`deviceId` is a required parameter of `EasClient`. The package does not
generate or store it automatically because:

- The package is pure Dart with no platform dependencies (no access to hardware IDs)
- Persistence strategy depends on the application (`SharedPreferences`, Hive, DB, etc.)
- Business logic (one ID per device vs. per account+device) is the consumer's decision

The utility method `DeviceIdGenerator.generate()` creates a random ID based on
`Random.secure()`. The consumer must persist the result and pass it on every
client creation.

### Provisioning: policies are not enforced

The package obtains a `PolicyKey` from the server and uses it in subsequent
request headers (MS-ASPROV). However, security policy contents (password
requirements, encryption, remote wipe, etc.) **are not enforced** on the
client side. Enforcement responsibility lies with the package consumer.

The consumer reports the outcome via `policyAckStatus`. If the server does
not allow non-provisionable devices (Exchange default), an acknowledgement
other than `PolicyAckStatus.success` gets no final `PolicyKey` and
`provision` throws `EasPolicyNotAcceptedException`. A remote wipe directive
throws `EasRemoteWipeException`; confirm it with `acknowledgeRemoteWipe`.

## Error handling

The package throws typed exceptions for key HTTP statuses:

| Exception | Trigger | Description |
|---|---|---|
| `EasAuthException` | HTTP 401 | Invalid credentials or expired OAuth token |
| `EasForbiddenException` | HTTP 403 | EAS disabled for user or blocked by policy |
| `EasRedirectException` | HTTP 451 | Server requires URL switch (mailbox migration) |
| `EasAccountException` | HTTP 456 / 457 | Account blocked / password expired |
| `EasServiceUnavailableException` | HTTP 503 | Server busy or throttling; see `retryAfter` |
| `EasProvisioningRequiredException` | HTTP 449, status 142–144 | Re-provisioning required; call `reprovision()` and retry (subclass of `EasCommandException`) |
| `EasCommandException` | other errors | Global status ≥ 101 (`easStatus`) or command failure |
| `EasRemoteWipeException` | status 140, Provision | Server requests a remote wipe |
| `EasPolicyNotAcceptedException` | Provision | Server requires applied policies |
| `EasResponseTooLargeException` | — | Response exceeds `maxResponseSize` |
| `AutodiscoverException` | — | Server not found; `errors` holds the reason per URL |

## Security

- All EAS commands are transmitted over HTTPS only
- Autodiscover sends credentials only over HTTPS; the opt-in HTTP and DNS SRV steps require consumer confirmation
- OOM protection: response size limit (25 MB), opaque data (50 MB), WBXML nesting depth (50)
- XML escaping in Autodiscover requests
- CR/LF header injection prevention (MIME headers, User-Agent, Accept-Language, cookies)
- PII is not included in exception `toString()` output
- DeviceId and DeviceType validation per MS-ASHTTP

## Dependencies

- `http` — HTTP client
- `xml` — XML parsing (Autodiscover)
- `collection` — collection utilities
- `meta` — annotations

## References

- [MS-ASHTTP: Exchange ActiveSync HTTP Protocol](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-ashttp/)
- [MS-ASCMD: ActiveSync Command Reference](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-ascmd/)
- [MS-ASWBXML: ActiveSync WBXML Algorithm](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-aswbxml/)
- [MS-OXDISCO: Autodiscover HTTP Service Protocol](https://learn.microsoft.com/en-us/openspecs/exchange_server_protocols/ms-oxdisco/)

## Donate

All work on this package consists of many hours of coding during our free time, to provide you with an
Exchange ActiveSync client that is easy to use. If you enjoy using this package and would like to say thank you,
donations are a great way to show your support.

Donations are invested back into the project 👍

Thank you for keeping this project alive 🙏

Available methods:
1. TGFFBC28Wo27aQ24L4ku6y3Egbe12Jhv1k (USDT TRC20)
2. 1PxyVPeYhRUtt5Mg1t3xSmFtHSYf2CabLR (BTC)
