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
    <h1 style="margin-top: 15px;">Kích hoạt VNKey</h1>
    <p class="subtitle">Bộ gõ tiếng Việt mã nguồn mở thế hệ mới</p>
  </header>

  <main class="content" data-tauri-drag-region>
    <div class="onboarding-card">
      <div class="badge-wrapper">
        <div class="accessibility-badge">
          <!-- Professional accessibility icon: universal access figure in a circle -->
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
            <circle cx="12" cy="12" r="10" />
            <path d="M12 8a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z" />
            <path d="M7 10.5c3.5-1 6.5-1 10 0" />
            <path d="M12 9v5" />
            <path d="M9.5 19.5 12 14l2.5 5.5" />
          </svg>
        </div>
      </div>
      
      <div class="instructions">
        <h2>Cấp quyền Trợ năng (Accessibility)</h2>
        <ol class="steps-list">
          <li>
            <span class="step-num">1</span>
            <span class="step-text">Nhấp nút <strong>Cấp quyền trợ năng</strong> bên dưới để mở Cài đặt Hệ thống.</span>
          </li>
          <li>
            <span class="step-num">2</span>
            <span class="step-text">Tìm <strong>VNKey</strong> và bật công tắc cho phép.</span>
          </li>
        </ol>
      </div>
    </div>
    
    <div class="info-notes">
      <p class="note">
        <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" class="info-icon"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/></svg>
        VNKey cần quyền Trợ năng để nhận diện phím bấm và gõ tiếng Việt.
      </p>
      <p class="note secondary-note">
        VNKey hoạt động hoàn toàn offline trên thiết bị của bạn. Cam kết tuyệt đối không thu thập bất kỳ dữ liệu nào.
      </p>
    </div>
  </main>

  <footer class="footer">
    <button class="btn btn-secondary" onclick={quitApp}>
      Thoát
    </button>
    <button class="btn btn-primary" onclick={requestAccessibility}>
      Cấp quyền trợ năng
    </button>
  </footer>
</div>

<style>
  :root {
    color-scheme: dark;
    --bg-app: #0d0d0e;
    --bg-card: rgba(26, 26, 28, 0.55);
    --text-primary: #f2f2f0;
    --text-secondary: #93939a;
    --color-accent: #4c8dff;
    --accent-rgb: 76, 141, 255;
    --border-color: rgba(255, 255, 255, 0.07);
    --border-color-strong: rgba(255, 255, 255, 0.14);
    --card-shadow: 0 8px 32px rgba(0, 0, 0, 0.35);
  }

  :global(.light) {
    color-scheme: light;
    --bg-app: #f7f7f5;
    --bg-card: rgba(255, 255, 255, 0.75);
    --text-primary: #17171a;
    --text-secondary: #6c6c72;
    --color-accent: #2f6fe0;
    --accent-rgb: 47, 111, 224;
    --border-color: rgba(0, 0, 0, 0.08);
    --border-color-strong: rgba(0, 0, 0, 0.16);
    --card-shadow: 0 8px 32px rgba(0, 0, 0, 0.08);
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
    padding: 24px 30px;
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
    margin-bottom: 8px;
    gap: 6px;
  }

  .logo {
    width: 72px;
    height: 72px;
    border-radius: 18px;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.15);
    object-fit: contain;
    transition: transform 0.3s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  }

  .logo:hover {
    transform: scale(1.08);
    box-shadow: 0 12px 28px rgba(0, 0, 0, 0.2);
  }

  h1 {
    font-size: 18px;
    font-weight: 700;
    color: var(--text-primary);
    margin: 0;
  }

  .subtitle {
    font-size: 12px;
    color: var(--text-secondary);
    margin: 0;
    opacity: 0.85;
  }

  .content {
    flex: 1;
    display: flex;
    flex-direction: column;
    justify-content: center;
    margin: 12px 0;
    gap: 16px;
  }

  .onboarding-card {
    background-color: var(--bg-card);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    border: 1px solid var(--border-color);
    border-radius: 16px;
    padding: 20px;
    box-shadow: var(--card-shadow);
    display: flex;
    align-items: flex-start;
    gap: 20px;
  }

  .badge-wrapper {
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  .accessibility-badge {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: linear-gradient(135deg, var(--color-accent), color-mix(in srgb, var(--color-accent) 60%, black 40%));
    color: #ffffff;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  }

  .accessibility-badge svg {
    width: 20px;
    height: 20px;
  }

  .instructions {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .instructions h2 {
    font-size: 13.5px;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .steps-list {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .steps-list li {
    display: flex;
    align-items: flex-start;
    gap: 8px;
  }

  .step-num {
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background-color: var(--border-color);
    color: var(--text-primary);
    font-size: 10.5px;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    margin-top: 1px;
  }

  .step-text {
    font-size: 12px;
    color: var(--text-secondary);
    line-height: 1.45;
  }

  .step-text strong {
    color: var(--text-primary);
  }

  .info-notes {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 0 8px;
  }

  .note {
    font-size: 11px;
    color: var(--text-secondary);
    margin: 0;
    text-align: center;
    line-height: 1.4;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 4px;
  }

  .info-icon {
    color: var(--color-accent);
    flex-shrink: 0;
  }

  .secondary-note {
    opacity: 0.65;
    font-size: 10.5px;
  }

  .footer {
    display: flex;
    gap: 12px;
    margin-top: 4px;
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
    box-shadow: 0 2px 6px rgba(var(--accent-rgb), 0.2);
  }

  .btn-primary:hover {
    background-color: color-mix(in srgb, var(--color-accent) 85%, white 15%);
    transform: translateY(-1px);
    box-shadow: 0 4px 10px rgba(var(--accent-rgb), 0.3);
  }

  .btn-primary:active {
    background-color: color-mix(in srgb, var(--color-accent) 70%, black 30%);
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
