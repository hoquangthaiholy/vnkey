# macOS Low-Flick Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce visible macOS replacement flick while retaining the existing event-hook architecture and CGEvent compatibility fallback.

**Architecture:** The engine emits the smallest Unicode-safe suffix edit instead of a full-word replacement. The macOS event tap attempts an atomic Accessibility range replacement for the focused editable control and falls back synchronously to signed CGEvents, with pure policy helpers and latency diagnostics kept separate from FFI.

**Tech Stack:** Rust 2021, vnkey-engine, Tauri 2, macOS ApplicationServices/CoreFoundation/AppKit, Cargo tests.

## Global Constraints

- Do not register an InputMethodKit input method.
- Preserve strict event ordering; do not spawn a worker per transformed key.
- Do not log typed characters, buffers, selected text, or replacement text.
- Secure text fields must bypass Accessibility replacement.
- Windows and Linux behavior are outside this implementation except for compilation compatibility required by shared engine API changes.

---

### Task 1: Unicode-safe minimal suffix edits

**Files:**
- Modify: `vnkey-engine/src/lib.rs`
- Test: `vnkey-engine/tests/engine_tests.rs`

**Interfaces:**
- Produces: `pub fn minimal_suffix_edit(old: &str, new: &str) -> (usize, String)`.
- Produces: every `EngineResult::Replace` uses the returned suffix edit.

- [ ] **Step 1: Write failing unit tests**

Add a table-driven test that asserts `("duong", "đường") -> (5, "đường")`, `("dươ", "đườ") -> (1, "ờ")`, `("tiếng", "tiếng") -> (0, "")`, `("ab", "abc") -> (0, "c")`, and `("abc", "a") -> (2, "")`. Add an engine-level assertion showing that a transformation sharing a prefix returns fewer backspaces than the prior buffer length.

- [ ] **Step 2: Verify RED**

Run: `cargo test -p vnkey-engine minimal_suffix_edit -- --nocapture`

Expected: compile failure because `minimal_suffix_edit` does not exist.

- [ ] **Step 3: Implement the helper and route Replace construction through it**

Compare `old.chars()` and `new.chars()` until the first unequal scalar, count the old suffix, and collect the new suffix. Introduce a private `replace_result(old: &str, new: String) -> EngineResult` wrapper so all four Replace branches use the same calculation.

- [ ] **Step 4: Verify GREEN and regression safety**

Run: `cargo test -p vnkey-engine minimal_suffix_edit -- --nocapture`

Expected: PASS.

Run: `cargo test -p vnkey-engine --test engine_tests --release -- --nocapture`

Expected at this stage: the new minimal-edit tests pass; only the two pre-existing `rượu` assertions may fail.

- [ ] **Step 5: Commit**

Commit message: `feat(engine): emit minimal suffix replacements`

### Task 2: Fix Telex and VNI rượu regressions

**Files:**
- Modify: `vnkey-engine/src/telex.rs`
- Modify: `vnkey-engine/src/vni.rs`
- Test: `vnkey-engine/tests/engine_tests.rs`

**Interfaces:**
- Consumes: unchanged `process_telex` and `process_vni` public signatures.
- Produces: `ruouwj -> rượu` and `ruou75 -> rượu` without weakening spelling recovery.

- [ ] **Step 1: Isolate failing tests**

Split the two existing assertions into focused tests named `test_telex_ruou_modifier_order` and `test_vni_ruou_modifier_order`, retaining the original expectations.

- [ ] **Step 2: Verify RED**

Run: `cargo test -p vnkey-engine ruou_modifier_order --release -- --nocapture`

Expected: both tests FAIL with the currently observed `ruouự` and `ruou75` results.

- [ ] **Step 3: Implement minimal modifier-order correction**

Trace the syllable state after each control key and adjust only the `ươu` free-modifier handling so a late Telex `w` or VNI `7` can normalize `uou` to `ươu` while preserving the existing tone. Do not add word-specific exceptions.

- [ ] **Step 4: Verify GREEN**

Run: `cargo test -p vnkey-engine ruou_modifier_order --release -- --nocapture`

Expected: PASS.

Run: `cargo test -p vnkey-engine --release -- --nocapture`

Expected: all engine tests PASS.

- [ ] **Step 5: Commit**

Commit message: `fix(engine): support late modifiers in ruou`

### Task 3: Extract testable macOS replacement policy

**Files:**
- Create: `vnkey-ui/src-tauri/src/macos_replacement.rs`
- Modify: `vnkey-ui/src-tauri/src/lib.rs`
- Test: inline `#[cfg(test)]` module in `macos_replacement.rs`

**Interfaces:**
- Produces: `ReplacementCapabilityCache` with bounded unsupported entries and `invalidate_for_app(&str)`.
- Produces: `ReplacementPolicy::should_try_accessibility(role: Option<&str>, force_cgevent: bool) -> bool`.
- Secure roles such as `AXSecureTextField` return false.

- [ ] **Step 1: Write policy tests**

Test that normal text fields try AX, secure fields do not, a cached unsupported app/role does not retry, cache invalidates when bundle ID changes, and capacity eviction keeps the cache bounded.

- [ ] **Step 2: Verify RED**

Run: `cargo test -p vnkey-ui macos_replacement --lib -- --nocapture`

Expected: compile failure because the module and policy types do not exist.

- [ ] **Step 3: Implement pure policy and cache**

Use a small `VecDeque`-backed cache with an explicit constant capacity. Keep Core Foundation pointers and FFI outside this module.

- [ ] **Step 4: Verify GREEN**

Run: `cargo test -p vnkey-ui macos_replacement --lib -- --nocapture`

Expected: PASS.

- [ ] **Step 5: Commit**

Commit message: `refactor(macos): isolate replacement policy`

### Task 4: Hybrid Accessibility-first replacement

**Files:**
- Modify: `vnkey-ui/src-tauri/src/lib.rs`
- Test: `vnkey-ui/src-tauri/src/macos_replacement.rs`

**Interfaces:**
- Consumes: minimal `EngineResult::Replace { backspaces, text }`.
- Produces: a single `replace_text(proxy, backspaces, text)` path that attempts AX then CGEvent.
- Produces: an RAII Core Foundation owner used for created/copied objects so every return path releases resources.

- [ ] **Step 1: Add failing strategy tests around a narrow backend trait**

Define a test-only/foundation-neutral `ReplacementBackend` contract with `try_accessibility` and `send_cgevent`. Assert AX success suppresses fallback, AX failure invokes fallback exactly once, and secure policy skips AX.

- [ ] **Step 2: Verify RED**

Run: `cargo test -p vnkey-ui replacement_strategy --lib -- --nocapture`

Expected: FAIL because orchestration is missing.

- [ ] **Step 3: Implement orchestration and macOS backend**

Remove `IS_SPOTLIGHT_OR_ELECTRON` and the hard-coded Electron detection. Query the focused element and role, reject secure controls, read `AXSelectedTextRange`, select the minimal preceding range plus current selection, set `AXSelectedText`, and fall back to existing signed CGEvents on any error. Preserve synchronous callback execution.

- [ ] **Step 4: Verify GREEN and compilation**

Run: `cargo test -p vnkey-ui --lib -- --nocapture`

Expected: PASS.

Run: `cargo check -p vnkey-ui`

Expected: success without new warnings from the replacement code.

- [ ] **Step 5: Commit**

Commit message: `feat(macos): add accessibility-first text replacement`

### Task 5: Composition reset and privacy-safe latency diagnostics

**Files:**
- Modify: `vnkey-ui/src-tauri/src/lib.rs`
- Modify: `vnkey-ui/src-tauri/src/macos_replacement.rs`
- Test: inline module tests in `macos_replacement.rs`

**Interfaces:**
- Produces: pure `should_reset_for_keycode(u16) -> bool` covering navigation and edit commands.
- Produces: `CallbackMetrics` counters and latency buckets containing durations and bundle ID only.

- [ ] **Step 1: Write failing reset and metrics tests**

Assert reset for arrows, Home, End, Page Up, Page Down, Forward Delete, Escape, Tab, Return, and Backspace; assert normal letter keycodes do not reset. Assert diagnostics formatting contains no typed content field and rate limiting suppresses repeated warnings.

- [ ] **Step 2: Verify RED**

Run: `cargo test -p vnkey-ui reset_for_keycode --lib -- --nocapture`

Expected: FAIL because the helper is absent.

- [ ] **Step 3: Implement reset handling and timings**

Reset before returning navigation/edit events. Reset when the frontmost bundle ID changes. Measure engine, AX, fallback, and total stages with `Instant`; aggregate without storing text. Emit only rate-limited slow-callback warnings in debug/diagnostic builds.

- [ ] **Step 4: Verify complete automated suite**

Run: `cargo fmt --all -- --check`

Expected: success.

Run: `cargo test -p vnkey-engine --release -- --nocapture`

Expected: all tests PASS.

Run: `cargo test -p vnkey-ui --lib -- --nocapture`

Expected: all tests PASS.

Run: `cargo check --workspace`

Expected: success.

- [ ] **Step 5: Manual macOS smoke test**

Build and run VNKey, then record AX/fallback selection, flick, ordering, and latency for TextEdit, Safari/Chrome, VS Code, Spotlight, Terminal, and a password field. No password content may appear in logs. This step requires an interactive macOS session and Accessibility permission.

- [ ] **Step 6: Commit**

Commit message: `perf(macos): reset stale composition and measure callback latency`

