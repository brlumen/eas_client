## Unreleased

### Breaking changes

- `EasEmail.mimeData` is `Uint8List?` (raw bytes) instead of `String?`
- `sendMail`, `smartReply`, `smartForward` and `SendMailCommand` / `SmartReplyCommand` / `SmartForwardCommand` take `mimeContent` as `Uint8List` (sent unchanged); `ComposeMailCommand.mimeContent` is `Uint8List?`
- `EasClient.resetSyncState` / `resetAllSyncStates` return `Future<void>`
- HTTP 449 and global statuses 142/143/144 throw `EasProvisioningRequiredException` (a subclass of `EasCommandException`, so existing `on EasCommandException` handlers and `requiresProvisioning` keep working)

### Added

- `EasSyncStateStore` (FolderSync key + per-collection Sync keys, sync or async) and `InMemoryEasSyncStateStore` (default); `EasClient(syncStateStore:)`, `EasClient.autodiscover(syncStateStore:)`, `EasClient.syncStateStore`
- `EasEmailChange` — partial Sync Change with nullable fields (`read`, `flag`, `categories`, `importance`, `lastVerbExecuted`, ...) and the raw `applicationData`; `SyncResult.emailChanges` / `smsChanges`
- `EasEmail.mime` — MIME bytes from Body Type 4 or EAS 2.5 `MIMEData`; `EasBody.dataBytes` (Type 4)
- Raw HTTP/1.1 for custom transports: `EasClient.buildRawRequest(cmd)`, `EasClient.parseRawHttpResponse(cmd, bytes)`, `EasCommand.prepare` / `handleResponse` / `buildRawRequest` / `parseRawHttpResponse`, `EasHttpClient.prepareCommand` / `send` / `acceptRawResponse`, `EasHttpRequest.toHttp11Bytes()`, `EasRawHttpParser` (Content-Length, chunked, 1xx, incremental `tryParse`)
- `EasClient.updateCredentials` / `EasHttpClient.updateCredentials` (credentials are no longer final)
- `EasClient.reprovision()` — Provision with `PolicyAckStatus.success`, stores the new policy key
- `ComposeMailCommand.validateMimeHeaderBytes`
- `WbxmlElement.rawText` — original bytes of a string that is not valid UTF-8
- `example/stand.dart` — CLI probing Ping cancellation, MIME + Attachments, folder types, max heartbeat and post-handshake TLS bytes

### Deprecated

- `SyncResult.changedEmails` / `changedSms` — they fill missing properties with defaults (`read: false`, `subject: ''`); use `emailChanges` / `smsChanges`

### Fixed

- WBXML strings that are not valid UTF-8 (e.g. 8-bit MIME in `airsyncbase:Data`) no longer fail the whole response; they are decoded leniently and kept losslessly in `rawText`
- Server `host:port` now works with the base64 query string too (it threw `FormatException`)
- Sync with an empty HTTP 200 body is mapped via `parseEmptyResponse` (also for raw responses)

## 0.1.0-alpha.3

- Support `xml` 7.x (`^7.0.1`)

## 0.1.0-alpha.2

Verified against a live Exchange Server 2019 (protocol 16.1).

### Breaking changes

- `EasClient.provision()` → `provision({required PolicyAckStatus policyAckStatus, EasDeviceInformation? deviceInformation})`; `ProvisionCommand` likewise requires `policyAckStatus`
- `EasClient.ping(List<String>)` → `ping(List<PingFolder>)`; `PingCommand.fromIds` / `PingCommand.empty` added, heartbeat must be 60–3540 s
- `SendMailCommand` is now an `EasCommand` (`ComposeMailCommand`)
- `MoveItemsCommand` takes `List<MoveItem>` (`MoveItemsCommand.items`)
- Commands validate input lengths/ranges (sync keys, ids, `clientId`, search ranges) and throw `ArgumentError`

### Added

- Commands: FolderCreate/Delete/Update, GetItemEstimate, MeetingResponse, Settings (OOF, DeviceInformation, UserInformation, RightsManagement, DevicePassword), ResolveRecipients, ValidateCert, SmartReply, SmartForward (incl. meeting forward, 16.x), Find (EAS 16.1), ItemOperations (batch fetch, EmptyFolderContents, Move conversation, document library), Search (mailbox query AST, GAL, document library), multi-collection Sync
- Sync of calendar, contacts, tasks, notes and SMS; client-side Add/Change/Delete/Fetch with serializers; drafts (16.x)
- `EasClient` high-level methods for all of the above
- Provision: protocol 2.5 policy type, full `EasProvisionDoc`, remote wipe detection and `acknowledgeRemoteWipe`
- `EasPolicyNotAcceptedException` — server rejects a non-success policy acknowledgement (non-provisionable devices not allowed)
- `EasClient.autodiscover(username:)` — login that differs from the email address
- Autodiscover: opt-in HTTP redirect step (`enableHttpRedirectStep`) and DNS SRV step (`srvResolver`, `UdpDnsSrvResolver`) with `confirmRedirect`; `Action/Redirect` and HTTPS redirect following; typed `AutodiscoverResponse`; per-URL `AutodiscoverException.errors`
- Transport: base64 query string (opt-in), multipart responses, cookie jar, `EasServerNotice` stream, raw MIME for protocol < 14.0
- WBXML code pages MeetingResponse, ResolveRecipients, ValidateCert, Contacts2, DocumentLibrary, Notes, RightsManagement, Find (25 in total)
- Typed status enums for all commands; `EasGlobalStatus` (101–184)

### Changed

- Global statuses ≥ 101 are handled centrally: 140 → `EasRemoteWipeException`, 142–144 → re-provision, others → `EasCommandException`
- HTTP 503 → `EasServiceUnavailableException`, 456/457 → `EasAccountException`
- Provision goes through the common HTTP status mapping
- `settings:DeviceInformation` is sent only for protocol 14.1+
- FolderSync status 9 resets the sync key and re-syncs once
- Autodiscover timeout 30 s, response limit 1 MB

### Fixed

- WBXML decoder kept the code page per element instead of document-wide
- Provision returned empty policies (acknowledgement data instead of phase 1 data)
- `AllowBluetooth = 2` parsed as `false`
- `Email2:ConversationId` read as text instead of opaque bytes
- SendMail reported success on HTTP 200 with an error status

### Security

- Autodiscover: credentials only over HTTPS, redirects only to HTTPS (max 10, loop detection), spoofable hosts require confirmation
- DNS SRV resolver hardening (random query id, source check, bounded parsing)
- CR/LF injection checks for MIME headers, User-Agent, Accept-Language, cookies; cookie jar limits
- `X-MS-Credential-Service-Url` accepted only over HTTPS; multipart part limit 50 MB
