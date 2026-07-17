<script setup>
import { ref, onMounted } from "vue";
import { invoke } from "@tauri-apps/api/core";

const method = ref("Telex");
const toneStyle = ref("Modern");
const spellingCheck = ref(true);
const saving = ref(false);
const statusMsg = ref("");

// Accessibility permission state
const isMac = ref(false);
const hasAccess = ref(true);

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

async function loadSettings() {
  try {
    const settings = await invoke("get_settings");
    method.value = settings.method;
    toneStyle.value = settings.tone_style;
    spellingCheck.value = settings.spelling_check;
  } catch (err) {
    console.error("Failed to load settings:", err);
  }
}

async function saveSettings() {
  saving.value = true;
  statusMsg.value = "";
  try {
    await invoke("update_settings", {
      newSettings: {
        method: method.value,
        tone_style: toneStyle.value,
        spelling_check: spellingCheck.value,
      }
    });
    statusMsg.value = "Đã lưu cài đặt!";
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

onMounted(() => {
  isMac.value = navigator.userAgent.includes("Macintosh");
  loadSettings();
  if (isMac.value) {
    checkAccess();
  }
});
</script>

<template>
  <!-- The entire window acts as the glassmorphic card itself -->
  <div class="relative min-h-screen bg-white/95 dark:bg-slate-900/90 text-slate-800 dark:text-slate-100 flex flex-col justify-between overflow-hidden font-sans select-none border border-slate-200 dark:border-slate-800 p-6 shadow-2xl transition-colors duration-300">
    <!-- Decorative background glow blobs -->
    <div class="absolute top-[-20%] left-[-20%] w-[60%] h-[60%] rounded-full bg-violet-600/10 dark:bg-violet-600/20 blur-[120px] pointer-events-none"></div>
    <div class="absolute bottom-[-20%] right-[-20%] w-[60%] h-[60%] rounded-full bg-emerald-600/10 dark:bg-emerald-600/20 blur-[120px] pointer-events-none"></div>

    <!-- Main settings area -->
    <div class="flex-grow flex flex-col space-y-5 z-10">
      
      <!-- Top Alert Banner if macOS Accessibility is missing -->
      <div v-if="isMac && !hasAccess" class="p-3.5 bg-amber-50 dark:bg-amber-950/20 border border-amber-200 dark:border-amber-900/50 rounded-xl flex flex-col space-y-2 shadow-sm">
        <div class="flex items-center space-x-2 text-amber-700 dark:text-amber-400">
          <span class="text-md">⚠️</span>
          <span class="text-xs font-bold">Cần cấp quyền Trợ năng</span>
        </div>
        <div class="text-xxs text-amber-600/90 dark:text-amber-500/80 space-y-1 leading-relaxed">
          <p>VNKey cần quyền Trợ năng để bắt sự kiện bàn phím.</p>
          <p class="font-medium bg-amber-100/50 dark:bg-amber-900/10 p-1.5 rounded text-xxs">
            💡 Mẹo: Cần cấp quyền cho <strong>Terminal (hoặc VS Code)</strong> đang chạy ứng dụng này để bắt được phím.
          </p>
        </div>
        <button 
          @click="requestAccess"
          class="w-full py-1.5 bg-amber-600 hover:bg-amber-700 dark:bg-amber-500/20 dark:hover:bg-amber-500/30 text-white dark:text-amber-300 text-xxs font-semibold rounded transition-colors border border-transparent dark:border-amber-500/30"
        >
          Mở Cài đặt hệ thống
        </button>
      </div>

      <!-- Integrated Header -->
      <div class="flex items-center justify-between">
        <div class="flex items-center space-x-3">
          <img src="/app.svg" class="w-8 h-8 rounded-xl object-contain" alt="VNKey Logo" />
          <div>
            <h1 class="text-base font-extrabold tracking-tight text-slate-900 dark:text-white">
              VNKey
            </h1>
            <p class="text-xxs text-slate-500 dark:text-slate-400">Bộ gõ tiếng Việt siêu nhẹ</p>
          </div>
        </div>
        
        <!-- Global Enable Toggle -->
        <div class="flex items-center space-x-2.5 bg-slate-100 dark:bg-slate-950/60 border border-slate-200 dark:border-slate-800 rounded-full px-2.5 py-1 shadow-inner">
          <span class="text-xxs font-bold" :class="method !== 'Off' ? 'text-emerald-600 dark:text-emerald-400' : 'text-slate-400'">
            {{ method !== 'Off' ? 'BẬT' : 'TẮT' }}
          </span>
          <button 
            @click="method = (method === 'Off' ? 'Telex' : 'Off'); saveSettings()"
            class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none"
            :class="method !== 'Off' ? 'bg-emerald-500' : 'bg-slate-300 dark:bg-slate-700'"
          >
            <span 
              class="pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"
              :class="method !== 'Off' ? 'translate-x-4' : 'translate-x-0'"
            ></span>
          </button>
        </div>
      </div>

      <hr class="border-slate-200 dark:border-slate-800/60" />

      <!-- Kiểu gõ -->
      <div class="space-y-2">
        <label class="text-xxs font-semibold text-slate-400 dark:text-slate-500 uppercase tracking-wider">Phương thức gõ</label>
        <div class="grid grid-cols-2 gap-3">
          <button 
            @click="method = 'Telex'; saveSettings()"
            class="flex flex-col items-center justify-center p-3.5 rounded-xl border transition-all duration-200"
            :class="method === 'Telex' ? 'bg-violet-600/5 dark:bg-violet-600/10 border-violet-500 text-violet-600 dark:text-white shadow-sm' : 'bg-transparent border-slate-200 dark:border-slate-800 text-slate-400 dark:text-slate-500 hover:border-slate-300 dark:hover:border-slate-700'"
          >
            <span class="font-bold text-base">Telex</span>
            <span class="text-xxs opacity-70 mt-0.5">Gõ chữ để bỏ dấu</span>
          </button>
          <button 
            @click="method = 'Vni'; saveSettings()"
            class="flex flex-col items-center justify-center p-3.5 rounded-xl border transition-all duration-200"
            :class="method === 'Vni' ? 'bg-violet-600/5 dark:bg-violet-600/10 border-violet-500 text-violet-600 dark:text-white shadow-sm' : 'bg-transparent border-slate-200 dark:border-slate-800 text-slate-400 dark:text-slate-500 hover:border-slate-300 dark:hover:border-slate-700'"
          >
            <span class="font-bold text-base">VNI</span>
            <span class="text-xxs opacity-70 mt-0.5">Gõ số để bỏ dấu</span>
          </button>
        </div>
      </div>

      <!-- Kiểu bỏ dấu -->
      <div class="space-y-2">
        <label class="text-xxs font-semibold text-slate-400 dark:text-slate-500 uppercase tracking-wider">Quy tắc đặt dấu</label>
        <div class="flex bg-slate-100 dark:bg-slate-950/60 p-1 border border-slate-200/60 dark:border-slate-800/60 rounded-xl">
          <button 
            @click="toneStyle = 'Modern'; saveSettings()"
            class="flex-1 py-1.5 text-center rounded-lg text-xs font-semibold transition-all duration-200"
            :class="toneStyle === 'Modern' ? 'bg-white dark:bg-slate-800 text-slate-900 dark:text-white shadow-xs' : 'text-slate-400 dark:text-slate-500 hover:text-slate-600 dark:hover:text-slate-300'"
          >
            Hiện đại (hòa)
          </button>
          <button 
            @click="toneStyle = 'Classic'; saveSettings()"
            class="flex-1 py-1.5 text-center rounded-lg text-xs font-semibold transition-all duration-200"
            :class="toneStyle === 'Classic' ? 'bg-white dark:bg-slate-800 text-slate-900 dark:text-white shadow-xs' : 'text-slate-400 dark:text-slate-500 hover:text-slate-600 dark:hover:text-slate-300'"
          >
            Cổ điển (hoà)
          </button>
        </div>
      </div>

      <hr class="border-slate-200 dark:border-slate-800/60" />

      <!-- Options -->
      <div class="space-y-4">
        <div class="flex items-center justify-between">
          <div class="flex flex-col">
            <span class="text-xs font-bold text-slate-700 dark:text-slate-300">Kiểm tra chính tả</span>
            <span class="text-xxs text-slate-400 dark:text-slate-500">Tự động sửa lỗi và hoàn trả phím sai</span>
          </div>
          <button 
            @click="spellingCheck = !spellingCheck; saveSettings()"
            class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none"
            :class="spellingCheck ? 'bg-violet-600' : 'bg-slate-300 dark:bg-slate-800'"
          >
            <span 
              class="pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"
              :class="spellingCheck ? 'translate-x-4' : 'translate-x-0'"
            ></span>
          </button>
        </div>
      </div>

    </div>

    <!-- Status & Footer -->
    <div class="mt-4 space-y-3 z-10">
      <div v-if="statusMsg" class="text-center text-xxs text-emerald-600 dark:text-emerald-400 font-bold animate-pulse">
        {{ statusMsg }}
      </div>
      <footer class="text-center text-xxs text-slate-400 dark:text-slate-600 border-t border-slate-200/50 dark:border-slate-800/60 pt-3">
        VNKey v0.1.0 • Hỗ trợ đa hệ điều hành
      </footer>
    </div>
  </div>
</template>

<style>
.text-xxs {
  font-size: 0.65rem;
}
</style>
