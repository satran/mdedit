# 005 · Agent access: an MCP server inside MDEdit, and a Review tab for proposed edits

Status: planned. Nothing is built yet. The mockup is `design.html` in this folder (open it in a browser; it follows the system's light and dark).

## Context

Agents can already read and write the notes as files. What they cannot see is the editor: which note is open, the selection, unsaved text. They also cannot edit without colliding with an open buffer, or show the user anything. The goal is to let agents (Claude Code and others) read that context and **propose** edits that the user accepts or rejects in the app. An accepted edit is one undoable change in the editor. Nothing an agent sends is applied silently.

Decision made in conversation: the server lives **in the app**, as an MCP server over streamable HTTP on loopback. That needs `com.apple.security.network.server`. Layer 1 from the earlier sketch (a URL scheme) is dropped: the project forbids URL types on purpose, and the in-app server covers the same ground.

## Facts that shape the design (from the code)

- **One `Workspace` per window, no registry.** `MDEditApp.swift:11`, `Workspace.swift`. A global server needs one: register in `Workspace.init`, remove in `deinit`, pick the front window by matching `NSApp.keyWindow` to `ws.hostWindow` (`Workspace.swift:75`).
- **Undoable edit path exists:** `EditorTextView.insertOutput(_:at:)` (`Model/Workspace+Shell.swift:221`) goes through `insertText(replacementRange:)`, so the delegate runs, `document.text` follows and ⌘Z works. `FindModel.withEditor` (`Workspace+Find.swift:97`) shows how to get to Write mode first. Setting `document.text` directly resets the text view and clears undo, so never do that.
- **Editor state:** selection from `ws.editor.textView?.selectedRange()`; `ws.jump(to:length:)` (`Workspace.swift:609`) navigates; `Outline.headings(in:)` (`Model/Outline.swift`), `WikiLink.parse`, `WikiIndex.resolve`, `FindEngine`/`FolderFind` (`Model/FindReplace.swift`) are reusable without UI state. `ws.openWiki` shows an `NSAlert`, so tools must not call it.
- **`DocumentStore`** saves 0.8 s after a change and refuses to overwrite a file changed on disk (`changedOnDisk`). Edits that go through the text view inherit all of that.
- **`Find` highlights use temporary `.backgroundColor` attributes and clear all of them** (`Workspace+Find.swift:359`). Proposal marks must not use that attribute. `drawBackground` already paints code bands from a range list (`EditorTextView.swift:352`): proposal marks use the same mechanism.
- **Policy gates that will fail on purpose:** `ProjectPolicyTests` lists `network.server` as forbidden and asserts no `CFBundleURLTypes`; `scripts/audit.sh` hard-codes the four allowed entitlements and greps for process/network patterns; `TESTING.md` rule 4. These are updated deliberately in step 1.
- **Right panel:** `enum RightPanel` (`Workspace+Find.swift:~182`), `RightPanelView` (header title ternary, `tabBar` with the Run tab gated on `prefs.shellEnabled`). The Review tab copies that gating.
- **Palette already has the diff colours:** `removedBg/removedInk`, `addedBg/addedInk` (`UI/Theme.swift`).
- **No Keychain use anywhere**, and ad-hoc signing makes it risky. The token goes in `Preferences` (the container is private). It guards against web pages and other users, not other software running as the user; the plan says so in Settings.

## Design of the Review tab (see `design.html`)

- **Fourth tab** in the side panel, icon `checklist`, shown only while the server is on (like Run). Title "Review". The panel toggle in the toolbar gets a small badge dot while proposals are pending and the panel is closed.
- **One card per proposal**, newest first, current note's cards above the rest:
  - Title (the agent's own short title), client name and age.
  - The agent's reason, two lines at most.
  - A line diff in mono: removed lines on `removedBg`, added on `addedBg`, with the changed words underlined.
  - **Reject** and **Accept**. Accept is the primary action: ⌘↩ accepts the focused card, ⌫ rejects it, ↑/↓ move between cards. The footer holds **Accept all in this note**.
  - A new-note proposal shows the file name and the first lines, and Accept creates the file.
- **Selecting a card** opens its note, scrolls to the passage and paints it in the editor (the same red wash as the card's removed lines, drawn behind the text, never saved). Nothing is shown in the text itself.
- **Stale proposals:** if the text under a card changes so its `old` text no longer matches exactly once, the card dims, says "Changed since proposed", and offers Dismiss and Re-check.
- **Accepting** applies one undoable edit named "Accept suggestion" (grouped for Accept all). The card collapses to "Accepted" for a few seconds and then leaves the list; the agent can still read the status.
- Empty state: "No suggestions" and a one-line note that agents appear here once connected.

## Server and protocol

- **Transport:** `NWListener` bound to loopback (`requiredInterfaceType = .loopback`), a minimal HTTP/1.1 parser (`POST /mcp`, `Content-Length`, one JSON-RPC message per request, JSON response, no SSE). 1 MB body cap, 8 concurrent connections, request timeouts. `GET /mcp` answers 405.
- **Methods:** `initialize` (protocol version `2025-06-18`, falls back to `2025-03-26`), `notifications/initialized` (202), `ping`, `tools/list`, `tools/call`.
- **Security:** off by default. Bearer token required. `Host` must be `127.0.0.1:<port>` or `localhost:<port>`. A present `Origin` must be loopback, else 403 (stops DNS rebinding). A connection list in Settings with Disconnect. A "listening" indicator in the footer while on.
- **Threading:** parse and respond on a private queue; every tool hops to the main actor through one `AgentBridge` (`@MainActor`) that owns the window registry and the proposal store.

### Tools

| Tool | Purpose |
|---|---|
| `list_windows` | Windows with folder and open note. Other tools take an optional `window`; the default is the front window. |
| `get_context` | Open note path and title, mode, unsaved flag, selection (text capped at 8 KB, UTF-16 range, line and column), heading path at the cursor. |
| `read_note` | Text of a note by path relative to the folder. Returns the buffer when the note is open with unsaved changes, and says `source: buffer` or `disk`. |
| `list_notes`, `outline`, `backlinks`, `find` | Wrappers over `BinderNode.files`, `Outline.headings`, a standalone copy of the backlink loop, `FindEngine`/`FolderFind`. |
| `open_note` | Open a note, optionally at a heading. Moves what is on screen only. |
| `propose_edit` | `{path, old, new, title, reason}`. `old` must match exactly once (otherwise an error with the match count, like an exact-replace edit). No offsets: agents are bad at UTF-16 positions, and text anchors survive edits. |
| `propose_new_note` | `{path, content, title, reason}`; path must be a fresh note name inside the folder. |
| `list_proposals`, `get_proposal`, `withdraw_proposal` | Status is `pending`, `accepted`, `rejected`, `stale` or `withdrawn`. `get_proposal` can wait up to 30 s for a decision. |

Every tool result that contains note text carries a short line saying the text is untrusted data. All paths go through `Workspace.isInside`/`cleanName`; hidden files, packages and non-note extensions are refused. HTML pages are read-only, so proposals for them are rejected.

## Proposal model

`Proposal { id, windowID, path, kind: .edit(old,new) | .newNote(content), title, reason, client, createdAt, status }` in a `ProposalStore` owned by `AgentBridge` (in memory; proposals do not survive a quit). The range is never stored: it is found again by searching `old` in the current buffer (or the file on disk if the note is closed) each time the text changes, and that search is also the stale check. Accepting an edit for a note that is not open opens it first, switches to Write mode, then applies through `insertOutput`.

## Implementation steps (separate commits)

1. **Docs and settings model.** This folder (`PLAN.md`, `design.html`) and `Preferences.agentsEnabled/agentPort/agentToken` (token generated from the system random source). The Settings "Agents" section (switch, port, token with Copy command and Regenerate) and the policy changes arrive with the server in step 3, so no entitlement or control exists before it does something.
2. **Registry and bridge.** `Model/WindowRegistry.swift` (register/unregister in `Workspace`, front-window lookup), `Agents/AgentBridge.swift` with the read and show tools as plain functions returning `Codable` results; unit tests with hosted workspaces.
3. **Server and policy.** `Agents/MCPServer.swift` (listener, HTTP parsing, auth, JSON-RPC dispatch). Add `network.server` to `MDEdit.entitlements` and `project.yml`; update `ALLOWED` in `scripts/audit.sh`, `ProjectPolicyTests` (entitlement present, still no URL types, listener bound to loopback only, only `MCPServer` opens a listener), `TESTING.md` rule 4, README rule 4 and the manual's "nothing is sent anywhere" line. Settings gets the "Agents" section. Tests drive it over a real loopback socket on a random port with an injected `AgentBridge`. Started from the app, never from `init`, and never under `AppEnvironment.isTesting` unless a test asks.
4. **Proposals.** `Agents/Proposal.swift`, `ProposalStore`, `propose_*` tools, the stale re-check, accept/reject through `insertOutput` with one undo group.
5. **Review tab.** `RightPanel.review`, `UI/ReviewPanelView.swift`, tab gating, panel badge, editor marks (`EditorTextView.proposalRanges` painted in `drawBackground`), keyboard handling, manual and README sections.
6. **Hardening and docs.** Connection list and indicator, `make audit` additions (the only listener is `MCPServer`, loopback only), a "Connect Claude Code" snippet in the manual.

## Tests

- **Protocol:** initialize handshake, tools/list, unknown method, malformed JSON, oversized body, missing/wrong token (401), bad `Host` or `Origin` (403), 9th connection refused.
- **Safety:** path traversal (`../`, absolute, symlink out of the folder), hidden files, HTML targets, `old` matching zero or twice, enormous `new`, note text containing instructions (returned only as data).
- **Editing:** accept applies one change and ⌘Z restores the exact text; accept with unsaved edits elsewhere; text changed under a proposal becomes stale; accept all is a single undo; accepting in a closed note; closed window (proposal becomes `withdrawn`).
- **UI:** snapshot test of the Review tab (light and dark) with edit, new-note and stale cards; panel-toggle badge; Find marks and proposal marks do not clear each other.
- **Policy:** updated `ProjectPolicyTests`, `make audit`.

## Verification

1. `scripts/test.sh` and `make audit` pass.
2. `make app`, turn the switch on in Settings, then `claude mcp add --transport http mdedit http://127.0.0.1:47821/mcp --header "Authorization: Bearer <token>"`.
3. In Claude Code: ask it to describe the open note and selection; ask it to tighten a paragraph; check the card, the red passage in the editor, Accept (⌘Z undoes it), Reject, and an edit made by hand under a pending card.
4. `curl` without the token and with a wrong `Origin` header: expect 401 and 403.

## Risks and open points

- The entitlement lets the app accept connections from any local process; loopback binding, token, `Host`/`Origin` checks and the off-by-default switch contain it. May complicate App Store review.
- A port clash is shown in Settings; the port is configurable.
- A fixed token means the client config survives restarts; Regenerate invalidates it.
- Not in v1: resources, prompts, server notifications, SSE, silent (auto-accepted) edits, persisted proposals, proposals for closed windows beyond withdrawing them.
