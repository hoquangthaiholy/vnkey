<script lang="ts">
  import { onMount } from "svelte";
  import { slide, fade, fly, scale } from "svelte/transition";
  import { flip } from "svelte/animate";
  import { quintOut } from "svelte/easing";
  import { invoke } from "@tauri-apps/api/core";
  import { listen } from "@tauri-apps/api/event";
  import { open } from "@tauri-apps/plugin-dialog";
  import { getVersion } from "@tauri-apps/api/app";
  import { check } from "@tauri-apps/plugin-updater";
  import { relaunch } from "@tauri-apps/plugin-process";
  import { Terminal, Copyright } from '@lucide/svelte';
  import VietnamFlag from './VietnamFlag.svelte';
  import USFlag from './USFlag.svelte';
  import ProgIcon from './ProgIcon.svelte';
  import { tooltip } from "$lib/tooltip";

  interface Settings {
    language: number;
    input_type: number;
    free_mark: number;
    code_table: number;
    switch_key_status: number;
    check_spelling: number;
    use_modern_orthography: number;
    quick_telex: number;
    use_english_dictionary: number;
    check_programming_keywords: number;
    fsm_priority_order: number[];
    fix_recommend_browser: number;
    fix_spotlight: number;
    use_macro: number;
    use_macro_in_english_mode: number;
    auto_caps_macro: number;
    use_smart_switch_key: number;
    upper_case_first_char: number;
    allow_consonant_zfwj: number;
    quick_start_consonant: number;
    quick_end_consonant: number;
    remember_code: number;
    send_key_step_by_step: number;
    fix_chromium_browser: number;
    perform_layout_compat: number;
    gray_icon: number;
    show_input_type_on_tray: number;
    convert_tool_dont_alert: number;
    convert_tool_to_all_caps: number;
    convert_tool_to_all_non_caps: number;
    convert_tool_to_caps_first_letter: number;
    convert_tool_to_caps_each_word: number;
    convert_tool_remove_mark: number;
    convert_tool_from_code: number;
    convert_tool_to_code: number;
    convert_tool_hotkey: number;
    clipboard_enabled: number;
    clipboard_pin_on_top: number;
    clipboard_auto_hide: number;
    clipboard_max_items: number;
    clipboard_hotkey: number;
    telex_w_as_u: number;
    telex_bracket_as_o: number;
    autostart: number;
    open_panel_on_start: number;
    panel_hotkey: number;
    late_accent_transformation: number;
    all_caps_auto_escape: number;
    use_paste_workaround: number;
    use_hud: number;
    smart_punct_check: number;
    use_perceptron_context: number;
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
    use_english_dictionary: 1,
    check_programming_keywords: 1,
    fsm_priority_order: [2, 0, 1],
    fix_recommend_browser: 1,
    fix_spotlight: 1,
    use_macro: 1,
    use_macro_in_english_mode: 0,
    auto_caps_macro: 1,
    use_smart_switch_key: 1,
    upper_case_first_char: 1,
    allow_consonant_zfwj: 1,
    quick_start_consonant: 0,
    quick_end_consonant: 0,
    remember_code: 1,
    send_key_step_by_step: 0,
    fix_chromium_browser: 0,
    perform_layout_compat: 0,
    gray_icon: 1,
    show_input_type_on_tray: 1,
    convert_tool_dont_alert: 0,
    convert_tool_to_all_caps: 0,
    convert_tool_to_all_non_caps: 0,
    convert_tool_to_caps_first_letter: 0,
    convert_tool_to_caps_each_word: 0,
    convert_tool_remove_mark: 0,
    convert_tool_from_code: 0,
    convert_tool_to_code: 0,
    convert_tool_hotkey: 0xFE0000FE,
    clipboard_enabled: 0,
    clipboard_pin_on_top: 1,
    clipboard_auto_hide: 1,
    clipboard_max_items: 10,
    clipboard_hotkey: 0x56000C09, // Command + Shift + V
    telex_w_as_u: 0,
    telex_bracket_as_o: 0,
    autostart: 1,
    open_panel_on_start: 1,
    panel_hotkey: 0x50000C23,
    late_accent_transformation: 0,
    all_caps_auto_escape: 1,
    use_paste_workaround: 1,
    use_hud: 1,
    smart_punct_check: 1,
    use_perceptron_context: 1,
  });

  let activeTab = $state(0);
  let isSaving = $state(false);
  let hasAccessibility = $state(true);
  let showResetModal = $state(false);
  let isResetting = $state(false);
  let showMacroModal = $state(false);

  // Update online state
  let appVersion = $state("1.0.0");
  let updateStatus = $state<"idle" | "checking" | "upToDate" | "available" | "error">("idle");
  let updateInfo = $state<{ version: string; releaseNotes: string; url: string; date: string } | null>(null);
  let showUpdateModal = $state(false);

  // Macros state
  let macrosList = $state<{ shortcut: string; content: string }[]>([]);
  let selectedMacroShortcut = $state<string | null>(null);
  let selectedMacro = $derived(macrosList.find(m => m.shortcut === selectedMacroShortcut));
  let searchQuery = $state("");
  let showViDictTable = $state(false);
  let showEnDictTable = $state(false);
  let showProgDictTable = $state(false);

  function parseVersion(v: string): number[] {
    return v.replace(/^v/, "").split(".").map(x => parseInt(x, 10) || 0);
  }

  function isNewerVersion(current: string, latest: string): boolean {
    const curParts = parseVersion(current);
    const latParts = parseVersion(latest);
    for (let i = 0; i < Math.max(curParts.length, latParts.length); i++) {
      const cur = curParts[i] || 0;
      const lat = latParts[i] || 0;
      if (lat > cur) return true;
      if (cur > lat) return false;
    }
    return false;
  }

  let updateProgress = $state<string>("");
  let isDownloading = $state<boolean>(false);
  let activeUpdate = $state<any>(null);

  async function checkUpdates(silent = false) {
    if (updateStatus === "checking") return;
    updateStatus = "checking";
    try {
      // 1. Try native Tauri updater first
      try {
        const update = await check();
        if (update) {
          activeUpdate = update;
          updateInfo = {
            version: update.version,
            releaseNotes: update.body || "Không có mô tả chi tiết.",
            url: "",
            date: update.date ? new Date(update.date).toLocaleDateString("vi-VN") : ""
          };
          updateStatus = "available";
          showUpdateModal = true;
          return;
        }
      } catch (updaterErr) {
        console.warn("Native updater check failed, falling back to GitHub API:", updaterErr);
      }

      // 2. Fallback to direct GitHub API check (useful if latest.json is missing or key not configured yet)
      const response = await fetch("https://api.github.com/repos/hoquangthaiholy/vnkey/releases/latest");
      if (!response.ok) {
        throw new Error("Không thể kết nối đến GitHub API");
      }
      const data = await response.json();
      const latestTag = data.tag_name;
      const releaseNotes = data.body || "Không có mô tả chi tiết.";
      const publishedAt = data.published_at ? new Date(data.published_at).toLocaleDateString("vi-VN") : "";
      
      let downloadUrl = data.html_url;
      if (data.assets && Array.isArray(data.assets)) {
        const asset = data.assets.find((a: any) => a.name.endsWith(".dmg") || a.name.endsWith(".tar.gz") || a.name.endsWith(".zip"));
        if (asset) {
          downloadUrl = asset.browser_download_url;
        }
      }

      if (isNewerVersion(appVersion, latestTag)) {
        activeUpdate = null;
        updateInfo = {
          version: latestTag,
          releaseNotes: releaseNotes,
          url: downloadUrl,
          date: publishedAt
        };
        updateStatus = "available";
        showUpdateModal = true;
      } else {
        updateStatus = "upToDate";
        if (!silent) {
          alert("Ứng dụng đang ở phiên bản mới nhất!");
        }
      }
    } catch (error) {
      console.error("Lỗi khi kiểm tra cập nhật:", error);
      updateStatus = "error";
      if (!silent) {
        alert("Có lỗi xảy ra khi kiểm tra cập nhật. Vui lòng thử lại sau.");
      }
    } finally {
      if (updateStatus !== "available") {
        updateStatus = "idle";
      }
    }
  }

  async function downloadAndInstallUpdate() {
    if (!activeUpdate) {
      // Fallback: Open release URL or DMG download in browser
      if (updateInfo && updateInfo.url) {
        showUpdateModal = false;
        await invoke("plugin:opener|open_url", { url: updateInfo.url });
      }
      return;
    }
    
    isDownloading = true;
    updateProgress = "0%";
    try {
      let downloaded = 0;
      let contentLength = 0;
      await activeUpdate.downloadAndInstall((event: any) => {
        switch (event.event) {
          case 'Started':
            contentLength = event.data.contentLength || 0;
            updateProgress = "Đang khởi động...";
            break;
          case 'Progress':
            downloaded += event.data.chunkLength;
            if (contentLength > 0) {
              const percentage = Math.round((downloaded / contentLength) * 100);
              updateProgress = `Đang tải: ${percentage}%`;
            } else {
              updateProgress = "Đang tải...";
            }
            break;
          case 'Finished':
            updateProgress = "Đang giải nén...";
            break;
        }
      });
      updateProgress = "Đang khởi động lại...";
      await relaunch();
    } catch (error) {
      console.error("Lỗi tải/cài đặt cập nhật:", error);
      alert("Lỗi tải/cài đặt cập nhật: " + error);
      isDownloading = false;
    }
  }

  // English Dictionary state
  let customEnglishWords = $state<string[]>([]);
  let dictionarySearch = $state("");
  let newEnglishWord = $state("");
  let dictionaryError = $state("");
  let savingDict = $state(false);
  let saveDictSuccess = $state(false);
  let filteredEnglishWords = $derived(
    customEnglishWords
      .filter((word) => word.includes(dictionarySearch.trim().toLowerCase()))
      .map(word => ({ word }))
  );
  let newShortcut = $state("");
  let newContent = $state("");
  let macroError = $state("");

  // Vietnamese Dictionary state
  let customVietnameseWords = $state<string[]>([]);
  let viDictSearch = $state("");
  let newViWord = $state("");
  let viDictError = $state("");
  let savingViDict = $state(false);
  let saveViDictSuccess = $state(false);
  let filteredVietnameseWords = $derived(
    customVietnameseWords
      .filter((word) => word.includes(viDictSearch.trim().toLowerCase()))
      .map(word => ({ word }))
  );

  // Programming Keywords state
  let customProgrammingKeywords = $state<string[]>([]);
  let keywordSearch = $state("");
  let newKeyword = $state("");
  let keywordError = $state("");
  let savingKeywords = $state(false);
  let saveKeywordsSuccess = $state(false);
  let filteredProgrammingKeywords = $derived(
    customProgrammingKeywords
      .filter((kw) => kw.toLowerCase().includes(keywordSearch.trim().toLowerCase()))
      .map(kw => ({ kw }))
  );

  // FSM Priority drag-and-drop — vertical-only, bounded within container
  const FSM_DEFS = [
    { id: 0, icon: VietnamFlag, name: 'Tiếng Việt',  desc: 'Kiểm tra âm tiết tiếng Việt' },
    { id: 1, icon: USFlag, name: 'Tiếng Anh',   desc: 'Luật cấu thành từ + từ điển tùy chỉnh' },
    { id: 2, icon: ProgIcon,  name: 'Lập trình',   desc: 'Keyword, camelCase, snake_case, ALL_CAPS' },
  ];
  let fsmDragIndex    = $state<number | null>(null);
  let fsmDragOverIndex = $state<number | null>(null);
  let fsmIsDragging   = $state(false);
  let fsmListEl       = $state<HTMLElement | null>(null);

  function fsmOrderedItems() {
    return settings.fsm_priority_order.map(id => FSM_DEFS.find(d => d.id === id)!);
  }

  // Hit-test: given clientY, return which row index (0..n-1) the pointer is over,
  // or null if outside the container bounds.
  function fsmSlotAtY(clientY: number): number | null {
    if (!fsmListEl) return null;
    const rect = fsmListEl.getBoundingClientRect();
    if (clientY < rect.top || clientY > rect.bottom) return null; // out of bounds
    
    // Use math based on container height rather than child bounding boxes
    // to avoid jitter when elements are animating.
    const itemCount = settings.fsm_priority_order.length;
    if (itemCount === 0) return null;
    const itemHeight = rect.height / itemCount;
    const relativeY = clientY - rect.top;
    const slot = Math.floor(relativeY / itemHeight);
    return Math.max(0, Math.min(itemCount - 1, slot));
  }

  function onFsmContainerPointerDown(e: PointerEvent) {
    // Find which row was clicked by hit-testing Y
    const slot = fsmSlotAtY(e.clientY);
    if (slot === null) return;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    fsmDragIndex  = slot;
    fsmDragOverIndex = slot;
    fsmIsDragging = true;
    e.preventDefault();
  }

  function onFsmContainerPointerMove(e: PointerEvent) {
    if (!fsmIsDragging || fsmDragIndex === null) return;
    const slot = fsmSlotAtY(e.clientY);
    if (slot !== null && slot !== fsmDragIndex) {
      // Swap immediately for real-time animation
      const newOrder = [...settings.fsm_priority_order];
      const [moved] = newOrder.splice(fsmDragIndex, 1);
      newOrder.splice(slot, 0, moved);
      settings.fsm_priority_order = newOrder;
      
      fsmDragIndex = slot;
      fsmDragOverIndex = slot;
    }
  }

  function onFsmContainerPointerUp(_e: PointerEvent) {
    if (fsmIsDragging) {
      saveSettings(); // Commit the new order to backend
    }
    fsmDragIndex    = null;
    fsmDragOverIndex = null;
    fsmIsDragging   = false;
  }

  // Convert Tool state
  let sourceText = $state("");
  let resultText = $state("");
  let convertError = $state("");
  let converting = $state(false);

  // Hotkey states
  let isRecordingSwitchKey = $state(false);
  let isRecordingConvertHotkey = $state(false);
  let isRecordingClipboardHotkey = $state(false);
  let isRecordingPanelHotkey = $state(false);

  // App-specific settings state
  let appConfigs = $state<Record<string, any>>({});
  let appConfigError = $state("");
  let newAppName = $state("");
  let selectedApp = $state("");
  let appIcons = $state<Record<string, string>>({});

  $effect(() => {
    if (appConfigs && Object.keys(appConfigs).length > 0) {
      if (!selectedApp || !appConfigs[selectedApp]) {
        selectedApp = Object.keys(appConfigs)[0];
      }
    }
  });

  $effect(() => {
    if (activeTab === 6) {
      loadAppIcons();
    }
  });

  async function loadAppIcons() {
    for (const bundleId of Object.keys(appConfigs)) {
      if (!appIcons[bundleId]) {
        try {
          const jsonStr: string | null = await invoke("get_application_info_by_bundle_id", { bundleId });
          if (jsonStr) {
            const info = JSON.parse(jsonStr);
            if (info && info.icon) {
              appIcons[bundleId] = info.icon;
            }
          }
        } catch (e) {
          console.error(`Failed to load icon for ${bundleId}`, e);
        }
      }
    }
  }

  // Cloud Sync state
  let cloudAccountId = $state("");
  let cloudAccessKey = $state("");
  let cloudSecretKey = $state("");
  let cloudBucketName = $state("");
  let isCloudSyncing = $state(false);
  let cloudSyncMessage = $state("");
  let cloudSyncError = $state(false);
  let syncMethod = $state("r2");
  let gdriveConnected = $state(false);

  // Sync Options
  let syncSettings = $state(true);
  let syncVietnameseDict = $state(true);
  let syncEnglishDict = $state(true);
  let syncProgrammingKeywords = $state(true);
  let syncMacros = $state(true);
  let syncClipboard = $state(false);
  let syncAppConfigs = $state(true);

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
  let clipboardHotkeyInfo = $derived(unpackHotkey(settings.clipboard_hotkey));
  let panelHotkeyInfo = $derived(unpackHotkey(settings.panel_hotkey));

  function formatHotkeyString(info: ReturnType<typeof unpackHotkey>) {
    let parts = [];
    const icon = (c: string) => `<span class="hotkey-icon">${c}</span>`;
    
    if (info.ctrl) parts.push(`${icon("⌃")} Control`);
    if (info.option) parts.push(`${icon("⌥")} Option`);
    if (info.command) parts.push(`${icon("⌘")} Command`);
    if (info.shift) parts.push(`${icon("⇧")} Shift`);
    
    if (info.keyCode === 0xfe) {
      if (parts.length === 0) return "Chưa thiết lập";
    } else if (info.keyCode === 49) {
      parts.push(`${icon("␣")} Space`);
    } else if (info.charStr) {
      const safeChar = info.charStr.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').toUpperCase();
      parts.push(`<span class="hotkey-text">${safeChar}</span>`);
    } else {
      parts.push(`<span class="hotkey-text">Key ${info.keyCode}</span>`);
    }
    return parts.join('<span class="hotkey-plus"> + </span>');
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
      const dictionary = await invoke<{ custom_words: string[] }>("get_english_dictionary");
      customEnglishWords = dictionary.custom_words;
    } catch (e) {
      console.error("Failed to load custom English words:", e);
    }
  }

  async function loadCustomProgrammingKeywords() {
    try {
      const dict = await invoke<{ custom_keywords: string[] }>("get_programming_keywords");
      customProgrammingKeywords = dict.custom_keywords;
    } catch (e) {
      console.error("Failed to load programming keywords:", e);
    }
  }

  async function saveCustomEnglishWords() {
    savingDict = true;
    saveDictSuccess = false;
    try {
      await invoke("save_custom_english_words", { words: customEnglishWords.join("\n") });
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

  async function loadCustomVietnameseWords() {
    try {
      const dictionary = await invoke<{ custom_words: string[] }>("get_vietnamese_dictionary");
      customVietnameseWords = dictionary.custom_words;
    } catch (e) {
      console.error("Failed to load custom Vietnamese words:", e);
    }
  }

  async function saveCustomVietnameseWords() {
    savingViDict = true;
    saveViDictSuccess = false;
    try {
      await invoke("save_custom_vietnamese_words", { words: customVietnameseWords.join("\n") });
      saveViDictSuccess = true;
      setTimeout(() => {
        saveViDictSuccess = false;
      }, 3000);
    } catch (e) {
      console.error("Failed to save custom Vietnamese words:", e);
    } finally {
      savingViDict = false;
    }
  }

  async function addVietnameseWord() {
    viDictError = "";
    const word = newViWord.trim().toLowerCase();
    if (word.length === 0) {
      return;
    }
    if (customVietnameseWords.includes(word)) {
      viDictError = "Từ này đã có trong từ điển.";
      return;
    }
    customVietnameseWords = [...customVietnameseWords, word].sort();
    newViWord = "";
    await saveCustomVietnameseWords();
  }

  async function deleteVietnameseWord(word: string) {
    customVietnameseWords = customVietnameseWords.filter((item) => item !== word);
    await saveCustomVietnameseWords();
  }

  async function addEnglishWord() {
    dictionaryError = "";
    const word = newEnglishWord.trim().toLowerCase();
    if (!/^[a-z]+$/.test(word)) {
      dictionaryError = "Chỉ nhập một từ gồm các chữ cái tiếng Anh a-z.";
      return;
    }
    if (customEnglishWords.includes(word)) {
      dictionaryError = "Từ này đã có trong từ điển.";
      return;
    }
    customEnglishWords = [...customEnglishWords, word].sort();
    newEnglishWord = "";
    await saveCustomEnglishWords();
  }

  async function deleteEnglishWord(word: string) {
    customEnglishWords = customEnglishWords.filter((item) => item !== word);
    await saveCustomEnglishWords();
  }



  async function saveCustomProgrammingKeywords() {
    savingKeywords = true;
    saveKeywordsSuccess = false;
    try {
      await invoke("save_custom_programming_keywords", { keywords: customProgrammingKeywords.join("\n") });
      saveKeywordsSuccess = true;
      setTimeout(() => { saveKeywordsSuccess = false; }, 3000);
    } catch (e) {
      console.error("Failed to save programming keywords:", e);
    } finally {
      savingKeywords = false;
    }
  }

  async function addProgrammingKeyword() {
    keywordError = "";
    const kw = newKeyword.trim();
    if (!kw) {
      keywordError = "Từ khóa không được để trống.";
      return;
    }
    if (customProgrammingKeywords.includes(kw)) {
      keywordError = "Từ khóa này đã có trong danh sách.";
      return;
    }
    customProgrammingKeywords = [...customProgrammingKeywords, kw].sort();
    newKeyword = "";
    await saveCustomProgrammingKeywords();
  }

  async function deleteProgrammingKeyword(kw: string) {
    customProgrammingKeywords = customProgrammingKeywords.filter((item) => item !== kw);
    await saveCustomProgrammingKeywords();
  }

  async function loadAppConfigs() {
    try {
      appConfigs = await invoke<Record<string, any>>("get_app_configs");
      if (selectedApp && !appConfigs[selectedApp]) {
        selectedApp = "";
      }
    } catch (e) {
      console.error("Failed to load app configs:", e);
    }
  }

  let showAppSelectorModal = $state(false);
  let isLoadingApps = $state(false);
  let runningAppsList = $state<{bundle_id: string, name: string, icon: string}[]>([]);

  async function openAppSelector() {
    showAppSelectorModal = true;
    isLoadingApps = true;
    try {
      let jsonStr: string | null = await invoke("get_running_applications");
      if (jsonStr) {
        runningAppsList = JSON.parse(jsonStr);
      }
    } catch (e) {
      console.error(e);
    } finally {
      isLoadingApps = false;
    }
  }

  async function browseAppFromFolder() {
    try {
      const selectedPath = await open({
        directory: false,
        multiple: false,
        filters: [{ name: 'Mac App', extensions: ['app'] }]
      });
      if (selectedPath && typeof selectedPath === 'string') {
        let jsonStr: string | null = await invoke("get_application_info_by_path", { path: selectedPath });
        if (jsonStr) {
          let appInfo = JSON.parse(jsonStr);
          if (appInfo && appInfo.bundle_id && appInfo.name) {
            addAppConfig(appInfo.bundle_id, appInfo.name);
            showAppSelectorModal = false;
          }
        }
      }
    } catch (e) {
      console.error(e);
    }
  }

  function addAppConfigByApp(bundleId: string, name: string) {
    addAppConfig(bundleId, name);
    showAppSelectorModal = false;
  }

  async function addAppConfig(bundleId: string, name: string) {
    appConfigError = "";
    if (!bundleId) {
      appConfigError = "Mã ứng dụng (Bundle ID) không hợp lệ.";
      return;
    }
    if (appConfigs[bundleId]) {
      appConfigError = "Ứng dụng này đã được cấu hình.";
      return;
    }

    const defaultAppConfig = {
      language: settings.language,
      input_type: settings.input_type,
      free_mark: settings.free_mark,
      code_table: settings.code_table,
      check_spelling: 1,
      use_modern_orthography: settings.use_modern_orthography,
      quick_telex: settings.quick_telex,
      use_english_dictionary: 1,
      check_programming_keywords: 1,
      use_macro: settings.use_macro,
      use_macro_in_english_mode: settings.use_macro_in_english_mode,
      auto_caps_macro: settings.auto_caps_macro,
      upper_case_first_char: 1,
      allow_consonant_zfwj: settings.allow_consonant_zfwj,
      quick_start_consonant: settings.quick_start_consonant,
      quick_end_consonant: settings.quick_end_consonant,
      fsm_priority_order: [...settings.fsm_priority_order],
      name: name,
    };

    try {
      await invoke("save_app_config", { bundleId, config: defaultAppConfig });
      await loadAppConfigs();
      selectedApp = bundleId;
    } catch (e: any) {
      appConfigError = e.toString();
    }
  }

  async function updateAppConfigField(field: string, value: any) {
    if (!selectedApp || !appConfigs[selectedApp]) return;
    const config = { ...appConfigs[selectedApp], [field]: value };
    try {
      await invoke("save_app_config", { bundleId: selectedApp, config });
      appConfigs[selectedApp] = config;
    } catch (e) {
      console.error("Failed to update app config field:", e);
    }
  }

  let appFsmDragIndex = $state<number | null>(null);
  let appFsmDragOverIndex = $state<number | null>(null);
  let appFsmIsDragging = $state(false);
  let appFsmListEl = $state<HTMLElement | null>(null);

  function appFsmOrderedItems() {
    if (!selectedApp || !appConfigs[selectedApp]) return [];
    const order: number[] = appConfigs[selectedApp].fsm_priority_order || [2, 0, 1];
    return order
      .map((id: number) => FSM_DEFS.find((d) => d.id === id))
      .filter((d): d is Exclude<typeof d, undefined> => !!d);
  }

  function appFsmSlotAtY(clientY: number): number | null {
    if (!appFsmListEl) return null;
    const rect = appFsmListEl.getBoundingClientRect();
    const order = appConfigs[selectedApp]?.fsm_priority_order || [2, 0, 1];
    const itemCount = order.length;
    if (itemCount === 0) return null;
    const itemHeight = rect.height / itemCount;
    const relativeY = clientY - rect.top;
    const slot = Math.floor(relativeY / itemHeight);
    return Math.max(0, Math.min(itemCount - 1, slot));
  }

  function onAppFsmContainerPointerDown(e: PointerEvent) {
    const slot = appFsmSlotAtY(e.clientY);
    if (slot === null) return;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    appFsmDragIndex = slot;
    appFsmDragOverIndex = slot;
    appFsmIsDragging = true;
    e.preventDefault();
  }

  function onAppFsmContainerPointerMove(e: PointerEvent) {
    if (!appFsmIsDragging || appFsmDragIndex === null) return;
    const slot = appFsmSlotAtY(e.clientY);
    if (slot !== null && slot !== appFsmDragIndex) {
      const currentOrder = appConfigs[selectedApp]?.fsm_priority_order || [2, 0, 1];
      const newOrder = [...currentOrder];
      const [moved] = newOrder.splice(appFsmDragIndex, 1);
      newOrder.splice(slot, 0, moved);
      updateAppConfigField('fsm_priority_order', newOrder);
      appFsmDragIndex = slot;
      appFsmDragOverIndex = slot;
    }
  }

  function onAppFsmContainerPointerUp(_e: PointerEvent) {
    appFsmDragIndex = null;
    appFsmDragOverIndex = null;
    appFsmIsDragging = false;
  }

  async function deleteAppConfig(bundleId: string, name: string) {
    if (!confirm(`Bạn có chắc chắn muốn xóa cấu hình riêng cho ứng dụng "${name}"?`)) {
      return;
    }
    try {
      await invoke("remove_app_config", { bundleId });
      if (selectedApp === bundleId) {
        selectedApp = "";
      }
      await loadAppConfigs();
    } catch (e: any) {
      appConfigError = e.toString();
    }
  }

  function openAddMacro() {
    newShortcut = "";
    newContent = "";
    macroError = "";
    showMacroModal = true;
  }

  function openEditMacro() {
    if (selectedMacroShortcut) {
      const m = macrosList.find(x => x.shortcut === selectedMacroShortcut);
      if (m) {
        newShortcut = m.shortcut;
        newContent = m.content;
        macroError = "";
        showMacroModal = true;
      }
    }
  }

  async function addMacro() {
    macroError = "";
    const shortcutStr = newShortcut.trim();
    if (!shortcutStr || !newContent.trim()) {
      macroError = "Từ gõ tắt và nội dung không được để trống.";
      return;
    }
    try {
      macrosList = await invoke<typeof macrosList>("upsert_macro", {
        shortcut: shortcutStr,
        content: newContent.trim(),
      });
      selectedMacroShortcut = shortcutStr;
      newShortcut = "";
      newContent = "";
      showMacroModal = false;
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

  async function setRecordingClipboardHotkey(val: boolean) {
    isRecordingClipboardHotkey = val;
    try {
      await invoke("disable_hotkeys", { disable: val });
    } catch (e) {
      console.error("Failed to set disable_hotkeys:", e);
    }
  }

  async function setRecordingPanelHotkey(val: boolean) {
    isRecordingPanelHotkey = val;
    try {
      await invoke("disable_hotkeys", { disable: val });
    } catch (e) {
      console.error("Failed to set disable_hotkeys:", e);
    }
  }

  function handleHotkeyKeyDown(event: KeyboardEvent, type: 'switch' | 'convert' | 'clipboard' | 'panel') {
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
    } else if (type === 'convert') {
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
    } else if (type === 'clipboard') {
      settings.clipboard_hotkey = packHotkey({
        keyCode: macCode,
        ctrl,
        option,
        command,
        shift,
        beep: false,
        charStr: charStr
      });
      setRecordingClipboardHotkey(false);
      saveSettings();
    } else if (type === 'panel') {
      settings.panel_hotkey = packHotkey({
        keyCode: macCode,
        ctrl,
        option,
        command,
        shift,
        beep: false,
        charStr: charStr
      });
      setRecordingPanelHotkey(false);
      saveSettings();
    }
  }

  function autofocusAction(node: HTMLButtonElement) {
    node.focus();
    setTimeout(() => {
      node.focus();
    }, 10);
  }

  function toggleModifier(type: 'switch' | 'convert' | 'clipboard' | 'panel', modifier: 'ctrl' | 'option' | 'command' | 'shift' | 'beep') {
    if (type === 'switch') {
      const current = unpackHotkey(settings.switch_key_status);
      if (modifier === 'beep') {
        current.beep = !current.beep;
      } else {
        current[modifier] = !current[modifier];
      }
      settings.switch_key_status = packHotkey(current);
    } else if (type === 'convert') {
      const current = unpackHotkey(settings.convert_tool_hotkey);
      if (modifier === 'beep') {
        current.beep = !current.beep;
      } else {
        current[modifier] = !current[modifier];
      }
      settings.convert_tool_hotkey = packHotkey(current);
    } else if (type === 'clipboard') {
      const current = unpackHotkey(settings.clipboard_hotkey);
      if (modifier === 'beep') {
        current.beep = !current.beep;
      } else {
        current[modifier] = !current[modifier];
      }
      settings.clipboard_hotkey = packHotkey(current);
    } else if (type === 'panel') {
      const current = unpackHotkey(settings.panel_hotkey);
      if (modifier === 'beep') {
        current.beep = !current.beep;
      } else {
        current[modifier] = !current[modifier];
      }
      settings.panel_hotkey = packHotkey(current);
    }
    saveSettings();
  }

  function handleCheckboxChange(key: NumericSettingsKey, value: boolean) {
    (settings as Record<NumericSettingsKey, number>)[key] = value ? 1 : 0;
    if (value) {
      if (key === 'check_spelling') showViDictTable = true;
      if (key === 'use_english_dictionary') showEnDictTable = true;
      if (key === 'check_programming_keywords') showProgDictTable = true;
    }
    saveSettings();
  }

  function handleMergeFixChromeSpotlightChange(checked: boolean) {
    settings.fix_chromium_browser = checked ? 1 : 0;
    settings.fix_spotlight = checked ? 1 : 0;
    saveSettings();
  }

  function handleUsePasteWorkaroundChange(checked: boolean) {
    settings.use_paste_workaround = checked ? 1 : 0;
    if (checked) {
      settings.send_key_step_by_step = 0;
    }
    saveSettings();
  }

  function handleSendKeyStepByStepChange(checked: boolean) {
    settings.send_key_step_by_step = checked ? 1 : 0;
    if (checked) {
      settings.use_paste_workaround = 0;
    }
    saveSettings();
  }

  type NumericSettingsKey = { [K in keyof Settings]: Settings[K] extends number ? K : never }[keyof Settings];

  function handleSelectChange(key: NumericSettingsKey, value: number) {
    (settings as Record<NumericSettingsKey, number>)[key] = value;
    saveSettings();
  }

  onMount(() => {
    let pollingInterval: number | undefined;
    let stopListeningSettings: (() => void) | undefined;
    let stopListeningAccessibility: (() => void) | undefined;
    let stopListeningShowTab: (() => void) | undefined;
    let stopListeningEnglishDictReset: (() => void) | undefined;

    getVersion().then((ver) => {
      appVersion = ver;
      checkUpdates(true);
    }).catch((err) => {
      console.error("Lỗi lấy phiên bản ứng dụng:", err);
    });

    // Theme sync listener
    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    const updateTheme = (e: MediaQueryListEvent | MediaQueryList) => {
      if (e.matches) {
        document.documentElement.classList.add('dark');
        document.documentElement.classList.remove('light');
      } else {
        document.documentElement.classList.add('light');
        document.documentElement.classList.remove('dark');
      }
    };
    updateTheme(mediaQuery);
    mediaQuery.addEventListener('change', updateTheme);

    checkAccessibility().then((granted) => {
      if (granted) {
        loadSettings();
        loadMacros();
        loadCustomEnglishWords();
        loadCustomVietnameseWords();
        loadCustomProgrammingKeywords();
        loadAppConfigs();
      } else {
        pollingInterval = window.setInterval(async () => {
          const ok = await checkAccessibility();
          if (ok) {
            loadSettings();
            loadMacros();
            loadCustomEnglishWords();
            loadCustomVietnameseWords();
            loadCustomProgrammingKeywords();
            loadAppConfigs();
            if (pollingInterval) {
              clearInterval(pollingInterval);
              pollingInterval = undefined;
            }
          }
        }, 1000);
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
      loadCloudSettings();
      loadMacros();
      loadAppConfigs();
      if (pollingInterval) {
        clearInterval(pollingInterval);
        pollingInterval = undefined;
      }
    }).then((unsub) => {
      stopListeningAccessibility = unsub;
    });

    let stopListeningWebAuth: (() => void) | undefined;

    listen<void>("gdrive_web_auth_success", () => {
      gdriveConnected = true;
      cloudSyncMessage = "Đã kết nối Google Drive qua Web App!";
      cloudSyncError = false;
    }).then((unsub) => {
      stopListeningWebAuth = unsub;
    });

    let stopListeningCheckUpdates: (() => void) | undefined;

    listen<void>("check-updates-manually", () => {
      activeTab = 4;
      checkUpdates(false);
    }).then((unsub) => {
      stopListeningCheckUpdates = unsub;
    });


    listen<void>("english-dict-reset", () => {
      loadCustomEnglishWords();
    }).then((unsub) => {
      stopListeningEnglishDictReset = unsub;
    });

    return () => {
      if (stopListeningSettings) stopListeningSettings();
      if (stopListeningAccessibility) stopListeningAccessibility();
      if (stopListeningShowTab) stopListeningShowTab();
      if (stopListeningEnglishDictReset) stopListeningEnglishDictReset();
      if (stopListeningWebAuth) stopListeningWebAuth();
      if (stopListeningCheckUpdates) stopListeningCheckUpdates();
      if (pollingInterval) clearInterval(pollingInterval);
      mediaQuery.removeEventListener('change', updateTheme);
    };
  });

  async function loadCloudSettings() {
    try {
      cloudAccountId = await invoke<string>("get_kv", { key: "cloudAccountId" }) || "";
      cloudAccessKey = await invoke<string>("get_kv", { key: "cloudAccessKey" }) || "";
      cloudSecretKey = await invoke<string>("get_kv", { key: "cloudSecretKey" }) || "";
      cloudBucketName = await invoke<string>("get_kv", { key: "cloudBucketName" }) || "";
      syncMethod = await invoke<string>("get_kv", { key: "syncMethod" }) || "r2";
      let gToken = await invoke<string>("get_kv", { key: "gdriveAccessToken" }) || "";
      gdriveConnected = gToken !== "";
      syncSettings = (await invoke<string>("get_kv", { key: "syncSettings" })) !== "0";
      syncVietnameseDict = (await invoke<string>("get_kv", { key: "syncVietnameseDict" })) !== "0";
      syncEnglishDict = (await invoke<string>("get_kv", { key: "syncEnglishDict" })) !== "0";
      syncProgrammingKeywords = (await invoke<string>("get_kv", { key: "syncProgrammingKeywords" })) !== "0";
      syncMacros = (await invoke<string>("get_kv", { key: "syncMacros" })) !== "0";
      syncClipboard = (await invoke<string>("get_kv", { key: "syncClipboard" })) === "1";
      syncAppConfigs = (await invoke<string>("get_kv", { key: "syncAppConfigs" })) !== "0";
    } catch (e) {
      console.error(e);
    }
  }

  async function saveCloudSettings() {
    try {
      await invoke("set_kv", { key: "cloudAccountId", value: cloudAccountId });
      await invoke("set_kv", { key: "cloudAccessKey", value: cloudAccessKey });
      await invoke("set_kv", { key: "cloudSecretKey", value: cloudSecretKey });
      await invoke("set_kv", { key: "cloudBucketName", value: cloudBucketName });
      await invoke("set_kv", { key: "syncMethod", value: syncMethod });
      await invoke("set_kv", { key: "syncSettings", value: syncSettings ? "1" : "0" });
      await invoke("set_kv", { key: "syncVietnameseDict", value: syncVietnameseDict ? "1" : "0" });
      await invoke("set_kv", { key: "syncEnglishDict", value: syncEnglishDict ? "1" : "0" });
      await invoke("set_kv", { key: "syncProgrammingKeywords", value: syncProgrammingKeywords ? "1" : "0" });
      await invoke("set_kv", { key: "syncMacros", value: syncMacros ? "1" : "0" });
      await invoke("set_kv", { key: "syncClipboard", value: syncClipboard ? "1" : "0" });
      await invoke("set_kv", { key: "syncAppConfigs", value: syncAppConfigs ? "1" : "0" });
    } catch (e) {
      console.error(e);
    }
  }

  async function syncToCloud() {
    if (!cloudAccountId || !cloudAccessKey || !cloudSecretKey || !cloudBucketName) {
      cloudSyncError = false;
      cloudSyncMessage = "";
      return;
    }
    isCloudSyncing = true;
    cloudSyncMessage = "Đang tải dữ liệu lên đám mây...";
    cloudSyncError = false;
    try {
      await saveCloudSettings();
      await invoke("sync_to_cloud", {
        accountId: cloudAccountId,
        accessKey: cloudAccessKey,
        secretKey: cloudSecretKey,
        bucketName: cloudBucketName
      });
      cloudSyncMessage = "Đồng bộ lên đám mây thành công!";
    } catch (e: any) {
      cloudSyncError = true;
      cloudSyncMessage = "Lỗi: " + e;
    } finally {
      isCloudSyncing = false;
    }
  }

  async function syncFromCloud() {
    if (!cloudAccountId || !cloudAccessKey || !cloudSecretKey || !cloudBucketName) {
      cloudSyncError = false;
      cloudSyncMessage = "";
      return;
    }
    isCloudSyncing = true;
    cloudSyncMessage = "Đang tải dữ liệu từ đám mây...";
    cloudSyncError = false;
    try {
      await saveCloudSettings();
      await invoke("sync_from_cloud", {
        accountId: cloudAccountId,
        accessKey: cloudAccessKey,
        secretKey: cloudSecretKey,
        bucketName: cloudBucketName
      });
      cloudSyncMessage = "Tải dữ liệu từ đám mây thành công!";
      loadMacros();
    } catch (e: any) {
      cloudSyncError = true;
      cloudSyncMessage = "Lỗi: " + e;
    } finally {
      isCloudSyncing = false;
    }
  }

  function generateRandomString(length: number) {
    const array = new Uint32Array(length);
    window.crypto.getRandomValues(array);
    return Array.from(array, dec => ('0' + dec.toString(16)).substring(-2)).join('');
  }

  async function sha256(plain: string) {
    const encoder = new TextEncoder();
    const data = encoder.encode(plain);
    return window.crypto.subtle.digest('SHA-256', data);
  }

  function base64urlencode(str: ArrayBuffer) {
    return btoa(String.fromCharCode.apply(null, new Uint8Array(str) as any))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  async function generateChallenge(verifier: string) {
    const hashed = await sha256(verifier);
    return base64urlencode(hashed);
  }

  async function startGdriveWebAuth() {
    isCloudSyncing = true;
    cloudSyncError = false;
    cloudSyncMessage = "Đang khởi tạo máy chủ xác thực cục bộ...";
    try {
      const clientId = await invoke("get_google_client_id") as string;
      if (!clientId) {
        throw new Error("Không tìm thấy Google Client ID.");
      }
      
      const codeVerifier = generateRandomString(64);
      const codeChallenge = await generateChallenge(codeVerifier);
      
      await invoke("start_local_auth_server", { codeVerifier });
      cloudSyncMessage = "Đang mở trình duyệt để liên kết...";
      
      const redirectUri = "http://127.0.0.1:12558/callback";
      const authUrl = 'https://accounts.google.com/o/oauth2/v2/auth?' + new URLSearchParams({
          client_id: clientId,
          redirect_uri: redirectUri,
          response_type: 'code',
          scope: 'openid email profile https://www.googleapis.com/auth/drive.file',
          code_challenge: codeChallenge,
          code_challenge_method: 'S256',
          access_type: 'offline',
          prompt: 'consent'
      }).toString();

      await invoke("plugin:opener|open_url", { url: authUrl });
    } catch (e: any) {
      cloudSyncError = true;
      cloudSyncMessage = "Lỗi khởi tạo Web Auth: " + e;
    } finally {
      isCloudSyncing = false;
    }
  }

  async function disconnectGdrive() {
    await invoke("set_kv", { key: "gdriveAccessToken", value: "" });
    await invoke("set_kv", { key: "gdriveRefreshToken", value: "" });
    await invoke("set_kv", { key: "googleClientId", value: "" });
    await invoke("set_kv", { key: "googleClientSecret", value: "" });
    gdriveConnected = false;
    cloudSyncMessage = "Đã ngắt kết nối Google Drive.";
    cloudSyncError = false;
  }



  async function syncToGdrive() {
    isCloudSyncing = true;
    cloudSyncMessage = "Đang tải dữ liệu lên Google Drive...";
    cloudSyncError = false;
    try {
      await saveCloudSettings();
      await invoke("sync_to_gdrive");
      cloudSyncMessage = "Đồng bộ lên Google Drive thành công!";
    } catch (e: any) {
      cloudSyncError = true;
      cloudSyncMessage = "Lỗi: " + e;
    } finally {
      isCloudSyncing = false;
    }
  }

  async function syncFromGdrive() {
    isCloudSyncing = true;
    cloudSyncMessage = "Đang tải dữ liệu từ Google Drive...";
    cloudSyncError = false;
    try {
      await saveCloudSettings();
      await invoke("sync_from_gdrive");
      cloudSyncMessage = "Tải dữ liệu từ Google Drive thành công!";
      loadMacros();
    } catch (e: any) {
      cloudSyncError = true;
      cloudSyncMessage = "Lỗi: " + e;
    } finally {
      isCloudSyncing = false;
    }
  }

</script>


  <div class="app-layout">
    <!-- Left Sidebar -->
    <aside class="sidebar" data-tauri-drag-region>
      <div class="sidebar-header" data-tauri-drag-region>
        <img src="/favicon.png" alt="VNKey" class="logo" />
        <div class="title-group">
          <span class="title">VNKey</span>
          <span class="subtitle">Bảng điều khiển</span>
        </div>
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
        <button class="nav-item" class:active={activeTab === 5} onclick={() => activeTab = 5}>
          <svg class="nav-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path><polyline points="14 2 14 8 20 8"></polyline><line x1="16" y1="13" x2="8" y2="13"></line><line x1="16" y1="17" x2="8" y2="17"></line><polyline points="10 9 9 9 8 9"></polyline></svg>
          Bảng ghi nhớ
        </button>
        <button class="nav-item" class:active={activeTab === 6} onclick={() => activeTab = 6}>
          <svg class="nav-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"></rect><line x1="8" y1="21" x2="16" y2="21"></line><line x1="12" y1="17" x2="12" y2="21"></line></svg>
          Ứng dụng
        </button>
        <button class="nav-item" class:active={activeTab === 7} onclick={() => activeTab = 7}>
          <svg class="nav-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="23 4 23 10 17 10"></polyline>
            <polyline points="1 20 1 14 7 14"></polyline>
            <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"></path>
          </svg>
          Đồng bộ
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
        <section class="panel" in:fly={{ y: 8, duration: 200, delay: 150 }} out:fade={{ duration: 150 }}>
          <div class="panel-header">
            <h2>Điều khiển & Gõ phím</h2>
            <p class="panel-subtitle">Thiết lập bộ gõ, bảng mã và các quy chuẩn chính tả tiếng Việt.</p>
          </div>

          <div class="grid-2col">
            <div class="card">
              <h3>Cơ bản</h3>
              <label class="form-group-inline">
                <span>Kiểu gõ</span>
                <select value={settings.input_type} onchange={(e) => handleSelectChange('input_type', parseInt((e.target as HTMLSelectElement).value))}>
                  <option value={0}>Telex</option>
                  <option value={1}>VNI</option>
                </select>
              </label>

              {#if settings.input_type === 0}
                <div class="sub-toggles-grid" transition:slide={{ duration: 250 }}>
                  <label class="toggle-container">
                    <span class="toggle-text">Gõ <kbd>w</kbd> thành <kbd>ư</kbd></span>
                    <div class="switch">
                      <input
                        type="checkbox"
                        checked={settings.telex_w_as_u === 1}
                        onchange={(e) => handleCheckboxChange('telex_w_as_u', (e.target as HTMLInputElement).checked)}
                      />
                      <span class="slider"></span>
                    </div>
                  </label>
                  <label class="toggle-container">
                    <span class="toggle-text">Gõ <kbd>[</kbd> thành <kbd>ơ</kbd></span>
                    <div class="switch">
                      <input
                        type="checkbox"
                        checked={settings.telex_bracket_as_o === 1}
                        onchange={(e) => handleCheckboxChange('telex_bracket_as_o', (e.target as HTMLInputElement).checked)}
                      />
                      <span class="slider"></span>
                    </div>
                  </label>
                </div>
              {/if}

              <label class="form-group-inline mt-15">
                <span>Bảng mã</span>
                <select value={settings.code_table} onchange={(e) => handleSelectChange('code_table', parseInt((e.target as HTMLSelectElement).value))}>
                  <option value={0}>Unicode dựng sẵn</option>
                  <option value={1}>TCVN3 (ABC)</option>
                  <option value={2}>VNI Windows</option>
                  <option value={3}>Unicode tổ hợp</option>
                  <option value={4}>Vietnamese Locale CP1258</option>
                </select>
              </label>
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
                      {@html formatHotkeyString(switchKeyInfo)}
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
                <span class="toggle-text">Viết hoa chữ cái đầu tiên của câu</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.upper_case_first_char === 1} onchange={(e) => handleCheckboxChange('upper_case_first_char', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Chỉ bỏ dấu khi kết thúc từ <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Chỉ bỏ dấu khi kết thúc từ:</strong><br/>Hoãn việc bỏ dấu tiếng Việt trong quá trình gõ thô. Khi bạn gõ xong từ và nhấn phím cách (Space) hoặc phím ngắt từ, bộ gõ mới tự động bỏ dấu toàn bộ từ cùng một lúc. Giúp tránh xung đột dấu khi gõ xen kẽ từ ngoại ngữ."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.late_accent_transformation === 1} onchange={(e) => handleCheckboxChange('late_accent_transformation', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Đặt dấu hiện đại <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Đặt dấu hiện đại:</strong><br/>Đặt dấu trên nguyên âm chính trong các cụm như <kbd>oà</kbd>, <kbd>uý</kbd> (thay vì kiểu cũ <kbd>òa</kbd>, <kbd>úy</kbd>). Áp dụng cho các cụm <kbd>oa</kbd>, <kbd>oe</kbd>, <kbd>uy</kbd>."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.use_modern_orthography === 1} onchange={(e) => handleCheckboxChange('use_modern_orthography', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Gõ nhanh phụ âm khi đúp từ <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Gõ nhanh phụ âm khi đúp từ:</strong><br/>Gõ đúp phụ âm để tạo nhanh:<br/>• <kbd>cc</kbd> → <b>ch</b> &nbsp;&nbsp; • <kbd>gg</kbd> → <b>gi</b><br/>• <kbd>kk</kbd> → <b>kh</b> &nbsp;&nbsp; • <kbd>nn</kbd> → <b>ng</b><br/>• <kbd>qq</kbd> → <b>qu</b> &nbsp;&nbsp; • <kbd>pp</kbd> → <b>ph</b><br/>• <kbd>tt</kbd> → <b>th</b><br/><i>Tự động khôi phục khi gõ từ tiếng Anh.</i>"}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.quick_telex === 1} onchange={(e) => handleCheckboxChange('quick_telex', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Gõ nhanh phụ âm đầu <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Gõ nhanh phụ âm đầu:</strong><br/>Dùng phím tắt đơn lẻ ở đầu từ:<br/>• <kbd>f</kbd> → <b>ph</b> (ví dụ: <kbd>fong</kbd> → <b>phong</b>)<br/>• <kbd>j</kbd> → <b>gi</b> (ví dụ: <kbd>ja</kbd> → <b>gia</b>)<br/>• <kbd>w</kbd> → <b>qu</b> (ví dụ: <kbd>wa</kbd> → <b>qua</b>)"}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.quick_start_consonant === 1} onchange={(e) => handleCheckboxChange('quick_start_consonant', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Gõ nhanh phụ âm cuối <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Gõ nhanh phụ âm cuối:</strong><br/>Dùng phím tắt đơn lẻ ở cuối từ:<br/>• <kbd>g</kbd> → <b>ng</b> (ví dụ: <kbd>lahg</kbd> → <b>làng</b>)<br/>• <kbd>h</kbd> → <b>nh</b> (ví dụ: <kbd>ah</kbd> → <b>anh</b>)<br/>• <kbd>k</kbd> → <b>ch</b> (ví dụ: <kbd>sak</kbd> → <b>sách</b>)"}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.quick_end_consonant === 1} onchange={(e) => handleCheckboxChange('quick_end_consonant', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>
            </div>
          </div>

          <!-- Card 1: Kiểm tra chính tả -->
          <div class="card mt-20">
            <h3>Kiểm tra chính tả</h3>

            <!-- SECTION 1: VIETNAMESE -->
            <div class="spell-section">
              <label class="toggle-container">
                <span class="toggle-text font-bold" style="font-size:14.5px; display: inline-flex; align-items: center; gap: 10px;">
                  <VietnamFlag size={20} />
                  Kiểm tra chính tả tiếng Việt <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Kiểm tra chính tả tiếng Việt:</strong><br/>Theo dõi cấu trúc âm tiết tiếng Việt chuẩn hóa để hạn chế các trường hợp tự động chuyển đổi sai dấu."}>?</span>
                </span>
                <div class="switch">
                  <input type="checkbox" checked={settings.check_spelling === 1} onchange={(e) => handleCheckboxChange('check_spelling', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              {#if settings.check_spelling === 1}
                <div class="spell-sub-section" transition:slide={{ duration: 200 }}>
                  <label class="toggle-container sub-toggle">
                    <span class="toggle-text">Sử dụng thêm bảng từ điển tiếng Việt cá nhân</span>
                    <div class="switch">
                      <input type="checkbox" checked={showViDictTable} onchange={(e) => showViDictTable = (e.target as HTMLInputElement).checked} />
                      <span class="slider"></span>
                    </div>
                  </label>

                  {#if showViDictTable}
                    <div class="dict-editor-container mt-10" transition:slide={{ duration: 250 }}>
                      <p class="dict-hint">Nhập các từ tiếng Việt viết tắt, đặc biệt hoặc từ ưu tiên muốn giữ nguyên dấu.</p>
                      <div class="dict-toolbar">
                        <input type="search" placeholder="Tìm trong từ điển..." bind:value={viDictSearch} aria-label="Tìm trong từ điển tiếng Việt" />
                        <div class="dict-add-row">
                          <input type="text" placeholder="Thêm từ mới (vd: nghành)" bind:value={newViWord} onkeydown={(event) => event.key === "Enter" && addVietnameseWord()} aria-label="Từ tiếng Việt mới" />
                          <button class="btn btn-primary" onclick={addVietnameseWord} disabled={savingViDict}>Thêm</button>
                        </div>
                      </div>
                      {#if viDictError}<p class="form-error">{viDictError}</p>{/if}
                      
                      <div class="dict-grid-container" aria-label="Danh sách từ tiếng Việt">
                        {#if filteredVietnameseWords.length === 0}
                          <div class="dict-empty">Không tìm thấy từ phù hợp.</div>
                        {:else}
                          <div class="dict-words-grid">
                            {#each filteredVietnameseWords as entry (entry.word)}
                              <div class="dict-word-badge">
                                <span class="font-mono word-text">{entry.word}</span>
                                <button class="btn-delete-x" onclick={() => deleteVietnameseWord(entry.word)} aria-label="Xóa">×</button>
                              </div>
                            {/each}
                          </div>
                        {/if}
                      </div>
                      <div class="dict-footer">
                        <span class="dict-count-muted">{customVietnameseWords.length} từ</span>
                        {#if saveViDictSuccess}<span class="save-status success">Đã đồng bộ từ điển.</span>{/if}
                      </div>
                    </div>
                  {/if}
                </div>
              {/if}
            </div>

            <div class="dict-section-divider"></div>

            <!-- SECTION 2: ENGLISH -->
            <div class="spell-section">
              <label class="toggle-container">
                <span class="toggle-text font-bold" style="font-size:14.5px; display: inline-flex; align-items: center; gap: 10px;">
                  <USFlag size={20} />
                  Kiểm tra chính tả tiếng Anh <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Kiểm tra từ tiếng Anh:</strong><br/>Dùng luật cấu thành từ tiếng Anh và từ điển tùy chỉnh để giữ nguyên các từ tiếng Anh dễ bị Telex biến đổi thành chữ tiếng Việt."}>?</span>
                </span>
                <div class="switch">
                  <input type="checkbox" checked={settings.use_english_dictionary === 1} onchange={(e) => handleCheckboxChange('use_english_dictionary', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              {#if settings.use_english_dictionary === 1}
                <div class="spell-sub-section" transition:slide={{ duration: 200 }}>
                  <label class="toggle-container sub-toggle">
                    <span class="toggle-text">Sử dụng thêm bảng từ điển tiếng Anh cá nhân</span>
                    <div class="switch">
                      <input type="checkbox" checked={showEnDictTable} onchange={(e) => showEnDictTable = (e.target as HTMLInputElement).checked} />
                      <span class="slider"></span>
                    </div>
                  </label>

                  {#if showEnDictTable}
                    <div class="dict-editor-container mt-10" transition:slide={{ duration: 250 }}>
                      <div class="dict-toolbar">
                        <input type="search" placeholder="Tìm trong từ điển..." bind:value={dictionarySearch} aria-label="Tìm trong từ điển tiếng Anh" />
                        <div class="dict-add-row">
                          <input type="text" placeholder="Thêm từ mới (a-z)" bind:value={newEnglishWord} onkeydown={(event) => event.key === "Enter" && addEnglishWord()} aria-label="Từ tiếng Anh mới" />
                          <button class="btn btn-primary" onclick={addEnglishWord} disabled={savingDict}>Thêm</button>
                        </div>
                      </div>
                      {#if dictionaryError}<p class="form-error">{dictionaryError}</p>{/if}
                      
                      <div class="dict-grid-container" aria-label="Danh sách từ tiếng Anh">
                        {#if filteredEnglishWords.length === 0}
                          <div class="dict-empty">Không tìm thấy từ phù hợp.</div>
                        {:else}
                          <div class="dict-words-grid">
                            {#each filteredEnglishWords as entry (entry.word)}
                              <div class="dict-word-badge">
                                <span class="font-mono word-text">{entry.word}</span>
                                <button class="btn-delete-x" onclick={() => deleteEnglishWord(entry.word)} aria-label="Xóa">×</button>
                              </div>
                            {/each}
                          </div>
                        {/if}
                      </div>
                      <div class="dict-footer">
                        <span class="dict-count-muted">{customEnglishWords.length} từ</span>
                        {#if saveDictSuccess}<span class="save-status success">Đã đồng bộ từ điển.</span>{/if}
                      </div>
                    </div>
                  {/if}
                </div>
              {/if}
            </div>

            <div class="dict-section-divider"></div>

            <!-- SECTION 3: PROGRAMMING -->
            <div class="spell-section">
              <label class="toggle-container">
                <span class="toggle-text font-bold" style="font-size:14.5px; display: inline-flex; align-items: center; gap: 10px;">
                  <ProgIcon size={20} />
                  Kiểm tra cú pháp lập trình <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Kiểm tra cú pháp lập trình:</strong><br/>Nhận diện các từ khóa lập trình phổ biến, kiểm tra cú pháp Caps và từ tiếng Anh trước ký hiệu lập trình để tối ưu việc gõ code."}>?</span>
                </span>
                <div class="switch">
                  <input type="checkbox" checked={settings.check_programming_keywords === 1} onchange={(e) => handleCheckboxChange('check_programming_keywords', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              {#if settings.check_programming_keywords === 1}
                <div class="spell-sub-section" transition:slide={{ duration: 200 }}>
                  <label class="toggle-container sub-toggle">
                    <span class="toggle-text">Khóa Caps thông minh <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Khóa Caps thông minh:</strong><br/>Tự động phát hiện khi bạn gõ 2 chữ viết hoa liên tiếp ở đầu từ (như <kbd>DA...</kbd> trong <kbd>DATABASE_URL</kbd>) để giữ nguyên chế độ gõ chữ thô tiếng Anh, tránh bị dính dấu tiếng Việt."}>?</span></span>
                    <div class="switch">
                      <input type="checkbox" checked={settings.all_caps_auto_escape === 1} onchange={(e) => handleCheckboxChange('all_caps_auto_escape', (e.target as HTMLInputElement).checked)} />
                      <span class="slider"></span>
                    </div>
                  </label>

                  <label class="toggle-container sub-toggle mt-10">
                    <span class="toggle-text">Khôi phục từ tiếng Anh trước ký tự lập trình/tên file <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Khôi phục trước ký tự lập trình:</strong><br/>Tự động khôi phục từ tiếng Anh gốc khi gõ liền trước các ký tự lập trình đặc trưng (như <kbd>.</kbd>, <kbd>&quot;</kbd>, <kbd>()</kbd>, <kbd>[]</kbd>, <kbd>{}</kbd>). Ví dụ: gõ <kbd>tar.gz</kbd> không bị thành <kbd>tả.gz</kbd>."}>?</span></span>
                    <div class="switch">
                      <input type="checkbox" checked={settings.smart_punct_check === 1} onchange={(e) => handleCheckboxChange('smart_punct_check', (e.target as HTMLInputElement).checked)} />
                      <span class="slider"></span>
                    </div>
                  </label>

                  <label class="toggle-container sub-toggle mt-10">
                    <span class="toggle-text">Sử dụng thêm bảng từ khóa lập trình cá nhân</span>
                    <div class="switch">
                      <input type="checkbox" checked={showProgDictTable} onchange={(e) => showProgDictTable = (e.target as HTMLInputElement).checked} />
                      <span class="slider"></span>
                    </div>
                  </label>

                  {#if showProgDictTable}
                    <div class="dict-editor-container mt-10" transition:slide={{ duration: 250 }}>
                      <p class="dict-hint">Đã bao gồm các từ khóa phổ biến của C++, Java, JavaScript, TypeScript, PHP, Python, Go, Rust, ...</p>
                      <div class="dict-toolbar">
                        <input type="search" placeholder="Tìm từ khóa..." bind:value={keywordSearch} aria-label="Tìm từ khóa lập trình" />
                        <div class="dict-add-row">
                          <input type="text" placeholder="Thêm từ khóa (vd: useState)" bind:value={newKeyword} onkeydown={(event) => event.key === "Enter" && addProgrammingKeyword()} aria-label="Từ khóa lập trình mới" />
                          <button class="btn btn-primary" onclick={addProgrammingKeyword} disabled={savingKeywords}>Thêm</button>
                        </div>
                      </div>
                      {#if keywordError}<p class="form-error">{keywordError}</p>{/if}
                      
                      <div class="dict-grid-container" aria-label="Danh sách từ khóa lập trình">
                        {#if filteredProgrammingKeywords.length === 0}
                          <div class="dict-empty">Không tìm thấy từ khóa phù hợp.</div>
                        {:else}
                          <div class="dict-words-grid">
                            {#each filteredProgrammingKeywords as entry (entry.kw)}
                              <div class="dict-word-badge">
                                <span class="font-mono word-text">{entry.kw}</span>
                                <button class="btn-delete-x" onclick={() => deleteProgrammingKeyword(entry.kw)} aria-label="Xóa">×</button>
                              </div>
                            {/each}
                          </div>
                        {/if}
                      </div>
                      <div class="dict-footer">
                        <span class="dict-count-muted">{customProgrammingKeywords.length} từ khóa</span>
                        {#if saveKeywordsSuccess}<span class="save-status success">Đã đồng bộ từ khóa.</span>{/if}
                      </div>
                    </div>
                  {/if}
                </div>
              {/if}
            </div>

          </div>

          <!-- Card 4: Thứ tự ưu tiên ngôn ngữ -->
          <div class="card mt-20">
            <h3>Thứ tự ưu tiên ngôn ngữ</h3>
            <p class="dict-hint" style="margin-bottom:14px;">Ngôn ngữ đứng trước được kiểm tra trước. Ví dụ: đặt <strong>Lập trình</strong> lên đầu để giữ nguyên <code>if</code>, <code>return</code>... thay vì bị chuyển thành tiếng Việt.</p>

            <div
              class="fsm-order-list"
              class:fsm-list-dragging={fsmIsDragging}
              role="list"
              aria-label="Thứ tự ưu tiên ngôn ngữ"
              bind:this={fsmListEl}
              onpointerdown={onFsmContainerPointerDown}
              onpointermove={onFsmContainerPointerMove}
              onpointerup={onFsmContainerPointerUp}
              onpointercancel={onFsmContainerPointerUp}
            >
              {#each fsmOrderedItems() as item, index (item.id)}
                {@const FlagIcon = item.icon}
                <div
                  class="fsm-order-item"
                  class:fsm-dragging={fsmDragIndex === index}
                  class:drag-over={fsmDragOverIndex === index && fsmDragIndex !== index}
                  role="listitem"
                  aria-label="{item.name}, vị trí {index + 1}"
                  animate:flip={{ duration: 250, easing: quintOut }}
                >
                  <span class="fsm-order-drag-handle" aria-hidden="true">⠿</span>
                  <span class="fsm-order-rank">{index + 1}</span>
                  <div class="fsm-order-emoji" style="display: flex; align-items: center; justify-content: center; width: 32px; height: 32px; margin-right: 12px; color: var(--text-color);">
                    <FlagIcon size={20} />
                  </div>
                  <div class="fsm-order-info">
                    <span class="fsm-order-name">{item.name}</span>
                    <span class="fsm-order-desc">{item.desc}</span>
                  </div>
                  <span class="fsm-order-badge {
                    (item.id === 0 && settings.check_spelling !== 1) ||
                    (item.id === 1 && settings.use_english_dictionary !== 1) ||
                    (item.id === 2 && settings.check_programming_keywords !== 1)
                      ? 'badge-off' : 'badge-on'
                  }">
                    {(item.id === 0 && settings.check_spelling !== 1) ||
                     (item.id === 1 && settings.use_english_dictionary !== 1) ||
                     (item.id === 2 && settings.check_programming_keywords !== 1) ? 'Tắt' : 'Bật'}
                  </span>
                </div>
              {/each}
            </div>
          </div>
        </section>




      <!-- Tab 1: Gõ tắt -->
      {:else if activeTab === 1}
        <section class="panel" in:fly={{ y: 8, duration: 200, delay: 150 }} out:fade={{ duration: 150 }}>
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
            
            <!-- Apps Layout for Macros -->
            <div class="apps-layout mt-15" style="height: 420px;">
              <!-- Left Column: Word List -->
              <div class="apps-sidebar">
                <div class="apps-sidebar-header" style="display: flex; gap: 8px;">
                  <div class="apps-search-box" style="flex: 1;">
                    <input type="text" placeholder="Tìm từ gõ tắt..." disabled={settings.use_macro !== 1} bind:value={searchQuery} />
                  </div>
                  <button class="btn btn-secondary" style="padding: 0 12px; font-weight: bold; font-size: 16px;" onclick={openAddMacro} disabled={settings.use_macro !== 1} aria-label="Thêm từ mới" title="Thêm từ viết tắt mới">+</button>
                </div>
                <div class="apps-list">
                  {#if filteredMacros.length === 0}
                    <div class="apps-empty-state" style="padding: 20px 0; font-size: 12px;">
                      <p>Không tìm thấy</p>
                    </div>
                  {:else}
                    {#each filteredMacros as macro}
                      <div 
                        class="app-item {selectedMacroShortcut === macro.shortcut ? 'active' : ''}" 
                        onclick={() => {
                          if (settings.use_macro === 1) selectedMacroShortcut = macro.shortcut;
                        }}
                        style={settings.use_macro !== 1 ? 'opacity: 0.5; cursor: not-allowed;' : ''}
                        role="button"
                        tabindex="0"
                        onkeydown={(e) => {
                          if (e.key === 'Enter' || e.key === ' ') {
                            if (settings.use_macro === 1) selectedMacroShortcut = macro.shortcut;
                          }
                        }}
                      >
                        <div style="display: flex; align-items: center; gap: 8px;">
                          <span>{macro.shortcut}</span>
                        </div>
                        <button
                          class="app-item-delete"
                          disabled={settings.use_macro !== 1}
                          onclick={(e) => {
                            e.stopPropagation();
                            deleteMacro(macro.shortcut);
                            if (selectedMacroShortcut === macro.shortcut) selectedMacroShortcut = null;
                          }}
                          aria-label="Xóa từ gõ tắt"
                        >×</button>
                      </div>
                    {/each}
                  {/if}
                </div>
              </div>

              <!-- Right Column: Detail & Form -->
              <div class="apps-content">
                <!-- Detail View -->
                {#if selectedMacro}
                  <div class="apps-header" style="display: flex; justify-content: space-between; align-items: center;">
                    <h3>{selectedMacro.shortcut}</h3>
                    <button class="btn btn-secondary" disabled={settings.use_macro !== 1} onclick={openEditMacro}>Sửa</button>
                  </div>
                  <div class="apps-sections-grid">
                    <div class="app-section">
                      <p style="white-space: pre-wrap; font-size: 14px; line-height: 1.5; color: var(--text-main); margin: 0; padding: 10px; background: rgba(0,0,0,0.1); border-radius: 6px;">{selectedMacro.content}</p>
                    </div>
                  </div>
                {:else}
                  <div class="apps-empty-state">
                    <p>Chọn một từ ở cột trái để xem chi tiết, hoặc ấn dấu + để thêm từ mới.</p>
                  </div>
                {/if}
              </div>
            </div>
          </div>
        </section>

      <!-- Tab 2: Chuyển mã -->
      {:else if activeTab === 2}
        <section class="panel" in:fly={{ y: 8, duration: 200, delay: 150 }} out:fade={{ duration: 150 }}>
          <div class="panel-header">
            <h2>Công cụ chuyển mã</h2>
            <p class="panel-subtitle">Chuyển đổi bảng mã văn bản tiếng Việt dễ dàng hoặc đặt phím tắt chuyển nhanh Clipboard.</p>
          </div>

          <div class="grid-2col">
            <!-- Convert Settings & Options -->
            <div class="card">
              <h3>Cấu hình chuyển đổi</h3>
              <label class="form-group">
                <span>Bảng mã nguồn</span>
                <select value={settings.convert_tool_from_code} onchange={(e) => handleSelectChange('convert_tool_from_code', parseInt((e.target as HTMLSelectElement).value))}>
                  <option value={0}>Unicode dựng sẵn</option>
                  <option value={1}>TCVN3 (ABC)</option>
                  <option value={2}>VNI Windows</option>
                  <option value={3}>Unicode tổ hợp</option>
                  <option value={4}>Vietnamese Locale CP1258</option>
                </select>
              </label>

              <div class="swap-button-container-vertical">
                <button class="btn btn-secondary swap-btn-vertical" onclick={swapConvertCodes} title="Đảo bảng mã">
                  ⇅ Đảo bảng mã nguồn & đích
                </button>
              </div>

              <label class="form-group">
                <span>Bảng mã đích</span>
                <select value={settings.convert_tool_to_code} onchange={(e) => handleSelectChange('convert_tool_to_code', parseInt((e.target as HTMLSelectElement).value))}>
                  <option value={0}>Unicode dựng sẵn</option>
                  <option value={1}>TCVN3 (ABC)</option>
                  <option value={2}>VNI Windows</option>
                  <option value={3}>Unicode tổ hợp</option>
                  <option value={4}>Vietnamese Locale CP1258</option>
                </select>
              </label>

              <div class="section-divider"></div>
              <div class="form-group mt-15">
                <h3>Tùy chọn văn bản đầu ra</h3>
                <div class="toggles-grid-compact">
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

                  <label class="toggle-container">
                    <span class="toggle-text">Loại bỏ hoàn toàn dấu Tiếng Việt</span>
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
                      {@html formatHotkeyString(convertHotkeyInfo)}
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

      <!-- Tab 7: Cloud Sync -->
      {:else if activeTab === 7}
        <section class="panel" in:fly={{ y: 8, duration: 200, delay: 150 }} out:fade={{ duration: 150 }}>
          <div class="panel-header">
            <h2>Đồng bộ dữ liệu</h2>
            <p class="panel-subtitle">Lưu trữ và khôi phục cài đặt, từ gõ tắt an toàn.</p>
          </div>

          <div class="card mb-20">
            <h3 style="margin-bottom: 15px;">Nội dung đồng bộ</h3>
            <div class="toggles-grid-compact" style="grid-template-columns: 1fr;">
              <label class="toggle-container">
                <span class="toggle-text">Thiết lập chung</span>
                <div class="switch">
                  <input type="checkbox" bind:checked={syncSettings} onchange={saveCloudSettings} />
                  <span class="slider"></span>
                </div>
              </label>
              <label class="toggle-container">
                <span class="toggle-text">Từ điển tiếng Việt cá nhân</span>
                <div class="switch">
                  <input type="checkbox" bind:checked={syncVietnameseDict} onchange={saveCloudSettings} />
                  <span class="slider"></span>
                </div>
              </label>
              <label class="toggle-container">
                <span class="toggle-text">Từ điển tiếng Anh cá nhân</span>
                <div class="switch">
                  <input type="checkbox" bind:checked={syncEnglishDict} onchange={saveCloudSettings} />
                  <span class="slider"></span>
                </div>
              </label>
              <label class="toggle-container">
                <span class="toggle-text">Từ khóa lập trình cá nhân</span>
                <div class="switch">
                  <input type="checkbox" bind:checked={syncProgrammingKeywords} onchange={saveCloudSettings} />
                  <span class="slider"></span>
                </div>
              </label>
              <label class="toggle-container">
                <span class="toggle-text">Thư viện từ gõ tắt</span>
                <div class="switch">
                  <input type="checkbox" bind:checked={syncMacros} onchange={saveCloudSettings} />
                  <span class="slider"></span>
                </div>
              </label>
              <label class="toggle-container">
                <span class="toggle-text">Bảng ghi nhớ</span>
                <div class="switch">
                  <input type="checkbox" bind:checked={syncClipboard} onchange={saveCloudSettings} />
                  <span class="slider"></span>
                </div>
              </label>
              <label class="toggle-container">
                <span class="toggle-text">Thiết lập ứng dụng cá nhân</span>
                <div class="switch">
                  <input type="checkbox" bind:checked={syncAppConfigs} onchange={saveCloudSettings} />
                  <span class="slider"></span>
                </div>
              </label>
            </div>
          </div>

          <div class="card">
            <h3 style="margin-bottom: 15px;">Dịch vụ lưu trữ</h3>
            <div class="sub-tabs-container mb-15">
              <button class="sub-tab-item" class:active={syncMethod === 'gdrive'} onclick={() => {syncMethod = 'gdrive'; saveCloudSettings();}}>
                Google Drive
              </button>
              <button class="sub-tab-item" class:active={syncMethod === 'r2'} onclick={() => {syncMethod = 'r2'; saveCloudSettings();}}>
                Cloudflare R2
              </button>
            </div>


            {#if syncMethod === 'gdrive'}
              <div class="gdrive-section" style="padding-top: 10px; border-top: 1px solid var(--border-color);">
                {#if gdriveConnected}
                  <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;">
                    <div style="color: var(--accent-color); font-weight: 500;">✓ Đã kết nối Google Drive</div>
                    <button class="btn btn-secondary" onclick={disconnectGdrive}>Đăng xuất</button>
                  </div>
                  <div class="flex-actions mt-15" style="display: flex; gap: 10px;">
                    <button class="btn btn-primary" onclick={syncToGdrive} disabled={isCloudSyncing}>
                      {isCloudSyncing ? "Đang xử lý..." : "Tải lên Drive"}
                    </button>
                    <button class="btn btn-secondary" onclick={syncFromGdrive} disabled={isCloudSyncing}>
                      {isCloudSyncing ? "Đang xử lý..." : "Tải về Máy"}
                    </button>
                  </div>
                {:else}
                  <button class="btn btn-primary" style="width: 100%;" onclick={startGdriveWebAuth} disabled={isCloudSyncing}>
                    Kết nối Google Drive
                  </button>
                {/if}
              </div>
            {:else}
              <div class="r2-section" style="padding-top: 10px; border-top: 1px solid var(--border-color);">
                <div style="margin-bottom: 12px; font-size: 12.5px; display: flex; justify-content: space-between; align-items: center;">
                  <span style="color: var(--text-secondary);">Cấu hình lưu trữ R2</span>
                  <a href="https://hoquangthaiholy.github.io/vnkey/r2_guide.html" target="_blank" style="color: var(--accent-color); text-decoration: none; font-weight: 500;" onclick={(e) => { e.preventDefault(); invoke("plugin:opener|open_url", { url: "https://hoquangthaiholy.github.io/vnkey/r2_guide.html" }); }}>
                    Hướng dẫn cấu hình ↗
                  </a>
                </div>
                <div class="form-group mb-15">
                  <label for="cloud-account-id">Account ID</label>
                  <input type="text" id="cloud-account-id" bind:value={cloudAccountId} onchange={saveCloudSettings} placeholder="Cloudflare Account ID" class="form-input" />
                </div>
                <div class="form-group mb-15">
                  <label for="cloud-access-key">Access Key ID</label>
                  <input type="text" id="cloud-access-key" bind:value={cloudAccessKey} onchange={saveCloudSettings} placeholder="R2 Access Key" class="form-input" />
                </div>
                <div class="form-group mb-15">
                  <label for="cloud-secret-key">Secret Access Key</label>
                  <input type="password" id="cloud-secret-key" bind:value={cloudSecretKey} onchange={saveCloudSettings} placeholder="R2 Secret Key" class="form-input" />
                </div>
                <div class="form-group mb-15">
                  <label for="cloud-bucket-name">Bucket Name</label>
                  <input type="text" id="cloud-bucket-name" bind:value={cloudBucketName} onchange={saveCloudSettings} placeholder="vnkey-sync" class="form-input" />
                </div>
                <div class="flex-actions mt-15" style="display: flex; gap: 10px;">
                  <button class="btn btn-primary" onclick={syncToCloud} disabled={isCloudSyncing}>
                    {isCloudSyncing ? "Đang xử lý..." : "Lưu Cấu hình & Bật Đồng bộ"}
                  </button>
                </div>
              </div>
            {/if}

            {#if cloudSyncMessage}
              <div class="mt-15" style="padding: 12px; border-radius: 6px; background-color: {cloudSyncError ? 'rgba(239, 68, 68, 0.1)' : 'rgba(34, 197, 94, 0.1)'}; color: {cloudSyncError ? '#ef4444' : '#22c55e'}; border: 1px solid {cloudSyncError ? '#ef4444' : '#22c55e'};">
                {cloudSyncMessage}
              </div>
            {/if}
          </div>
        </section>

      <!-- Tab 3: Hệ thống -->
      {:else if activeTab === 3}
        <section class="panel" in:fly={{ y: 8, duration: 200, delay: 150 }} out:fade={{ duration: 150 }}>
          <div class="panel-header">
            <h2>Thiết lập hệ thống</h2>
            <p class="panel-subtitle">Tùy chỉnh tích hợp sâu của bộ gõ vào hệ điều hành macOS.</p>
          </div>

          <div class="card mb-20">
            <h3>Khởi động & Vận hành</h3>
            <div class="toggles-grid">
              <label class="toggle-container">
                <span class="toggle-text">Khởi động cùng hệ thống</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.autostart === 1} onchange={(e) => handleCheckboxChange('autostart', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Mở bảng điều khiển khi khởi động</span>
                <div class="switch">
                  <input type="checkbox" checked={settings.open_panel_on_start === 1} onchange={(e) => handleCheckboxChange('open_panel_on_start', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>
            </div>
          </div>

          <div class="card">
            <h3>Tích hợp ứng dụng</h3>
            <div class="toggles-grid">
              <label class="toggle-container">
                <span class="toggle-text">Chuyển chế độ gõ thông minh theo từng ứng dụng <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Chuyển chế độ gõ thông minh:</strong><br/>Ghi nhớ và khôi phục trạng thái bộ gõ <kbd>VI</kbd>/<kbd>EN</kbd> riêng cho từng ứng dụng khi bạn chuyển cửa sổ."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.use_smart_switch_key === 1} onchange={(e) => handleCheckboxChange('use_smart_switch_key', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Tự động nhớ bảng mã riêng cho từng ứng dụng <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Nhớ bảng mã riêng:</strong><br/>Khôi phục tự động bảng mã đã sử dụng gần nhất khi bạn quay lại làm việc trên ứng dụng đó."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.remember_code === 1} onchange={(e) => handleCheckboxChange('remember_code', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Hiển thị bảng trạng thái nổi khi đổi chế độ gõ <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Bảng trạng thái nổi:</strong><br/>Hiển thị cửa sổ chỉ báo nhỏ <kbd>VI</kbd> hoặc <kbd>EN</kbd> xuất hiện sát con trỏ chuột mỗi khi bạn chuyển đổi chế độ gõ (bằng phím tắt hoặc chuyển ứng dụng). Cửa sổ sẽ tự mờ dần sau 1.5 giây và không cản trở các thao tác gõ hay nhấn chuột của bạn."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.use_hud === 1} onchange={(e) => handleCheckboxChange('use_hud', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Nhận diện ngữ cảnh thông minh<span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Bộ phân lớp ngữ cảnh:</strong><br/>Tự động phân lớp để chọn bộ nhận diện ngôn ngữ tối ưu dựa trên ứng dụng đang hoạt động (như VS Code/Xcode vs Telegram/Browser) và cấu trúc từ đang gõ."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.use_perceptron_context === 1} onchange={(e) => handleCheckboxChange('use_perceptron_context', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>
            </div>
          </div>

          <!-- Hotkey Panel Config Card -->
          <div class="card mt-20">
            <h3>Phím tắt mở bảng điều khiển</h3>
            <div class="hotkey-section">
              <div class="hotkey-recorder-container">
                {#if isRecordingPanelHotkey}
                  <button 
                    use:autofocusAction
                    class="btn btn-primary recording-btn pulse w-full"
                    onkeydown={(e) => handleHotkeyKeyDown(e, 'panel')}
                    onblur={() => setRecordingPanelHotkey(false)}
                  >
                    Nhập phím tắt...
                  </button>
                {:else}
                  <button 
                    class="btn btn-secondary hotkey-btn w-full" 
                    onclick={() => setRecordingPanelHotkey(true)}
                    title="Click và nhấn tổ hợp phím để đặt phím tắt"
                  >
                    {@html formatHotkeyString(panelHotkeyInfo)}
                  </button>
                {/if}
              </div>
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

              <label class="toggle-container">
                <span class="toggle-text">Hiển thị tên kiểu gõ trên thanh trạng thái <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Hiển thị trên thanh trạng thái:</strong><br/>Hiển thị tên kiểu gõ (Telex, VNI...) kế bên biểu tượng trạng thái gõ trên thanh menu bar."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.show_input_type_on_tray === 1} onchange={(e) => handleCheckboxChange('show_input_type_on_tray', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>
            </div>
          </div>
          
          <div class="card mt-20">
            <h3>Khắc phục lỗi & Tương thích</h3>
            <div class="toggles-grid">
              <label class="toggle-container">
                <span class="toggle-text">Sửa lỗi gõ trên thanh địa chỉ của trình duyệt <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Sửa lỗi thanh địa chỉ trình duyệt:</strong><br/>Sử dụng cách thay thế văn bản tương thích cao với ô gợi ý và thanh địa chỉ (có thể làm thao tác thay chữ chậm hơn một chút)."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.fix_recommend_browser === 1} onchange={(e) => handleCheckboxChange('fix_recommend_browser', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Sửa lỗi Google Chrome/Chromium & Spotlight <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Sửa lỗi Chrome & Spotlight:</strong><br/>Khắc phục lỗi tự động gợi ý/mất dấu trên Chrome/Chromium (sử dụng bôi đen thay thế Backspace) và lỗi lặp nguyên âm khi gõ từ đầu tiên trên thanh tìm kiếm macOS Spotlight."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.fix_chromium_browser === 1 || settings.fix_spotlight === 1} onchange={(e) => handleMergeFixChromeSpotlightChange((e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Sử dụng cơ chế dán từ giảm độ trễ trong Trình duyệt <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Cơ chế dán giảm trễ:</strong><br/>Khi gõ trong các trình duyệt (Chrome, Safari, Firefox,...), bộ gõ sẽ gửi các từ đã sửa dấu qua bộ nhớ đệm (Paste) thay vì gửi từng phím xóa và ký tự đơn lẻ. Giúp tăng tốc độ phản hồi và triệt tiêu giật lag trên các trang web nặng như Gemini, Claude, Facebook."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.use_paste_workaround === 1} onchange={(e) => handleUsePasteWorkaroundChange((e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Gửi phím từng bước <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Gửi phím từng bước:</strong><br/>Gửi từng ký tự riêng để tương thích tốt với một số ứng dụng đặc biệt, tốc độ sẽ chậm hơn chế độ gửi chuỗi. <span style='color:#ff9f0a;'>Chỉ bật khi gặp lỗi lặp hoặc mất chữ.</span>"}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.send_key_step_by_step === 1} onchange={(e) => handleSendKeyStepByStepChange((e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container">
                <span class="toggle-text">Tương thích với bố cục bàn phím khác hệ Mỹ <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Tương thích bàn phím khác hệ Mỹ:</strong><br/>Đọc ký tự theo bố cục (layout) hiện tại của bạn thay vì keycode bàn phím chuẩn Mỹ. Bật khi dùng <kbd>AZERTY</kbd>, <kbd>Dvorak</kbd>, v.v..."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.perform_layout_compat === 1} onchange={(e) => handleCheckboxChange('perform_layout_compat', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>
            </div>
          </div>

          <div class="card mt-20">
            <h3>Đặt lại thiết lập</h3>
            <div style="display: flex; align-items: center; justify-content: space-between;">
              <span class="text-secondary" style="font-size: 13px;">Đặt lại toàn bộ thiết lập về giá trị mặc định ban đầu.</span>
              <button
                class="btn"
                style="background: #ff453a; color: white; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-weight: 500;"
                onclick={() => showResetModal = true}
              >
                Đặt lại mặc định
              </button>
            </div>
          </div>
        </section>

        {#if showResetModal}
          <div class="modal-overlay" transition:fade={{ duration: 150 }} role="dialog" aria-modal="true" aria-label="Xác nhận đặt lại thiết lập">
            <div class="modal-content" transition:scale={{ duration: 180, start: 0.95 }} onclick={(e) => e.stopPropagation()} role="presentation">
              <h3>Xác nhận đặt lại thiết lập</h3>
              <p>Bạn có chắc chắn muốn đặt lại toàn bộ thiết lập về giá trị mặc định? Hành động này sẽ:</p>
              <ul>
                <li>Đặt lại tất cả thiết lập gõ phím, bảng mã, chính tả</li>
                <li>Đặt lại thiết lập hệ thống, hiển thị, tương thích</li>
                <li>Đặt lại thiết lập công cụ chuyển mã</li>
                <li>Đặt lại thiết lập Bảng ghi nhớ</li>
                <li>Đặt lại phím tắt chuyển đổi, công cụ chuyển mã, Bảng ghi nhớ</li>
                <li>Khôi phục tất cả các từ điển cá nhân (tiếng Việt, tiếng Anh, từ khóa lập trình)</li>
                <li>Đặt lại thứ tự ưu tiên ngôn ngữ về mặc định</li>
              </ul>
              <div class="modal-actions">
                <button class="btn btn-secondary" disabled={isResetting} onclick={() => showResetModal = false}>Hủy</button>
                <button
                  class="btn"
                  style="background: #ff453a; color: white; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-weight: 500;"
                  disabled={isResetting}
                  onclick={async () => {
                    isResetting = true;
                    try {
                      await invoke("reset_settings");
                      alert("Đã đặt lại thiết lập về mặc định.");
                      showResetModal = false;
                    } catch (e) {
                      console.error(e);
                    } finally {
                      isResetting = false;
                    }
                  }}
                >
                  {isResetting ? "Đang xử lý..." : "Xác nhận đặt lại"}
                </button>
              </div>
            </div>
          </div>
        {/if}

      <!-- Tab 5: Bảng ghi nhớ -->
      {:else if activeTab === 5}
        <section class="panel" in:fly={{ y: 8, duration: 200, delay: 150 }} out:fade={{ duration: 150 }}>
          <div class="panel-header">
            <h2>Bảng ghi nhớ</h2>
            <p class="panel-subtitle">Quản lý sao chép bản văn, hình ảnh và tệp tin.</p>
          </div>

          <div class="card">
            <h3>Cấu hình Bảng ghi nhớ</h3>
            <div class="toggles-grid">
              <label class="toggle-container">
                <span class="toggle-text">Kích hoạt Bảng ghi nhớ <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Kích hoạt Bảng ghi nhớ (Clipboard):</strong><br/>Theo dõi nội dung sao chép để hiển thị lại nhanh chóng. Dữ liệu nhạy cảm từ ứng dụng bảo mật sẽ tự động bị bỏ qua."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" checked={settings.clipboard_enabled === 1} onchange={(e) => handleCheckboxChange('clipboard_enabled', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container" class:disabled-zone={settings.clipboard_enabled !== 1}>
                  <span class="toggle-text">Tự động ẩn cửa sổ sau khi chọn dán <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Tự động ẩn cửa sổ:</strong><br/>Đóng Bảng ghi nhớ ngay sau khi thực hiện dán văn bản hoặc khi cửa sổ bị mất tiêu điểm."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" disabled={settings.clipboard_enabled !== 1} checked={settings.clipboard_auto_hide === 1} onchange={(e) => handleCheckboxChange('clipboard_auto_hide', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>

              <label class="toggle-container" class:disabled-zone={settings.clipboard_enabled !== 1}>
                  <span class="toggle-text">Ghim cửa sổ Bảng ghi nhớ luôn nổi lên trên <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Ghim cửa sổ luôn nổi:</strong><br/>Giữ cửa sổ Bảng ghi nhớ luôn hiển thị phía trên các cửa sổ ứng dụng khác cho đến khi bạn bấm bỏ ghim."}>?</span></span>
                <div class="switch">
                  <input type="checkbox" disabled={settings.clipboard_enabled !== 1} checked={settings.clipboard_pin_on_top === 1} onchange={(e) => handleCheckboxChange('clipboard_pin_on_top', (e.target as HTMLInputElement).checked)} />
                  <span class="slider"></span>
                </div>
              </label>
              <div class="toggle-container" class:disabled-zone={settings.clipboard_enabled !== 1}>
                <span class="toggle-text">Số lượng mục tối đa trong Bảng ghi nhớ</span>
                <input
                  type="number"
                  disabled={settings.clipboard_enabled !== 1}
                  min="10"
                  max="30"
                  value={settings.clipboard_max_items}
                  onchange={(e) => {
                    let val = parseInt((e.target as HTMLInputElement).value) || 10;
                    if (val < 10) val = 10;
                    if (val > 30) val = 30;
                    settings.clipboard_max_items = val;
                    saveSettings();
                  }}
                  style="width: 70px; padding: 4px 8px; border-radius: 6px; border: 1px solid var(--border-color); background: var(--bg-input, rgba(128,128,128,0.1)); color: var(--text-primary); text-align: center; font-size: 13px; outline: none;"
                />
              </div>
            </div>
          </div>

          <div class="card mt-20" class:disabled-zone={settings.clipboard_enabled !== 1}>
            <h3>Phím tắt kích hoạt</h3>
            <div class="hotkey-section">
              <div class="hotkey-recorder-container">
                {#if isRecordingClipboardHotkey}
                  <button 
                    class="btn btn-primary recording-btn pulse w-full" 
                    use:autofocusAction
                    onblur={() => setRecordingClipboardHotkey(false)}
                    onkeydown={(e) => handleHotkeyKeyDown(e, 'clipboard')}
                  >
                    Đang nhấn tổ hợp phím... (Esc để hủy)
                  </button>
                {:else}
                  <button 
                    class="btn btn-secondary hotkey-btn w-full" 
                    disabled={settings.clipboard_enabled !== 1}
                    onclick={() => setRecordingClipboardHotkey(true)}
                  >
                    {@html formatHotkeyString(clipboardHotkeyInfo)}
                  </button>
                {/if}
              </div>
            </div>
          </div>

          <div class="card mt-20">
            <h3>Dọn dẹp Bảng ghi nhớ</h3>
            <div style="display: flex; align-items: center; justify-content: space-between;">
              <span class="text-secondary" style="font-size: 13px;">Xóa sạch toàn bộ nội dung đang lưu trong Bảng ghi nhớ.</span>
              <button
                class="btn"
                style="background: #ff453a; color: white; border: none; padding: 8px 16px; border-radius: 6px; cursor: pointer; font-weight: 500;"
                onclick={async () => {
                  if (confirm("Bạn có chắc chắn muốn xóa toàn bộ Bảng ghi nhớ không?")) {
                    try {
                      await invoke("clear_clipboard_history");
                      alert("Đã xóa sạch Bảng ghi nhớ.");
                    } catch (e) {
                      console.error(e);
                    }
                  }
                }}
              >
                Xóa Bảng ghi nhớ
              </button>
            </div>
          </div>
        </section>

      <!-- Tab 6: Ứng dụng -->
      {:else if activeTab === 6}
        <section class="panel" in:fly={{ y: 8, duration: 200, delay: 150 }} out:fade={{ duration: 150 }}>
          <div class="panel-header">
            <h2>Thiết lập cho từng ứng dụng</h2>
            <p class="panel-subtitle">Tùy chỉnh chế độ gõ và phím tắt riêng cho mỗi ứng dụng đang chạy.</p>
          </div>

          <div class="apps-layout">
            <!-- Left Pane: List of Apps -->
            <div class="apps-sidebar">
              <div class="apps-sidebar-header">
                <button class="btn btn-primary w-full" onclick={openAppSelector} style="padding: 10px; font-size: 13px;">+ Thêm ứng dụng...</button>
                {#if appConfigError}
                  <p class="form-error mt-5" style="font-size: 11px; margin: 4px 0 0 0;">{appConfigError}</p>
                {/if}
              </div>

              <div class="apps-list">
                {#each Object.keys(appConfigs) as bundleId}
                  <div
                    class="app-item"
                    class:active={selectedApp === bundleId}
                    onclick={() => selectedApp = bundleId}
                    onkeydown={(e) => {
                      if (e.key === 'Enter' || e.key === ' ') {
                        selectedApp = bundleId;
                      }
                    }}
                    role="button"
                    tabindex="0"
                  >
                    <div style="display: flex; align-items: center; gap: 8px;">
                      {#if appIcons[bundleId]}
                        <img src="data:image/png;base64,{appIcons[bundleId]}" width="20" height="20" style="border-radius: 4px; object-fit: contain;" alt="" />
                      {:else}
                        <div style="width: 20px; height: 20px; border-radius: 4px; background: rgba(128,128,128,0.2);"></div>
                      {/if}
                      <span>{appConfigs[bundleId].name || bundleId}</span>
                    </div>
                    <button
                      class="app-item-delete"
                      onclick={(e) => {
                        e.stopPropagation();
                        deleteAppConfig(bundleId, appConfigs[bundleId].name || bundleId);
                      }}
                      aria-label="Xóa cấu hình"
                    >×</button>
                  </div>
                {:else}
                  <div class="apps-empty-state" style="padding: 20px 0; font-size: 12px;">
                    Chưa có cấu hình riêng nào.
                  </div>
                {/each}
              </div>
            </div>

            <!-- Right Pane: App Config Options -->
            <div class="apps-content">
              {#if selectedApp && appConfigs[selectedApp]}
                <div class="apps-header">
                  <h3>Cấu hình cho {appConfigs[selectedApp]?.name || selectedApp}</h3>
                </div>

                <div class="apps-sections-grid">
                  <!-- Section 1: Cơ bản -->
                  <div class="app-section">
                    <h4>Cơ bản</h4>
                    
                    <label class="form-group-stacked">
                      <span>Ngôn ngữ mặc định</span>
                      <select value={appConfigs[selectedApp].language} onchange={(e) => updateAppConfigField('language', parseInt((e.target as HTMLSelectElement).value))}>
                        <option value={1}>Tiếng Việt</option>
                        <option value={0}>Tiếng Anh</option>
                      </select>
                    </label>

                    <label class="form-group-stacked mt-15">
                      <span>Kiểu gõ</span>
                      <select value={appConfigs[selectedApp].input_type} onchange={(e) => updateAppConfigField('input_type', parseInt((e.target as HTMLSelectElement).value))}>
                        <option value={0}>Telex</option>
                        <option value={1}>VNI</option>
                      </select>
                    </label>

                    <label class="form-group-stacked mt-15">
                      <span>Bảng mã</span>
                      <select value={appConfigs[selectedApp].code_table} onchange={(e) => updateAppConfigField('code_table', parseInt((e.target as HTMLSelectElement).value))}>
                        <option value={0}>Unicode dựng sẵn</option>
                        <option value={1}>TCVN3 (ABC)</option>
                        <option value={2}>VNI Windows</option>
                        <option value={3}>Unicode tổ hợp</option>
                        <option value={4}>Vietnamese Locale CP1258</option>
                      </select>
                    </label>
                  </div>

                  <!-- Section 2: Quy tắc gõ dấu -->
                  <div class="app-section">
                    <h4>Quy tắc gõ dấu</h4>
                    <div class="toggles-grid-compact mt-10">
                      <label class="toggle-container">
                        <span class="toggle-text">Viết hoa chữ cái đầu tiên của câu</span>
                        <div class="switch">
                          <input type="checkbox" checked={appConfigs[selectedApp].upper_case_first_char === 1} onchange={(e) => updateAppConfigField('upper_case_first_char', (e.target as HTMLInputElement).checked ? 1 : 0)} />
                          <span class="slider"></span>
                        </div>
                      </label>

                      <label class="toggle-container">
                        <span class="toggle-text">Đặt dấu hiện đại <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Đặt dấu hiện đại:</strong><br/>Đặt dấu trên nguyên âm chính trong các cụm như <kbd>oà</kbd>, <kbd>uý</kbd> (thay vì kiểu cũ <kbd>òa</kbd>, <kbd>úy</kbd>). Áp dụng cho các cụm <kbd>oa</kbd>, <kbd>oe</kbd>, <kbd>uy</kbd>."}>?</span></span>
                        <div class="switch">
                          <input type="checkbox" checked={appConfigs[selectedApp].use_modern_orthography === 1} onchange={(e) => updateAppConfigField('use_modern_orthography', (e.target as HTMLInputElement).checked ? 1 : 0)} />
                          <span class="slider"></span>
                        </div>
                      </label>

                      <label class="toggle-container">
                        <span class="toggle-text">Gõ nhanh phụ âm khi đúp từ <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Gõ nhanh phụ âm khi đúp từ:</strong><br/>Gõ đúp phụ âm để tạo nhanh:<br/>• <kbd>cc</kbd> → <b>ch</b> &nbsp;&nbsp; • <kbd>gg</kbd> → <b>gi</b><br/>• <kbd>kk</kbd> → <b>kh</b> &nbsp;&nbsp; • <kbd>nn</kbd> → <b>ng</b><br/>• <kbd>qq</kbd> → <b>qu</b> &nbsp;&nbsp; • <kbd>pp</kbd> → <b>ph</b><br/>• <kbd>tt</kbd> → <b>th</b><br/><i>Tự động khôi phục khi gõ từ tiếng Anh.</i>"}>?</span></span>
                        <div class="switch">
                          <input type="checkbox" checked={appConfigs[selectedApp].quick_telex === 1} onchange={(e) => updateAppConfigField('quick_telex', (e.target as HTMLInputElement).checked ? 1 : 0)} />
                          <span class="slider"></span>
                        </div>
                      </label>

                      <label class="toggle-container">
                        <span class="toggle-text">Gõ nhanh phụ âm đầu <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Gõ nhanh phụ âm đầu:</strong><br/>Dùng phím tắt đơn lẻ ở đầu từ:<br/>• <kbd>f</kbd> → <b>ph</b> (ví dụ: <kbd>fong</kbd> → <b>phong</b>)<br/>• <kbd>j</kbd> → <b>gi</b> (ví dụ: <kbd>ja</kbd> → <b>gia</b>)<br/>• <kbd>w</kbd> → <b>qu</b> (ví dụ: <kbd>wa</kbd> → <b>qua</b>)"}>?</span></span>
                        <div class="switch">
                          <input type="checkbox" checked={appConfigs[selectedApp].quick_start_consonant === 1} onchange={(e) => updateAppConfigField('quick_start_consonant', (e.target as HTMLInputElement).checked ? 1 : 0)} />
                          <span class="slider"></span>
                        </div>
                      </label>

                      <label class="toggle-container">
                        <span class="toggle-text">Gõ nhanh phụ âm cuối <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Gõ nhanh phụ âm cuối:</strong><br/>Dùng phím tắt đơn lẻ ở cuối từ:<br/>• <kbd>g</kbd> → <b>ng</b> (ví dụ: <kbd>lahg</kbd> → <b>làng</b>)<br/>• <kbd>h</kbd> → <b>nh</b> (ví dụ: <kbd>ah</kbd> → <b>anh</b>)<br/>• <kbd>k</kbd> → <b>ch</b> (ví dụ: <kbd>sak</kbd> → <b>sách</b>)"}>?</span></span>
                        <div class="switch">
                          <input type="checkbox" checked={appConfigs[selectedApp].quick_end_consonant === 1} onchange={(e) => updateAppConfigField('quick_end_consonant', (e.target as HTMLInputElement).checked ? 1 : 0)} />
                          <span class="slider"></span>
                        </div>
                      </label>
                    </div>
                  </div>

                  <!-- Section 3: Kiểm tra chính tả -->
                  <div class="app-section">
                    <h4>Kiểm tra chính tả</h4>
                    <div class="toggles-grid-compact mt-10">
                      <label class="toggle-container">
                        <span class="toggle-text">Kiểm tra chính tả tiếng Việt <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Kiểm tra chính tả tiếng Việt:</strong><br/>Theo dõi cấu trúc âm tiết tiếng Việt chuẩn hóa để hạn chế các trường hợp tự động chuyển đổi sai dấu."}>?</span></span>
                        <div class="switch">
                          <input type="checkbox" checked={appConfigs[selectedApp].check_spelling === 1} onchange={(e) => updateAppConfigField('check_spelling', (e.target as HTMLInputElement).checked ? 1 : 0)} />
                          <span class="slider"></span>
                        </div>
                      </label>

                      <label class="toggle-container">
                        <span class="toggle-text">Kiểm tra chính tả tiếng Anh <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Kiểm tra từ tiếng Anh:</strong><br/>Dùng luật cấu thành từ tiếng Anh và từ điển tùy chỉnh để giữ nguyên các từ tiếng Anh dễ bị Telex biến đổi thành chữ tiếng Việt."}>?</span></span>
                        <div class="switch">
                          <input type="checkbox" checked={appConfigs[selectedApp].use_english_dictionary === 1} onchange={(e) => updateAppConfigField('use_english_dictionary', (e.target as HTMLInputElement).checked ? 1 : 0)} />
                          <span class="slider"></span>
                        </div>
                      </label>

                      <label class="toggle-container">
                        <span class="toggle-text">Kiểm tra từ khóa lập trình <span class="help-tooltip" role="img" aria-label="Thông tin" use:tooltip={"<strong>Kiểm tra từ khóa lập trình:</strong><br/>Dùng luật nhận diện từ khóa lập trình phổ biến (<kbd>C++</kbd>, <kbd>Java</kbd>, <kbd>JS/TS</kbd>, <kbd>PHP</kbd>, <kbd>Python</kbd>, <kbd>Go</kbd>, <kbd>Rust</kbd>...) để giữ nguyên từ khi gõ code."}>?</span></span>
                        <div class="switch">
                          <input type="checkbox" checked={appConfigs[selectedApp].check_programming_keywords === 1} onchange={(e) => updateAppConfigField('check_programming_keywords', (e.target as HTMLInputElement).checked ? 1 : 0)} />
                          <span class="slider"></span>
                        </div>
                      </label>
                    </div>
                  </div>

                  <!-- Section 4: Gõ tắt -->
                  <div class="app-section">
                    <h4>Gõ tắt & Phím tắt</h4>
                    <div class="toggles-grid-compact mt-10">
                      <label class="toggle-container">
                        <span class="toggle-text">Cho phép gõ tắt</span>
                        <div class="switch">
                          <input type="checkbox" checked={appConfigs[selectedApp].use_macro === 1} onchange={(e) => updateAppConfigField('use_macro', (e.target as HTMLInputElement).checked ? 1 : 0)} />
                          <span class="slider"></span>
                        </div>
                      </label>

                      <label class="toggle-container">
                        <span class="toggle-text">Cho phép gõ tắt ở chế độ tiếng Anh</span>
                        <div class="switch">
                          <input type="checkbox" checked={appConfigs[selectedApp].use_macro_in_english_mode === 1} onchange={(e) => updateAppConfigField('use_macro_in_english_mode', (e.target as HTMLInputElement).checked ? 1 : 0)} />
                          <span class="slider"></span>
                        </div>
                      </label>

                      <label class="toggle-container">
                        <span class="toggle-text">Tự động viết hoa từ gõ tắt</span>
                        <div class="switch">
                          <input type="checkbox" checked={appConfigs[selectedApp].auto_caps_macro === 1} onchange={(e) => updateAppConfigField('auto_caps_macro', (e.target as HTMLInputElement).checked ? 1 : 0)} />
                          <span class="slider"></span>
                        </div>
                      </label>
                    </div>
                  </div>

                  <!-- Section 5: Thứ tự ưu tiên -->
                  <div class="app-section">
                    <h4>Thứ tự ưu tiên</h4>
                    <p class="dict-hint" style="margin-bottom: 8px; font-size: 11px;">Kéo thả để sắp xếp thứ tự kiểm tra từ trên xuống.</p>
                    <div 
                      class="app-fsm-list"
                      class:fsm-list-dragging={appFsmIsDragging}
                      role="list"
                      aria-label="Thứ tự ưu tiên cho ứng dụng"
                      bind:this={appFsmListEl}
                      onpointerdown={onAppFsmContainerPointerDown}
                      onpointermove={onAppFsmContainerPointerMove}
                      onpointerup={onAppFsmContainerPointerUp}
                      onpointercancel={onAppFsmContainerPointerUp}
                    >
                      {#each appFsmOrderedItems() as item, index (item.id)}
                        {@const FsmIcon = item.icon}
                        <div 
                          class="app-fsm-item"
                          class:fsm-dragging={appFsmDragIndex === index}
                          class:drag-over={appFsmDragOverIndex === index && appFsmDragIndex !== index}
                          role="listitem"
                          animate:flip={{ duration: 200, easing: quintOut }}
                        >
                          <span class="app-fsm-drag-handle" aria-hidden="true">⠿</span>
                          <span class="app-fsm-rank">{index + 1}</span>
                          <div class="app-fsm-icon">
                            <FsmIcon size={15} />
                          </div>
                          <span class="app-fsm-name">{item.name}</span>
                          <span class="app-fsm-badge {
                            (item.id === 0 && appConfigs[selectedApp].check_spelling !== 1) ||
                            (item.id === 1 && appConfigs[selectedApp].use_english_dictionary !== 1) ||
                            (item.id === 2 && appConfigs[selectedApp].check_programming_keywords !== 1)
                              ? 'badge-off' : 'badge-on'
                          }">
                            {(item.id === 0 && appConfigs[selectedApp].check_spelling !== 1) ||
                             (item.id === 1 && appConfigs[selectedApp].use_english_dictionary !== 1) ||
                             (item.id === 2 && appConfigs[selectedApp].check_programming_keywords !== 1)
                              ? 'Tắt' : 'Bật'}
                          </span>
                        </div>
                      {/each}
                    </div>
                  </div>
                </div>
              {:else}
                <div class="apps-empty-state">
                  <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="3" width="20" height="14" rx="2" ry="2"></rect><line x1="8" y1="21" x2="16" y2="21"></line><line x1="12" y1="17" x2="12" y2="21"></line></svg>
                  <p>Chọn một ứng dụng ở cột bên trái hoặc thêm mới để bắt đầu cấu hình riêng biệt.</p>
                </div>
              {/if}
            </div>
          </div>
        </section>

      <!-- Tab 4: Thông tin -->
      {:else}
        <section class="panel" in:fly={{ y: 8, duration: 200, delay: 150 }} out:fade={{ duration: 150 }}>
          <div class="panel-header">
            <h2>Thông tin ứng dụng</h2>
            <p class="panel-subtitle">Lịch sử phát triển và hỗ trợ kỹ thuật cho bộ gõ VNKey.</p>
          </div>

          <div class="card info-card">
            <div class="info-header">
              <img src="/favicon.png" alt="VNKey" class="app-icon" />
              <div>
                <h3>VNKey</h3>
                <p class="version">
                  Phiên bản {appVersion}
                  {#if updateStatus === 'checking'}
                    <span style="color: var(--text-secondary); margin-left: 8px; font-size: 11px;">(Đang kiểm tra...)</span>
                  {/if}
                </p>
              </div>
            </div>
            <p class="desc">Bộ gõ tiếng Việt mã nguồn mở, gọn nhẹ, chạy nhanh và an toàn tuyệt đối cho người dùng trên nền tảng macOS, Windows và Linux.</p>
            
            <div class="links-grid">
              <a href="https://hoquangthaiholy.github.io/vnkey/" target="_blank" class="link-item">Trang chủ VNKey</a>
              <a href="https://github.com/hoquangthaiholy/vnkey" target="_blank" class="link-item">Nguồn mở (GitHub)</a>
              <a href="mailto:vnkey.dev@gmail.com" class="link-item">Liên hệ tác giả</a>
            </div>

            <div class="info-footer pt-15 mt-10" style="border-top: 1px solid var(--border-color); display: flex; justify-content: space-between; align-items: center;">
              <span class="text-secondary" style="font-size: 13px; display: flex; align-items: center; gap: 4px;">
                Copyright <Copyright size={14} strokeWidth={2} /> 2026
              </span>
              <button 
                class="btn btn-secondary" 
                style="padding: 6px 12px; font-size: 12px;"
                onclick={() => checkUpdates(false)} 
                disabled={updateStatus === 'checking'}
              >
                {#if updateStatus === 'checking'}
                  Đang kiểm tra...
                {:else}
                  Kiểm tra cập nhật
                {/if}
              </button>
            </div>
          </div>
        </section>
      {/if}
    </main>

    <!-- App Selector Modal -->
    {#if showAppSelectorModal}
      <div class="app-modal-overlay" transition:fade={{ duration: 150 }} role="dialog" tabindex="-1" onkeydown={(e) => e.key === 'Escape' && (showAppSelectorModal = false)}>
        <div class="app-modal-content" transition:scale={{ duration: 180, start: 0.95 }}>
          <div class="app-modal-header">
            <h3>Thêm ứng dụng</h3>
            <button class="app-modal-close" aria-label="Đóng" onclick={() => showAppSelectorModal = false}>&times;</button>
          </div>
          
          <button class="btn btn-secondary w-full mb-15" onclick={browseAppFromFolder}>
            Duyệt từ thư mục Application...
          </button>
          
          <h4 style="margin-bottom: 10px; font-size: 13px; color: var(--text-secondary); font-weight: 500;">Hoặc chọn từ ứng dụng đang chạy:</h4>
          
          <div class="running-apps-list">
            {#if isLoadingApps}
              <div style="padding: 20px; text-align: center; grid-column: 1 / -1; color: var(--text-secondary);">
                Đang tải danh sách...
              </div>
            {:else if runningAppsList.length === 0}
              <div style="padding: 20px; text-align: center; grid-column: 1 / -1; color: var(--text-secondary);">
                Không tìm thấy ứng dụng.
              </div>
            {:else}
              {#each runningAppsList as app}
                <div class="running-app-item" onclick={() => addAppConfigByApp(app.bundle_id, app.name)} role="button" tabindex="0" onkeydown={(e) => e.key === 'Enter' && addAppConfigByApp(app.bundle_id, app.name)}>
                  <img src="data:image/png;base64,{app.icon}" width="48" height="48" alt={app.name} />
                  <span title={app.name}>{app.name}</span>
                </div>
              {/each}
            {/if}
          </div>
        </div>
      </div>
    {/if}

    {#if showMacroModal}
      <div class="modal-overlay" transition:fade={{ duration: 150 }} role="dialog" aria-modal="true" aria-label="Thêm hoặc sửa từ gõ tắt">
        <div class="modal-content" transition:scale={{ duration: 180, start: 0.95 }} onclick={(e) => e.stopPropagation()} style="max-width: 500px;" role="presentation">
          <h3 style="margin-bottom: 20px;">{newShortcut && macrosList.some(m => m.shortcut === newShortcut) ? 'Chỉnh sửa từ gõ tắt' : 'Thêm từ gõ tắt mới'}</h3>
          
          <div style="margin-bottom: 15px;">
            <label for="shortcut-input" style="display: block; margin-bottom: 5px; font-weight: 500; font-size: 14px;">Từ viết tắt</label>
            <input id="shortcut-input" type="text" placeholder="Ví dụ: ok" bind:value={newShortcut} class="form-input" style="width: 100%; box-sizing: border-box;" />
          </div>

          <div style="margin-bottom: 20px;">
            <label for="content-input" style="display: block; margin-bottom: 5px; font-weight: 500; font-size: 14px;">Nội dung thay thế</label>
            <textarea id="content-input" placeholder="Nội dung thay thế (hỗ trợ nhập nhiều dòng)..." bind:value={newContent} rows="4" class="form-input" style="width: 100%; box-sizing: border-box; resize: vertical; min-height: 100px; font-family: inherit; padding: 10px;"></textarea>
          </div>

          {#if macroError}
            <p class="error-text" style="margin-bottom: 15px; margin-top: 0;">{macroError}</p>
          {/if}

          <div class="modal-actions" style="margin-top: 0;">
            <button class="btn btn-secondary" onclick={() => showMacroModal = false}>Hủy</button>
            <button class="btn btn-primary" onclick={addMacro}>Lưu thay đổi</button>
          </div>
        </div>
      </div>
    {/if}

    {#if showUpdateModal && updateInfo}
      <div class="modal-overlay" transition:fade={{ duration: 150 }} role="dialog" aria-modal="true" aria-label="Thông báo cập nhật phiên bản mới">
        <div class="modal-content" transition:scale={{ duration: 180, start: 0.95 }} onclick={(e) => e.stopPropagation()} style="max-width: 500px;" role="presentation">
          <h3 style="margin-bottom: 5px; font-size: 18px; font-weight: 600;">Cập nhật phiên bản mới</h3>
          <p style="margin-bottom: 15px; font-size: 13px; color: var(--text-secondary);">
            Phiên bản mới <strong>{updateInfo.version}</strong> đã sẵn sàng (phát hành ngày {updateInfo.date}).
          </p>
          
          <div style="margin-bottom: 20px;">
            <span style="display: block; margin-bottom: 5px; font-weight: 500; font-size: 13px; color: var(--text-primary);">Nhật ký thay đổi:</span>
            <div style="background: var(--bg-input); border: 1px solid var(--border-color); border-radius: 6px; padding: 12px; max-height: 200px; overflow-y: auto; font-size: 12px; line-height: 1.6; white-space: pre-wrap; color: var(--text-secondary);">
              {updateInfo.releaseNotes}
            </div>
          </div>

          <div class="modal-actions" style="margin-top: 0; align-items: center; justify-content: flex-end; gap: 10px;">
            {#if isDownloading}
              <span style="font-size: 13px; color: var(--color-accent); font-weight: 500;">
                {updateProgress}
              </span>
            {:else}
              <button class="btn btn-secondary" onclick={() => showUpdateModal = false}>Để sau</button>
              <button 
                class="btn btn-primary" 
                onclick={downloadAndInstallUpdate}
              >
                {activeUpdate ? "Cập nhật & Khởi động lại" : "Tải về bản mới"}
              </button>
            {/if}
          </div>
        </div>
      </div>
    {/if}
  </div>

<style>


  :global(.hotkey-icon) {
    font-size: 1.4em;
    vertical-align: -0.1em;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    font-weight: 500;
  }
  :global(.hotkey-plus) {
    opacity: 0.5;
    margin: 0 4px;
    font-weight: 400;
  }
  :global(.hotkey-text) {
    font-weight: 600;
  }

  /* Apps Tab Styles */
  .apps-layout {
    display: flex;
    height: calc(100vh - 180px);
    margin-top: 15px;
    gap: 20px;
  }
  
  .apps-sidebar {
    width: 250px;
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 8px;
    display: flex;
    flex-direction: column;
    padding: 12px;
    box-sizing: border-box;
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  }
  
  .apps-sidebar-header {
    margin-bottom: 12px;
  }
  
  .apps-search-box {
    display: flex;
    gap: 6px;
  }
  
  .apps-search-box input {
    flex: 1;
    background: var(--bg-input);
    border: 1px solid var(--border-color);
    color: var(--text-primary);
    border-radius: 6px;
    padding: 6px 10px;
    font-size: 13px;
    outline: none;
    transition: border-color 0.15s ease;
  }
  
  .apps-search-box input:focus {
    border-color: var(--color-accent);
  }
  
  .apps-list {
    flex: 1;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  
  .apps-list::-webkit-scrollbar {
    width: 4px;
  }
  .apps-list::-webkit-scrollbar-thumb {
    background: rgba(128,128,128,0.2);
    border-radius: 4px;
  }
  
  .app-item {
    background: transparent;
    border: 1px solid transparent;
    color: var(--text-primary);
    text-align: left;
    padding: 8px 10px;
    border-radius: 6px;
    cursor: pointer;
    font-size: 13px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    transition: all 0.12s ease;
  }
  
  .app-item:hover {
    background: rgba(255, 255, 255, 0.03);
  }
  
  :global(.light) .app-item:hover {
    background: rgba(0, 0, 0, 0.02);
  }
  
  .app-item.active {
    background: rgba(0, 122, 255, 0.1);
    color: var(--color-accent);
    border-color: rgba(0, 122, 255, 0.15);
  }
  
  .app-item-delete {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    font-size: 16px;
    cursor: pointer;
    padding: 0 4px;
    border-radius: 4px;
    opacity: 0;
    transition: opacity 0.12s ease, color 0.12s ease;
  }
  
  .app-item:hover .app-item-delete {
    opacity: 0.6;
  }
  
  .app-item-delete:hover {
    color: #ff453a;
    opacity: 1 !important;
  }
  
  .apps-content {
    flex: 1;
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 8px;
    padding: 20px;
    box-sizing: border-box;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    box-shadow: 0 4px 12px rgba(0,0,0,0.1);
  }
  
  .apps-content::-webkit-scrollbar {
    width: 6px;
  }
  .apps-content::-webkit-scrollbar-thumb {
    background: rgba(128,128,128,0.2);
    border-radius: 4px;
  }
  
  .apps-empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: var(--text-secondary);
    text-align: center;
    opacity: 0.8;
  }
  
  .apps-empty-state svg {
    margin-bottom: 12px;
    opacity: 0.4;
    color: var(--text-secondary);
  }

  .apps-empty-state p {
    font-size: 13px;
  }
  
  .apps-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 1px solid var(--border-color);
    padding-bottom: 15px;
    margin-bottom: 20px;
  }
  
  .apps-header h3 {
    margin: 0;
    font-size: 16px;
    font-weight: 600;
  }
  
  .apps-sections-grid {
    display: flex;
    flex-direction: column;
    gap: 20px;
  }
  
  .app-section {
    border-bottom: 1px solid var(--border-color);
    padding-bottom: 20px;
  }
  
  .app-section:last-child {
    border-bottom: none;
    padding-bottom: 0;
  }
  
  .app-section h4 {
    margin: 0 0 12px 0;
    font-size: 11px;
    font-weight: 700;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.75px;
  }

  :root {
    color-scheme: dark;
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

  :global(.light) {
    color-scheme: light;
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

  :global(body) {
    margin: 0;
    padding: 0;
    background-color: transparent !important;
    color: var(--text-primary);
    overflow: hidden;
    user-select: none;
  }

  .app-layout {
    display: flex;
    flex-direction: row;
    width: 100vw;
    height: 100vh;
    background-color: var(--bg-app);
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
    padding: 14px 24px 20px 24px;
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .sidebar-header .logo {
    width: 44px;
    height: 44px;
    border-radius: 10px;
    object-fit: contain;
  }

  .sidebar-header .title-group {
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .sidebar-header .title {
    font-weight: 700;
    font-size: 16px;
    letter-spacing: 0.2px;
    line-height: 1.2;
  }

  .sidebar-header .subtitle {
    font-size: 11px;
    font-weight: 400;
    color: var(--text-secondary, #8c8c93);
    line-height: 1.2;
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
    row-gap: 14px;
    padding: 16px;
    margin-top: 14px;
    border: 1px solid var(--border-color);
    background: rgba(128, 128, 128, 0.04);
    border-radius: 10px;
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

  .form-group label,
  .form-group > span:first-child {
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

  .form-group-inline > span:first-child {
    font-size: 13.5px;
    color: var(--text-primary);
    font-weight: 500;
    white-space: nowrap;
    flex-shrink: 0;
  }

  .form-input {
    width: 100%;
    padding: 8px 12px;
    border-radius: 6px;
    border: 1px solid var(--border-color);
    background: var(--bg-input);
    color: var(--text-primary);
    font-size: 13px;
    box-sizing: border-box;
    transition: all 0.2s;
  }

  .form-input:focus {
    border-color: var(--color-accent);
    outline: none;
  }

  .form-group-inline select {
    flex: 0 0 200px;
    min-width: 0;
  }



  kbd {
    display: inline-block;
    padding: 1px 5px;
    border: 1px solid var(--border-color, #444);
    border-radius: 4px;
    font-family: monospace;
    font-size: 12px;
    background: var(--bg-input, #2a2a2a);
    color: var(--text-primary, #eee);
    line-height: 1.4;
  }

  .form-group-stacked {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .form-group-stacked > span:first-child {
    font-size: 13.5px;
    color: var(--text-primary);
    font-weight: 500;
  }

  .form-group-stacked select {
    width: 100%;
  }

  /* App Selector Modal */
  .app-modal-overlay {
    position: fixed;
    top: 0; left: 0; right: 0; bottom: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    backdrop-filter: blur(6px);
    -webkit-backdrop-filter: blur(6px);
  }

  .app-modal-content {
    background: var(--bg-card);
    padding: 24px;
    border-radius: 12px;
    width: 480px;
    max-width: 90%;
    max-height: 80vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 10px 25px rgba(0,0,0,0.2);
    border: 1px solid var(--border-color);
  }

  .app-modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
  }

  .app-modal-header h3 {
    margin: 0;
    font-size: 16px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .app-modal-close {
    background: none;
    border: none;
    font-size: 24px;
    line-height: 1;
    color: var(--text-secondary);
    cursor: pointer;
    padding: 0;
  }

  .running-apps-list {
    flex: 1;
    overflow-y: auto;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(100px, 1fr));
    gap: 12px;
    margin-bottom: 5px;
    padding-right: 8px;
  }

  .running-app-item {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 12px;
    border-radius: 8px;
    background: var(--bg-input);
    border: 1px solid var(--border-color);
    cursor: pointer;
    transition: all 0.2s;
    text-align: center;
  }

  .running-app-item:hover {
    border-color: var(--accent-color, #007bff);
    background: var(--bg-hover, rgba(0,123,255,0.05));
  }

  .running-app-item img {
    margin-bottom: 8px;
    border-radius: 8px;
    object-fit: contain;
  }

  .running-app-item span {
    font-size: 12px;
    color: var(--text-primary);
    word-break: break-word;
    display: -webkit-box;
    line-clamp: 2;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }


  select {
    width: 100%;
    box-sizing: border-box;
    padding: 10px 36px 10px 14px;
    border-radius: 8px;
    background-color: var(--bg-input);
    color: var(--text-primary);
    border: 1px solid var(--border-color);
    outline: none;
    font-size: 13.5px;
    cursor: pointer;
    appearance: none;
    -webkit-appearance: none;
    transition: all 0.2s ease;
    background-image: url("data:image/svg+xml;charset=UTF-8,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23666' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3e%3cpolyline points='6 9 12 15 18 9'%3e%3c/polyline%3e%3c/svg%3e");
    background-repeat: no-repeat;
    background-position: right 12px center;
    background-size: 14px;
  }

  select:hover {
    border-color: var(--text-secondary);
  }

  select:focus {
    border-color: #007bff;
    box-shadow: 0 0 0 3px rgba(0, 123, 255, 0.15);
  }

  :global(.dark) select {
    background-image: url("data:image/svg+xml;charset=UTF-8,%3csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ccc' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3e%3cpolyline points='6 9 12 15 18 9'%3e%3c/polyline%3e%3c/svg%3e");
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

  .hotkey-recorder-container {
    display: flex;
    align-items: center;
    gap: 10px;
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

  /* Macro form & list table styles removed (unused) */

  .error-text {
    color: #ff453a;
    font-size: 12.5px;
    margin: 8px 0 0 0;
  }

  /* Convert Tool text areas layout */
  .editors-layout {
    display: flex;
    flex-direction: column;
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
    border-radius: 10px;
    object-fit: contain;
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

  /* Utility classes */
  .mt-5 { margin-top: 5px; }
  .mt-10 { margin-top: 10px; }
  .mt-15 { margin-top: 15px; }
  .mt-20 { margin-top: 20px; }
  .mb-15 { margin-bottom: 15px; }
  .mb-20 { margin-bottom: 20px; }
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

  /* Section divider inside cards */
  .section-divider {
    height: 1px;
    background: var(--border-color);
    margin: 18px 0 16px;
    opacity: 0.5;
  }

  /* Dict hint text */
  .dict-hint {
    font-size: 11px;
    margin: 4px 0 0;
    font-style: italic;
    opacity: 0.75;
  }

  /* Dict Editor styling */

  .dict-editor-container {
    display: flex;
    flex-direction: column;
    gap: 12px;
    margin-top: 15px;
    padding: 16px;
    background: linear-gradient(145deg, rgba(255, 255, 255, 0.04), rgba(0, 0, 0, 0.02));
    border: 1px solid var(--border-color);
    border-radius: 12px;
    box-shadow: inset 0 1px 1px rgba(255, 255, 255, 0.05), 0 2px 8px rgba(0, 0, 0, 0.02);
  }

  @media (prefers-color-scheme: light) {
    .dict-editor-container {
      background: linear-gradient(145deg, rgba(255, 255, 255, 0.8), rgba(240, 240, 245, 0.5));
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.04);
      border: 1px solid rgba(0,0,0,0.06);
    }
  }



  .dict-toolbar,
  .dict-add-row {
    display: flex;
    gap: 8px;
  }

  .dict-toolbar {
    flex-wrap: wrap;
  }

  .dict-toolbar > input,
  .dict-add-row {
    flex: 1 1 220px;
  }

  .dict-add-row input {
    flex: 1;
  }

  .dict-toolbar input {
    min-width: 0;
    padding: 8px 10px;
    background-color: var(--bg-input);
    color: var(--text-primary);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    outline: none;
    font-size: 13px;
    box-sizing: border-box;
  }

  .spell-section {
    padding: 6px 0;
  }

  .spell-sub-section {
    margin-top: 10px;
    margin-left: 10px;
    padding-left: 20px;
    border-left: 2px dashed var(--border-color);
  }

  .toggle-container.sub-toggle {
    margin-bottom: 0;
    font-size: 13px;
    color: var(--text-secondary);
  }

  .dict-section-divider {
    height: 1px;
    background: var(--border-color);
    margin: 15px 0;
    opacity: 0.6;
  }

  .dict-grid-container {
    max-height: 240px;
    overflow-y: auto;
    background: rgba(0, 0, 0, 0.15);
    border: 1px solid rgba(0, 0, 0, 0.1);
    border-radius: 10px;
    box-shadow: inset 0 2px 6px rgba(0,0,0,0.1);
    margin-top: 10px;
  }

  @media (prefers-color-scheme: light) {
    .dict-grid-container {
      background: rgba(250, 250, 253, 0.8);
      border: 1px solid rgba(0, 0, 0, 0.05);
      box-shadow: inset 0 2px 6px rgba(0,0,0,0.03);
    }
  }

  .dict-words-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 8px;
    padding: 12px;
  }

  @media (max-width: 600px) {
    .dict-words-grid {
      grid-template-columns: repeat(2, 1fr);
    }
  }

  .dict-word-badge {
    display: flex;
    align-items: center;
    justify-content: space-between;
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    padding: 6px 10px;
    font-size: 13px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    transition: transform 0.15s ease, border-color 0.15s ease, box-shadow 0.15s ease;
  }

  .dict-word-badge:hover {
    transform: translateY(-1px);
    border-color: var(--color-accent);
    box-shadow: 0 3px 6px rgba(0,0,0,0.15);
  }

  .dict-word-badge .word-text {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    margin-right: 4px;
  }

  .btn-delete-x {
    background: none;
    border: none;
    color: var(--text-secondary);
    cursor: pointer;
    font-size: 16px;
    font-weight: bold;
    line-height: 1;
    padding: 2px 6px;
    border-radius: 4px;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: color 0.15s ease, background-color 0.15s ease;
  }

  .btn-delete-x:hover {
    color: #ff453a;
    background-color: rgba(255, 69, 58, 0.1);
  }

  .dict-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-top: 8px;
    padding: 0 4px;
  }

  .dict-count-muted {
    font-size: 11px;
    color: var(--text-secondary);
    opacity: 0.65;
  }

  .dict-empty {
    padding: 18px;
    text-align: center;
    color: var(--text-secondary);
    font-size: 12px;
  }

  .form-error {
    margin: 0;
    color: #ff453a;
    font-size: 12px;
  }



  .save-status {
    font-size: 12px;
    font-weight: 500;
    transition: opacity 0.3s ease;
  }

  .save-status.success {
    color: var(--color-success);
  }

  :global(.custom-floating-tooltip) {
    position: absolute;
    z-index: 9999;
    padding: 12px 16px;
    border-radius: 10px;
    background: rgba(28, 28, 30, 0.95);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    border: 1px solid rgba(255, 255, 255, 0.1);
    color: #e5e5e7;
    font-size: 13.5px;
    line-height: 1.5;
    max-width: 360px;
    white-space: normal;
    pointer-events: none;
    opacity: 0;
    transform: translateY(4px);
    transition: opacity 0.15s cubic-bezier(0.4, 0, 0.2, 1), transform 0.15s cubic-bezier(0.4, 0, 0.2, 1);
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.3);
  }

  :global(.light .custom-floating-tooltip) {
    background: rgba(255, 255, 255, 0.95);
    border: 1px solid rgba(0, 0, 0, 0.1);
    color: #1c1c1e;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.15);
  }

  :global(.custom-floating-tooltip.visible) {
    opacity: 1;
    transform: translateY(0);
  }

  :global(.custom-floating-tooltip kbd) {
    background: rgba(255, 255, 255, 0.15);
    border: 1px solid rgba(255, 255, 255, 0.25);
    border-radius: 4px;
    padding: 2px 5px;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 12px;
    color: #fff;
    box-shadow: 0 1px 0 rgba(0, 0, 0, 0.2);
  }

  :global(.light .custom-floating-tooltip kbd) {
    background: rgba(0, 0, 0, 0.06);
    border: 1px solid rgba(0, 0, 0, 0.15);
    color: #1c1c1e;
    box-shadow: 0 1px 0 rgba(0, 0, 0, 0.1);
  }

  :global(.custom-floating-tooltip strong) {
    color: var(--color-accent);
    display: inline-block;
    font-size: 15px;
    margin-bottom: 6px;
  }

  .help-tooltip {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 15px;
    height: 15px;
    margin-left: 5px;
    border: 1px solid var(--text-secondary);
    border-radius: 50%;
    color: var(--text-secondary);
    font-size: 10px;
    font-weight: 700;
    cursor: help;
    vertical-align: 1px;
  }

  .sub-tabs-container {
    display: flex;
    gap: 8px;
    background: rgba(0, 0, 0, 0.05);
    padding: 4px;
    border-radius: 10px;
  }

  :global(.dark) .sub-tabs-container {
    background: rgba(0, 0, 0, 0.25);
  }

  .sub-tab-item {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 8px 12px;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    font-size: 13.5px;
    font-weight: 500;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.2s ease;
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }

  .sub-tab-item:hover {
    color: var(--text-primary);
    background: rgba(0, 0, 0, 0.03);
  }

  :global(.dark) .sub-tab-item:hover {
    background: rgba(255, 255, 255, 0.04);
  }

  .sub-tab-item.active {
    background: var(--bg-input);
    color: var(--color-accent);
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08), 0 1px 2px rgba(0, 0, 0, 0.04);
  }

  :global(.dark) .sub-tab-item.active {
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2), 0 1px 2px rgba(0, 0, 0, 0.1);
  }

  .modal-overlay {
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(0, 0, 0, 0.5);
    backdrop-filter: blur(6px);
    -webkit-backdrop-filter: blur(6px);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
  }

  .modal-content {
    background: var(--bg-card);
    border-radius: 12px;
    padding: 24px;
    max-width: 440px;
    width: 90%;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.25);
  }

  .modal-content h3 {
    margin: 0 0 12px 0;
    font-size: 16px;
  }

  .modal-content p {
    margin: 0 0 12px 0;
    font-size: 13px;
    color: var(--text-secondary);
    line-height: 1.5;
  }

  .modal-content ul {
    margin: 0 0 20px 0;
    padding-left: 20px;
    font-size: 13px;
    color: var(--text-secondary);
    line-height: 1.8;
  }

  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: 10px;
  }



  .fsm-order-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-top: 10px;
    touch-action: none;       /* prevent browser scroll interference during drag */
    user-select: none;
  }

  .fsm-order-list.fsm-list-dragging {
    cursor: grabbing;
  }

  .fsm-order-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 14px;
    background: linear-gradient(135deg, rgba(255,255,255,0.05), rgba(0,0,0,0.03));
    border: 1px solid var(--border-color);
    border-radius: 10px;
    cursor: grab;
    user-select: none;
    transition: background 0.15s ease, border-color 0.15s ease, transform 0.12s ease, box-shadow 0.15s ease;
    position: relative;
  }

  .fsm-order-item:hover {
    background: linear-gradient(135deg, rgba(var(--accent-rgb, 99,102,241),0.08), rgba(var(--accent-rgb, 99,102,241),0.03));
    border-color: var(--color-accent);
    box-shadow: 0 2px 12px rgba(0,0,0,0.08);
  }

  /* Added via class:fsm-dragging Svelte directive */
  .fsm-order-item.fsm-dragging {
    opacity: 0.45;
    cursor: grabbing;
    transform: scale(0.97);
    box-shadow: none;
  }

  .fsm-order-item.drag-over {
    border-color: var(--color-accent);
    border-style: dashed;
    background: linear-gradient(135deg, rgba(var(--accent-rgb, 99,102,241),0.12), rgba(var(--accent-rgb, 99,102,241),0.05));
    transform: translateY(-2px);
    box-shadow: 0 4px 16px rgba(var(--accent-rgb, 99,102,241), 0.15);
  }

  .fsm-order-drag-handle {
    font-size: 18px;
    color: var(--text-secondary);
    opacity: 0.5;
    flex-shrink: 0;
    cursor: grab;
  }

  .fsm-order-rank {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: var(--color-accent);
    color: white;
    font-size: 11px;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .fsm-order-emoji {
    font-size: 20px;
    flex-shrink: 0;
    line-height: 1;
  }

  .fsm-order-info {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .fsm-order-name {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .fsm-order-desc {
    font-size: 11px;
    color: var(--text-secondary);
    opacity: 0.75;
  }

  .fsm-order-badge {
    flex-shrink: 0;
    font-size: 10px;
    font-weight: 600;
    padding: 2px 8px;
    border-radius: 20px;
    letter-spacing: 0.3px;
  }

  .fsm-order-badge.badge-on {
    background: rgba(34, 197, 94, 0.15);
    color: #22c55e;
    border: 1px solid rgba(34, 197, 94, 0.3);
  }

  .fsm-order-badge.badge-off {
    background: rgba(156, 163, 175, 0.12);
    color: var(--text-secondary);
    border: 1px solid var(--border-color);
  }

  @media (prefers-color-scheme: light) {
    .fsm-order-item {
      background: rgba(255, 255, 255, 0.8);
      box-shadow: 0 1px 4px rgba(0,0,0,0.05);
    }
    .fsm-order-item:hover {
      background: rgba(99,102,241,0.05);
    }
    .fsm-order-item.drag-over {
      background: rgba(99,102,241,0.08);
    }
  }

  .app-fsm-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
    margin-top: 8px;
  }

  .app-fsm-item {
    display: flex;
    align-items: center;
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    padding: 8px 12px;
    font-size: 13px;
    box-shadow: 0 1px 2px rgba(0,0,0,0.05);
  }

  .app-fsm-rank {
    font-size: 11px;
    font-weight: bold;
    color: var(--text-secondary);
    opacity: 0.6;
    width: 14px;
    margin-right: 8px;
  }

  .app-fsm-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    margin-right: 8px;
  }

  .app-fsm-name {
    font-weight: 500;
    flex-grow: 1;
  }

  .app-fsm-drag-handle {
    cursor: grab;
    color: var(--text-secondary);
    opacity: 0.5;
    margin-right: 8px;
    font-size: 14px;
    user-select: none;
    -webkit-user-select: none;
  }

  .app-fsm-drag-handle:active {
    cursor: grabbing;
  }

  .app-fsm-item.fsm-dragging {
    opacity: 0.4;
    border-color: var(--color-accent);
    box-shadow: 0 4px 10px rgba(0,0,0,0.15);
  }

  .app-fsm-item.drag-over {
    border-color: var(--color-accent);
    background: rgba(99,102,241,0.05);
  }

  .app-fsm-badge {
    flex-shrink: 0;
    font-size: 10px;
    font-weight: 600;
    padding: 2px 7px;
    border-radius: 12px;
    letter-spacing: 0.2px;
  }

  .app-fsm-badge.badge-on {
    background: rgba(34, 197, 94, 0.15);
    color: #22c55e;
    border: 1px solid rgba(34, 197, 94, 0.3);
  }

  .app-fsm-badge.badge-off {
    background: rgba(156, 163, 175, 0.12);
    color: var(--text-secondary);
    border: 1px solid var(--border-color);
  }
</style>
