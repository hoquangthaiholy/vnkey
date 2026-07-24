<script setup>
import { ref, onMounted, onUnmounted } from "vue";
import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { register, unregisterAll } from "@tauri-apps/plugin-global-shortcut";
import { listen } from "@tauri-apps/api/event";
import Tooltip from "./components/Tooltip.vue";

// System Dark/Light mode detection
const isDarkMode = ref(true);
let mediaQuery = null;

function updateSystemTheme(e) {
  if (e && typeof e.matches === 'boolean') {
    isDarkMode.value = e.matches;
  } else {
    isDarkMode.value = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
  }
}

// Window Drag Handler
async function startWindowDrag(e) {
  if (e.button === 0 && !e.target.closest('button, select, input, a')) {
    try {
      const appWindow = getCurrentWindow();
      await appWindow.startDragging();
    } catch (err) {
      console.error("Window drag error:", err);
    }
  }
}

// Active Navigation item: 'typing' | 'accessibility' | 'system' | 'info'
const activeTab = ref("typing");

// Settings state
const method = ref("Telex");
const toneStyle = ref("Modern");
const spellingCheck = ref(true);
const charset = ref("Unicode");
const shortcut = ref("Cmd + Shift + Space");
const autostart = ref(false);
const openOnStartup = ref(false);
const perAppLanguage = ref(false);

// Interactive Hotkey Recorder State
const isRecordingShortcut = ref(false);

function formatKeyName(key, code) {
  if (key === " " || code === "Space") return "Space";
  if (key === "Meta" || key === "Command") return "Cmd";
  if (key === "Alt") return "Option";
  if (key === "Control") return "Ctrl";
  if (key === "Shift") return "Shift";
  if (code && code.startsWith("Key")) return code.replace("Key", "");
  if (code && code.startsWith("Digit")) return code.replace("Digit", "");
  return key.length === 1 ? key.toUpperCase() : key;
}

function handleShortcutKeydown(e) {
  if (!isRecordingShortcut.value) return;
  e.preventDefault();
  e.stopPropagation();

  if (e.key === "Escape") {
    shortcut.value = "";
    isRecordingShortcut.value = false;
    saveSettings();
    return;
  }

  const isModifierOnly = ["Meta", "Control", "Alt", "Shift", "Command"].includes(e.key);

  const keys = [];
  if (e.metaKey) keys.push("Cmd");
  if (e.ctrlKey) keys.push("Ctrl");
  if (e.altKey) keys.push("Option");
  if (e.shiftKey) keys.push("Shift");

  if (!isModifierOnly) {
    const keyName = formatKeyName(e.key, e.code);
    if (!keys.includes(keyName)) {
      keys.push(keyName);
    }
  }

  if (keys.length > 0) {
    shortcut.value = keys.join(" + ");
  }

  if (!isModifierOnly && keys.length > 0) {
    isRecordingShortcut.value = false;
    saveSettings();
  }
}

// Accessibility state
const isMac = ref(true);
const hasAccess = ref(false);

// UI Helper state
const saving = ref(false);
const statusMsg = ref("");
const updateStatus = ref("");
const isCheckingUpdate = ref(false);

// Dynamic Accessibility Whitelisted Apps State
const accessibilityApps = ref([]);
const runningAppsModalOpen = ref(false);
const runningAppsList = ref([]);
const isLoadingRunningApps = ref(false);

const availableCharsets = [
  { id: 'Unicode', name: 'Unicode (Mặc định)', desc: 'UTF-8 / Precomposed' },
  { id: 'TCVN3', name: 'TCVN3 (ABC)', desc: '.VNTime, .VNTimeH' },
  { id: 'VNI', name: 'VNI Windows', desc: 'VNI-Times, VNI-Helve' },
  { id: 'UnicodeComposite', name: 'Unicode Tổ hợp', desc: 'Decomposed Unicode' },
  { id: 'VIQR', name: 'VIQR', desc: 'Vietnamese Quoted-Readable' }
];

async function setupGlobalShortcut(scKey) {
  try {
    await unregisterAll();
    const keyToRegister = scKey || shortcut.value;
    if (!keyToRegister) return;

    let shortcutString = keyToRegister
      .replace(/Cmd/g, "CommandOrControl")
      .replace(/Option/g, "Alt")
      .replace(/\s+\+\s+/g, "+");

    await register(shortcutString, async (event) => {
      if (event.state === "Pressed" && !isRecordingShortcut.value) {
        method.value = (method.value === "Off" ? "Telex" : "Off");
        await saveSettings();
      }
    });
  } catch (err) {
    console.warn("Global shortcut register note:", err);
  }
}

async function checkAccess() {
  try {
    const access = await invoke("has_accessibility");
    hasAccess.value = access;
  } catch (err) {
    console.error("Failed to check accessibility:", err);
  }
}

async function requestAccess() {
  try {
    await invoke("request_accessibility");
    const interval = setInterval(async () => {
      const access = await invoke("has_accessibility");
      if (access) {
        hasAccess.value = true;
        clearInterval(interval);
      }
    }, 2000);
  } catch (err) {
    console.error("Failed to request accessibility:", err);
  }
}

async function fetchAppIcon(bundleId) {
  try {
    const icon = await invoke("get_app_icon_base64", { bundleId });
    return icon;
  } catch (e) {
    return null;
  }
}

// Default system preset applications (Read-only, non-removable)
const defaultPresetApps = [
  { bundle: 'com.apple.Terminal', name: 'Terminal / iTerm2', category: 'Hệ thống', isDefault: true },
  { bundle: 'com.microsoft.VSCode', name: 'Visual Studio Code', category: 'Lập trình', isDefault: true },
  { bundle: 'com.google.Chrome', name: 'Google Chrome', category: 'Trình duyệt', isDefault: true },
  { bundle: 'com.apple.Safari', name: 'Safari', category: 'Trình duyệt', isDefault: true },
  { bundle: 'com.tinyspeck.slackmacgap', name: 'Slack', category: 'Trò chuyện', isDefault: true },
  { bundle: 'com.vng.zalo', name: 'Zalo', category: 'Trò chuyện', isDefault: true },
  { bundle: 'com.microsoft.Word', name: 'Microsoft Word', category: 'Soạn thảo', isDefault: true },
  { bundle: 'com.microsoft.Outlook', name: 'Microsoft Outlook', category: 'Email', isDefault: true },
  { bundle: 'com.apple.Notes', name: 'Notes / Pages', category: 'Soạn thảo', isDefault: true },
  { bundle: 'com.figma.Desktop', name: 'Figma', category: 'Thiết kế', isDefault: true },
];

async function loadSettings() {
  try {
    const settings = await invoke("get_settings");
    if (settings) {
      method.value = settings.method || "Telex";
      toneStyle.value = settings.tone_style || "Modern";
      spellingCheck.value = settings.spelling_check ?? true;
      charset.value = settings.charset || "Unicode";
      shortcut.value = settings.shortcut || "Cmd + Shift + Space";
      autostart.value = settings.autostart ?? false;
      openOnStartup.value = settings.open_on_startup ?? false;
      perAppLanguage.value = settings.per_app_language ?? false;

      const userBundles = settings.accessibility_apps || [];
      const mergedApps = [];

      // If userBundles is empty on first launch, enable all default preset apps
      const isFirstLaunch = !settings.accessibility_apps || settings.accessibility_apps.length === 0;

      // Add default preset apps first
      for (const preset of defaultPresetApps) {
        const icon_base64 = await fetchAppIcon(preset.bundle);
        const isEnabled = isFirstLaunch ? true : userBundles.includes(preset.bundle);
        mergedApps.push({
          ...preset,
          enabled: isEnabled,
          icon_base64
        });
      }

      // Add custom user-added apps
      for (const bundleId of userBundles) {
        if (!mergedApps.some(a => a.bundle === bundleId)) {
          const parts = bundleId.split('.');
          const lastPart = parts[parts.length - 1] || bundleId;
          const name = lastPart.charAt(0).toUpperCase() + lastPart.slice(1);
          const icon_base64 = await fetchAppIcon(bundleId);
          mergedApps.push({
            bundle: bundleId,
            name,
            enabled: true,
            icon_base64,
            isDefault: false
          });
        }
      }

      accessibilityApps.value = mergedApps;
      setupGlobalShortcut(shortcut.value);
    }
  } catch (err) {
    console.error("Failed to load settings:", err);
  }
}

async function saveSettings() {
  saving.value = true;
  statusMsg.value = "";
  try {
    const bundleList = accessibilityApps.value.filter(app => app.enabled).map(app => app.bundle);
    await invoke("update_settings", {
      newSettings: {
        method: method.value,
        tone_style: toneStyle.value,
        spelling_check: spellingCheck.value,
        charset: charset.value,
        shortcut: shortcut.value,
        autostart: autostart.value,
        open_on_startup: openOnStartup.value,
        per_app_language: perAppLanguage.value,
        accessibility_apps: bundleList
      }
    });
    statusMsg.value = "Đã tự động lưu Cài đặt";
    setupGlobalShortcut(shortcut.value);
    setTimeout(() => {
      statusMsg.value = "";
    }, 2000);
  } catch (err) {
    statusMsg.value = "Lỗi khi lưu cài đặt!";
    console.error(err);
  } finally {
    saving.value = false;
  }
}

async function openRunningAppsModal() {
  runningAppsModalOpen.value = true;
  isLoadingRunningApps.value = true;
  try {
    const apps = await invoke("get_running_apps");
    runningAppsList.value = (apps || []).map(app => ({
      ...app,
      icon_base64: null
    }));
    isLoadingRunningApps.value = false;

    // Async background fetch of icons for each app without blocking modal render
    for (const app of runningAppsList.value) {
      fetchAppIcon(app.bundle_id).then(icon => {
        if (icon) {
          app.icon_base64 = icon;
        }
      });
    }
  } catch (e) {
    console.error("Failed to load running apps:", e);
    isLoadingRunningApps.value = false;
  }
}

function addAppToAccessibility(app) {
  if (!accessibilityApps.value.some(a => a.bundle === app.bundle_id)) {
    accessibilityApps.value.push({
      bundle: app.bundle_id,
      name: app.name,
      icon_base64: app.icon_base64
    });
    saveSettings();
  }
}

function removeAppFromAccessibility(bundleId) {
  accessibilityApps.value = accessibilityApps.value.filter(a => a.bundle !== bundleId);
  saveSettings();
}

function checkUpdates() {
  isCheckingUpdate.value = true;
  updateStatus.value = "";
  setTimeout(() => {
    isCheckingUpdate.value = false;
    updateStatus.value = "VNKey v0.1.0 — Đang sử dụng phiên bản mới nhất!";
  }, 1200);
}

let unlistenSettings = null;

onMounted(async () => {
  isMac.value = navigator.userAgent.includes("Macintosh") || navigator.platform.includes("Mac");
  loadSettings();
  if (isMac.value) {
    checkAccess();
  }

  // Set up System Dark/Light listener
  updateSystemTheme();
  mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
  if (mediaQuery?.addEventListener) {
    mediaQuery.addEventListener('change', updateSystemTheme);
  }

  try {
    unlistenSettings = await listen("settings-changed", (event) => {
      if (event.payload) {
        method.value = event.payload.method || "Telex";
        shortcut.value = event.payload.shortcut || "Cmd + Shift + Space";
      }
    });
  } catch (e) {}
});

onUnmounted(() => {
  if (mediaQuery?.removeEventListener) {
    mediaQuery.removeEventListener('change', updateSystemTheme);
  }
  if (unlistenSettings) {
    unlistenSettings();
  }
});
</script>

<template>
  <div 
    class="relative h-screen w-screen flex overflow-hidden font-sans select-none transition-colors duration-200"
    :class="isDarkMode 
      ? 'bg-[#090d16] text-slate-100' 
      : 'bg-slate-50 text-slate-800'"
  >
    <!-- LEFT SIDEBAR NAVIGATION (Top padding pt-9 for native floating macOS traffic lights) -->
    <aside 
      class="w-44 shrink-0 flex flex-col justify-between p-3 pt-9 border-r transition-colors"
      :class="isDarkMode 
        ? 'bg-[#05080e] border-[#1a202c]' 
        : 'bg-slate-100/90 border-slate-200'"
    >
      <div class="space-y-4">
        
        <!-- App Branding & Drag Handle -->
        <div 
          @mousedown="startWindowDrag"
          data-tauri-drag-region
          class="flex items-center space-x-2.5 px-2 pt-1 cursor-grab active:cursor-grabbing rounded-lg py-1 transition-colors hover:bg-slate-800/20"
        >
          <div class="w-7 h-7 rounded-lg bg-blue-600 flex items-center justify-center text-white font-extrabold text-xs shadow-xs shrink-0 pointer-events-none">
            VN
          </div>
          <div data-tauri-drag-region class="flex flex-col pointer-events-none">
            <h1 class="text-xs font-bold tracking-tight" :class="isDarkMode ? 'text-white' : 'text-slate-900'">
              VNKey
            </h1>
            <span class="text-[10px] text-blue-500 font-medium">Bảng điều khiển</span>
          </div>
        </div>

        <!-- Navigation Menu -->
        <nav class="space-y-1">
          
          <!-- 1. Gõ phím -->
          <button
            @click="activeTab = 'typing'"
            class="w-full flex items-center space-x-2.5 px-2.5 py-1.5 rounded-lg text-[12px] font-medium transition-colors text-left cursor-pointer"
            :class="activeTab === 'typing' 
              ? (isDarkMode 
                  ? 'bg-blue-600/15 text-blue-400 font-semibold border border-blue-500/30' 
                  : 'bg-blue-50 text-blue-700 font-semibold border border-blue-200')
              : (isDarkMode 
                  ? 'text-slate-400 hover:text-slate-200 hover:bg-[#0e131f]' 
                  : 'text-slate-600 hover:text-slate-900 hover:bg-slate-200/70')"
          >
            <svg class="w-4 h-4 shrink-0" :class="activeTab === 'typing' ? (isDarkMode ? 'text-blue-400' : 'text-blue-600') : 'text-slate-400'" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
              <rect x="2" y="4" width="20" height="16" rx="3" />
              <path stroke-linecap="round" d="M6 8h.01M10 8h.01M14 8h.01M18 8h.01M6 12h.01M10 12h.01M14 12h.01M18 12h.01M8 16h8" />
            </svg>
            <span class="truncate">Gõ phím</span>
          </button>

          <!-- 2. Trợ năng -->
          <button
            @click="activeTab = 'accessibility'"
            class="w-full flex items-center justify-between px-2.5 py-1.5 rounded-lg text-[12px] font-medium transition-colors text-left cursor-pointer"
            :class="activeTab === 'accessibility' 
              ? (isDarkMode 
                  ? 'bg-blue-600/15 text-blue-400 font-semibold border border-blue-500/30' 
                  : 'bg-blue-50 text-blue-700 font-semibold border border-blue-200')
              : (isDarkMode 
                  ? 'text-slate-400 hover:text-slate-200 hover:bg-[#0e131f]' 
                  : 'text-slate-600 hover:text-slate-900 hover:bg-slate-200/70')"
          >
            <div class="flex items-center space-x-2.5 truncate">
              <svg class="w-4 h-4 shrink-0" :class="activeTab === 'accessibility' ? (isDarkMode ? 'text-blue-400' : 'text-blue-600') : 'text-slate-400'" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
                <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
              </svg>
              <span class="truncate">Trợ năng</span>
            </div>
            <span v-if="isMac && !hasAccess" class="w-2 h-2 bg-amber-500 rounded-full shrink-0"></span>
          </button>

          <!-- 3. Hệ thống -->
          <button
            @click="activeTab = 'system'"
            class="w-full flex items-center space-x-2.5 px-2.5 py-1.5 rounded-lg text-[12px] font-medium transition-colors text-left cursor-pointer"
            :class="activeTab === 'system' 
              ? (isDarkMode 
                  ? 'bg-blue-600/15 text-blue-400 font-semibold border border-blue-500/30' 
                  : 'bg-blue-50 text-blue-700 font-semibold border border-blue-200')
              : (isDarkMode 
                  ? 'text-slate-400 hover:text-slate-200 hover:bg-[#0e131f]' 
                  : 'text-slate-600 hover:text-slate-900 hover:bg-slate-200/70')"
          >
            <svg class="w-4 h-4 shrink-0" :class="activeTab === 'system' ? (isDarkMode ? 'text-blue-400' : 'text-blue-600') : 'text-slate-400'" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
              <path stroke-linecap="round" stroke-linejoin="round" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4" />
            </svg>
            <span class="truncate">Hệ thống</span>
          </button>

          <!-- 4. Thông tin -->
          <button
            @click="activeTab = 'info'"
            class="w-full flex items-center space-x-2.5 px-2.5 py-1.5 rounded-lg text-[12px] font-medium transition-colors text-left cursor-pointer"
            :class="activeTab === 'info' 
              ? (isDarkMode 
                  ? 'bg-blue-600/15 text-blue-400 font-semibold border border-blue-500/30' 
                  : 'bg-blue-50 text-blue-700 font-semibold border border-blue-200')
              : (isDarkMode 
                  ? 'text-slate-400 hover:text-slate-200 hover:bg-[#0e131f]' 
                  : 'text-slate-600 hover:text-slate-900 hover:bg-slate-200/70')"
          >
            <svg class="w-4 h-4 shrink-0" :class="activeTab === 'info' ? (isDarkMode ? 'text-blue-400' : 'text-blue-600') : 'text-slate-400'" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">
              <circle cx="12" cy="12" r="9" />
              <path stroke-linecap="round" d="M12 16v-4m0-4h.01" />
            </svg>
            <span class="truncate">Thông tin</span>
          </button>

        </nav>
      </div>

      <!-- Master Enable/Disable Toggle Card in Sidebar Bottom -->
      <div 
        class="p-2.5 rounded-lg border flex items-center justify-between transition-colors"
        :class="isDarkMode 
          ? 'bg-[#0e131f] border-[#1e2638]' 
          : 'bg-white border-slate-200 shadow-xs'"
      >
        <div class="flex flex-col">
          <span class="text-[11px] font-semibold" :class="isDarkMode ? 'text-slate-300' : 'text-slate-700'">Bộ gõ</span>
          <span class="text-[9px] font-bold uppercase tracking-wider" :class="method !== 'Off' ? 'text-blue-500' : 'text-slate-400'">
            {{ method !== 'Off' ? 'Đang bật' : 'Tắt' }}
          </span>
        </div>
        
        <!-- PIXEL PERFECT TOGGLE SWITCH -->
        <button 
          @click="method = (method === 'Off' ? 'Telex' : 'Off'); saveSettings()"
          class="relative inline-flex h-5 w-9 p-0.5 items-center cursor-pointer rounded-full border border-transparent transition-colors duration-200 ease-in-out focus:outline-none"
          :class="method !== 'Off' ? 'bg-blue-600' : (isDarkMode ? 'bg-[#1e2638]' : 'bg-slate-300')"
        >
          <span 
            class="pointer-events-none inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow-xs transition-transform duration-200 ease-in-out"
            :class="method !== 'Off' ? 'translate-x-4' : 'translate-x-0'"
          ></span>
        </button>
      </div>

    </aside>

    <!-- RIGHT CONTENT AREA WITH TOP FADING OVERLAY EXTENDED TO TOP EDGE -->
    <main class="relative flex-1 flex flex-col h-full overflow-hidden z-10">
      
      <!-- TOP FADING EFFECT OVERLAY AT VERY TOP EDGE (h-9 / 36px) -->
      <div 
        @mousedown="startWindowDrag"
        data-tauri-drag-region
        class="pointer-events-none absolute top-0 left-0 right-0 h-9 z-20 transition-colors"
        :class="isDarkMode 
          ? 'bg-gradient-to-b from-[#090d16] via-[#090d16]/80 to-transparent' 
          : 'bg-gradient-to-b from-slate-50 via-slate-50/80 to-transparent'"
      ></div>

      <!-- RIGHT SCROLLABLE CONTENT PANE WITH TOP PADDING pt-8 FOR INITIAL ALIGNMENT -->
      <div class="flex-1 overflow-y-auto px-5 py-4 pt-8 custom-scrollbar">
        
        <!-- ==================== TAB 1: GÕ PHÍM ==================== -->
        <div v-if="activeTab === 'typing'" class="space-y-4 animate-fadeIn">

          <!-- Kiểu gõ (Telex / VNI) -->
          <div class="space-y-1.5">
            <div class="flex items-center space-x-1.5">
              <label class="text-[11px] font-semibold uppercase tracking-wider" :class="isDarkMode ? 'text-slate-400' : 'text-slate-500'">Kiểu gõ tiếng Việt</label>
              <!-- ESSENTIAL TOOLTIP #1: Telex vs VNI -->
              <Tooltip text="Telex: Gõ chữ bỏ dấu (s, f, r, x, j, aa). VNI: Gõ phím số bỏ dấu (1, 2, 3...)." position="bottom" :is-dark-mode="isDarkMode" />
            </div>
            <div class="grid grid-cols-2 gap-3">
              <button 
                @click="method = 'Telex'; saveSettings()"
                class="flex items-center justify-between p-3 rounded-lg border transition-all cursor-pointer"
                :class="method === 'Telex' 
                  ? (isDarkMode ? 'bg-blue-600/10 border-blue-500/80 text-white' : 'bg-blue-50/80 border-blue-500 text-slate-900 font-medium') 
                  : (isDarkMode ? 'bg-[#0e131f] border-[#1e2638] text-slate-400 hover:border-slate-700' : 'bg-white border-slate-200 text-slate-600 hover:border-slate-300')"
              >
                <span class="font-bold text-xs" :class="isDarkMode ? 'text-slate-100' : 'text-slate-800'">Telex</span>
                <span v-if="method === 'Telex'" class="w-2 h-2 rounded-full bg-blue-600"></span>
              </button>

              <button 
                @click="method = 'Vni'; saveSettings()"
                class="flex items-center justify-between p-3 rounded-lg border transition-all cursor-pointer"
                :class="method === 'Vni' 
                  ? (isDarkMode ? 'bg-blue-600/10 border-blue-500/80 text-white' : 'bg-blue-50/80 border-blue-500 text-slate-900 font-medium') 
                  : (isDarkMode ? 'bg-[#0e131f] border-[#1e2638] text-slate-400 hover:border-slate-700' : 'bg-white border-slate-200 text-slate-600 hover:border-slate-300')"
              >
                <span class="font-bold text-xs" :class="isDarkMode ? 'text-slate-100' : 'text-slate-800'">VNI</span>
                <span v-if="method === 'Vni'" class="w-2 h-2 rounded-full bg-blue-600"></span>
              </button>
            </div>
          </div>

          <!-- Bảng mã & Vị trí đặt dấu -->
          <div class="grid grid-cols-2 gap-3">
            <!-- Bảng mã -->
            <div class="space-y-1.5">
              <label class="text-[11px] font-semibold uppercase tracking-wider" :class="isDarkMode ? 'text-slate-400' : 'text-slate-500'">Bảng mã</label>
              <div class="relative">
                <select 
                  v-model="charset"
                  @change="saveSettings"
                  class="w-full border rounded-lg px-3 py-2 text-xs font-semibold focus:outline-none focus:border-blue-500 transition-colors appearance-none cursor-pointer pr-8"
                  :class="isDarkMode ? 'bg-[#0e131f] border-[#1e2638] text-slate-200' : 'bg-white border-slate-200 text-slate-800'"
                >
                  <option v-for="cs in availableCharsets" :key="cs.id" :value="cs.id" :class="isDarkMode ? 'bg-[#0e131f] text-white' : 'bg-white text-slate-800'">
                    {{ cs.name }}
                  </option>
                </select>
                <div class="absolute right-3 top-2.5 pointer-events-none text-slate-400">
                  <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
                  </svg>
                </div>
              </div>
            </div>

            <!-- Quy tắc đặt dấu -->
            <div class="space-y-1.5">
              <div class="flex items-center space-x-1.5">
                <label class="text-[11px] font-semibold uppercase tracking-wider" :class="isDarkMode ? 'text-slate-400' : 'text-slate-500'">Vị trí đặt dấu</label>
                <!-- ESSENTIAL TOOLTIP #2: Modern vs Classic tone placement -->
                <Tooltip text="Hiện đại: đặt dấu ở nguyên âm thứ hai (hòa). Cổ điển: đặt dấu ở nguyên âm thứ nhất (hoà)." position="bottom" :is-dark-mode="isDarkMode" />
              </div>
              <div class="flex p-1 border rounded-lg" :class="isDarkMode ? 'bg-[#0e131f] border-[#1e2638]' : 'bg-slate-200/60 border-slate-200'">
                <button 
                  @click="toneStyle = 'Modern'; saveSettings()"
                  class="flex-1 py-1 text-center rounded-md text-xs font-semibold transition-colors cursor-pointer"
                  :class="toneStyle === 'Modern' 
                    ? (isDarkMode ? 'bg-[#1a2233] text-white shadow-xs' : 'bg-white text-slate-900 shadow-xs') 
                    : (isDarkMode ? 'text-slate-400 hover:text-slate-200' : 'text-slate-600 hover:text-slate-900')"
                >
                  Hiện đại (hòa)
                </button>
                <button 
                  @click="toneStyle = 'Classic'; saveSettings()"
                  class="flex-1 py-1 text-center rounded-md text-xs font-semibold transition-colors cursor-pointer"
                  :class="toneStyle === 'Classic' 
                    ? (isDarkMode ? 'bg-[#1a2233] text-white shadow-xs' : 'bg-white text-slate-900 shadow-xs') 
                    : (isDarkMode ? 'text-slate-400 hover:text-slate-200' : 'text-slate-600 hover:text-slate-900')"
                >
                  Cổ điển (hoà)
                </button>
              </div>
            </div>
          </div>

          <!-- Kiểm tra chính tả -->
          <div 
            class="p-3 border rounded-lg flex items-center justify-between"
            :class="isDarkMode ? 'bg-[#0e131f] border-[#1e2638]' : 'bg-white border-slate-200 shadow-xs'"
          >
            <span class="text-[13px] font-medium" :class="isDarkMode ? 'text-slate-200' : 'text-slate-800'">Kiểm tra chính tả</span>

            <!-- PIXEL PERFECT TOGGLE SWITCH -->
            <button 
              @click="spellingCheck = !spellingCheck; saveSettings()"
              class="relative inline-flex h-5 w-9 p-0.5 items-center cursor-pointer rounded-full border border-transparent transition-colors duration-200 ease-in-out focus:outline-none"
              :class="spellingCheck ? 'bg-blue-600' : (isDarkMode ? 'bg-[#1e2638]' : 'bg-slate-300')"
            >
              <span 
                class="pointer-events-none inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow-xs transition-transform duration-200 ease-in-out"
                :class="spellingCheck ? 'translate-x-4' : 'translate-x-0'"
              ></span>
            </button>
          </div>

          <!-- Phím tắt chuyển đổi ngôn ngữ (INTERACTIVE INPUT BOX RECORDING) -->
          <div 
            class="p-3 border rounded-lg space-y-2"
            :class="isDarkMode ? 'bg-[#0e131f] border-[#1e2638]' : 'bg-white border-slate-200 shadow-xs'"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-1.5">
                <span class="text-[13px] font-medium" :class="isDarkMode ? 'text-slate-200' : 'text-slate-800'">Phím tắt chuyển đổi</span>
                <!-- ESSENTIAL TOOLTIP #3: Hotkey recording instructions -->
                <Tooltip text="Bấm ô bên dưới để gõ tổ hợp phím mới. Bấm Esc để xóa phím tắt." position="bottom" :is-dark-mode="isDarkMode" />
              </div>
              <span v-if="isRecordingShortcut" class="text-[10px] text-blue-400 font-semibold animate-pulse">
                ● Đang nhận phím... (Bấm Esc để xóa)
              </span>
            </div>
            
            <div 
              @click="isRecordingShortcut = true"
              tabindex="0"
              @keydown="handleShortcutKeydown"
              @blur="isRecordingShortcut = false"
              class="w-full px-3 py-2 rounded-lg border flex items-center justify-between cursor-pointer transition-all focus:outline-none"
              :class="isRecordingShortcut 
                ? 'border-blue-500 bg-blue-500/10 ring-2 ring-blue-500/20' 
                : (isDarkMode ? 'bg-[#090d16] border-[#1e2638] hover:border-slate-700' : 'bg-slate-50 border-slate-200 hover:border-slate-300')"
            >
              <div class="flex items-center space-x-1.5 min-h-[22px]">
                <template v-if="shortcut">
                  <span 
                    v-for="k in shortcut.split(' + ')" 
                    :key="k" 
                    class="px-2 py-0.5 rounded text-xs font-mono font-bold border"
                    :class="isDarkMode ? 'bg-[#1a2233] border-[#252f45] text-blue-400' : 'bg-blue-50 border-blue-200 text-blue-700'"
                  >
                    {{ k === 'Cmd' ? '⌘' : k === 'Shift' ? '⇧' : k === 'Option' ? '⌥' : k }}
                  </span>
                </template>
                <span v-else class="text-xs text-slate-500 italic">Chưa đăng ký (Bấm phím để nhập)</span>
              </div>

              <button 
                v-if="shortcut" 
                @click.stop="shortcut = ''; saveSettings()" 
                class="text-xs text-slate-400 hover:text-red-400 p-1 font-bold"
                title="Xóa phím tắt (Esc)"
              >
                ✕
              </button>
            </div>
          </div>

        </div>

        <!-- ==================== TAB 2: TRỢ NĂNG (macOS) ==================== -->
        <div v-else-if="activeTab === 'accessibility'" class="space-y-4 animate-fadeIn">

          <!-- Access status card -->
          <div class="p-3 rounded-lg border flex flex-col space-y-2.5"
            :class="hasAccess 
              ? (isDarkMode ? 'bg-emerald-950/20 border-emerald-800/40' : 'bg-emerald-50/60 border-emerald-200') 
              : (isDarkMode ? 'bg-amber-950/20 border-amber-800/40' : 'bg-amber-50/60 border-amber-200')"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-3">
                <div class="w-7 h-7 rounded-md flex items-center justify-center shrink-0"
                  :class="hasAccess ? 'bg-emerald-500/20 text-emerald-500' : 'bg-amber-500/20 text-amber-500'"
                >
                  <svg v-if="hasAccess" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                  <svg v-else class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                  </svg>
                </div>

                <div class="flex flex-col">
                  <span class="text-[13px] font-semibold" :class="hasAccess ? (isDarkMode ? 'text-emerald-300' : 'text-emerald-900') : (isDarkMode ? 'text-amber-300' : 'text-amber-900')">
                    {{ hasAccess ? 'Trợ năng API đã kích hoạt' : 'Cần cấp quyền Trợ năng' }}
                  </span>
                  <span class="text-[11px] leading-tight" :class="hasAccess ? (isDarkMode ? 'text-emerald-400/80' : 'text-emerald-700') : (isDarkMode ? 'text-amber-400/80' : 'text-amber-700')">
                    {{ hasAccess ? 'VNKey có đủ quyền bắt sự kiện bàn phím.' : 'Bật Trợ năng để VNKey ghi nhận và gõ tiếng Việt.' }}
                  </span>
                </div>
              </div>

              <button 
                @click="requestAccess"
                class="px-3 py-1.5 text-xs font-semibold rounded-md transition-colors border shrink-0 cursor-pointer"
                :class="hasAccess 
                  ? 'bg-emerald-500/20 text-emerald-600 border-emerald-500/30 hover:bg-emerald-500/30' 
                  : 'bg-amber-500 text-slate-950 border-amber-400 hover:bg-amber-400 shadow-xs'"
              >
                {{ hasAccess ? 'Cài đặt' : 'Cấp quyền' }}
              </button>
            </div>
          </div>

          <!-- Dynamic Whitelisted Apps List -->
          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-1.5">
                <label class="text-[11px] font-semibold uppercase tracking-wider" :class="isDarkMode ? 'text-slate-400' : 'text-slate-500'">
                  Ứng dụng dùng Trợ năng API
                </label>
                <Tooltip text="Mặc định tất cả ứng dụng dùng phím mô phỏng chuẩn (CGEvent). Chỉ những ứng dụng trong danh sách này mới dùng Trợ năng API." position="bottom" :is-dark-mode="isDarkMode" />
              </div>

              <!-- Button to open running apps modal -->
              <button
                @click="openRunningAppsModal"
                class="px-2.5 py-1 text-xs font-semibold bg-blue-600 hover:bg-blue-700 text-white rounded-md transition-colors flex items-center space-x-1.5 cursor-pointer shadow-xs"
              >
                <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" />
                </svg>
                <span>Thêm ứng dụng</span>
              </button>
            </div>

            <!-- List of Whitelisted Apps -->
            <div 
              class="border rounded-lg divide-y transition-colors min-h-[100px]"
              :class="isDarkMode ? 'bg-[#0e131f] border-[#1e2638] divide-[#1e2638]' : 'bg-white border-slate-200 divide-slate-100 shadow-xs'"
            >
              <template v-if="accessibilityApps.length > 0">
                <div 
                  v-for="app in accessibilityApps" 
                  :key="app.bundle" 
                  class="p-2.5 flex items-center justify-between transition-colors"
                  :class="isDarkMode ? 'hover:bg-[#151c2d]' : 'hover:bg-slate-50'"
                >
                  <div class="flex items-center space-x-3 min-w-0 flex-1 mr-2">
                    <!-- Real Application Native Icon -->
                    <div 
                      class="w-7 h-7 rounded-md overflow-hidden flex items-center justify-center shrink-0 border"
                      :class="isDarkMode ? 'bg-[#090d16] border-[#1e2638]' : 'bg-slate-100 border-slate-200'"
                    >
                      <img v-if="app.icon_base64" :src="app.icon_base64" class="w-6 h-6 object-contain" />
                      <svg v-else class="w-4 h-4 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <rect x="4" y="4" width="16" height="16" rx="3" />
                      </svg>
                    </div>

                    <div class="flex flex-col min-w-0 flex-1">
                      <span class="text-xs font-semibold leading-tight truncate" :class="isDarkMode ? 'text-slate-200' : 'text-slate-800'">{{ app.name }}</span>
                      <span class="text-[10px] font-mono truncate" :class="isDarkMode ? 'text-slate-500' : 'text-slate-400'" :title="app.bundle">{{ app.bundle }}</span>
                    </div>
                  </div>

                  <div class="flex items-center space-x-2">
                    <!-- Toggle switch for enabling/disabling Accessibility API for this app -->
                    <button 
                      @click="app.enabled = !app.enabled; saveSettings()"
                      class="relative inline-flex h-5 w-9 p-0.5 items-center cursor-pointer rounded-full border border-transparent transition-colors duration-200 ease-in-out focus:outline-none"
                      :class="app.enabled ? 'bg-blue-600' : (isDarkMode ? 'bg-[#1e2638]' : 'bg-slate-300')"
                      :title="app.enabled ? 'Đang dùng Trợ năng API' : 'Đang dùng Mô phỏng phím (CGEvent)'"
                    >
                      <span 
                        class="pointer-events-none inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow-xs transition-transform duration-200 ease-in-out"
                        :class="app.enabled ? 'translate-x-4' : 'translate-x-0'"
                      ></span>
                    </button>

                    <!-- Remove button for non-default apps -->
                    <button 
                      v-if="!app.isDefault"
                      @click="removeAppFromAccessibility(app.bundle)"
                      class="p-1 rounded text-slate-400 hover:text-red-400 hover:bg-red-500/10 transition-colors cursor-pointer ml-1"
                      title="Xóa ứng dụng tùy chỉnh khỏi danh sách"
                    >
                      <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                      </svg>
                    </button>
                  </div>
                </div>
              </template>

              <!-- Empty State -->
              <div v-else class="p-6 text-center flex flex-col items-center justify-center space-y-1.5">
                <span class="text-xs font-medium" :class="isDarkMode ? 'text-slate-400' : 'text-slate-500'">Chưa có ứng dụng nào dùng Trợ năng API.</span>
                <span class="text-[11px]" :class="isDarkMode ? 'text-slate-600' : 'text-slate-400'">Mặc định tất cả ứng dụng đang sử dụng phím mô phỏng chuẩn (CGEvent Simulation).</span>
              </div>
            </div>
          </div>

        </div>

        <!-- ==================== TAB 3: HỆ THỐNG ==================== -->
        <div v-else-if="activeTab === 'system'" class="space-y-4 animate-fadeIn">

          <!-- System Boot Settings Card -->
          <div 
            class="p-3 border rounded-lg space-y-3"
            :class="isDarkMode ? 'bg-[#0e131f] border-[#1e2638]' : 'bg-white border-slate-200 shadow-xs'"
          >
            <!-- Khởi động cùng hệ thống -->
            <div class="flex items-center justify-between">
              <span class="text-[13px] font-medium" :class="isDarkMode ? 'text-slate-200' : 'text-slate-800'">Khởi động cùng hệ thống</span>

              <!-- PIXEL PERFECT TOGGLE SWITCH -->
              <button 
                @click="autostart = !autostart; saveSettings()"
                class="relative inline-flex h-5 w-9 p-0.5 items-center cursor-pointer rounded-full border border-transparent transition-colors duration-200 ease-in-out focus:outline-none"
                :class="autostart ? 'bg-blue-600' : (isDarkMode ? 'bg-[#1e2638]' : 'bg-slate-300')"
              >
                <span 
                  class="pointer-events-none inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow-xs transition-transform duration-200 ease-in-out"
                  :class="autostart ? 'translate-x-4' : 'translate-x-0'"
                ></span>
              </button>
            </div>

            <hr :class="isDarkMode ? 'border-[#1e2638]' : 'border-slate-200'" />

            <!-- Mở bảng điều khiển khi khởi động -->
            <div class="flex items-center justify-between">
              <span class="text-[13px] font-medium" :class="isDarkMode ? 'text-slate-200' : 'text-slate-800'">Mở bảng điều khiển khi khởi động</span>

              <!-- PIXEL PERFECT TOGGLE SWITCH -->
              <button 
                @click="openOnStartup = !openOnStartup; saveSettings()"
                class="relative inline-flex h-5 w-9 p-0.5 items-center cursor-pointer rounded-full border border-transparent transition-colors duration-200 ease-in-out focus:outline-none"
                :class="openOnStartup ? 'bg-blue-600' : (isDarkMode ? 'bg-[#1e2638]' : 'bg-slate-300')"
              >
                <span 
                  class="pointer-events-none inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow-xs transition-transform duration-200 ease-in-out"
                  :class="openOnStartup ? 'translate-x-4' : 'translate-x-0'"
                ></span>
              </button>
            </div>

          </div>

          <!-- Separator Line (---) -->
          <div class="relative flex py-1 items-center">
            <div class="flex-grow border-t" :class="isDarkMode ? 'border-[#1e2638]' : 'border-slate-200'"></div>
            <span class="flex-shrink mx-3 text-[10px] uppercase font-bold tracking-wider" :class="isDarkMode ? 'text-slate-600' : 'text-slate-400'">Mở rộng</span>
            <div class="flex-grow border-t" :class="isDarkMode ? 'border-[#1e2638]' : 'border-slate-200'"></div>
          </div>

          <!-- Per-app Language memory -->
          <div 
            class="p-3 border rounded-lg flex items-center justify-between"
            :class="isDarkMode ? 'bg-[#0e131f] border-[#1e2638]' : 'bg-white border-slate-200 shadow-xs'"
          >
            <span class="text-[13px] font-medium" :class="isDarkMode ? 'text-slate-200' : 'text-slate-800'">Nhớ ngôn ngữ gõ theo ứng dụng</span>

            <!-- PIXEL PERFECT TOGGLE SWITCH -->
            <button 
              @click="perAppLanguage = !perAppLanguage; saveSettings()"
              class="relative inline-flex h-5 w-9 p-0.5 items-center cursor-pointer rounded-full border border-transparent transition-colors duration-200 ease-in-out focus:outline-none"
              :class="perAppLanguage ? 'bg-blue-600' : (isDarkMode ? 'bg-[#1e2638]' : 'bg-slate-300')"
            >
              <span 
                class="pointer-events-none inline-block h-3.5 w-3.5 transform rounded-full bg-white shadow-xs transition-transform duration-200 ease-in-out"
                :class="perAppLanguage ? 'translate-x-4' : 'translate-x-0'"
              ></span>
            </button>
          </div>

        </div>

        <!-- ==================== TAB 4: THÔNG TIN ==================== -->
        <div v-else-if="activeTab === 'info'" class="space-y-4 animate-fadeIn">

          <!-- Hero Card (Solid Antigravity Blue Theme) -->
          <div 
            class="p-3.5 border rounded-lg flex items-center space-x-3.5 transition-colors"
            :class="isDarkMode 
              ? 'bg-[#0e131f] border-[#1e2638]' 
              : 'bg-white border-slate-200 shadow-xs'"
          >
            <div class="w-10 h-10 rounded-lg bg-blue-600 flex items-center justify-center text-white text-base font-extrabold shadow-xs shrink-0">
              VN
            </div>
            <div class="flex flex-col">
              <div class="flex items-center space-x-2">
                <h2 class="text-sm font-bold" :class="isDarkMode ? 'text-white' : 'text-slate-900'">VNKey Engine</h2>
                <span class="px-1.5 py-0.5 text-[10px] font-semibold bg-blue-500/15 text-blue-400 border border-blue-500/20 rounded">v0.1.0-beta</span>
              </div>
              <p class="text-[11px] mt-0.5" :class="isDarkMode ? 'text-slate-400' : 'text-slate-600'">Bộ gõ tiếng Việt thế hệ mới siêu nhẹ & tối ưu hiệu năng cao.</p>
            </div>
          </div>

          <!-- Technical details table -->
          <div 
            class="border rounded-lg divide-y text-xs"
            :class="isDarkMode ? 'bg-[#0e131f] border-[#1e2638] divide-[#1e2638]' : 'bg-white border-slate-200 divide-slate-100 shadow-xs'"
          >
            <div class="p-2.5 flex justify-between">
              <span :class="isDarkMode ? 'text-slate-400' : 'text-slate-500'">Lõi xử lý Engine:</span>
              <span class="font-mono font-semibold text-[11px]" :class="isDarkMode ? 'text-slate-200' : 'text-slate-800'">Rust Core (vnkey-engine)</span>
            </div>
            <div class="p-2.5 flex justify-between">
              <span :class="isDarkMode ? 'text-slate-400' : 'text-slate-500'">Giao diện (UI Framework):</span>
              <span class="font-mono font-semibold text-[11px]" :class="isDarkMode ? 'text-slate-200' : 'text-slate-800'">Tauri v2 + Vue 3</span>
            </div>
            <div class="p-2.5 flex justify-between">
              <span :class="isDarkMode ? 'text-slate-400' : 'text-slate-500'">Hệ điều hành hỗ trợ:</span>
              <span class="font-medium text-[11px]" :class="isDarkMode ? 'text-slate-200' : 'text-slate-800'">macOS 11.0+, Windows 10/11</span>
            </div>
            <div class="p-2.5 flex justify-between">
              <span :class="isDarkMode ? 'text-slate-400' : 'text-slate-500'">Bản quyền:</span>
              <span class="font-medium text-[11px]" :class="isDarkMode ? 'text-slate-200' : 'text-slate-800'">Open Source (MIT License)</span>
            </div>
          </div>

          <!-- Actions & Update check -->
          <div class="flex items-center space-x-2">
            <button 
              @click="checkUpdates"
              :disabled="isCheckingUpdate"
              class="flex-1 py-2 px-3 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-xs font-semibold transition-colors disabled:opacity-50 flex items-center justify-center space-x-2 cursor-pointer shadow-xs"
            >
              <svg class="w-4 h-4" :class="isCheckingUpdate ? 'animate-spin' : ''" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                <path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
              </svg>
              <span>{{ isCheckingUpdate ? 'Đang kiểm tra...' : 'Kiểm tra cập nhật' }}</span>
            </button>
          </div>

          <div v-if="updateStatus" class="p-2 bg-emerald-950/30 border border-emerald-800/40 rounded-lg text-center text-emerald-400 text-[11px] font-semibold animate-pulse">
            {{ updateStatus }}
          </div>

        </div>

      </div>

    </main>

    <!-- MODAL CHỌN ỨNG DỤNG ĐANG CHẠY -->
    <Teleport to="body">
      <div 
        v-if="runningAppsModalOpen"
        class="fixed inset-0 z-[9999] flex items-center justify-center bg-black/60 backdrop-blur-xs p-4 animate-fadeIn"
        @click.self="runningAppsModalOpen = false"
      >
        <div 
          class="w-full max-w-sm rounded-xl border shadow-2xl overflow-hidden flex flex-col max-h-[80vh]"
          :class="isDarkMode ? 'bg-[#0e131f] border-[#1e2638] text-slate-100' : 'bg-white border-slate-200 text-slate-900'"
        >
          <!-- Modal Header -->
          <div class="px-4 py-3 border-b flex items-center justify-between" :class="isDarkMode ? 'border-[#1e2638]' : 'border-slate-200'">
            <div class="flex flex-col">
              <h3 class="text-xs font-bold">Thêm ứng dụng dùng Trợ năng</h3>
              <span class="text-[10px]" :class="isDarkMode ? 'text-slate-400' : 'text-slate-500'">Chọn từ ứng dụng đang mở trên hệ thống</span>
            </div>

            <button 
              @click="runningAppsModalOpen = false"
              class="p-1 rounded-md hover:bg-slate-800 text-slate-400 hover:text-white transition-colors"
            >
              ✕
            </button>
          </div>

          <!-- Modal Body: Running Apps List -->
          <div class="flex-1 overflow-y-auto p-2 divide-y custom-scrollbar" :class="isDarkMode ? 'divide-[#1e2638]' : 'divide-slate-100'">
            <div v-if="isLoadingRunningApps" class="p-8 text-center text-xs text-slate-400 animate-pulse">
              Đang quét các ứng dụng đang chạy...
            </div>

            <template v-else-if="runningAppsList.length > 0">
              <div 
                v-for="app in runningAppsList" 
                :key="app.bundle_id"
                class="p-2 flex items-center justify-between rounded-lg transition-colors cursor-pointer"
                :class="isDarkMode ? 'hover:bg-[#151c2d]' : 'hover:bg-slate-100'"
                @click="addAppToAccessibility(app); runningAppsModalOpen = false"
              >
                <div class="flex items-center space-x-3 min-w-0 flex-1 mr-2">
                  <div 
                    class="w-7 h-7 rounded-md overflow-hidden flex items-center justify-center shrink-0 border"
                    :class="isDarkMode ? 'bg-[#090d16] border-[#1e2638]' : 'bg-slate-200 border-slate-300'"
                  >
                    <img v-if="app.icon_base64" :src="app.icon_base64" class="w-6 h-6 object-contain" />
                    <svg v-else class="w-4 h-4 text-slate-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <rect x="4" y="4" width="16" height="16" rx="3" />
                    </svg>
                  </div>

                  <div class="flex flex-col min-w-0 flex-1">
                    <span class="text-xs font-semibold leading-tight truncate">{{ app.name }}</span>
                    <span class="text-[10px] font-mono text-slate-500 truncate" :title="app.bundle_id">{{ app.bundle_id }}</span>
                  </div>
                </div>

                <span 
                  v-if="accessibilityApps.some(a => a.bundle === app.bundle_id)"
                  class="text-[10px] text-emerald-400 font-bold px-2 py-0.5 rounded bg-emerald-500/10 border border-emerald-500/20"
                >
                  Đã thêm
                </span>
                <span 
                  v-else
                  class="text-[10px] text-blue-400 font-medium px-2 py-0.5 rounded bg-blue-500/10 border border-blue-500/20"
                >
                  + Thêm
                </span>
              </div>
            </template>

            <div v-else class="p-6 text-center text-xs text-slate-400">
              Không tìm thấy ứng dụng nào đang chạy.
            </div>
          </div>
        </div>
      </div>
    </Teleport>

  </div>
</template>

<style>
/* Custom scrollbar */
.custom-scrollbar::-webkit-scrollbar {
  width: 4px;
}
.custom-scrollbar::-webkit-scrollbar-track {
  background: transparent;
}
.custom-scrollbar::-webkit-scrollbar-thumb {
  background: rgba(148, 163, 184, 0.2);
  border-radius: 4px;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(1px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.animate-fadeIn {
  animation: fadeIn 0.12s ease-out forwards;
}
</style>
