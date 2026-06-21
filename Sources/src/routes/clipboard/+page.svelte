<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { invoke, convertFileSrc } from "@tauri-apps/api/core";
  import { listen } from "@tauri-apps/api/event";
  import { getCurrentWindow } from "@tauri-apps/api/window";
  import { tooltip } from "$lib/tooltip";

  interface ClipboardItem {
    id: string;
    timestamp: number;
    content_type: string; // "text" | "html" | "image" | "file"
    text: string | null;
    html: string | null;
    image_path: string | null;
    file_paths: string[] | null;
    app_name: string | null;
    app_pid: number | null;
  }

  let items = $state<ClipboardItem[]>([]);
  let searchQuery = $state("");
  let selectedIndex = $state(0);
  let prevPid = $state(0);
  let settings = $state<any>(null);
  let isPin = $state(false);
  let autoHide = $state(false);

  let unlistenChange: (() => void) | null = null;
  let unlistenPid: (() => void) | null = null;
  let unlistenBlur: (() => void) | null = null;
  let cleanupTheme: (() => void) | null = null;

  let filteredItems = $derived(
    items.filter((item) => {
      if (!searchQuery) return true;
      const query = searchQuery.toLowerCase();
      if (item.text && item.text.toLowerCase().includes(query)) return true;
      if (item.file_paths && item.file_paths.some(p => p.toLowerCase().includes(query))) return true;
      if (item.app_name && item.app_name.toLowerCase().includes(query)) return true;
      return false;
    })
  );

  async function loadItems() {
    try {
      items = await invoke<ClipboardItem[]>("get_clipboard_items");
      if (selectedIndex >= filteredItems.length) {
        selectedIndex = Math.max(0, filteredItems.length - 1);
      }
    } catch (e) {
      console.error("Failed to load clipboard items:", e);
    }
  }

  async function loadSettings() {
    try {
      settings = await invoke("get_settings");
      if (settings) {
        isPin = settings.clipboard_pin_on_top === 1;
        autoHide = settings.clipboard_auto_hide === 1;
      }
    } catch (e) {
      console.error("Failed to load settings in clipboard:", e);
    }
  }

  async function toggleAlwaysOnTop() {
    if (!settings) return;
    const nextPin = !isPin;
    settings.clipboard_pin_on_top = nextPin ? 1 : 0;
    try {
      await invoke("update_settings", { settings });
      isPin = nextPin;
    } catch (e) {
      settings.clipboard_pin_on_top = isPin ? 1 : 0;
      console.error("Failed to update always on top setting:", e);
    }
  }

  async function toggleAutoHide() {
    if (!settings) return;
    autoHide = !autoHide;

    settings.clipboard_auto_hide = autoHide ? 1 : 0;
    try {
      await invoke("update_settings", { settings });
    } catch (e) {
      console.error("Failed to update auto hide setting:", e);
    }
  }

  async function clearAll() {
    if (confirm("Bạn có chắc chắn muốn xóa toàn bộ bảng nhớ không?")) {
      try {
        await invoke("clear_clipboard_history");
        await loadItems();
      } catch (e) {
        console.error("Failed to clear clipboard history:", e);
      }
    }
  }

  async function pasteItem(item: ClipboardItem) {
    try {
      await invoke("paste_clipboard_item", { id: item.id, prevPid });
      await invoke("hide_clipboard_picker_window");
    } catch (e) {
      console.error("Failed to paste item:", e);
    }
  }

  async function removeItem(id: string, event?: Event) {
    if (event) {
      event.stopPropagation();
    }
    try {
      await invoke("remove_clipboard_item", { id });
      await loadItems();
    } catch (e) {
      console.error("Failed to remove item:", e);
    }
  }

  async function stripFormatting(id: string, event?: Event) {
    if (event) {
      event.stopPropagation();
    }
    try {
      await invoke("strip_clipboard_formatting", { id });
      await loadItems();
    } catch (e) {
      console.error("Failed to strip formatting:", e);
    }
  }

  function handleKeydown(event: KeyboardEvent) {
    if (event.key === "Escape") {
      event.preventDefault();
      invoke("hide_clipboard_picker_window");
      return;
    }

    if (event.key === "ArrowDown") {
      event.preventDefault();
      if (filteredItems.length > 0) {
        selectedIndex = (selectedIndex + 1) % filteredItems.length;
        scrollSelectedIntoView();
      }
      return;
    }

    if (event.key === "ArrowUp") {
      event.preventDefault();
      if (filteredItems.length > 0) {
        selectedIndex = (selectedIndex - 1 + filteredItems.length) % filteredItems.length;
        scrollSelectedIntoView();
      }
      return;
    }

    if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault();
      if (filteredItems.length > 0 && selectedIndex < filteredItems.length) {
        pasteItem(filteredItems[selectedIndex]);
      }
      return;
    }

    const num = parseInt(event.key);
    if (!isNaN(num) && num >= 1 && num <= 9) {
      const isCmdOrCtrl = event.metaKey || event.ctrlKey || event.altKey;
      if (isCmdOrCtrl || !searchQuery) {
        const idx = num - 1;
        if (idx < filteredItems.length) {
          event.preventDefault();
          pasteItem(filteredItems[idx]);
        }
      }
    }
  }

  function scrollSelectedIntoView() {
    setTimeout(() => {
      const selectedEl = document.querySelector(".item-container.selected");
      if (selectedEl) {
        selectedEl.scrollIntoView({ block: "nearest" });
      }
    }, 0);
  }

  function formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = date.getHours().toString().padStart(2, "0");
    const minutes = date.getMinutes().toString().padStart(2, "0");
    const seconds = date.getSeconds().toString().padStart(2, "0");
    return `${hours}:${minutes}:${seconds}`;
  }

  function getItemTitle(item: ClipboardItem): string {
    if (item.content_type === "text") {
      return item.text?.trim() || "";
    } else if (item.content_type === "image") {
      return "Hình ảnh";
    } else if (item.content_type === "file" && item.file_paths) {
      const fileName = item.file_paths[0].split("/").pop() || "";
      if (item.file_paths.length > 1) {
        return `${fileName} và ${item.file_paths.length - 1} tệp khác`;
      }
      return fileName;
    }
    return "";
  }

  onMount(async () => {
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
    cleanupTheme = () => mediaQuery.removeEventListener('change', updateTheme);

    await loadSettings();
    await loadItems();
    
    const searchInput = document.getElementById("search-input");
    if (searchInput) {
      searchInput.focus();
    }

    unlistenChange = await listen("clipboard-changed", () => {
      loadItems();
    });

    unlistenPid = await listen<number>("set-prev-pid", (event) => {
      prevPid = event.payload;
      searchQuery = "";
      selectedIndex = 0;
      loadItems();
      loadSettings();
      if (searchInput) {
        searchInput.focus();
      }
    });

    const appWindow = getCurrentWindow();
    unlistenBlur = await appWindow.listen("tauri://blur", () => {
      if (autoHide) {
        invoke("hide_clipboard_picker_window");
      }
    });
  });

  onDestroy(() => {
    if (unlistenChange) unlistenChange();
    if (unlistenPid) unlistenPid();
    if (unlistenBlur) unlistenBlur();
    if (cleanupTheme) cleanupTheme();
  });
</script>

<div class="clipboard-picker" onkeydown={handleKeydown} role="presentation">
  <!-- Header Bar -->
  <header class="clipboard-header" data-tauri-drag-region>
    <div class="traffic-light-space" data-tauri-drag-region></div>

    <div class="header-title" data-tauri-drag-region>
      <span class="header-icon">
        <svg xmlns="http://www.w3.org/2000/svg" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
          <rect width="8" height="4" x="8" y="2" rx="1" ry="1"/>
          <path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/>
        </svg>
      </span>
      <h2>Bảng nhớ</h2>
      {#if items.length > 0}
        <span class="items-count">{items.length} mục</span>
      {/if}
    </div>
    
    <div class="header-right">
      <button
        class="header-btn" 
        class:active={isPin} 
        onclick={toggleAlwaysOnTop} 
        use:tooltip={isPin ? "Bỏ ghim trên cùng" : "Ghim cửa sổ trên cùng"}
        aria-label={isPin ? "Bỏ ghim trên cùng" : "Ghim cửa sổ trên cùng"}
      >
        {#if isPin}
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="12" y1="17" x2="12" y2="22"/>
            <path d="M5 17h14v-1.76a2 2 0 0 0-.44-1.24l-2.33-2.91A8 8 0 0 1 15 6V3H9v3a8 8 0 0 1-1.23 5.09l-2.33 2.9A2 2 0 0 0 5 15.24Z"/>
          </svg>
        {:else}
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <line x1="12" y1="17" x2="12" y2="22"/>
            <path d="M5 17h14v-1.76a2 2 0 0 0-.44-1.24l-2.33-2.91A8 8 0 0 1 15 6V3H9v3a8 8 0 0 1-1.23 5.09l-2.33 2.9A2 2 0 0 0 5 15.24Z"/>
          </svg>
        {/if}
      </button>

      <button 
        class="header-btn" 
        class:active={autoHide} 
        onclick={toggleAutoHide} 
        use:tooltip={autoHide ? "Tắt tự động ẩn khi mất tiêu điểm" : "Bật tự động ẩn khi mất tiêu điểm"}
        aria-label={autoHide ? "Tắt tự động ẩn" : "Bật tự động ẩn"}
      >
        {#if autoHide}
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M9.88 9.88a3 3 0 1 0 4.24 4.24"/>
            <path d="M10.73 5.08A10.43 10.43 0 0 1 12 5c7 0 10 7 10 7a13.16 13.16 0 0 1-1.67 2.68"/>
            <path d="M6.61 6.61A13.52 13.52 0 0 0 2 12s3 7 10 7a9.74 9.74 0 0 0 5.39-1.61"/>
            <line x1="2" y1="2" x2="22" y2="22"/>
          </svg>
        {:else}
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0z"/>
            <circle cx="12" cy="12" r="3"/>
          </svg>
        {/if}
      </button>

      {#if items.length > 0}
        <button 
          class="header-btn delete-all-btn" 
          onclick={clearAll} 
          use:tooltip={"Xóa tất cả lịch sử"}
          aria-label="Xóa tất cả lịch sử"
        >
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M3 6h18"/>
            <path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/>
            <path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/>
            <line x1="10" x2="10" y1="11" y2="17"/>
            <line x1="14" x2="14" y1="11" y2="17"/>
          </svg>
        </button>
      {/if}
    </div>
  </header>

  <!-- Search Input Area -->
  <div class="search-box">
    <span class="search-icon">
      <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="search-icon-svg">
        <circle cx="11" cy="11" r="8"/>
        <path d="m21 21-4.3-4.3"/>
      </svg>
    </span>
    <input
      id="search-input"
      type="text"
      placeholder="Tìm kiếm bảng nhớ..."
      bind:value={searchQuery}
      autocomplete="off"
    />
    {#if searchQuery}
      <button class="clear-search-btn" onclick={() => searchQuery = ""} use:tooltip={"Xóa tìm kiếm"} aria-label="Xóa tìm kiếm">
        <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
          <path d="M18 6 6 18"/><path d="m6 6 12 12"/>
        </svg>
      </button>
    {/if}
  </div>

  <!-- Clipboard Items List -->
  <div class="items-list">
    {#if filteredItems.length === 0}
      <div class="empty-state">
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="empty-svg">
          <rect width="8" height="4" x="8" y="2" rx="1" ry="1"/>
          <path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/>
        </svg>
        <p>Bảng nhớ trống</p>
      </div>
    {:else}
      {#each filteredItems as item, index}
        <div
          class="item-container"
          class:selected={index === selectedIndex}
          onmouseenter={() => selectedIndex = index}
          onclick={() => pasteItem(item)}
          onkeydown={(event) => {
            if (event.key === "Enter" || event.key === " ") {
              event.preventDefault();
              pasteItem(item);
            }
          }}
          role="button"
          tabindex="0"
        >
          <!-- Shortcut Key Number -->
          <div class="shortcut-indicator">
            {#if index < 9}
              <span>{index + 1}</span>
            {:else}
              <span class="dot">•</span>
            {/if}
          </div>

          <!-- Thumbnail Col -->
          <div class="thumbnail-col">
            {#if item.content_type === "image"}
              <div class="thumbnail-box image-box">
                {#if item.image_path}
                  <img src={convertFileSrc(item.image_path)} alt="Clipboard thumbnail" />
                {:else}
                  <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" class="item-icon-svg image-icon">
                    <rect width="18" height="18" x="3" y="3" rx="2" ry="2"/>
                    <circle cx="9" cy="9" r="2"/>
                    <path d="m21 15-3.08-3.09a2 2 0 0 0-2.83 0L11 16"/>
                  </svg>
                {/if}
              </div>
            {:else if item.content_type === "file" && item.file_paths}
              {#if item.file_paths.length > 1}
                <!-- Stack of files -->
                <div class="file-stack-container">
                  <div class="file-stack-back-2"></div>
                  <div class="file-stack-back-1"></div>
                  <div class="file-stack-front">
                    {#if item.image_path}
                      <img src={convertFileSrc(item.image_path)} alt="Stacked file thumbnail" class="cover-image" />
                    {:else}
                      <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" class="item-icon-svg stack-front-icon">
                        <path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/>
                        <path d="M14 2v4a2 2 0 0 0 2 2h4"/>
                      </svg>
                    {/if}
                  </div>
                  <span class="file-count-badge">{item.file_paths.length}</span>
                </div>
              {:else}
                <!-- Single file -->
                <div class="thumbnail-box file-box">
                  {#if item.image_path}
                    <img src={convertFileSrc(item.image_path)} alt="File icon thumbnail" />
                  {:else}
                    <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" class="item-icon-svg file-icon">
                      <path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/>
                      <path d="M14 2v4a2 2 0 0 0 2 2h4"/>
                    </svg>
                  {/if}
                </div>
              {/if}
            {:else}
              <!-- Text -->
              <div class="thumbnail-box text-box" class:rich-text-bg={item.html !== null}>
                {#if item.html !== null}
                  <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" class="item-icon-svg html-icon">
                    <path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/>
                    <path d="M14 2v4a2 2 0 0 0 2 2h4"/>
                    <path d="M10 9H8"/>
                    <path d="M16 13H8"/>
                    <path d="M16 17H8"/>
                    <path d="M12 13h4"/>
                    <path d="M12 17h4"/>
                  </svg>
                {:else}
                  <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" class="item-icon-svg text-icon">
                    <path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/>
                    <path d="M14 2v4a2 2 0 0 0 2 2h4"/>
                    <path d="M10 9H8"/>
                    <path d="M16 13H8"/>
                    <path d="M16 17H8"/>
                  </svg>
                {/if}
              </div>
            {/if}
          </div>

          <!-- Main Info (Text Preview, Metadata) -->
          <div class="item-main-info">
            <div class="item-title">
              {getItemTitle(item)}
            </div>
            <div class="item-meta">
              {#if item.app_name}
                <span class="app-badge">{item.app_name}</span>
              {/if}
              <span class="time-badge">{formatTime(item.timestamp)}</span>
            </div>
          </div>

          <!-- Quick Row Actions -->
          <div class="item-actions">
            {#if item.content_type === "text" && item.html}
              <button
                class="action-btn strip-btn"
                use:tooltip={"Chuyển sang văn bản thô"}
                aria-label="Chuyển sang văn bản thô"
                onclick={(e) => stripFormatting(item.id, e)}
              >
                <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                  <path d="m7 21-4.3-4.3c-1-1-1-2.5 0-3.4l9.6-9.6c1-1 2.5-1 3.4 0l5.6 5.6c1 1 1 2.5 0 3.4L13 21Z"/>
                  <path d="M22 21H7"/>
                  <path d="m5 11 9 9"/>
                </svg>
              </button>
            {/if}
            <button
              class="action-btn delete-btn"
              use:tooltip={"Xóa mục này"}
              aria-label="Xóa mục này"
              onclick={(e) => removeItem(item.id, e)}
            >
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                <path d="M3 6h18"/>
                <path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/>
                <path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/>
              </svg>
            </button>
          </div>
        </div>
      {/each}
    {/if}
  </div>

  <!-- Bottom Hints Footer -->
  <footer class="clipboard-footer">
    <span class="hint"><span class="key">↑↓</span> Chọn</span>
    <span class="hint"><span class="key">Enter / Tab</span> Dán</span>
    {#if !searchQuery}
      <span class="hint"><span class="key">1–9</span> Dán nhanh</span>
    {/if}
    <span class="hint"><span class="key">Esc</span> Đóng</span>
  </footer>
</div>

<style>
  :root {
    --bg-app: #121216;
    --bg-card: #1f1f2a;
    --text-primary: #f5f5f7;
    --text-secondary: #a1a1b5;
    --color-accent: #007aff;
    --border-color: rgba(255, 255, 255, 0.08);
    --bg-input: rgba(255, 255, 255, 0.05);
  }

  :global(.light) {
    --bg-app: #f4f4f6;
    --bg-card: #ffffff;
    --text-primary: #1c1c1e;
    --text-secondary: #6c6c78;
    --border-color: rgba(0, 0, 0, 0.08);
    --bg-input: rgba(0, 0, 0, 0.03);
  }

  :global(html), :global(body) {
    margin: 0;
    padding: 0;
    width: 100vw;
    height: 100vh;
    background-color: var(--bg-app) !important;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
    overflow: hidden;
    user-select: none;
  }

  .clipboard-picker {
    width: 100vw;
    height: 100vh;
    display: flex;
    flex-direction: column;
    box-sizing: border-box;
    background-color: var(--bg-app);
  }

  /* Header Bar Styles */
  .clipboard-header {
    display: grid;
    grid-template-columns: minmax(72px, 1fr) auto minmax(72px, 1fr);
    align-items: center;
    min-height: 38px;
    padding: 0 10px;
    border-bottom: 1px solid var(--border-color);
    -webkit-app-region: drag;
  }

  .traffic-light-space {
    min-width: 72px;
    height: 100%;
  }

  .header-title {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    color: var(--text-primary);
    pointer-events: none;
    white-space: nowrap;
  }

  .header-icon {
    display: flex;
    align-items: center;
    color: var(--color-accent);
  }

  .clipboard-header h2 {
    font-size: 13.5px;
    font-weight: 600;
    margin: 0;
  }

  .items-count {
    font-size: 10px;
    color: var(--text-secondary);
    background: rgba(255, 255, 255, 0.06);
    padding: 1px 6px;
    border-radius: 10px;
    font-weight: 500;
  }

  :global(.light) .items-count {
    background: rgba(0, 0, 0, 0.05);
  }

  .header-right {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 4px;
    -webkit-app-region: no-drag;
  }

  .header-btn {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    cursor: pointer;
    border-radius: 6px;
    width: 26px;
    height: 26px;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.12s ease;
  }

  .header-btn:hover {
    background: rgba(255, 255, 255, 0.06);
    color: var(--text-primary);
  }

  :global(.light) .header-btn:hover {
    background: rgba(0, 0, 0, 0.04);
  }

  .header-btn.active {
    color: var(--color-accent);
    background: rgba(0, 122, 255, 0.1);
  }

  :global(.custom-floating-tooltip) {
    position: absolute;
    z-index: 9999;
    padding: 6px 8px;
    border-radius: 6px;
    background: rgba(28, 28, 30, 0.96);
    backdrop-filter: blur(8px);
    border: 1px solid rgba(255, 255, 255, 0.08);
    color: white;
    font-size: 11px;
    line-height: 1.3;
    white-space: nowrap;
    pointer-events: none;
    opacity: 0;
    transform: translateY(4px);
    transition: opacity 0.12s cubic-bezier(0.4, 0, 0.2, 1), transform 0.12s cubic-bezier(0.4, 0, 0.2, 1);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
  }

  :global(.light .custom-floating-tooltip) {
    background: rgba(255, 255, 255, 0.96);
    border: 1px solid rgba(0, 0, 0, 0.08);
    color: #1c1c1e;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
  }

  :global(.custom-floating-tooltip.visible) {
    opacity: 1;
    transform: translateY(0);
  }

  .header-btn.delete-all-btn:hover {
    color: #ff453a;
    background: rgba(255, 69, 58, 0.1);
  }

  /* Search Input Area */
  .search-box {
    display: flex;
    align-items: center;
    background: var(--bg-input);
    border: 1px solid var(--border-color);
    border-radius: 8px;
    padding: 6px 10px;
    margin: 10px 12px;
    gap: 8px;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
  }

  .search-icon {
    display: flex;
    align-items: center;
  }

  .search-icon-svg {
    color: var(--text-secondary);
    opacity: 0.6;
  }

  .search-box input {
    flex: 1;
    background: transparent;
    border: none;
    outline: none;
    font-size: 13px;
    color: var(--text-primary);
  }

  .search-box input::placeholder {
    color: var(--text-secondary);
    opacity: 0.6;
  }

  .clear-search-btn {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 2px;
    border-radius: 4px;
  }

  .clear-search-btn:hover {
    background: rgba(255, 255, 255, 0.08);
    color: var(--text-primary);
  }

  /* Clipboard Items List */
  .items-list {
    flex: 1;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 0 12px 10px 12px;
  }

  .items-list::-webkit-scrollbar {
    width: 5px;
  }
  .items-list::-webkit-scrollbar-track {
    background: transparent;
  }
  .items-list::-webkit-scrollbar-thumb {
    background: rgba(128, 128, 128, 0.2);
    border-radius: 10px;
  }
  .items-list::-webkit-scrollbar-thumb:hover {
    background: rgba(128, 128, 128, 0.4);
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: var(--text-secondary);
    opacity: 0.6;
    text-align: center;
    padding: 40px 0;
  }

  .empty-svg {
    color: var(--text-secondary);
    margin-bottom: 8px;
    opacity: 0.7;
  }

  /* List Row Items */
  .item-container {
    display: flex;
    align-items: center;
    background: rgba(255, 255, 255, 0.02);
    border: 1px solid var(--border-color);
    border-radius: 8px;
    padding: 8px 10px;
    cursor: pointer;
    transition: all 0.12s ease;
    position: relative;
    outline: none;
    gap: 12px;
  }

  :global(.light) .item-container {
    background: rgba(0, 0, 0, 0.01);
  }

  .item-container:hover, .item-container.selected {
    background: rgba(0, 122, 255, 0.1);
    border-color: rgba(0, 122, 255, 0.3);
  }

  .shortcut-indicator {
    width: 14px;
    font-size: 11px;
    font-weight: 600;
    color: var(--text-secondary);
    opacity: 0.6;
    display: flex;
    align-items: center;
    justify-content: flex-end;
  }

  .item-container:hover .shortcut-indicator, .item-container.selected .shortcut-indicator {
    color: var(--color-accent);
    opacity: 1;
  }

  /* Thumbnail Column and Box */
  .thumbnail-col {
    width: 52px;
    height: 38px;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .thumbnail-box {
    width: 46px;
    height: 32px;
    border-radius: 4px;
    border: 1px solid var(--border-color);
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
    background: rgba(255, 255, 255, 0.03);
    box-sizing: border-box;
  }

  :global(.light) .thumbnail-box {
    background: rgba(0, 0, 0, 0.02);
  }

  .thumbnail-box.text-box.rich-text-bg {
    background: rgba(0, 122, 255, 0.04);
    border-color: rgba(0, 122, 255, 0.15);
  }

  .thumbnail-box img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .item-icon-svg {
    opacity: 0.55;
    color: var(--text-secondary);
  }

  .item-container:hover .item-icon-svg, .item-container.selected .item-icon-svg {
    opacity: 0.85;
    color: var(--text-primary);
  }

  .thumbnail-box.text-box.rich-text-bg .item-icon-svg.html-icon {
    color: var(--color-accent);
    opacity: 0.75;
  }

  /* Stack of Files CSS */
  .file-stack-container {
    position: relative;
    width: 46px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .file-stack-back-2 {
    position: absolute;
    width: 40px;
    height: 26px;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid var(--border-color);
    border-radius: 4px;
    transform: translate(3px, -3px);
    z-index: 1;
  }

  .file-stack-back-1 {
    position: absolute;
    width: 40px;
    height: 26px;
    background: rgba(255, 255, 255, 0.09);
    border: 1px solid var(--border-color);
    border-radius: 4px;
    transform: translate(1.5px, -1.5px);
    z-index: 2;
  }

  .file-stack-front {
    position: absolute;
    width: 40px;
    height: 26px;
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 4px;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 3;
    overflow: hidden;
  }

  :global(.light) .file-stack-back-2 {
    background: rgba(0, 0, 0, 0.02);
  }
  :global(.light) .file-stack-back-1 {
    background: rgba(0, 0, 0, 0.04);
  }
  :global(.light) .file-stack-front {
    background: #fcfcfd;
  }

  .file-stack-front img.cover-image {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .file-count-badge {
    position: absolute;
    right: -1px;
    bottom: -3px;
    font-size: 8.5px;
    font-weight: 700;
    color: white;
    background: #ff9500;
    padding: 1px 4px;
    border-radius: 6px;
    z-index: 4;
    border: 1px solid rgba(255, 255, 255, 0.2);
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
    line-height: 1;
  }

  /* Info Column */
  .item-main-info {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }

  .item-title {
    font-size: 13px;
    font-weight: 500;
    color: var(--text-primary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .item-meta {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .app-badge {
    background: rgba(255, 255, 255, 0.07);
    color: var(--text-secondary);
    font-size: 9.5px;
    padding: 1px 5px;
    border-radius: 4px;
    font-weight: 500;
  }

  :global(.light) .app-badge {
    background: rgba(0, 0, 0, 0.04);
  }

  .time-badge {
    font-size: 10px;
    color: var(--text-secondary);
    opacity: 0.7;
  }

  /* Row Actions */
  .item-actions {
    display: flex;
    gap: 4px;
    margin-left: 10px;
    opacity: 0;
    transition: opacity 0.12s ease;
  }

  .item-container:hover .item-actions, .item-container.selected .item-actions {
    opacity: 1;
  }

  .action-btn {
    background: transparent;
    border: none;
    border-radius: 6px;
    width: 24px;
    height: 24px;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    color: var(--text-secondary);
    transition: all 0.1s ease;
  }

  .action-btn:hover {
    background: rgba(255, 255, 255, 0.08);
    color: var(--text-primary);
  }

  :global(.light) .action-btn:hover {
    background: rgba(0, 0, 0, 0.05);
  }

  .action-btn.delete-btn:hover {
    color: #ff453a;
    background: rgba(255, 69, 58, 0.1);
  }

  /* Hints Footer */
  .clipboard-footer {
    display: flex;
    align-items: center;
    justify-content: center;
    flex-wrap: wrap;
    gap: 16px;
    padding: 8px 14px;
    border-top: 1px solid var(--border-color);
    font-size: 11px;
    color: var(--text-secondary);
  }

  .hint {
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .key {
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid var(--border-color);
    padding: 1px 4px;
    border-radius: 4px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    font-size: 9.5px;
    font-weight: 500;
  }

  :global(.light) .key {
    background: rgba(0, 0, 0, 0.03);
  }
</style>
