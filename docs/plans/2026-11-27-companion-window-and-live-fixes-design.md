# Design: companion chat window and live UI fixes

Date: 2026-11-27
Status: Approved in brainstorming; implementation not started.

## Context

Live use of the first-run wizard and the companion found seven issues that headless tests did not catch:

1. Every chat message ends as `[empty response]`.
2. The italic preview line on the wizard's "Choose your voice" page does not change when a different voice is picked.
3. The extended view does not scroll with the mouse wheel.
4. The membrane has too much inner padding.
5. The frame outline looks layered under the membrane instead of cleanly around it.
6. The pet can be dragged over the taskbar and then cannot be dragged back.
7. Expanding or maximizing resizes the pet itself, so closing the expanded view does not reliably restore its position.

A direct probe of the bundled brain explains issue 1: `llama-server` returns the answer in `reasoning_content` and leaves `content` empty. `Read-SlopSseStream` in `src/Slop.Lifecycle.ps1` reads only `choices[0].delta.content`, so the accumulated reply is blank and `Format-SlopEmptyResponse` writes `[empty response]`. With the current token budget the thinking consumes the whole reply.

Issue 2 has a likely cause in the same class as a previously confirmed PowerShell bug: the wizard's radio-button `Checked` handler assigns `$SampleLine.Text`, but `$SampleLine` is a function-local captured by an event-handler scriptblock. Earlier live work proved that PowerShell event handlers do not close over function locals, so the assignment throws on the UI thread and the text never changes. The swatch handler's `$PreviewPea` has the same shape and must be fixed at the same time.

## Goals

- Put extended and full-work-area chat in a **separate window**, leaving the pet's position and size untouched.
- Make the pet non-interactive (but still visible) while that window is open, and restore interaction at the same coordinates when it closes.
- Keep both pet and chat window inside the work area so neither can cover the taskbar.
- Make the built-in brain produce visible answers, with a fallback that never labels a real reply as empty.
- Make the voice preview update immediately on selection.
- Fix extended-view mouse-wheel scrolling, membrane padding, and frame outline layering.
- Reshape Settings/Customization so stable facts display as values and real choices use readable dropdowns.
- Prove each fix with focused RED/GREEN tests before claiming it fixed.

## Non-goals

- No third tier, brain, provider, or route-policy change.
- No installer, release workflow, tag, push, deploy, or remote/visibility change.
- No change to the voice transcription path; the user reports mic input works.
- No spoken replies, TTS, VAD, or image input.
- No claim of live visual verification by the agent; the user performs those checks.
- No migration of existing `data\config.json` or `data\persona.md`.

## Decisions

### One separate chat window, two modes

The pet gets one small **open** button in place of the current □ full-screen behaviour. Clicking it opens a new WPF window:

- Initial size is the current extended size (760x540), centred near the pet but fully inside the work area.
- The window has its own toggle between extended size and full work-area size, plus its own close button.
- The window is resizable and is **not** topmost.
- Only one chat window exists. Pressing the pet's open button while it is already open brings that window to the front instead of creating a second one.
- Closing it disposes the window and returns control to the pet.

Alternatives rejected: two separate windows (redundant modes), and resizing the pet in place (the reported position bug).

### Pet behaviour while the chat window is open

- The pet stays visible at the exact same coordinates and keeps its current size.
- While the window is open, the pet is no longer topmost, so the chat window renders above it; its position and size still do not change.
- Its click, drag, face, and control-dot handlers are disabled while the window is open, so it cannot steal input.
- Closing the chat window re-enables those handlers without touching position or size.
- The pet is never moved, resized, or re-anchored by opening, switching, or closing the chat window.

### Work-area clamping

- Pet drag and pet position writes are clamped to `SystemParameters.WorkArea`.
- The chat window's initial placement and mode changes are clamped to the same work area.
- This removes the "stuck over the taskbar" state rather than trying to recover from it after the fact.

### Built-in brain answers

- The local route request asks Qwen to disable thinking for ordinary chat (`chat_template_kwargs` with `enable_thinking: false`), so token budget goes to visible text.
- `Read-SlopSseStream` also accumulates `choices[0].delta.reasoning_content` as a separate field. If the stream finishes with empty visible content but non-empty thinking, show the thinking text (clearly labelled) instead of `[empty response]`.
- `[empty response]` remains only for a genuinely empty reply.
- Verification includes a direct request to the running bundled `llama-server`, not only mocked SSE.

### Wizard voice preview

- `$SampleLine` and `$PreviewPea` are published to script scope (or re-fetched from the dialog inside the handler) before any event handler is registered.
- Each voice/preset `Checked` and swatch `Click` handler updates the preview from that script-scope reference.
- A static guard asserts that no wizard XAML `x:Name` used as a variable inside an event handler relies on a function-local.

### Scroll, padding, outline

- The chat panel inside the new window uses a `ScrollViewer` that receives mouse-wheel input; the organic overlay layers must not intercept it.
- Membrane inner geometry is reduced so content is not floating in a large empty margin.
- The outline is drawn as the outermost layer with the membrane inside it, so the frame reads as a clean border rather than a layer underneath.

### Settings and Customization shape

Stable facts become read-only text, real choices become dropdowns. The exact split chosen here:

**Read-only values (display only):**
- Data location, About/version, Whisper readiness, route/effective model, installed brain and model names, OpenCode agent id when using the built-in brain.

**Dropdowns:**
- Voice language, colour, personality, brain tier, brain model, capability profile, and the wizard's voice/personality preset.

**Contrast rule:** every dropdown gets a dark background and light foreground, including its item containers, so text remains readable on the glass panel. No dependency on the OS theme.

Editable text boxes remain only for values a user can meaningfully type: custom instructions, persona text, loopback endpoint URL, and voice max seconds.

## Error handling

- Missing or unreachable bundled model keeps the existing explicit readiness error; no silent empty reply.
- If the "disable thinking" request field is rejected by the server, the fallback reader still returns content rather than failing the request.
- If the chat window fails to construct or show, the pet remains fully interactive and the open button stays enabled.
- Closing the chat window always restores pet interaction, including when the window is closed from the taskbar or by `Close()`.

## Verification

- Focused RED tests for: separate-window contract, work-area clamp, pet interaction gate, local thinking fallback, wizard preview handler scope, settings read-only/dropdown shape and contrast.
- GREEN implementation per bounded task, then the full CI-equivalent suite, tour anchor check, diff check, and review gate.
- Live checks performed by the user: open/switch/close the chat window, pet stays put, taskbar clamp, scrolling, preview changes, readability, and non-empty replies.
- No push, tag, release, or visibility change.

## Open items resolved during planning

- Exact pet button replacement: □ becomes "open chat window"; `_` and `X` keep their current meanings.
- Which settings are read-only vs dropdown: as listed above.
- Whether the new window is topmost: no, it is a normal window inside the work area.
