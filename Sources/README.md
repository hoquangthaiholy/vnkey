# VNKey Control Panel

The VNKey control panel is implemented with Tauri 2, Svelte 5, TypeScript,
Rust, and the shared C++ VNKey engine.

The webview owns all user-facing configuration screens:

- input method and Vietnamese spelling rules;
- macro management;
- text/code-page conversion;
- application compatibility settings;
- tray menu state.

Platform-specific keyboard capture remains behind native adapters. macOS uses
`tauri_event_tap.mm`; Windows and Linux can provide their own adapter without
changing the control panel or its command API.

## Development

```sh
npm install
npm run check
npm run tauri dev
```

Create a release bundle with:

```sh
npm run tauri build
```
