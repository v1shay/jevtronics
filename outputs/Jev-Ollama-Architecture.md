# Jev Notch: Jev-Controlled, Ollama-Assisted Architecture

## Product contract

Jev is the only component allowed to decide what an utterance means operationally. It selects the action domain, the next registered tool, whether the workflow is complete, and whether an action needs confirmation. Native Swift adapters are the only components allowed to touch the Mac or external services.

Ollama is a private text worker. The initial model is `gemma3:4b`. It receives a text operation, the original request, and bounded source text. It never receives the tool catalog, native handles, credentials, executable commands, or a tool-calling schema. Its output is inert text stored in workflow state until Jev selects a separate tool that consumes it.

```text
Command hold → Apple Speech transcript
                  │
                  ▼
        Jev domain choice (finite)
                  │
                  ▼
         Jev next-tool choice (finite)
                  │
          ┌───────┴────────┐
          │                │
    Native adapter    Ollama text worker
          │                │
          └──── result ────┘
                  │
          compact step history
                  │
                  └──→ Jev chooses next tool or finish
```

## Non-negotiable safety boundaries

1. Ollama cannot select, name, invoke, or parameterize a native tool.
2. Jev can only choose identifiers present in the runtime registry.
3. Tool arguments come from explicit user text, trusted native observations, finite candidate sets, or artifacts created by earlier steps.
4. Secrets stay in Keychain and are never included in Jev or Ollama state.
5. Sending, deleting, quitting, shell execution, calendar creation, and other external side effects pause for confirmation.
6. A workflow stops after eight steps, on a failed step, or after a repeated step with identical output.
7. Observation precedes mutation when targets are ambiguous.
8. Generated text remains inert until Jev selects a consumer such as `email.draft`, `notes.create`, or `keyboard.type`.

## Multi-step decision loop

Every workflow stores:

- Original transcript
- Frontmost application and focused element
- Ordered successful and failed step records
- Bounded textual outputs
- Typed artifacts such as `file_path`, `email_address`, or `calendar_event_id`
- Current step count

For each step, Jev first chooses a domain. Jev then receives only tools in that domain and selects one next action. This hierarchical choice prevents a flat catalog of dozens or hundreds of actions from degrading routing quality.

After execution, the coordinator sends Jev a compact description of what actually happened. Jev can then select another observation, transform text, perform an action, or choose `workflow.finish`. Jev never predicts a whole unverified plan in advance; it replans from observed results after every step.

Example:

```text
“Find the launch brief, summarize it, and draft an email to Maya.”

1. Jev → file.search
2. Native adapter → file_path artifact
3. Jev → file.read_text
4. Native adapter → document text
5. Jev → text.summarize
6. Ollama → inert summary text
7. Jev → contact.search
8. Contacts adapter → finite email_address artifact
9. Jev → email.draft
10. Confirmation → user approves
11. Mail adapter → visible draft; it is not silently sent
12. Jev → workflow.finish
```

The production step limit is eight, so workflows that naturally require more operations should use compound deterministic adapters, such as `document.find_and_read`, after their behavior is proven.

## Implemented tool surface

The current build registers more than fifty typed actions.

### Local text

- Generate prose
- Rewrite text
- Summarize text
- Extract action items
- Draft an email body

All five run through `gemma3:4b` at `127.0.0.1:11434`. The app can start the local Homebrew Ollama daemon when it is absent, verifies the exact model tag, and keeps the model warm for ten minutes. The text worker has no execution interface.

### Computer control

- Inspect frontmost app and focused element
- Inspect a compact Accessibility control tree
- Click a named visible control
- Type, copy, paste, cut, undo, redo, and select all
- Scroll up or down
- Open, activate, hide, or quit applications
- Close, minimize, full-screen, or half-screen tile windows
- Read, write, or clear the clipboard
- Set volume, mute, unmute, and control Music playback

### Browser

- Open a URL
- Read the active URL
- Read active-page text
- Back, forward, reload, and open a tab

Safari and Chrome use their native Apple-event interfaces. Accessibility remains the fallback for visible controls.

### Personal information

- List today’s calendar events
- Create an event from an explicit recognized date and time
- List incomplete reminders
- Create a reminder
- Search contacts and return finite email candidates
- Search Apple Notes
- Create an Apple Note
- Search recent Apple Mail messages
- Create a visible Mail draft

Calendar, Reminders, and Contacts use Apple frameworks and request their own macOS permissions. Notes and Mail use Apple Events. Email drafting accepts an explicit address or an address artifact returned by the Contacts adapter.

### Files and automation

- Open files
- Spotlight file search
- Read bounded plain-text files
- Run Apple Shortcuts
- Run an explicitly dictated shell command after confirmation

Shell execution is retained as an expert escape hatch, not as a substitute for typed tools.

## Complete high-ROI expansion map

The following tool families should be added behind the same interfaces. “Read” actions can normally execute immediately. “Write” actions require target validation; consequential writes require confirmation.

### Observation and computer use

- Stable element IDs, full element attributes, menu trees, windows, installed apps, screen geometry
- Wait for element, element disappearance, navigation, or UI change
- Focus, select, toggle, expand, collapse, increment, decrement, and set value
- Mouse fallback: click point, drag, right-click, and element-relative scrolling
- Window focus, unminimize, maximize, move, resize, screen placement, and switching
- Menu discovery and menu-item activation
- Screenshot and region capture

Vision should not be delegated to Gemma under the text-only policy. Screen OCR can use Apple Vision locally; Jev then chooses among finite OCR/Accessibility candidates.

### Browser

- List, switch, close, duplicate, pin, and reopen tabs
- Extract links, forms, images, selected text, and page metadata
- Focus, type, select, toggle, submit, hover, and scroll to DOM/AX elements
- Upload and download with explicit paths
- Wait for navigation, text, elements, and network idle

A browser extension or CDP bridge should expose stable element IDs. Jev chooses among observed elements; it never invents selectors.

### Files and documents

- Directory listing and metadata
- Content search and recent files
- Create, append, copy, move, rename, reveal, compress, extract, and trash
- Recover from Trash
- PDF text extraction, page rendering, merge, and split
- Office/iWork conversion through native exporters
- Image metadata, resize, crop, and format conversion

Deletion targets must be explicit resolved paths and should go to Trash by default.

### Email

- Account and mailbox listing
- Message, thread, and attachment retrieval
- Full-text search
- Draft creation and revision
- Reply, reply-all, and forward
- Archive, mark read, star, and label
- Send only after showing exact recipients, subject, attachments, and body

Prefer Gmail/Outlook APIs when connected, Mail.app otherwise. Jev selects messages from finite search results.

### Messaging

- Search and read conversations
- Create drafts, replies, reactions, and attachments
- Send through Messages, Slack, Teams, Discord, Telegram, or WhatsApp adapters

Every send operation must display service, recipient, and final generated text before confirmation.

### Calendar, reminders, contacts, and notes

- Calendar search, availability, event update/delete, attendee resolution, and invitation response
- Reminder search, update, completion, deletion, list selection, and recurrence
- Contact creation/update with duplicate detection
- Note retrieval, append/update, move, and deletion

Natural dates are detected locally. Ambiguous times become finite choices such as 9:00 AM, 1:00 PM, or ask the user.

### Development and local processes

- Git status, diff, log, branch, stage, commit, fetch, pull, push, merge, and rebase
- Detect project and package manager
- Build, test, lint, format, and parse diagnostics
- Start and supervise persistent development servers
- Process status, output, input, and termination

Ollama may explain an observed diagnostic or draft code text, but Jev selects each filesystem, Git, or process operation.

### System and media

- Battery, memory, CPU, disk, network, Wi-Fi, Bluetooth, displays, and audio devices
- Brightness, display sleep, and lock screen
- Media state, play, pause, seek, and per-player selection
- Notifications with safe actions

Shutdown, reboot, account changes, security settings, and credential operations require elevated confirmation and should never be inferred from vague language.

### External APIs

- Typed HTTP endpoints with per-service allowlists
- OAuth connection inventory and explicit connection flows
- GitHub, Linear, Notion, Google Drive, Slack, and other service-specific adapters

Generic HTTP requests should be development-only. Production workflows should use typed request/response schemas and redact credentials before results reach Jev.

## Argument resolution

Jev should never be forced to emit free-form JSON. Each tool declares typed slots and a resolver strategy:

| Slot type | Resolution strategy |
|---|---|
| Explicit text | Exact span from the transcript |
| Generated content | Artifact from a prior local text step |
| Person | Contacts search → Jev finite choice |
| File | Spotlight/filesystem candidates → Jev finite choice |
| UI element | Accessibility/DOM candidates → Jev finite choice |
| Date/time | Native detector → finite normalized choices |
| App/window/tab | Native inventory → Jev finite choice |
| Message/event | Service search results → Jev finite choice |

If a required slot has no trustworthy candidate, the workflow asks one concise question instead of guessing.

## Latency strategy

- Keep `gemma3:4b` warm for ten minutes after use.
- Do not call Ollama for routing, confirmations, direct commands, or data retrieval.
- Use hierarchical Jev routing so each tool-choice set remains small.
- Cache stable inventories such as installed apps and browser names.
- Run independent read-only observations in parallel only after Jev explicitly selects a compound observation tool.
- Stream future Ollama text into the expanded notch, while treating it as incomplete until generation ends.

## Recommended next implementation order

1. Stable AX/DOM element IDs and wait primitives
2. Browser tab and form adapters
3. Calendar availability/update and reminder completion
4. Mail thread retrieval, reply drafts, and attachment handling
5. Filesystem mutation tools with Trash-based recovery
6. Messaging adapters
7. PDF/document extraction
8. Git/build/test tools
9. Apple Vision OCR candidate generation
10. OAuth-backed cloud connectors

This sequence makes the assistant broadly useful without weakening the central rule: Jev decides, native code acts, and Ollama writes text only.
