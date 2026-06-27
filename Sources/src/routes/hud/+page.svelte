<script lang="ts">
  import { onMount } from 'svelte';
  import { listen } from '@tauri-apps/api/event';

  // Payload format from Rust: "V|Telex", "V|VNI", "E|English"
  let letter = $state<'V' | 'E'>('V');
  let sublabel = $state('Telex');
  let visible = $state(false);

  onMount(() => {
    let unlistenUpdate: (() => void) | undefined;
    let unlistenHide: (() => void) | undefined;

    // Show and update HUD
    listen<string>('hud-update', (event) => {
      const [l, s] = event.payload.split('|');
      letter = (l as 'V' | 'E') ?? 'V';
      sublabel = s ?? 'Telex';
      visible = true;
    }).then(fn => { unlistenUpdate = fn; });

    // Hide HUD (fade-out only, positioning is handled by Rust)
    listen<void>('hud-hide', () => {
      visible = false;
    }).then(fn => { unlistenHide = fn; });

    return () => {
      if (unlistenUpdate) unlistenUpdate();
      if (unlistenHide) unlistenHide();
    };
  });
</script>

<svelte:head><title>VNKey HUD</title></svelte:head>

<div class="root" class:visible>
  <div class="pill" class:vi={letter === 'V'} class:en={letter === 'E'}>
    <span class="letter">{letter}</span>
    <span class="sep"></span>
    <span class="sub">{sublabel}</span>
  </div>
</div>

<style>
  :global(*) { margin: 0; padding: 0; box-sizing: border-box; }

  :global(html, body) {
    background: transparent !important;
    overflow: hidden;
    width: 160px;
    height: 40px;
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
    -webkit-font-smoothing: antialiased;
  }

  .root {
    width: 160px;
    height: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    opacity: 0;
    transform: translateY(3px) scale(0.95);
    transition: opacity 0.3s ease-out, transform 0.3s ease-out;
    pointer-events: none;
  }

  .root.visible {
    opacity: 1;
    transform: translateY(0) scale(1);
    transition: opacity 0.1s ease-out, transform 0.16s cubic-bezier(0.34, 1.56, 0.64, 1);
  }

  .pill {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 130px;
    height: 28px;
    border-radius: 14px; /* Perfect capsule shape */
    /* Semi-opaque solid dark background — NO backdrop-filter to prevent macOS GPU lag */
    background: #1a1a1e;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.45);
    gap: 0;
  }

  .letter {
    font-size: 13px;
    font-weight: 700;
    line-height: 1;
    letter-spacing: 0.04em;
    width: 14px;
    text-align: center;
  }
  .pill.vi .letter { color: #ff7675; }
  .pill.en .letter { color: #74b9ff; }

  .sep {
    display: block;
    width: 1px;
    height: 10px;
    background: rgba(255, 255, 255, 0.15);
    margin: 0 8px;
    flex-shrink: 0;
  }

  .sub {
    font-size: 11.5px;
    font-weight: 600;
    color: rgba(255, 255, 255, 0.85);
    line-height: 1;
    letter-spacing: 0.02em;
    white-space: nowrap;
  }
</style>
