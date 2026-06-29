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
    width: 240px;
    height: 80px;
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
    -webkit-font-smoothing: antialiased;
  }

  .root {
    width: 240px;
    height: 80px;
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
    width: 180px;
    height: 40px;
    border-radius: 20px; /* Perfect capsule shape */
    background: #16161a;
    border: 1px solid rgba(255, 255, 255, 0.12);
    /* High quality CSS shadow to replace native macOS shadow */
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.65), 0 2px 6px rgba(0, 0, 0, 0.4);
    overflow: hidden;
  }

  .letter {
    width: 35%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 16px;
    font-weight: 800;
    line-height: 1;
    letter-spacing: 0.04em;
  }
  .pill.vi .letter { color: #ff7675; }
  .pill.en .letter { color: #74b9ff; }

  .sep {
    display: block;
    width: 1px;
    height: 16px; /* Shorter separator */
    background: rgba(255, 255, 255, 0.15);
    align-self: center; /* Vertically centered */
    flex-shrink: 0;
  }

  .sub {
    width: 65%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 13px;
    font-weight: 600;
    color: rgba(255, 255, 255, 0.9);
    line-height: 1;
    letter-spacing: 0.02em;
    white-space: nowrap;
  }
</style>
