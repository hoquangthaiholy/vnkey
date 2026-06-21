<script lang="ts">
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { listen } from "@tauri-apps/api/event";

  interface Settings {
    language: number;
    input_type: number;
    free_mark: number;
    code_table: number;
    switch_key_status: number;
    check_spelling: number;
    use_modern_orthography: number;
    quick_telex: number;
    restore_if_wrong_spelling: number;
    use_english_dictionary: number;
    fix_recommend_browser: number;
    use_macro: number;
    use_macro_in_english_mode: number;
    auto_caps_macro: number;
    use_smart_switch_key: number;
    upper_case_first_char: number;
    temp_off_spelling: number;
    allow_consonant_zfwj: number;
    quick_start_consonant: number;
    quick_end_consonant: number;
    remember_code: number;
    other_language: number;
    temp_off_vnkey: number;
    send_key_step_by_step: number;
    fix_chromium_browser: number;
    perform_layout_compat: number;
    gray_icon: number;
    convert_tool_dont_alert: number;
    convert_tool_to_all_caps: number;
    convert_tool_to_all_non_caps: number;
    convert_tool_to_caps_first_letter: number;
    convert_tool_to_caps_each_word: number;
    convert_tool_remove_mark: number;
    convert_tool_from_code: number;
    convert_tool_to_code: number;
    convert_tool_hotkey: number;
  }

  let settings = $state<Settings>({
    language: 1,
    input_type: 0,
    free_mark: 0,
    code_table: 0,
    switch_key_status: 0x20000C31, // Cmd + Shift + Space
    check_spelling: 1,
    use_modern_orthography: 0,
    quick_telex: 0,
    restore_if_wrong_spelling: 0,
    use_english_dictionary: 1,
    fix_recommend_browser: 1,
    use_macro: 1,
    use_macro_in_english_mode: 0,
    auto_caps_macro: 1,
    use_smart_switch_key: 1,
    upper_case_first_char: 0,
    temp_off_spelling: 0,
    allow_consonant_zfwj: 0,
    quick_start_consonant: 0,
    quick_end_consonant: 0,
    remember_code: 1,
    other_language: 1,
    temp_off_vnkey: 0,
    send_key_step_by_step: 0,
    fix_chromium_browser: 0,
    perform_layout_compat: 0,
    gray_icon: 1,
    convert_tool_dont_alert: 0,
    convert_tool_to_all_caps: 0,
    convert_tool_to_all_non_caps: 0,
    convert_tool_to_caps_first_letter: 0,
    convert_tool_to_caps_each_word: 0,
    convert_tool_remove_mark: 0,
    convert_tool_from_code: 0,
    convert_tool_to_code: 0,
    convert_tool_hotkey: 0xFE0000FE,
  });

  let activeTab = $state(0);
  let isSaving = $state(false);
  let hasAccessibility = $state(true);

  // Macros state
  let macrosList = $state<{ shortcut: string; content: string }[]>([]);
  let searchQuery = $state("");

  // English Dictionary state
  let customEnglishWords = $state("");
  let savingDict = $state(false);
  let saveDictSuccess = $state(false);
  let newShortcut = $state("");
  let newContent = $state("");
  let macroError = $state("");

  // Convert Tool state
  let sourceText = $state("");
  let resultText = $state("");
  let convertError = $state("");
  let converting = $state(false);

  // Hotkey states
  let isRecordingSwitchKey = $state(false);
  let isRecordingConvertHotkey = $state(false);

  const charToMacKeyCode: Record<string, number> = {
    "`": 50, "~": 50, "1": 18, "!": 18, "2": 19, "@": 19, "3": 20, "#": 20, "4": 21, "$": 21,
    "5": 23, "%": 23, "6": 22, "^": 22, "7": 26, "&": 26, "8": 28, "*": 28, "9": 25, "(": 25,
    "0": 29, ")": 29, "-": 27, "_": 27, "=": 24, "+": 24,
    "q": 12, "w": 13, "e": 14, "r": 15, "t": 17, "y": 16, "u": 32, "i": 34, "o": 31, "p": 35,
    "[": 33, "{": 33, "]": 30, "}": 30, "\\": 42, "|": 42,
    "a": 0, "s": 1, "d": 2, "f": 3, "g": 5, "h": 4, "j": 38, "k": 40, "l": 37,
    ";": 41, ":": 41, "'": 39, "\"": 39,
    "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "n": 45, "m": 46,
    ",": 43, "<": 43, ".": 47, ">": 47, "/": 44, "?": 44,
    " ": 49
  };

  function unpackHotkey(status: number) {
    const keyCode = status & 0xff;
    const ctrl = (status & 0x100) !== 0;
    const option = (status & 0x200) !== 0;
    const command = (status & 0x400) !== 0;
    const shift = (status & 0x800) !== 0;
    const beep = (status & 0x8000) !== 0;
    const charCode = (status >> 24) & 0xff;
    const charStr = charCode > 0 ? String.fromCharCode(charCode).toUpperCase() : "";
    return { keyCode, ctrl, option, command, shift, beep, charStr };
  }

  function packHotkey(info: {
    keyCode: number;
    ctrl: boolean;
    option: boolean;
    command: boolean;
    shift: boolean;
    beep: boolean;
    charStr: string;
  }) {
    let status = info.keyCode & 0xff;
    if (info.ctrl) status |= 0x100;
    if (info.option) status |= 0x200;
    if (info.command) status |= 0x400;
    if (info.shift) status |= 0x800;
    if (info.beep) status |= 0x8000;
    const charCode = info.charStr ? info.charStr.charCodeAt(0) : 0;
    status |= (charCode & 0xff) << 24;
    return status;
  }

  let switchKeyInfo = $derived(unpackHotkey(settings.switch_key_status));
  let convertHotkeyInfo = $derived(unpackHotkey(settings.convert_tool_hotkey));

  function formatHotkeyString(info: ReturnType<typeof unpackHotkey>) {
    let parts = [];
    if (info.ctrl) parts.push("⌃ Control");
    if (info.option) parts.push("⌥ Option");
    if (info.command) parts.push("⌘ Command");
    if (info.shift) parts.push("⇧ Shift");
    
    if (info.keyCode === 0xfe) {
      if (parts.length === 0) return "Chưa thiết lập";
    } else if (info.keyCode === 49) {
      parts.push("␣ Space");
    } else if (info.charStr) {
      parts.push(info.charStr);
    } else {
      parts.push(`Key ${info.keyCode}`);
    }
    return parts.join(" + ");
  }

  async function checkAccessibility() {
    try {
      const granted = await invoke<boolean>("check_accessibility");
      hasAccessibility = granted;
      return granted;
    } catch (error) {
      console.error("Failed to check accessibility:", error);
      return false;
    }
  }

  function requestAccessibility() {
    invoke("request_accessibility");
  }

  async function loadSettings() {
    try {
      const res = await invoke<Settings>("get_settings");
      if (res) {
        settings = res;
      }
    } catch (e) {
      console.error("Failed to load settings:", e);
    }
  }

  async function saveSettings() {
    isSaving = true;
    try {
      await invoke("update_settings", { settings });
    } catch (e) {
      console.error("Failed to save settings:", e);
    } finally {
      setTimeout(() => {
        isSaving = false;
      }, 300);
    }
  }

  async function loadMacros() {
    try {
      macrosList = await invoke<typeof macrosList>("list_macros");
    } catch (e) {
      console.error("Failed to list macros:", e);
    }
  }

  async function loadCustomEnglishWords() {
    try {
      customEnglishWords = await invoke<string>("get_custom_english_words");
    } catch (e) {
      console.error("Failed to load custom English words:", e);
    }
  }

  async function saveCustomEnglishWords() {
    savingDict = true;
    saveDictSuccess = false;
    try {
      await invoke("save_custom_english_words", { words: customEnglishWords });
      saveDictSuccess = true;
      setTimeout(() => {
        saveDictSuccess = false;
      }, 3000);
    } catch (e) {
      console.error("Failed to save custom English words:", e);
    } finally {
      savingDict = false;
    }
  }

  async function addMacro() {
    macroError = "";
    if (!newShortcut.trim() || !newContent.trim()) {
      macroError = "Từ gõ tắt và nội dung không được để trống.";
      return;
    }
    try {
      macrosList = await invoke<typeof macrosList>("upsert_macro", {
        shortcut: newShortcut.trim(),
        content: newContent.trim()
      });
      newShortcut = "";
      newContent = "";
    } catch (e: any) {
      macroError = e.toString();
    }
  }

  async function deleteMacro(shortcut: string) {
    try {
      macrosList = await invoke<typeof macrosList>("remove_macro", { shortcut });
    } catch (e) {
      console.error("Failed to delete macro:", e);
    }
  }

  let filteredMacros = $derived(
    macrosList.filter(m => 
      m.shortcut.toLowerCase().includes(searchQuery.toLowerCase()) ||
      m.content.toLowerCase().includes(searchQuery.toLowerCase())
    )
  );

  async function convertText() {
    if (!sourceText) {
      resultText = "";
      return;
    }
    convertError = "";
    converting = true;
    try {
      const res = await invoke<string>("convert_text", {
        request: {
          source: sourceText,
          fromCode: settings.convert_tool_from_code,
          toCode: settings.convert_tool_to_code,
          allCaps: settings.convert_tool_to_all_caps === 1,
          allNonCaps: settings.convert_tool_to_all_non_caps === 1,
          capsFirstLetter: settings.convert_tool_to_caps_first_letter === 1,
          capsEachWord: settings.convert_tool_to_caps_each_word === 1,
          removeMark: settings.convert_tool_remove_mark === 1,
        }
      });
      resultText = res;
    } catch (e: any) {
      convertError = e.toString();
    } finally {
      converting = false;
    }
  }

  async function triggerClipboardConvert() {
    try {
      await invoke("trigger_quick_convert");
    } catch (e) {
      console.error("Clipboard convert failed:", e);
    }
  }

  function swapConvertCodes() {
    const temp = settings.convert_tool_from_code;
    settings.convert_tool_from_code = settings.convert_tool_to_code;
    settings.convert_tool_to_code = temp;
    saveSettings();
  }

  function handleConvertCapChange(capType: 'all_caps' | 'all_non_caps' | 'caps_first_letter' | 'caps_each_word', checked: boolean) {
    settings.convert_tool_to_all_caps = 0;
    settings.convert_tool_to_all_non_caps = 0;
    settings.convert_tool_to_caps_first_letter = 0;
    settings.convert_tool_to_caps_each_word = 0;

    if (checked) {
      if (capType === 'all_caps') settings.convert_tool_to_all_caps = 1;
      else if (capType === 'all_non_caps') settings.convert_tool_to_all_non_caps = 1;
      else if (capType === 'caps_first_letter') settings.convert_tool_to_caps_first_letter = 1;
      else if (capType === 'caps_each_word') settings.convert_tool_to_caps_each_word = 1;
    }
    saveSettings();
  }

  async function setRecordingSwitchKey(val: boolean) {
    isRecordingSwitchKey = val;
    try {
      await invoke("disable_hotkeys", { disable: val });
    } catch (e) {
      console.error("Failed to set disable_hotkeys:", e);
    }
  }

  async function setRecordingConvertHotkey(val: boolean) {
    isRecordingConvertHotkey = val;
    try {
      await invoke("disable_hotkeys", { disable: val });
    } catch (e) {
      console.error("Failed to set disable_hotkeys:", e);
    }
  }

  function handleHotkeyKeyDown(event: KeyboardEvent, type: 'switch' | 'convert') {
    event.preventDefault();
    event.stopPropagation();
    
    if (["Control", "Alt", "Meta", "Shift"].includes(event.key)) {
      return;
    }

    let key = event.key.toLowerCase();
    let macCode = 0xfe;
    let charStr = "";
    
    let ctrl = event.ctrlKey;
    let option = event.altKey;
    let command = event.metaKey;
    let shift = event.shiftKey;

    if (key === "escape") {
      macCode = 0xfe;
      charStr = "";
      ctrl = false;
      option = false;
      command = false;
      shift = false;
    } else if (charToMacKeyCode[key] !== undefined) {
      macCode = charToMacKeyCode[key];
      charStr = event.key.toUpperCase();
    } else if (event.key.length === 1) {
      const letterMap: Record<string, number> = {
        a:0, b:11, c:8, d:2, e:14, f:3, g:5, h:4, i:34, j:38, k:40, l:37, m:46,
        n:45, o:31, p:35, q:12, r:15, s:1, t:17, u:32, v:9, w:13, x:7, y:16, z:6
      };
      macCode = letterMap[key] !== undefined ? letterMap[key] : 0xfe;
      charStr = event.key.toUpperCase();
    }

    if (type === 'switch') {
      const current = unpackHotkey(settings.switch_key_status);
      settings.switch_key_status = packHotkey({
        keyCode: macCode,
        ctrl,
        option,
        command,
        shift,
        beep: current.beep,
        charStr: charStr
      });
      setRecordingSwitchKey(false);
      saveSettings();
    } else {
      settings.convert_tool_hotkey = packHotkey({
        keyCode: macCode,
        ctrl,
        option,
        command,
        shift,
        beep: false,
        charStr: charStr
      });
      setRecordingConvertHotkey(false);
      saveSettings();
    }
  }

  function autofocusAction(node: HTMLButtonElement) {
    node.focus();
    setTimeout(() => {
      node.focus();
    }, 10);
  }

  function toggleModifier(type: 'switch' | 'convert', modifier: 'ctrl' | 'option' | 'command' | 'shift' | 'beep') {
    if (type === 'switch') {
      const current = unpackHotkey(settings.switch_key_status);
      if (modifier === 'beep') {
        current.beep = !current.beep;
      } else {
        current[modifier] = !current[modifier];
      }
      settings.switch_key_status = packHotkey(current);
    } else {
      const current = unpackHotkey(settings.convert_tool_hotkey);
      if (modifier === 'beep') {
        current.beep = !current.beep;
      } else {
        current[modifier] = !current[modifier];
      }
      settings.convert_tool_hotkey = packHotkey(current);
    }
    saveSettings();
  }

  function handleCheckboxChange(key: keyof Settings, value: boolean) {
    settings[key] = value ? 1 : 0;
    saveSettings();
  }

  function handleSelectChange(key: keyof Settings, value: number) {
    settings[key] = value;
    saveSettings();
  }

  onMount(() => {
    let pollingInterval: number | undefined;
    let stopListeningSettings: (() => void) | undefined;
    let stopListeningAccessibility: (() => void) | undefined;
    let stopListeningShowTab: (() => void) | undefined;

    checkAccessibility().then((granted) => {
      if (granted) {
        loadSettings();
        loadMacros();
        loadCustomEnglishWords();
      } else {
        pollingInterval = window.setInterval(async () => {
          const ok = await checkAccessibility();
          if (ok) {
            loadSettings();
            loadMacros();
            loadCustomEnglishWords();
            if (pollingInterval) {
              clearInterval(pollingInterval);
              pollingInterval = undefined;
            }
          }
        }, 1500);
      }
    });

    listen<Settings>("settings-changed", (event) => {
      settings = event.payload;
    }).then((unsub) => {
      stopListeningSettings = unsub;
    });

    listen<number>("show-tab", (event) => {
      activeTab = event.payload;
    }).then((unsub) => {
      stopListeningShowTab = unsub;
    });

    listen<boolean>("quick-convert-result", (event) => {
      if (event.payload) {
        alert("Chuyển mã thành công! Kết quả đã được lưu trong clipboard.");
      } else {
        alert("Không có dữ liệu trong clipboard! Hãy sao chép một đoạn text để chuyển đổi!");
      }
    });

    listen<void>("accessibility-granted", () => {
      hasAccessibility = true;
      loadSettings();
      loadMacros();
      if (pollingInterval) {
        clearInterval(pollingInterval);
        pollingInterval = undefined;
      }
    }).then((unsub) => {
      stopListeningAccessibility = unsub;
    });

    return () => {
      if (stopListeningSettings) stopListeningSettings();
      if (stopListeningAccessibility) stopListeningAccessibility();
      if (stopListeningShowTab) stopListeningShowTab();
      if (pollingInterval) clearInterval(pollingInterval);
    };
  });
</script>

{#if !hasAccessibility}
  <div class="welcome-screen">
    <div class="welcome-drag-bar" data-tauri-drag-region></div>
    
    <div class="welcome-header" data-tauri-drag-region>
      <div class="welcome-logo">V</div>
      <h1>Chào mừng đến với VNKey</h1>
      <p class="welcome-desc">
        VNKey cần quyền <strong>Trợ năng (Accessibility)</strong> để có thể nhận diện phím gõ tiếng Việt trên macOS.
      </p>
    </div>

    <div class="welcome-steps-grid">
      <div class="step-card">
        <div class="step-num">1</div>
        <h4>Cấp quyền</h4>
        <p>Nhấp vào nút <strong>Cấp quyền trợ năng</strong> ở phía dưới.</p>
      </div>

      <div class="step-card">
        <div class="step-num">2</div>
        <h4>Mở Cài đặt</h4>
        <p>Chọn <strong>Mở Cài đặt hệ thống</strong> trong hộp thoại xuất hiện.</p>
      </div>

      <div class="step-card">
        <div class="step-num">3</div>
        <h4>Kích hoạt</h4>
        <p>Tìm ứng dụng <strong>VNKey</strong> và gạt công tắc cho phép hoạt động.</p>
      </div>
    </div>

    <div class="welcome-footer">
      <div class="welcome-actions-row">
        <button class="btn btn-primary" onclick={requestAccessibility}>Cấp quyền trợ năng</button>
        <button class="btn btn-secondary" onclick={() => invoke("quit")}>Thoát ứng dụng</button>
      </div>
      <p class="welcome-footer-note">
        <span class="pulse-dot"></span> Ứng dụng sẽ tự động kích hoạt ngay sau khi quyền trợ năng được bật.
      </p>
    </div>
  </div>
{:else}
  <div class="app-layout">
    <!-- Left Sidebar -->
    <aside class="sidebar" data-tauri-drag-region>
      <div class="sidebar-header" data-tauri-drag-region>
        <span class="logo">V</span>
        <span class="title">VNKey</span>
      </div>

      <nav class="nav-menu" data-tauri-drag-region>
        <button class="nav-item" class:active={activeTab === 0} onclick={() => activeTab = 0}>
          <svg class="nav-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="4" width="20" height="16" rx="2" ry="2"></rect><line x1="6" y1="8" x2="6" y2="8"></line><line x1="10" y1="8" x2="10" y2="8"></line><line x1="14" y1="8" x2="14" y2="8"></line><line x1="18" y1="8" x2="18" y2="8"></line><line x1="6" y1="12" x2="6" y2="12"></line><line x1="10" y1="12" x2="10" y2="12"></line><line x1="14" y1="12" x2="14" y2="12"></line><line x1="18" y1="12" x2="18" y2="12"></line><line x1="7" y1="16" x2="17" y2="16"></line></svg>
          Gõ phím
        </button>
        <button class="nav-item" class:active={activeTab === 1} onclick={() => activeTab = 1}>
          <svg class="nav-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"></polygon></svg>
          Gõ tắt
        </button>
        <button class="nav-item" class:active={activeTab === 2} onclick={() => activeTab = 2}>
          <svg class="nav-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 1V23M17 23L13 19M17 23L21 19M7 23V1M7 1L3 5M7 1L11 5" /></svg>
          Chuyển mã
        </button>
        <button class="nav-item" class:active={activeTab === 3} onclick={() => activeTab = 3}>
          <svg class="nav-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"></path></svg>
          Hệ thống
        </button>
        <button class="nav-item" class:active={activeTab === 4} onclick={() => activeTab = 4}>
          <svg class="nav-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>
          Thông tin
        </button>
      </nav>

      <div class="sidebar-footer" data-tauri-drag-region>
        <div class="lang-switch">
          <button class:active={settings.language === 1} onclick={() => handleSelectChange('language', 1)}>VI</button>
          <button class:active={settings.language === 0} onclick={() => handleSelectChange('language', 0)}>EN</button>
        </div>
        <div class="sync-status" class:saving={isSaving} title={isSaving ? "Đang lưu cấu hình..." : "Cấu hình đã đồng bộ"}>
          <span class="status-indicator"></span>
        </div>
      </div>
    </aside>

    <!-- Content Drag Bar for dragging from empty header area on the right -->
    <div class="content-top-drag-bar" data-tauri-drag-region></div>

    <!-- Main Content Area -->
    <main class="content-area">
      <!-- Tab 0: Gõ phím -->
      {#if activeTab === 0}
        <section class="panel">
          <div class="panel-header">
            <h2>Điều khiển & Gõ phím</h2>
            <p class="panel-subtitle">Thiết lập bộ gõ, bảng mã và các quy chuẩn chính tả tiếng Việt.</p>
          </div>

          <div class="grid-2col">
            <div class="card">
              <h3>Cơ bản</h3>
              <div class="form-group-inline">
                <label for="input-type">Kiểu gõ</label>
                <select id="input-type" value={settings.input_type} onchange={(e) => handleSelectChange('input_type', parseInt((e.target as HTMLSelectElement).value))}>
                  <option value={0}>Telex</option>
                  <option value={1}>VNI</option>
                  <option value={2}>Simple Telex 1</option>
                  <option value={3}>Simple Telex 2</option>
                </select>
              </div>
              <div class="form-group-inline mt-15">
                <label for="code-table">Bảng mã</label>
                <select id="code-table" value={settings.code_table} onchange={(e) => handleSelectChange('code_table', parseInt((e.target as HTMLSelectElement).value))}>
                  <option value={0}>Unicode dựng sẵn</option>
                  <option value={1}>TCVN3 (ABC)</option>
                  <option value={2}>VNI Windows</option>
                  <option value={3}>Unicode tổ hợp</option>
                  <option value={4}>Vietnamese Locale CP1258</option>
                </select>
              </div>
            </div>

            <!-- Hotkey Switcher Config Card -->
            <div class="card">
              <h3>Phím chuyển bộ gõ</h3>
              <div class="hotkey-section">
                <div class="hotkey-recorder-container">
                  {#if isRecordingSwitchKey}
                    <button 
                      use:autofocusAction
                      class="btn btn-primary recording-btn pulse w-full"
                      onkeydown={(e) => handleHotkeyKeyDown(e, 'switch')}
                      onblur={() => setRecordingSwitchKey(false)}
                    >
                      Nhập phím tắt...
                    </button>
                  {:else}
                    <button 
                      class="btn btn-secondary hotkey-btn w-full" 
                      onclick={() => setRecordingSwitchKey(true)}
                      title="Click và nhấn tổ hợp phím để đặt phím tắt"
                    >
                      {formatHotkeyString(switchKeyInfo)}
                    </button>
                  {/if}
                </div>

                <label class="toggle-container mt-15">
                  <span class="toggle-text">Phát tiếng bíp khi chuyển bộ gõ</span>
                  <div class="switch">
                    <input type="checkbox" checked={switchKeyInfo.beep} onchange={() => toggleModifier('switch', 'beep')} />
                    <span class="slider"></span>
                  </div>
                </label>
              </div>
            </div>
          </div>

          <div class="card mt-20">
            <h3>Quy tắc gõ dấu</h3>
            <div class="toggles-grid">
              <label class="toggle-container">
                <span class="toggle-text">Cho phép bỏ dấu tự do</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.free_mark === 1} onchange={(e) => handleCheckboxChange('free_mark', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Đặt dấu oà, uý (thay vì òa, úy)</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.use_modern_orthography === 1} onchange={(e) => handleCheckboxChange('use_modern_orthography', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Viết hoa chữ cái đầu tiên của câu</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.upper_case_first_char === 1} onchange={(e) => handleCheckboxChange('upper_case_first_char', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Cho phép gõ tắt Telex nhanh</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.quick_telex === 1} onchange={(e) => handleCheckboxChange('quick_telex', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Gõ nhanh phụ âm đầu</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.quick_start_consonant === 1} onchange={(e) => handleCheckboxChange('quick_start_consonant', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Gõ nhanh phụ âm cuối</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.quick_end_consonant === 1} onchange={(e) => handleCheckboxChange('quick_end_consonant', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>
            </div>
          </div>

          <div class="card mt-20">
            <h3>Chính tả & Kiểm tra</h3>
            <label class="toggle-container mb-15">
              <span class="toggle-text font-bold">Bật kiểm tra chính tả</span>
              <div class="switch">
                <input type="checkbox" checked={settings.check_spelling === 1} onchange={(e) => handleCheckboxChange('check_spelling', (e.target as HTMLInputElement).checked)} />
                <span class="slider"></span>
              </div>
            </label>

            <div class="sub-toggles-grid" class:disabled-zone={settings.check_spelling !== 1}>
              <label class="toggle-container">
                <span class="toggle-text">Khôi phục từ khi gõ sai chính tả</span>
                <div class="switch">
                  <input type="checkbox" disabled={settings.check_spelling !== 1} checked={settings.restore_if_wrong_spelling === 1} onchange={(e) => handleCheckboxChange('restore_if_wrong_spelling', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Tự động ngắt chính tả khi gõ chữ và số</span>
                <div class="switch">
                  <input type="checkbox" disabled={settings.check_spelling !== 1} checked={settings.temp_off_spelling === 1} onchange={(e) => handleCheckboxChange('temp_off_spelling', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Cho phép gõ tự do các phụ âm [z, f, w, j] đầu từ</span>
                <div class="switch">
                  <input type="checkbox" disabled={settings.check_spelling !== 1} checked={settings.allow_consonant_zfwj === 1} onchange={(e) => handleCheckboxChange('allow_consonant_zfwj', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Sử dụng từ điển tiếng Anh</span>
                <div class="switch">
                  <input type="checkbox" disabled={settings.check_spelling !== 1} checked={settings.use_english_dictionary === 1} onchange={(e) => handleCheckboxChange('use_english_dictionary', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              {#if settings.check_spelling === 1 && settings.use_english_dictionary === 1}
                <div class="dict-editor-container">
                  <div class="dict-editor-header">
                    <span>Danh sách từ tiếng Anh cần bảo vệ (cách nhau bởi khoảng trắng hoặc xuống dòng):</span>
                  </div>
                  <textarea 
                    bind:value={customEnglishWords}
                    placeholder="# Thêm các từ tiếng Anh cần bảo vệ tại đây&#10;# Ví dụ:&#10;source&#10;rust&#10;test"
                    class="dict-textarea"
                  ></textarea>
                  <div class="dict-editor-actions">
                    <button class="btn btn-primary" onclick={saveCustomEnglishWords} disabled={savingDict}>
                      {savingDict ? 'Đang lưu...' : 'Lưu danh sách'}
                    </button>
                    {#if saveDictSuccess}
                      <span class="save-status success">Lưu thành công!</span>
                    {/if}
                  </div>
                </div>
              {/if}
            </div>
          </div>
        </section>

      <!-- Tab 1: Gõ tắt -->
      {:else if activeTab === 1}
        <section class="panel">
          <div class="panel-header">
            <h2>Gõ tắt & Macro</h2>
            <p class="panel-subtitle">Tùy biến viết tắt giúp tăng tốc độ soạn thảo văn bản hàng ngày.</p>
          </div>

          <div class="card">
            <h3>Cấu hình chung</h3>
            <div class="toggles-grid">
              <label class="toggle-container">
                <span class="toggle-text">Cho phép gõ tắt</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.use_macro === 1} onchange={(e) => handleCheckboxChange('use_macro', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Cho phép gõ tắt ở chế độ tiếng Anh</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.use_macro_in_english_mode === 1} onchange={(e) => handleCheckboxChange('use_macro_in_english_mode', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Tự động viết hoa từ gõ tắt</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.auto_caps_macro === 1} onchange={(e) => handleCheckboxChange('auto_caps_macro', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>
            </div>
          </div>

          <div class="card mt-20" class:disabled-zone={settings.use_macro !== 1}>
            <h3>Bảng quản lý viết tắt</h3>
            
            <!-- Add New Macro Form -->
            <div class="macro-form mt-10">
              <input type="text" placeholder="Từ viết tắt (ví dụ: ok)" disabled={settings.use_macro !== 1} bind:value={newShortcut} />
              <input type="text" placeholder="Nội dung thay thế (ví dụ: OpenKey)" disabled={settings.use_macro !== 1} bind:value={newContent} onkeydown={(e) => e.key === 'Enter' && addMacro()} />
              <button class="btn btn-primary" disabled={settings.use_macro !== 1} onclick={addMacro}>Thêm mới</button>
            </div>
            
            {#if macroError}
              <p class="error-text">{macroError}</p>
            {/if}

            <div class="macro-search mt-15">
              <input type="text" placeholder="Tìm kiếm nhanh từ gõ tắt..." disabled={settings.use_macro !== 1} bind:value={searchQuery} />
            </div>

            <!-- Scrollable Macro Table -->
            <div class="macro-list-container mt-15">
              {#if filteredMacros.length === 0}
                <div class="empty-state">Không tìm thấy mục gõ tắt nào.</div>
              {:else}
                <table class="macro-table">
                  <thead>
                    <tr>
                      <th>Từ tắt</th>
                      <th>Nội dung thay thế</th>
                      <th style="width: 80px; text-align: center;">Thao tác</th>
                    </tr>
                  </thead>
                  <tbody>
                    {#each filteredMacros as macro}
                      <tr>
                        <td class="font-mono font-bold">{macro.shortcut}</td>
                        <td>{macro.content}</td>
                        <td style="text-align: center;">
                          <button class="btn-delete" disabled={settings.use_macro !== 1} onclick={() => deleteMacro(macro.shortcut)}>Xóa</button>
                        </td>
                      </tr>
                    {/each}
                  </tbody>
                </table>
              {/if}
            </div>
          </div>
        </section>

      <!-- Tab 2: Chuyển mã -->
      {:else if activeTab === 2}
        <section class="panel">
          <div class="panel-header">
            <h2>Công cụ chuyển mã</h2>
            <p class="panel-subtitle">Chuyển đổi bảng mã văn bản tiếng Việt dễ dàng hoặc đặt phím tắt chuyển nhanh Clipboard.</p>
          </div>

          <div class="grid-2col">
            <!-- Convert Settings & Options -->
            <div class="card">
              <h3>Cấu hình chuyển đổi</h3>
              <div class="form-group">
                <label for="convert-from">Bảng mã nguồn</label>
                <select id="convert-from" value={settings.convert_tool_from_code} onchange={(e) => handleSelectChange('convert_tool_from_code', parseInt((e.target as HTMLSelectElement).value))}>
                  <option value={0}>Unicode dựng sẵn</option>
                  <option value={1}>TCVN3 (ABC)</option>
                  <option value={2}>VNI Windows</option>
                  <option value={3}>Unicode tổ hợp</option>
                  <option value={4}>Vietnamese Locale CP1258</option>
                </select>
              </div>

              <div class="swap-button-container-vertical">
                <button class="btn btn-secondary swap-btn-vertical" onclick={swapConvertCodes} title="Đảo bảng mã">
                  ⇅ Đảo bảng mã nguồn & đích
                </button>
              </div>

              <div class="form-group">
                <label for="convert-to">Bảng mã đích</label>
                <select id="convert-to" value={settings.convert_tool_to_code} onchange={(e) => handleSelectChange('convert_tool_to_code', parseInt((e.target as HTMLSelectElement).value))}>
                  <option value={0}>Unicode dựng sẵn</option>
                  <option value={1}>TCVN3 (ABC)</option>
                  <option value={2}>VNI Windows</option>
                  <option value={3}>Unicode tổ hợp</option>
                  <option value={4}>Vietnamese Locale CP1258</option>
                </select>
              </div>

              <div class="form-group mt-15">
                <label>Tùy chọn văn bản đầu ra</label>
                <div class="toggles-grid-compact mt-5">
                  <label class="toggle-container">
                    <span class="toggle-text">Chuyển sang CHỮ HOA</span>
                    <div class="switch">
                      <input type="checkbox" checked={settings.convert_tool_to_all_caps === 1} onchange={(e) => handleConvertCapChange('all_caps', (e.target as HTMLInputElement).checked)} />
                      <span class="slider"></span>
                    </div>
                  </label>

                  <label class="toggle-container">
                    <span class="toggle-text">Chuyển sang chữ thường</span>
                    <div class="switch">
                      <input type="checkbox" checked={settings.convert_tool_to_all_non_caps === 1} onchange={(e) => handleConvertCapChange('all_non_caps', (e.target as HTMLInputElement).checked)} />
                      <span class="slider"></span>
                    </div>
                  </label>

                  <label class="toggle-container">
                    <span class="toggle-text">Viết hoa chữ đầu tiên</span>
                    <div class="switch">
                      <input type="checkbox" checked={settings.convert_tool_to_caps_first_letter === 1} onchange={(e) => handleConvertCapChange('caps_first_letter', (e.target as HTMLInputElement).checked)} />
                      <span class="slider"></span>
                    </div>
                  </label>

                  <label class="toggle-container">
                    <span class="toggle-text">Viết Hoa Đầu Mỗi Từ</span>
                    <div class="switch">
                      <input type="checkbox" checked={settings.convert_tool_to_caps_each_word === 1} onchange={(e) => handleConvertCapChange('caps_each_word', (e.target as HTMLInputElement).checked)} />
                      <span class="slider"></span>
                    </div>
                  </label>

                  <label class="toggle-container pt-5" style="border-top: 1px solid var(--border-color);">
                    <span class="toggle-text font-bold">Loại bỏ hoàn toàn dấu Tiếng Việt</span>
                    <div class="switch">
                      <input type="checkbox" checked={settings.convert_tool_remove_mark === 1} onchange={(e) => handleCheckboxChange('convert_tool_remove_mark', (e.target as HTMLInputElement).checked)} />
                      <span class="slider"></span>
                    </div>
                  </label>
                </div>
              </div>
            </div>

            <!-- Quick Clipboard Convert Hotkey Card -->
            <div class="card">
              <h3>Phím tắt chuyển mã nhanh</h3>
              <div class="hotkey-section">
                <div class="hotkey-recorder-container">
                  {#if isRecordingConvertHotkey}
                    <button 
                      use:autofocusAction
                      class="btn btn-primary recording-btn pulse w-full"
                      onkeydown={(e) => handleHotkeyKeyDown(e, 'convert')}
                      onblur={() => setRecordingConvertHotkey(false)}
                    >
                      Nhập phím tắt...
                    </button>
                  {:else}
                    <button 
                      class="btn btn-secondary hotkey-btn w-full" 
                      onclick={() => setRecordingConvertHotkey(true)}
                      title="Click và nhấn tổ hợp phím để đặt phím tắt"
                    >
                      {formatHotkeyString(convertHotkeyInfo)}
                    </button>
                  {/if}
                </div>

                <label class="toggle-container mt-15">
                  <span class="toggle-text">Tắt cảnh báo thành công khi chuyển mã</span>
                  <div class="switch">
                    <input type="checkbox" checked={settings.convert_tool_dont_alert === 1} onchange={(e) => handleCheckboxChange('convert_tool_dont_alert', (e.target as HTMLInputElement).checked)} />
                    <span class="slider"></span>
                  </div>
                </label>

                <div class="convert-clipboard-shortcut-area mt-15">
                  <button class="btn btn-secondary w-full" onclick={triggerClipboardConvert}>
                    Chuyển đổi Clipboard ngay
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- Text Editors Area -->
          <div class="card mt-20">
            <h3>Soạn thảo & Chuyển đổi trực tiếp</h3>
            <div class="editors-layout mt-10">
              <div class="editor-pane">
                <label for="source-pane">Văn bản gốc (Nguồn)</label>
                <textarea id="source-pane" placeholder="Nhập hoặc dán văn bản tiếng Việt cần chuyển đổi vào đây..." bind:value={sourceText}></textarea>
              </div>
              <div class="editor-pane">
                <label for="target-pane">Văn bản kết quả (Đích)</label>
                <textarea id="target-pane" placeholder="Kết quả chuyển đổi sẽ xuất hiện ở đây..." readonly bind:value={resultText}></textarea>
              </div>
            </div>

            {#if convertError}
              <p class="error-text">{convertError}</p>
            {/if}

            <div class="editor-actions mt-15">
              <button class="btn btn-primary" disabled={converting} onclick={convertText}>
                {converting ? "Đang chuyển..." : "Chuyển mã văn bản"}
              </button>
              <button class="btn btn-secondary" onclick={() => {
                navigator.clipboard.writeText(resultText);
                alert("Đã copy kết quả vào clipboard!");
              }} disabled={!resultText}>
                Copy kết quả
              </button>
              <button class="btn btn-secondary" onclick={() => { sourceText = ""; resultText = ""; }}>
                Xóa tất cả
              </button>
            </div>
          </div>
        </section>

      <!-- Tab 3: Hệ thống -->
      {:else if activeTab === 3}
        <section class="panel">
          <div class="panel-header">
            <h2>Thiết lập hệ thống</h2>
            <p class="panel-subtitle">Tùy chỉnh tích hợp sâu của bộ gõ vào hệ điều hành macOS.</p>
          </div>

          <div class="card">
            <h3>Tích hợp ứng dụng</h3>
            <div class="toggles-grid">
              <label class="toggle-container">
                <span class="toggle-text">Chuyển chế độ gõ thông minh theo từng ứng dụng</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.use_smart_switch_key === 1} onchange={(e) => handleCheckboxChange('use_smart_switch_key', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Tự động nhớ bảng mã riêng cho từng ứng dụng</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.remember_code === 1} onchange={(e) => handleCheckboxChange('remember_code', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Tắt tiếng Việt khi bộ gõ hệ thống khác tiếng Anh</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.other_language === 1} onchange={(e) => handleCheckboxChange('other_language', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Tạm tắt bộ gõ bằng phím tắt</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.temp_off_vnkey === 1} onchange={(e) => handleCheckboxChange('temp_off_vnkey', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>
            </div>
          </div>

          <div class="card mt-20">
            <h3>Hiển thị</h3>
            <div class="toggles-grid">
              <label class="toggle-container">
                <span class="toggle-text">Sử dụng biểu tượng đơn sắc xám trên thanh menu (Template mode)</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.gray_icon === 1} onchange={(e) => handleCheckboxChange('gray_icon', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>
            </div>
          </div>
          
          <div class="card mt-20">
            <h3>Khắc phục lỗi & Tương thích</h3>
            <div class="toggles-grid">
              <label class="toggle-container">
                <span class="toggle-text">Sửa lỗi gõ trên thanh địa chỉ của trình duyệt</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.fix_recommend_browser === 1} onchange={(e) => handleCheckboxChange('fix_recommend_browser', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container" class:disabled-zone={settings.fix_recommend_browser !== 1}>
                <span class="toggle-text">Sửa lỗi trình duyệt Google Chrome/Chromium</span>
                <div class="switch">
                  <input type="checkbox" disabled={settings.fix_recommend_browser !== 1} checked={settings.fix_chromium_browser === 1} onchange={(e) => handleCheckboxChange('fix_chromium_browser', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Gửi phím từng bước (sửa lỗi lặp từ trên trình duyệt Chrome/Safari)</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.send_key_step_by_step === 1} onchange={(e) => handleCheckboxChange('send_key_step_by_step', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Tương thích với các bố cục (layout) bàn phím khác hệ Mỹ</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.perform_layout_compat === 1} onchange={(e) => handleCheckboxChange('perform_layout_compat', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>
            </div>
          </div>
        </section>

      <!-- Tab 4: Thông tin -->
      {:else}
        <section class="panel">
          <div class="panel-header">
            <h2>Thông tin ứng dụng</h2>
            <p class="panel-subtitle">Lịch sử phát triển và hỗ trợ kỹ thuật cho bộ gõ VNKey.</p>
          </div>

          <div class="card info-card">
            <div class="info-header">
              <div class="app-icon">V</div>
              <div>
                <h3>VNKey</h3>
                <p class="version">Phiên bản 2.0.0 (Tauri Native Build)</p>
              </div>
            </div>
            <p class="desc">Bộ gõ tiếng Việt mã nguồn mở, gọn nhẹ, chạy nhanh và an toàn tuyệt đối cho người dùng trên nền tảng macOS, Windows và Linux.</p>
            
            <div class="links-grid">
              <a href="https://open-key.org" target="_blank" class="link-item">Trang chủ VNKey</a>
              <a href="https://github.com/tuyenvm/OpenKey" target="_blank" class="link-item">Nguồn mở (GitHub)</a>
              <a href="mailto:maivutuyen.91@gmail.com" class="link-item">Liên hệ tác giả</a>
            </div>

            <div class="info-footer pt-15 mt-10" style="border-top: 1px solid var(--border-color); display: flex; justify-content: space-between; align-items: center;">
              <span class="text-secondary" style="font-size: 13px;">Copyright © 2026 theodore & OpenKey Contributors</span>
              <button class="btn btn-secondary" onclick={() => alert("Ứng dụng đang ở phiên bản mới nhất!")}>Kiểm tra cập nhật</button>
            </div>
          </div>
        </section>
      {/if}
    </main>
  </div>
{/if}

<style>
  :root {
    --bg-app: #121216;
    --bg-sidebar: #191922;
    --bg-card: #1f1f2a;
    --bg-input: #121216;
    --bg-switch-off: #3a3a4c;
    --text-primary: #f5f5f7;
    --text-secondary: #a1a1b5;
    --color-accent: #007aff;
    --color-success: #30d158;
    --border-color: rgba(255, 255, 255, 0.08);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }

  @media (prefers-color-scheme: light) {
    :root {
      --bg-app: #f4f4f6;
      --bg-sidebar: #ffffff;
      --bg-card: #f9f9fb;
      --bg-input: #ffffff;
      --bg-switch-off: #e5e5ea;
      --text-primary: #1c1c1e;
      --text-secondary: #6c6c78;
      --color-accent: #007aff;
      --color-success: #34c759;
      --border-color: rgba(0, 0, 0, 0.08);
    }
  }

  :global(body) {
    margin: 0;
    padding: 0;
    background-color: var(--bg-app);
    color: var(--text-primary);
    overflow: hidden;
    user-select: none;
  }

  .app-layout {
    display: flex;
    flex-direction: row;
    width: 100vw;
    height: 100vh;
  }

  /* Left Sidebar */
  .sidebar {
    width: 220px;
    background-color: var(--bg-sidebar);
    border-right: 1px solid var(--border-color);
    display: flex;
    flex-direction: column;
    flex-shrink: 0;
    box-sizing: border-box;
    padding-top: 52px; /* Margin to clear native macOS Traffic Lights */
    height: 100%;
  }

  .sidebar-header {
    padding: 10px 24px 20px 24px;
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .sidebar-header .logo {
    width: 24px;
    height: 24px;
    background-color: var(--color-accent);
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 6px;
    font-weight: bold;
    font-size: 14px;
  }

  .sidebar-header .title {
    font-weight: 700;
    font-size: 16px;
    letter-spacing: 0.3px;
  }

  /* Navigation tab menu on Sidebar */
  .nav-menu {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 10px 16px;
    flex-grow: 1;
  }

  .nav-item {
    background: none;
    border: none;
    outline: none;
    color: var(--text-secondary);
    padding: 10px 14px;
    font-size: 13.5px;
    font-weight: 500;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.15s ease;
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    box-sizing: border-box;
  }

  .nav-item:hover {
    background-color: rgba(255, 255, 255, 0.04);
    color: var(--text-primary);
  }

  @media (prefers-color-scheme: light) {
    .nav-item:hover {
      background-color: rgba(0, 0, 0, 0.03);
    }
  }

  .nav-item.active {
    background-color: rgba(255, 255, 255, 0.08);
    color: var(--text-primary);
    font-weight: 600;
  }

  @media (prefers-color-scheme: light) {
    .nav-item.active {
      background-color: rgba(0, 0, 0, 0.06);
    }
  }

  .nav-icon {
    width: 18px;
    height: 18px;
    stroke: currentColor;
    flex-shrink: 0;
  }

  .sidebar-footer {
    padding: 20px 24px;
    border-top: 1px solid var(--border-color);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  /* sliding indicator / pill switch */
  .lang-switch {
    display: flex;
    background: rgba(0, 0, 0, 0.2);
    padding: 2px;
    border-radius: 6px;
    border: 1px solid var(--border-color);
  }

  @media (prefers-color-scheme: light) {
    .lang-switch {
      background: rgba(0, 0, 0, 0.05);
    }
  }

  .lang-switch button {
    background: none;
    border: none;
    color: var(--text-secondary);
    padding: 4px 10px;
    font-size: 11px;
    font-weight: 700;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.2s ease;
  }

  .lang-switch button.active {
    background: var(--color-accent);
    color: white;
  }

  .sync-status {
    width: 20px;
    height: 20px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .status-indicator {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background-color: var(--color-success);
    transition: background-color 0.2s ease;
  }

  .sync-status.saving .status-indicator {
    background-color: #ff9500;
    box-shadow: 0 0 8px #ff9500;
  }

  /* Content drag bar helper for frameless dragging on the right */
  .content-top-drag-bar {
    position: absolute;
    top: 0;
    left: 220px;
    right: 0;
    height: 48px;
    z-index: 10;
  }

  /* Content area scrollable */
  .content-area {
    flex-grow: 1;
    padding: 48px 40px 32px 40px;
    overflow-y: auto;
    box-sizing: border-box;
    height: 100%;
    position: relative;
  }

  .panel-header {
    margin-bottom: 20px;
  }

  .panel h2 {
    margin: 0;
    font-size: 19px;
    font-weight: 700;
    letter-spacing: -0.2px;
  }

  .panel-subtitle {
    margin: 4px 0 0 0;
    font-size: 12.5px;
    color: var(--text-secondary);
  }

  .card {
    background-color: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 12px;
    padding: 18px 20px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.05);
  }

  .card h3 {
    margin-top: 0;
    margin-bottom: 14px;
    font-size: 12.5px;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.8px;
    font-weight: 700;
  }

  /* layouts */
  .grid-2col {
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .swap-button-container-vertical {
    display: flex;
    justify-content: center;
    margin: 8px 0;
  }

  .swap-btn-vertical {
    padding: 6px 12px !important;
    font-size: 13px !important;
    display: flex;
    align-items: center;
    gap: 6px;
  }

  /* toggles layouts */
  .toggles-grid {
    display: grid;
    grid-template-columns: 1fr;
    column-gap: 30px;
    row-gap: 12px;
  }

  .sub-toggles-grid {
    display: grid;
    grid-template-columns: 1fr;
    column-gap: 30px;
    row-gap: 12px;
    padding-left: 10px;
    border-left: 2px solid var(--border-color);
  }

  .toggles-grid-compact {
    display: grid;
    grid-template-columns: 1fr;
    column-gap: 20px;
    row-gap: 8px;
  }

  .disabled-zone {
    opacity: 0.4;
    pointer-events: none;
    transition: opacity 0.2s ease;
  }

  /* Form Elements */
  .form-group {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .form-group label {
    font-size: 12.5px;
    color: var(--text-secondary);
    font-weight: 500;
  }

  .form-group-inline {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .form-group-inline label {
    font-size: 13.5px;
    color: var(--text-primary);
    font-weight: 500;
    width: 80px;
    flex-shrink: 0;
  }

  .form-group-inline select {
    width: auto;
    min-width: 240px;
  }

  select {
    width: 100%;
    box-sizing: border-box;
    padding: 12px 16px;
    border-radius: 6px;
    background-color: var(--bg-input);
    color: var(--text-primary);
    border: 1px solid var(--border-color);
    outline: none;
    font-size: 13.5px;
    cursor: pointer;
  }

  .form-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .form-row .form-group {
    flex: 1;
  }

  .swap-button-container {
    padding-top: 22px;
  }

  .swap-btn {
    padding: 6px 10px !important;
    font-size: 15px !important;
  }

  /* toggle switch vanilla */
  .toggle-container {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 13.5px;
    cursor: pointer;
  }

  .toggle-text {
    flex-grow: 1;
    padding-right: 12px;
  }

  .switch {
    position: relative;
    display: inline-block;
    width: 38px;
    height: 20px;
  }

  .switch input {
    opacity: 0;
    width: 0;
    height: 0;
  }

  .slider {
    position: absolute;
    cursor: pointer;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background-color: var(--bg-switch-off);
    transition: 0.15s;
    border-radius: 20px;
  }

  .slider:before {
    position: absolute;
    content: "";
    height: 14px;
    width: 14px;
    left: 3px;
    bottom: 3px;
    background-color: white;
    transition: 0.15s;
    border-radius: 50%;
  }

  input:checked + .slider {
    background-color: var(--color-accent);
  }

  input:checked + .slider:before {
    transform: translateX(18px);
  }

  /* Hotkey configurations styling */
  .modifiers-row {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }

  .badge-checkbox {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 4px 8px;
    border-radius: 6px;
    background-color: rgba(255, 255, 255, 0.03);
    border: 1px solid var(--border-color);
    font-size: 12px;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  @media (prefers-color-scheme: light) {
    .badge-checkbox {
      background-color: #ffffff;
    }
  }

  .badge-checkbox.checked {
    background-color: rgba(0, 122, 255, 0.1);
    border-color: var(--color-accent);
    color: var(--color-accent);
  }

  .badge-checkbox input {
    display: none;
  }

  .hotkey-recorder-container {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .hotkey-label {
    font-size: 12.5px;
    color: var(--text-secondary);
  }

  .hotkey-btn {
    flex-grow: 1;
    text-align: center;
    font-family: monospace;
    font-weight: bold;
    font-size: 13px !important;
    padding: 11px 16px !important;
  }

  .recording-btn {
    flex-grow: 1;
    font-size: 12.5px !important;
    background-color: #ff3b30 !important;
    color: white;
    padding: 11px 16px !important;
  }

  /* Buttons */
  .btn {
    border: none;
    outline: none;
    padding: 7px 16px;
    border-radius: 6px;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .btn-primary {
    background-color: var(--color-accent);
    color: white;
  }

  .btn-primary:hover {
    background-color: #0062cc;
  }

  .btn-secondary {
    background-color: rgba(255, 255, 255, 0.05);
    color: var(--text-primary);
    border: 1px solid var(--border-color);
  }

  @media (prefers-color-scheme: light) {
    .btn-secondary {
      background-color: #ffffff;
    }
  }

  .btn-secondary:hover {
    background-color: rgba(255, 255, 255, 0.1);
  }

  @media (prefers-color-scheme: light) {
    .btn-secondary:hover {
      background-color: rgba(0, 0, 0, 0.04);
    }
  }

  /* Macro form & list table */
  .macro-form {
    display: flex;
    gap: 8px;
  }

  .macro-form input {
    padding: 8px 12px;
    border-radius: 6px;
    background-color: var(--bg-input);
    border: 1px solid var(--border-color);
    color: var(--text-primary);
    outline: none;
    font-size: 13px;
  }

  .macro-form input[type="text"]:first-child {
    width: 150px;
  }

  .macro-form input[type="text"]:nth-child(2) {
    flex-grow: 1;
  }

  .macro-search input {
    width: 100%;
    padding: 7px 12px;
    border-radius: 6px;
    background-color: var(--bg-input);
    border: 1px solid var(--border-color);
    color: var(--text-primary);
    outline: none;
    font-size: 13px;
    box-sizing: border-box;
  }

  .macro-list-container {
    max-height: 250px;
    overflow-y: auto;
    border: 1px solid var(--border-color);
    border-radius: 6px;
  }

  .macro-table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
  }

  .macro-table th,
  .macro-table td {
    padding: 8px 12px;
    text-align: left;
    border-bottom: 1px solid var(--border-color);
  }

  .macro-table th {
    background-color: rgba(0, 0, 0, 0.15);
    color: var(--text-secondary);
    font-weight: 600;
    position: sticky;
    top: 0;
  }

  @media (prefers-color-scheme: light) {
    .macro-table th {
      background-color: rgba(0, 0, 0, 0.03);
    }
  }

  .macro-table tr:last-child td {
    border-bottom: none;
  }

  .btn-delete {
    background: none;
    border: none;
    color: #ff453a;
    font-weight: 600;
    cursor: pointer;
  }

  .btn-delete:hover {
    text-decoration: underline;
  }

  .btn-delete:disabled {
    opacity: 0.3;
    pointer-events: none;
  }

  .error-text {
    color: #ff453a;
    font-size: 12.5px;
    margin: 8px 0 0 0;
  }

  /* Convert Tool text areas layout */
  .editors-layout {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 16px;
  }

  .editor-pane {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .editor-pane label {
    font-size: 12px;
    color: var(--text-secondary);
    font-weight: 600;
  }

  textarea {
    width: 100%;
    height: 140px;
    padding: 10px;
    background-color: var(--bg-input);
    color: var(--text-primary);
    border: 1px solid var(--border-color);
    border-radius: 8px;
    outline: none;
    font-size: 13.5px;
    resize: none;
    box-sizing: border-box;
    font-family: inherit;
  }

  .editor-actions {
    display: flex;
    gap: 10px;
  }

  /* Info / About panel styling */
  .info-card {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .info-header {
    display: flex;
    align-items: center;
    gap: 14px;
  }

  .info-header h3 {
    margin: 0;
    text-transform: none;
    font-size: 18px;
    color: var(--text-primary);
  }

  .info-header .version {
    font-size: 12.5px;
    color: var(--text-secondary);
    margin: 2px 0 0 0;
  }

  .app-icon {
    width: 44px;
    height: 44px;
    background-color: var(--color-accent);
    color: white;
    border-radius: 10px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 24px;
    font-weight: bold;
  }

  .desc {
    font-size: 13.5px;
    line-height: 1.5;
    color: var(--text-secondary);
  }

  .links-grid {
    display: flex;
    gap: 15px;
  }

  .link-item {
    color: var(--color-accent);
    text-decoration: none;
    font-size: 13px;
    font-weight: 500;
  }

  .link-item:hover {
    text-decoration: underline;
  }

  /* Accessibility onboarding styles */
  .welcome-screen {
    box-sizing: border-box;
    width: 100vw;
    height: 100vh;
    padding: 50px 40px 40px;
    background-color: var(--bg-app);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: space-between;
    position: relative;
    text-align: center;
  }

  .welcome-drag-bar {
    position: absolute;
    left: 0;
    top: 0;
    width: 100%;
    height: 50px;
    cursor: default;
  }

  .welcome-header {
    display: flex;
    flex-direction: column;
    align-items: center;
    margin-top: 10px;
  }

  .welcome-logo {
    width: 64px;
    height: 64px;
    font-size: 32px;
    font-weight: bold;
    background: linear-gradient(135deg, var(--color-accent), #0056b3);
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 14px;
    box-shadow: 0 4px 12px rgba(0, 110, 255, 0.3);
  }

  .welcome-header h1 {
    font-size: 24px;
    font-weight: bold;
    color: var(--text-primary);
    margin: 16px 0 8px;
  }

  .welcome-desc {
    font-size: 13.5px;
    line-height: 1.5;
    color: var(--text-secondary);
    max-width: 500px;
    margin: 0;
  }

  .welcome-desc strong {
    color: var(--text-primary);
  }

  .welcome-steps-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 16px;
    width: 100%;
    max-width: 720px;
    margin: 20px 0;
  }

  .step-card {
    background-color: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 12px;
    padding: 20px 16px;
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  }

  @media (prefers-color-scheme: light) {
    .step-card {
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.03);
    }
  }

  .step-num {
    width: 28px;
    height: 28px;
    border-radius: 50%;
    background-color: rgba(0, 110, 255, 0.1);
    color: var(--color-accent);
    font-weight: bold;
    font-size: 14px;
    display: flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 12px;
  }

  .step-card h4 {
    margin: 0 0 6px;
    font-size: 14px;
    font-weight: bold;
    color: var(--text-primary);
  }

  .step-card p {
    margin: 0;
    font-size: 12px;
    line-height: 1.45;
    color: var(--text-secondary);
  }

  .welcome-footer {
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
  }

  .welcome-actions-row {
    display: flex;
    gap: 12px;
    width: 100%;
    max-width: 440px;
  }

  .welcome-actions-row .btn {
    flex: 1;
    padding: 10px 20px;
    font-size: 13.5px;
    border-radius: 8px;
  }

  .welcome-footer-note {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    color: var(--text-secondary);
    margin: 0;
  }

  .pulse-dot {
    width: 6px;
    height: 6px;
    background-color: var(--color-success);
    border-radius: 50%;
    display: inline-block;
    animation: pulse-dot-anim 1.5s infinite;
  }

  @keyframes pulse-dot-anim {
    0% {
      transform: scale(0.95);
      box-shadow: 0 0 0 0px rgba(48, 209, 88, 0.7);
    }
    70% {
      transform: scale(1);
      box-shadow: 0 0 0 5px rgba(48, 209, 88, 0);
    }
    100% {
      transform: scale(0.95);
      box-shadow: 0 0 0 0px rgba(48, 209, 88, 0);
    }
  }

  /* Utility classes */
  .mt-5 { margin-top: 5px; }
  .mt-10 { margin-top: 10px; }
  .mt-15 { margin-top: 15px; }
  .mt-20 { margin-top: 20px; }
  .mb-15 { margin-bottom: 15px; }
  .pt-5 { padding-top: 5px; }
  .pt-15 { padding-top: 15px; }
  .font-bold { font-weight: bold; }
  .font-mono { font-family: monospace; }
  .w-full { width: 100%; }

  .pulse {
    animation: pulse-animation 2s infinite;
  }

  @keyframes pulse-animation {
    0% {
      box-shadow: 0 0 0 0px rgba(255, 59, 48, 0.7);
    }
    100% {
      box-shadow: 0 0 0 8px rgba(255, 59, 48, 0);
    }
  }

  /* Dict Editor styling */
  .dict-editor-container {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-top: 10px;
    padding: 12px;
    background-color: rgba(255, 255, 255, 0.02);
    border: 1px dashed var(--border-color);
    border-radius: 8px;
  }

  @media (prefers-color-scheme: light) {
    .dict-editor-container {
      background-color: rgba(0, 0, 0, 0.01);
    }
  }

  .dict-editor-header {
    font-size: 12.5px;
    color: var(--text-secondary);
    font-weight: 500;
  }

  .dict-textarea {
    width: 100%;
    height: 120px;
    padding: 8px;
    background-color: var(--bg-input);
    color: var(--text-primary);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    outline: none;
    font-size: 13px;
    font-family: var(--font-mono, monospace);
    resize: vertical;
    box-sizing: border-box;
  }

  .dict-editor-actions {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .save-status {
    font-size: 12px;
    font-weight: 500;
    transition: opacity 0.3s ease;
  }

  .save-status.success {
    color: var(--color-success);
  }
</style>
