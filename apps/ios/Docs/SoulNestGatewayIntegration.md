# SoulNest Gateway integration boundary

SoulNest is a Companion Client for the existing OpenClaw `yujie` agent. It must reuse the repository's existing Gateway pairing, authentication, event, reconnect, and chat implementation.

## Boundary

SwiftUI and SoulNest feature code depend on:

- `SoulNestGatewaySession` for observable connection and error state.
- `SoulNestGatewayClient` for connect, disconnect, pairing cancellation, text requests, and Gateway events.
- `SoulNestGatewayEndpoint` for validated Gateway identity and URL metadata.

Feature code must not directly own a WebSocket, parse raw Gateway frames, store credentials, or call an AI provider.

## Production adapter requirements

The production adapter should wrap the existing OpenClaw iOS runtime rather than create another transport. It must:

1. Delegate pairing and authentication to the current OpenClaw pairing flow.
2. Reuse current reconnect, timeout, event subscription, and request correlation behavior.
3. Translate existing runtime state into `SoulNestGatewayConnectionState`.
4. Translate existing errors into `SoulNestGatewayError` without exposing tokens or raw payloads.
5. Send chat requests using the caller-provided OpenClaw `sessionKey`.
6. Emit assistant text and request failures through `SoulNestGatewayEvent`.
7. Keep Gateway credentials outside this abstraction; secure storage belongs to #11.

## Explicit non-goals

- No OpenAI-compatible endpoint.
- No Hermes or OpenMinis adapter.
- No second WebSocket implementation.
- No direct provider fallback.
- No local SOUL, durable memory, transcript replay, or compaction.
- No ownership of the conversation-to-`sessionKey` mapping; that belongs to #6.

## Remaining work for #4

This change establishes the testable UI boundary and mock fixture. Completing #4 still requires wiring a production adapter to the repository's existing OpenClaw iOS Gateway runtime and validating one real Yujie text turn, pairing cancellation, reconnect, and authentication failure handling.
