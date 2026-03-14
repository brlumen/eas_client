# eas_client

Dart implementation of the Microsoft Exchange ActiveSync (EAS) protocol client.
Supports WBXML codec, email/contacts/calendar sync, push notifications, and Autodiscover.

> **Alpha release.** The API is unstable and may change without notice.
> Use at your own risk in production environments.

## Features

- **WBXML codec** — WAP-192 encoding/decoding with 18 EAS code pages
- **Autodiscover** — automatic server discovery by email (MS-OXDISCO)
- **Provisioning** — security policy negotiation (MS-ASPROV)
- **Sync** — folder and item synchronization (email, contacts, calendar, tasks)
- **Ping** — push notifications via long-poll (MS-ASCMD)
- **SendMail** — send email through EAS
- **Search** — server-side mailbox search
- **MoveItems** — move items between folders
- **ItemOperations** — fetch full message body and attachments

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

// Provisioning (required before other commands)
await client.provision();

// Get folder list
final folders = await client.syncFolders();

// Sync inbox
final inboxId = folders.addedFolders
    .firstWhere((f) => f.type == EasFolderType.defaultInbox)
    .serverId;
final emails = await client.fullSync(inboxId);

client.dispose();
```

## Deviations from the Microsoft specification

### Autodiscover: HTTP redirect (step 3) not implemented

The MS-OXDISCO specification defines 4 discovery steps:

1. `https://domain/autodiscover/autodiscover.xml`
2. `https://autodiscover.domain/autodiscover/autodiscover.xml`
3. `http://autodiscover.domain/autodiscover/autodiscover.xml` (HTTP redirect)
4. `https://autodiscover-s.outlook.com/...` (Office 365)

**Step 3 is intentionally excluded.** It starts with a plain-HTTP request
vulnerable to MitM and DNS spoofing. MS-OXDISCO section 4.1 (Security
Considerations) warns: the server cannot be identified by the client when
using a non-SSL URI. An attacker on the network can substitute the response
and redirect credentials to an arbitrary server.

Steps 1, 2, and 4 (all HTTPS) cover all modern Exchange configurations:
on-premise with valid TLS, Exchange Online (Microsoft 365), and z-push.
If Autodiscover cannot find the server automatically, use direct connection
via the `EasClient(server: ...)` constructor.

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

## Error handling

The package throws typed exceptions for key HTTP statuses:

| Exception | HTTP code | Description |
|---|---|---|
| `EasAuthException` | 401 | Invalid credentials or expired OAuth token |
| `EasForbiddenException` | 403 | EAS disabled for user or blocked by policy |
| `EasRedirectException` | 451 | Server requires URL switch (mailbox migration) |
| `EasCommandException` | 449 | Re-provisioning required |

## Security

- All EAS commands are transmitted over HTTPS only
- Autodiscover works exclusively through HTTPS endpoints
- OOM protection: response size limit (25 MB), opaque data (50 MB), WBXML nesting depth (50)
- XML escaping in Autodiscover requests
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
