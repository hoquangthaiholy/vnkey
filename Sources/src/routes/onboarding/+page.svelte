<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { invoke } from "@tauri-apps/api/core";

  let cleanupTheme: (() => void) | null = null;

  onMount(() => {
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
  });

  onDestroy(() => {
    if (cleanupTheme) cleanupTheme();
  });

  function requestAccessibility() {
    invoke("request_accessibility");
  }

  function quitApp() {
    invoke("quit");
  }
</script>

<div class="onboarding-container" data-tauri-drag-region>
  <header class="header" data-tauri-drag-region>
    <img src="/favicon.png" alt="VNKey Logo" class="logo" data-tauri-drag-region />
    <h1>Kích hoạt VNKey</h1>
    <p class="subtitle">Bộ gõ tiếng Việt mã nguồn mở thế hệ mới</p>
  </header>

  <main class="content" data-tauri-drag-region>
    <div class="steps-timeline">
      <div class="timeline-item">
        <div class="timeline-badge">1</div>
        <div class="timeline-content">
          <span class="timeline-title">Cấp quyền Trợ năng</span>
          <span class="timeline-desc">Nhấp nút <strong>Cấp quyền trợ năng</strong> để mở Cài đặt Hệ thống. Tìm <strong>VNKey</strong> và bật công tắc.</span>
        </div>
      </div>
    </div>
    
    <p class="note">
      💡 VNKey cần quyền Trợ năng để nhận diện và gõ tiếng Việt. 
      <br/><span style="color: var(--color-accent); font-weight: 500;">VNKey tuyệt đối không thu thập bất kỳ thông tin nào, mọi thứ hoạt động hoàn toàn Offline trên máy của bạn.</span>
    </p>
  </main>

  <footer class="footer">
    <button class="btn btn-primary" onclick={requestAccessibility}>
      Cấp quyền trợ năng
    </button>
    <button class="btn btn-secondary" onclick={quitApp}>
      Thoát
    </button>
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
  }

  :global(.light) {
    --bg-app: #f4f4f6;
    --bg-card: #ffffff;
    --text-primary: #1c1c1e;
    --text-secondary: #6c6c78;
    --border-color: rgba(0, 0, 0, 0.08);
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

  .onboarding-container {
    box-sizing: border-box;
    width: 100vw;
    height: 100vh;
    padding: 24px;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    background-color: var(--bg-app);
  }

  .header {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-align: center;
    margin-top: 4px;
    margin-bottom: 12px;
    gap: 8px;
  }

  .logo {
    width: 80px;
    height: 80px;
    border-radius: 20px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.15);
    object-fit: contain;
    transition: transform 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .logo:hover {
    transform: scale(1.1);
  }

  h1 {
    font-size: 17px;
    font-weight: 700;
    color: var(--text-primary);
    margin: 0;
  }

  .subtitle {
    font-size: 11.5px;
    color: var(--text-secondary);
    margin: 0;
    opacity: 0.85;
  }

  .content {
    flex: 1;
    display: flex;
    flex-direction: column;
    justify-content: center;
    margin: 8px 0;
  }

  .steps-timeline {
    display: flex;
    flex-direction: column;
    gap: 16px;
    padding: 16px;
    background-color: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 12px;
    margin-bottom: 12px;
    position: relative;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.12);
  }

  @media (prefers-color-scheme: light) {
    .steps-timeline {
      box-shadow: 0 4px 12px rgba(0, 0, 0, 0.02);
    }
  }

  .timeline-item {
    display: flex;
    gap: 12px;
    position: relative;
  }

  .timeline-item:not(:last-child)::after {
    content: '';
    position: absolute;
    left: 11px;
    top: 24px;
    bottom: -18px;
    width: 2px;
    background-color: var(--border-color);
  }

  .timeline-badge {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background-color: rgba(0, 122, 255, 0.1);
    border: 1px solid rgba(0, 122, 255, 0.2);
    color: var(--color-accent);
    font-weight: 700;
    font-size: 11px;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1;
    flex-shrink: 0;
  }

  .timeline-content {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .timeline-title {
    font-size: 12.5px;
    font-weight: 600;
    color: var(--text-primary);
  }

  .timeline-desc {
    font-size: 11.5px;
    color: var(--text-secondary);
    line-height: 1.4;
  }

  .timeline-desc strong {
    color: var(--text-primary);
  }

  .note {
    font-size: 11px;
    color: var(--text-secondary);
    margin: 0;
    padding: 0 4px;
    text-align: center;
    line-height: 1.4;
  }

  .footer {
    display: flex;
    gap: 12px;
    margin-top: 8px;
  }

  .btn {
    flex: 1;
    padding: 10px 16px;
    font-size: 12.5px;
    font-weight: 600;
    border-radius: 8px;
    border: none;
    cursor: pointer;
    transition: all 0.15s ease;
    text-align: center;
    box-sizing: border-box;
  }

  .btn-primary {
    background-color: var(--color-accent);
    color: white;
    box-shadow: 0 2px 6px rgba(0, 122, 255, 0.2);
  }

  .btn-primary:hover {
    background-color: #006ce6;
    transform: translateY(-1px);
    box-shadow: 0 4px 10px rgba(0, 122, 255, 0.3);
  }

  .btn-primary:active {
    background-color: #0056b3;
    transform: translateY(0);
  }

  .btn-secondary {
    background-color: var(--bg-card);
    color: var(--text-primary);
    border: 1px solid var(--border-color);
  }

  .btn-secondary:hover {
    background-color: rgba(255, 255, 255, 0.04);
  }

  :global(.light) .btn-secondary:hover {
    background-color: rgba(0, 0, 0, 0.03);
  }
</style>
