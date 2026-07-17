# macOS Low-Flick Input Design

## Objective

Improve VNKey's current macOS event-hook architecture without registering a native input method. Vietnamese transformations should appear smoothly in as many applications as possible, while preserving a reliable CGEvent fallback for controls that do not support Accessibility text replacement.

## Scope

This change is limited to macOS and the shared engine contract needed by macOS. It does not add InputMethodKit, change the Windows or Linux implementation, redesign the settings UI, or introduce asynchronous processing of intercepted key events.

## Success Criteria

- A transformed word is represented as the smallest suffix replacement that preserves the longest common character prefix.
- Controls supporting `AXSelectedTextRange` and `AXSelectedText` are updated through one Accessibility replacement operation.
- Controls that reject Accessibility replacement continue to work through ordered CGEvent backspace and Unicode injection.
- Accessibility support is discovered from the focused control instead of a hard-coded Electron application list.
- No worker thread is created per transformed keystroke, and intercepted transformations remain strictly ordered.
- The event callback records engine, Accessibility, fallback, and total latency in debug/diagnostic builds without logging typed content.
- Existing engine tests pass, including the Telex and VNI `rượu` regressions.

## Architecture

### Minimal edit contract

The engine continues to own the logical word buffers, but `EngineResult::Replace` describes only the changed suffix. For old rendered text `old` and transformed text `new`, it finds the longest common prefix on Unicode scalar boundaries. The result contains:

- `backspaces`: character count of the old suffix after that prefix.
- `text`: new suffix after that prefix.

The calculation is a pure helper with table-driven tests covering ASCII, precomposed Vietnamese characters, complete replacement, insertion-only suffixes, deletion-only suffixes, and identical strings. macOS must never calculate byte offsets as character counts.

### macOS replacement strategy

For every non-empty minimal edit, the event tap uses this ordered strategy:

1. Obtain the focused Accessibility element.
2. Read and validate its selected-text range.
3. Select exactly `backspaces` characters immediately before the caret, preserving any existing selection as part of the replacement range.
4. Set `AXSelectedText` to the replacement suffix.
5. If any required AX operation is unsupported or fails, post the minimal backspaces and Unicode suffix through the existing signed CGEvent source.

The original physical key is swallowed only after VNKey has synchronously completed one of these paths. The CGEvent signature continues to prevent injected events from being processed recursively.

### Capability handling

The hard-coded Spotlight/Electron gate is removed. AX replacement is attempted based on the focused element's actual behavior.

A small bounded cache records recent unsupported combinations using the frontmost application's bundle identifier and focused element role. Positive capability is not assumed permanently: transient AX failures still fall back safely. The cache must be invalidated when the frontmost application changes. Secure text fields are treated as unsupported and immediately use the fallback path.

### Composition validity

VNKey resets its engine buffer on navigation and editing commands that can invalidate the assumed caret position. The existing reset set is expanded to include arrow keys, Home, End, Page Up, Page Down, Delete Forward, Escape, Tab, Return, and physical Backspace. Application activation changes also reset the buffer.

Mouse-driven caret movement cannot be observed reliably through the current key-only event tap. Before an AX replacement, the selected range is therefore treated as authoritative. CGEvent-only controls retain this limitation; this is explicitly accepted for this iteration rather than adding a global mouse tap.

### Ordering and latency

All processing remains synchronous on the event-tap thread. This prevents a later physical keystroke from overtaking an earlier replacement. No per-key threads or queues are introduced on macOS.

Timing uses a monotonic clock around four stages: engine processing, AX attempt, CGEvent fallback, and total callback. Diagnostics aggregate counts and latency buckets and never include the typed character, buffer, replacement text, focused value, or selected text. Slow callbacks can emit a rate-limited warning containing only stage timings and application bundle ID.

## Engine correctness

The existing failing `rượu` cases are fixed before performance refactoring:

- Telex input `ruouwj` must produce `rượu`.
- VNI input `ruou75` must produce `rượu`.

The fix must be driven by focused failing tests and preserve all recovery and corpus tests. Parsing/allocation optimization is deferred unless profiling after the injection changes shows engine processing materially contributes to callback latency.

## Error Handling

- Null Core Foundation or Accessibility objects cause an immediate fallback.
- Every owned Core Foundation object is released on every return path.
- An invalid range, negative location, unsupported attribute, secure field, or failed AX setter causes fallback rather than dropping input.
- Failure to allocate a CGEvent must not panic; remaining events are attempted and the diagnostic failure counter is incremented.
- Poisoned Rust locks must not unwind across the C event callback boundary. Callback state should use thread-confined ownership where practical, with explicit recovery for shared configuration.

## Testing

### Automated

- Unit tests for minimal suffix edits, including Vietnamese Unicode.
- Existing engine suite, with focused regression runs for `rượu` followed by the complete release suite.
- Pure tests for replacement-strategy selection and capability-cache invalidation, with AX/CGEvent calls behind narrow interfaces.
- Tests confirming secure and unsupported controls select CGEvent fallback.
- Tests confirming navigation/focus events reset engine state.

### Manual compatibility matrix

Test fast typing, tone changes, modifier changes, caret movement, selection replacement, and application switching in:

- TextEdit and Notes.
- Safari and Chrome form fields.
- VS Code.
- Slack or another Electron editor.
- Spotlight.
- Terminal.
- A password field, which must not expose or log content.

For each application, record whether AX or CGEvent was selected, visible flick, lost/reordered characters, and p50/p95/p99 callback latency. Acceptance requires no lost or reordered characters. AX-supported controls should have no visible erase-and-repaint flick; fallback controls should emit fewer events than the current full-word replacement whenever old and new text share a prefix.

## Rollout

The hybrid strategy is enabled by default on macOS. A temporary diagnostic setting may force CGEvent fallback for comparison and recovery during testing, but it is not exposed as a permanent end-user preference unless compatibility evidence shows it is needed.
