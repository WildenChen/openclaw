# SoulNest Companion Client architecture

Status: Accepted for the first SoulNest MVP.

Related issues: #22, #4, #6, #10, #11.

## Decision

SoulNest iOS is a companion client for the existing OpenClaw `yujie` agent. It
is not a second agent runtime and it does not own a second copy of Yujie's
identity or durable memory.

The OpenClaw `yujie` workspace is the only authoritative source for:

- SOUL and role behavior
- user context and durable memory
- memory maintenance and compaction
- tools and tool permissions
- cron jobs, reminders, and proactive secretary work
- model/provider selection and fallback behavior

SoulNest communicates with Yujie only through the paired OpenClaw Gateway. The
app must not add a direct model-provider path for Yujie conversations.

## Responsibility and data ownership

| Concern | Authority | SoulNest local role |
| --- | --- | --- |
| Agent identity and behavior | OpenClaw `yujie` workspace | Display the selected profile and capabilities |
| Durable user/agent memory | OpenClaw | No durable-memory replica |
| Model calls and compaction | OpenClaw | No direct provider call or local compaction |
| Tools, schedules, and automation | OpenClaw/Gateway | Present requests, confirmations, status, and results |
| Pairing and transport authentication | Gateway | Store device credentials in Keychain |
| Active conversation session | Gateway `sessionKey` | Store a recoverable conversation-to-session mapping |
| Message/event history | Gateway | Cache recent presentation data for startup and offline reading |
| Character artwork and UI state | SoulNest | Authoritative local/app asset state |
| Media received from or sent through Gateway | Gateway for transfer; app for local file cache | Store thumbnails, local file references, and cache metadata |
| Notification navigation state | Gateway payload plus app routing | Store non-secret routing metadata |

A local database entry must identify whether a field is:

1. an authoritative local UI preference,
2. a remote identifier or pointer,
3. a rebuildable cache, or
4. a pending local action not yet accepted by the Gateway.

A rebuildable cache must never silently become durable memory or model context.

## Prohibited client behavior

The first SoulNest implementation must not:

- ship a second SOUL or hidden Yujie system prompt,
- maintain a second persistent-memory engine,
- run client-side transcript compaction for model input,
- replay the complete local transcript into a new session after reconnect,
- send Yujie chat directly to an OpenAI-compatible or other model endpoint,
- infer that a model statement means a tool operation succeeded,
- merge Telegram and iOS active transcripts merely because they share Yujie's
  durable workspace.

Product copy, onboarding text, and character presentation are allowed local UI
content. They must not alter the remote agent identity by being automatically
inserted into model context.

## Session boundaries

Telegram and SoulNest use the same OpenClaw agent workspace and durable memory,
but they use separate active-session namespaces.

For SoulNest:

- one local conversation maps to exactly one active OpenClaw `sessionKey`,
- reopening that conversation reuses its valid `sessionKey`,
- creating a new conversation creates a different `sessionKey`,
- reset affects only the selected SoulNest conversation,
- reconnect does not create a replacement session unless the previous session
  is confirmed missing, expired, or intentionally reset,
- the exact canonical key format is owned by #6, but it must include a stable
  SoulNest channel/client boundary and a stable conversation identifier.

Telegram sessions must not be automatically imported or appended to a SoulNest
conversation. A future explicit session viewer may expose them read-only or
through a separately confirmed transition.

## Cache and reconciliation lifecycle

### App launch

1. Load the local conversation index and recent cached presentation records.
2. Display cached content as provisional/offline data.
3. Pair or reconnect to the Gateway.
4. Validate the mapped `sessionKey` and subscribe to the authoritative event
   stream/history supported by the Gateway.
5. Reconcile by stable remote message/event identity and state, not by comparing
   rendered text alone.
6. Replace provisional state with confirmed remote state without resending the
   local transcript.

### Missing or corrupt local cache

The app discards the affected cache, retains only recoverable secure credentials
and remote identifiers, and rebuilds the usable view from the Gateway. Cache
loss must not damage Yujie's durable memory.

### Missing or expired remote session

The app marks the mapping stale and explains the state to the user. A new
session may be created, but the app must not reconstruct context by injecting
its complete local transcript. Any continuity must come from OpenClaw's durable
memory or an explicit server-supported continuation mechanism.

### Conflicting local and remote state

Remote completed/cancelled/failed states win for Gateway-owned messages and
tool actions. Unsent local drafts remain local. Pending sends use idempotency or
stable client IDs where supported so reconnect does not duplicate messages.

## Security boundary

- Gateway tokens, pairing credentials, and device credentials belong in
  Keychain.
- Non-secret endpoint/display preferences may use normal settings storage.
- Cached conversations, media indexes, and session metadata use iOS Data
  Protection.
- Logs and exports must redact authorization data, private prompts, headers,
  local paths, and sensitive message/tool payloads.
- Removing a local cache is distinct from deleting a remote session or durable
  memory and must be labelled accordingly.

Detailed implementation belongs to #11.

## Code-level dependency rule

User-facing chat and character UI may depend on a SoulNest companion/Gateway
interface, but must not import or instantiate a model-provider client.

The intended direction is:

```text
Character / Chat UI
        |
Conversation and presentation state
        |
SoulNest Gateway facade
        |
Existing OpenClaw Gateway client and protocol
```

Provider credentials, provider model selection, SOUL loading, memory search,
and compaction remain outside the iOS application boundary.

## Failure behavior

- Gateway offline: show cached content and a clear offline state; do not fall
  back to a separate model.
- Authentication failure: require pairing/credential repair; do not expose the
  token in UI or logs.
- Unknown Gateway event: preserve a redacted diagnostic event and use a safe
  generic UI state.
- Tool result missing: show unknown/interrupted, not success.
- Character renderer failure: fall back to static character presentation while
  preserving the same Gateway conversation.

## Future multi-agent expansion

The architecture may later support additional profiles, but every profile must
identify its own authoritative backend, agent identity, session namespace,
credentials, cache, media, and capabilities. No future backend may be presented
as equivalent to OpenClaw Yujie unless it provides the required memory, tools,
and session semantics.

Multi-agent and alternate-endpoint implementation is explicitly deferred to
#24 and must not add speculative provider abstractions to the first Yujie MVP.

## Required verification

Later implementation PRs must add checks proving that:

- no direct provider client is reachable from the Yujie chat path,
- two SoulNest conversations cannot share one `sessionKey`,
- Telegram and SoulNest active sessions remain isolated,
- clearing local cache leaves the remote Yujie agent usable,
- reconnect does not replay the complete transcript,
- tool success UI requires a verifiable Gateway/tool result.
