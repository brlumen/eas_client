## 0.1.0-alpha.2

Verified against a live Exchange Server 2019 (protocol 16.1).

The Git repository history was reset with this release; the 0.1.0-alpha.1
sources remain available on pub.dev.

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

## 0.1.0-alpha.1

- Initial alpha release
- WBXML codec with 18 EAS code pages (WAP-192)
- Autodiscover — automatic server discovery via MS-OXDISCO (steps 1, 2, 4)
- Provisioning — security policy negotiation (MS-ASPROV)
- FolderSync — folder hierarchy synchronization
- Sync — email/contacts/calendar/tasks synchronization
- Ping — push notifications via long-poll
- SendMail — send email through EAS
- Search — server-side mailbox search
- MoveItems — move items between folders
- ItemOperations — fetch full message body and attachments
- Basic and OAuth2 authentication support
- Security: HTTPS-only, OOM protection, PII-safe exceptions
