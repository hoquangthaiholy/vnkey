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
    gray_icon: number;
  }

  let settings = $state<Settings>({
    language: 1,
    input_type: 0,
    free_mark: 0,
    code_table: 0,
    switch_key_status: 0x7A000206, // Option + Z
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
    gray_icon: 1,
  });

  let activeTab = $state(0);
  let isSaving = $state(false);
  let hasAccessibility = $state(true);

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

  onMount(() => {
    let pollingInterval: number | undefined;
    let stopListeningSettings: (() => void) | undefined;
    let stopListeningAccessibility: (() => void) | undefined;

    checkAccessibility().then((granted) => {
      if (granted) {
        loadSettings();
      } else {
        pollingInterval = window.setInterval(async () => {
          const ok = await checkAccessibility();
          if (ok) {
            loadSettings();
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
      if (pollingInterval) clearInterval(pollingInterval);
    };
  });

  function handleCheckboxChange(key: keyof Settings, value: boolean) {
    settings[key] = value ? 1 : 0;
    saveSettings();
  }

  function handleSelectChange(key: keyof Settings, value: number) {
    settings[key] = value;
    saveSettings();
  }
</script>

{#if !hasAccessibility}
  <div class="welcome-screen">
    <div class="welcome-card">
      <div class="welcome-icon">V</div>
      <h1>Chào mừng đến với VNKey</h1>
      <p class="welcome-desc">
        VNKey cần quyền <strong>Trợ năng (Accessibility)</strong> để có thể nhận diện phím gõ tiếng Việt trên macOS.
      </p>

      <div class="steps">
        <h3>Các bước kích hoạt:</h3>
        <ol>
          <li>Nhấp vào nút <strong>Cấp quyền trợ năng</strong> bên dưới.</li>
          <li>Chọn <strong>Mở Cài đặt hệ thống (Open System Settings)</strong> trong hộp thoại.</li>
          <li>Tìm <strong>VNKey</strong> và bật công tắc cho phép.</li>
        </ol>
      </div>

      <div class="welcome-actions">
        <button class="btn btn-primary" onclick={requestAccessibility}>Cấp quyền trợ năng</button>
        <button class="btn btn-secondary" onclick={() => invoke("quit")}>Thoát ứng dụng</button>
      </div>
    </div>
  </div>
{:else}
  <div class="app-layout">
    <!-- Sidebar -->
    <aside class="sidebar">
      <div class="sidebar-header">
        <span class="logo">V</span>
        <span class="title">VNKey</span>
      </div>
      <nav class="nav-menu">
        <button class="nav-item" class:active={activeTab === 0} onclick={() => activeTab = 0}>
           Gõ phím
        </button>
        <button class="nav-item" class:active={activeTab === 1} onclick={() => activeTab = 1}>
           Gõ tắt
        </button>
        <button class="nav-item" class:active={activeTab === 2} onclick={() => activeTab = 2}>
           Hệ thống
        </button>
        <button class="nav-item" class:active={activeTab === 3} onclick={() => activeTab = 3}>
           Thông tin
        </button>
      </nav>
      <div class="sidebar-footer">
        <span class="status-indicator" class:saving={isSaving}></span>
        <span class="status-text">{isSaving ? "Đang lưu..." : "Đã đồng bộ"}</span>
      </div>
    </aside>

    <!-- Main Content Area -->
    <main class="content-area">
      <!-- Active Tab Panel -->
      {#if activeTab === 0}
        <section class="panel">
          <h2>Điều khiển & Nhân gõ</h2>
          
          <div class="card">
            <h3>Cấu hình chính</h3>
            <div class="form-row">
              <div class="form-group">
                <label for="input-type">Kiểu gõ</label>
                <select id="input-type" value={settings.input_type} onchange={(e) => handleSelectChange('input_type', parseInt((e.target as HTMLSelectElement).value))}>
                  <option value={0}>Telex</option>
                  <option value={1}>VNI</option>
                  <option value={2}>Simple Telex 1</option>
                  <option value={3}>Simple Telex 2</option>
                </select>
              </div>
              <div class="form-group">
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
            <div class="form-group mt-15">
              <label>Chế độ hoạt động</label>
              <div class="radio-group">
                <label class="radio-label">
                  <input type="radio" name="language" checked={settings.language === 1} onclick={() => handleSelectChange('language', 1)} />
                  Tiếng Việt
                </label>
                <label class="radio-label">
                  <input type="radio" name="language" checked={settings.language === 0} onclick={() => handleSelectChange('language', 0)} />
                  English
                </label>
              </div>
            </div>
          </div>

          <div class="card">
            <h3>Quy tắc gõ dấu & Chính tả</h3>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.free_mark === 1} onchange={(e) => handleCheckboxChange('free_mark', (e.target as HTMLInputElement).checked)} />
              Cho phép bỏ dấu tự do
            </label>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.use_modern_orthography === 1} onchange={(e) => handleCheckboxChange('use_modern_orthography', (e.target as HTMLInputElement).checked)} />
              Đặt dấu oà, uý (thay vì òa, úy)
            </label>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.check_spelling === 1} onchange={(e) => handleCheckboxChange('check_spelling', (e.target as HTMLInputElement).checked)} />
              Kiểm tra chính tả
            </label>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.restore_if_wrong_spelling === 1} onchange={(e) => handleCheckboxChange('restore_if_wrong_spelling', (e.target as HTMLInputElement).checked)} />
              Tự động khôi phục từ khi gõ sai chính tả
            </label>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.upper_case_first_char === 1} onchange={(e) => handleCheckboxChange('upper_case_first_char', (e.target as HTMLInputElement).checked)} />
              Viết hoa chữ cái đầu tiên của câu
            </label>
          </div>
        </section>
      {:else if activeTab === 1}
        <section class="panel">
          <h2>Gõ tắt (Macro)</h2>
          <div class="card">
            <h3>Tùy chọn gõ tắt</h3>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.use_macro === 1} onchange={(e) => handleCheckboxChange('use_macro', (e.target as HTMLInputElement).checked)} />
              Cho phép gõ tắt
            </label>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.use_macro_in_english_mode === 1} onchange={(e) => handleCheckboxChange('use_macro_in_english_mode', (e.target as HTMLInputElement).checked)} />
              Cho phép gõ tắt ở chế độ tiếng Anh
            </label>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.auto_caps_macro === 1} onchange={(e) => handleCheckboxChange('auto_caps_macro', (e.target as HTMLInputElement).checked)} />
              Tự động viết hoa từ gõ tắt
            </label>

            <button class="btn btn-primary mt-20">
              Thiết lập bảng gõ tắt...
            </button>
          </div>
        </section>
      {:else if activeTab === 2}
        <section class="panel">
          <h2>Thiết lập hệ thống</h2>
          <div class="card">
            <h3>Khởi động & Hiển thị</h3>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.use_smart_switch_key === 1} onchange={(e) => handleCheckboxChange('use_smart_switch_key', (e.target as HTMLInputElement).checked)} />
              Chuyển chế độ gõ thông minh theo từng ứng dụng
            </label>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.other_language === 1} onchange={(e) => handleCheckboxChange('other_language', (e.target as HTMLInputElement).checked)} />
              Tắt tiếng Việt khi bộ gõ hệ thống khác tiếng Anh
            </label>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.remember_code === 1} onchange={(e) => handleCheckboxChange('remember_code', (e.target as HTMLInputElement).checked)} />
              Tự động nhớ bảng mã cho từng ứng dụng
            </label>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.temp_off_vnkey === 1} onchange={(e) => handleCheckboxChange('temp_off_vnkey', (e.target as HTMLInputElement).checked)} />
              Tạm tắt bộ gõ bằng phím tắt
            </label>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.gray_icon === 1} onchange={(e) => handleCheckboxChange('gray_icon', (e.target as HTMLInputElement).checked)} />
              Biểu tượng xám trên thanh menu (Template mode)
            </label>
          </div>
          
          <div class="card">
            <h3>Tương thích & Sửa lỗi</h3>
            <label class="checkbox-label">
              <input type="checkbox" checked={settings.fix_recommend_browser === 1} onchange={(e) => handleCheckboxChange('fix_recommend_browser', (e.target as HTMLInputElement).checked)} />
              Khắc phục lỗi trên thanh địa chỉ trình duyệt
            </label>
          </div>
        </section>
      {:else}
        <section class="panel">
          <h2>Thông tin ứng dụng</h2>
          <div class="card info-card">
            <div class="info-header">
              <div class="app-icon">V</div>
              <div>
                <h3>VNKey</h3>
                <p class="version">Phiên bản 2.0.0 (Tauri Build)</p>
              </div>
            </div>
            <p class="desc">Bộ gõ Tiếng Việt nguồn mở, gọn nhẹ và đa nền tảng cho macOS, Windows và Linux.</p>
            
            <div class="links-grid">
              <a href="https://vn-key.org" target="_blank" class="link-item">Trang chủ</a>
              <a href="https://github.com/tuyenvm/VNKey" target="_blank" class="link-item">GitHub</a>
              <a href="https://www.facebook.com/VNKey" target="_blank" class="link-item">Fanpage</a>
            </div>
          </div>
        </section>
      {/if}
    </main>
  </div>
{/if}

<style>
  :root {
    --bg-app: #1e1e24;
    --bg-sidebar: #121216;
    --bg-card: #282830;
    --text-primary: #f5f5f7;
    --text-secondary: #8e8e93;
    --color-accent: #007aff;
    --color-success: #34c759;
    --border-color: rgba(255, 255, 255, 0.08);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }

  @media (prefers-color-scheme: light) {
    :root {
      --bg-app: #f5f5f7;
      --bg-sidebar: #e5e5ea;
      --bg-card: #ffffff;
      --text-primary: #1c1c1e;
      --text-secondary: #68686e;
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
  }

  .app-layout {
    display: flex;
    width: 100vw;
    height: 100vh;
  }

  /* Sidebar */
  .sidebar {
    width: 180px;
    background-color: var(--bg-sidebar);
    border-right: 1px solid var(--border-color);
    display: flex;
    flex-direction: column;
    padding: 20px 10px;
  }

  .sidebar-header {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 10px 25px 10px;
  }

  .sidebar-header .logo {
    width: 28px;
    height: 28px;
    background-color: var(--color-accent);
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 6px;
    font-weight: bold;
    font-size: 16px;
  }

  .sidebar-header .title {
    font-weight: bold;
    font-size: 18px;
  }

  .nav-menu {
    display: flex;
    flex-direction: column;
    gap: 6px;
    flex-grow: 1;
  }

  .nav-item {
    background: none;
    border: none;
    outline: none;
    color: var(--text-secondary);
    padding: 10px 12px;
    text-align: left;
    border-radius: 8px;
    font-size: 14px;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 10px;
    transition: all 0.2s ease;
  }

  .nav-item:hover {
    background-color: rgba(255, 255, 255, 0.04);
    color: var(--text-primary);
  }

  :global(.light-theme) .nav-item:hover {
    background-color: rgba(0, 0, 0, 0.04);
  }

  .nav-item.active {
    background-color: var(--color-accent);
    color: white;
  }

  .sidebar-footer {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px;
    font-size: 12px;
    color: var(--text-secondary);
  }

  .status-indicator {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background-color: var(--color-success);
    transition: background-color 0.2s ease;
  }

  .status-indicator.saving {
    background-color: #ff9500;
  }

  /* Content Area */
  .content-area {
    flex-grow: 1;
    padding: 30px;
    overflow-y: auto;
  }

  .panel h2 {
    margin-top: 0;
    margin-bottom: 20px;
    font-size: 22px;
    font-weight: 700;
  }

  .card {
    background-color: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 12px;
    padding: 20px;
    margin-bottom: 20px;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.02);
  }

  .card h3 {
    margin-top: 0;
    margin-bottom: 15px;
    font-size: 15px;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  /* Forms */
  .form-row {
    display: flex;
    gap: 20px;
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: 6px;
    flex-grow: 1;
  }

  .form-group label {
    font-size: 13px;
    color: var(--text-secondary);
  }

  select {
    padding: 8px 12px;
    border-radius: 8px;
    background-color: var(--bg-app);
    color: var(--text-primary);
    border: 1px solid var(--border-color);
    outline: none;
    font-size: 14px;
  }

  .radio-group {
    display: flex;
    gap: 20px;
  }

  .radio-label {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 14px;
    cursor: pointer;
  }

  .checkbox-label {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-bottom: 12px;
    font-size: 14px;
    cursor: pointer;
  }

  .checkbox-label:last-child {
    margin-bottom: 0;
  }

  input[type="checkbox"],
  input[type="radio"] {
    width: 16px;
    height: 16px;
    cursor: pointer;
  }

  /* Buttons */
  .btn {
    border: none;
    outline: none;
    padding: 10px 20px;
    border-radius: 8px;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    transition: background-color 0.2s ease;
  }

  .btn-primary {
    background-color: var(--color-accent);
    color: white;
  }

  .btn-primary:hover {
    background-color: #0062cc;
  }

  .btn-secondary {
    background-color: transparent;
    color: var(--text-primary);
    border: 1px solid var(--border-color);
  }

  .btn-secondary:hover {
    background-color: rgba(255, 255, 255, 0.05);
  }

  @media (prefers-color-scheme: light) {
    .btn-secondary:hover {
      background-color: rgba(0, 0, 0, 0.05);
    }
  }

  /* Info Screen */
  .info-card {
    display: flex;
    flex-direction: column;
    gap: 15px;
  }

  .info-header {
    display: flex;
    align-items: center;
    gap: 15px;
  }

  .info-header h3 {
    margin: 0;
    text-transform: none;
    font-size: 20px;
    color: var(--text-primary);
  }

  .info-header .version {
    font-size: 13px;
    color: var(--text-secondary);
    margin: 4px 0 0 0;
  }

  .app-icon {
    width: 50px;
    height: 50px;
    background-color: var(--color-accent);
    color: white;
    border-radius: 12px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 28px;
    font-weight: bold;
  }

  .desc {
    font-size: 14px;
    line-height: 1.5;
    color: var(--text-secondary);
  }

  .links-grid {
    display: flex;
    gap: 15px;
    margin-top: 10px;
  }

  .link-item {
    color: var(--color-accent);
    text-decoration: none;
    font-size: 14px;
  }

  .link-item:hover {
    text-decoration: underline;
  }

  /* Utilities */
  .mt-15 { margin-top: 15px; }
  .mt-20 { margin-top: 20px; }

  /* Accessibility Onboarding Screen */
  .welcome-screen {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 100vw;
    height: 100vh;
    background-color: var(--bg-app);
  }

  .welcome-card {
    max-width: 420px;
    width: 90%;
    padding: 30px;
    background-color: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 16px;
    box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
    text-align: center;
  }

  .welcome-icon {
    width: 56px;
    height: 56px;
    margin: 0 auto 20px;
    background-color: var(--color-accent);
    color: white;
    font-size: 28px;
    font-weight: bold;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 14px;
  }

  .welcome-card h1 {
    font-size: 20px;
    font-weight: bold;
    margin: 0 0 10px;
    color: var(--text-primary);
  }

  .welcome-desc {
    font-size: 13.5px;
    line-height: 1.5;
    color: var(--text-secondary);
    margin: 0 0 20px;
  }

  .welcome-desc strong {
    color: var(--text-primary);
  }

  .steps {
    background-color: rgba(0, 0, 0, 0.15);
    border: 1px solid var(--border-color);
    border-radius: 10px;
    padding: 15px 18px;
    margin-bottom: 24px;
    text-align: left;
  }

  @media (prefers-color-scheme: light) {
    .steps {
      background-color: rgba(0, 0, 0, 0.03);
    }
  }

  .steps h3 {
    margin: 0 0 8px;
    font-size: 11px;
    font-weight: bold;
    text-transform: uppercase;
    color: var(--text-secondary);
    letter-spacing: 0.5px;
  }

  .steps ol {
    margin: 0;
    padding-left: 18px;
    font-size: 13px;
    color: var(--text-secondary);
    line-height: 1.5;
  }

  .steps li strong {
    color: var(--text-primary);
  }

  .welcome-actions {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .welcome-actions .btn {
    width: 100%;
    padding: 12px;
  }
</style>
