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

  :global(html) {
    /* Dark Theme (Default) */
    --hud-bg: linear-gradient(135deg, #1e1e24 0%, #121215 100%);
    --hud-border: rgba(255, 255, 255, 0.15);
    --hud-shadow: 0 12px 30px rgba(0, 0, 0, 0.7), 0 4px 10px rgba(0, 0, 0, 0.4);
    --hud-inset: inset 0 1px 1px rgba(255, 255, 255, 0.1);
    
    --hud-vi-color: #ff5252;
    --hud-vi-glow: rgba(255, 82, 82, 0.4);
    --hud-en-color: #40a9ff;
    --hud-en-glow: rgba(64, 169, 255, 0.4);
    
    --hud-sep: linear-gradient(to bottom, rgba(255, 255, 255, 0.05), rgba(255, 255, 255, 0.38) 50%, rgba(255, 255, 255, 0.05));
    --hud-sub-color: rgba(255, 255, 255, 0.95);
  }

  @media (prefers-color-scheme: light) {
    :global(html) {
      /* Light Theme */
      --hud-bg: linear-gradient(135deg, rgba(255, 255, 255, 0.95) 0%, rgba(245, 245, 247, 0.98) 100%);
      --hud-border: rgba(0, 0, 0, 0.08);
      --hud-shadow: 0 10px 25px rgba(0, 0, 0, 0.15), 0 3px 8px rgba(0, 0, 0, 0.06);
      --hud-inset: inset 0 1px 1px rgba(255, 255, 255, 0.9);
      
      --hud-vi-color: #d63031;
      --hud-vi-glow: rgba(214, 48, 49, 0.15);
      --hud-en-color: #0984e3;
      --hud-en-glow: rgba(9, 132, 227, 0.15);
      
      --hud-sep: linear-gradient(to bottom, rgba(0, 0, 0, 0.03), rgba(0, 0, 0, 0.26) 50%, rgba(0, 0, 0, 0.03));
      --hud-sub-color: rgba(0, 0, 0, 0.8);
    }
  }

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
    transform: translateY(12px) scale(0.96);
    transition: opacity 0.25s cubic-bezier(0.25, 1, 0.5, 1), transform 0.3s cubic-bezier(0.25, 1, 0.5, 1);
    pointer-events: none;
  }

  .root.visible {
    opacity: 1;
    transform: translateY(0) scale(1);
    transition: opacity 0.15s cubic-bezier(0.34, 1.56, 0.64, 1), transform 0.25s cubic-bezier(0.34, 1.56, 0.64, 1);
  }

  .pill {
    display: inline-flex;
    align-items: center;
    width: 180px;
    height: 40px;
    border-radius: 20px; /* Perfect capsule shape */
    background: var(--hud-bg);
    border: 1px solid var(--hud-border);
    box-shadow: var(--hud-shadow), var(--hud-inset);
    overflow: hidden;
  }

  .letter {
    width: 35%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 17px;
    font-weight: 900;
    line-height: 1;
    letter-spacing: 0.05em;
  }
  .pill.vi .letter { 
    color: var(--hud-vi-color); 
    text-shadow: 0 0 12px var(--hud-vi-glow);
  }
  .pill.en .letter { 
    color: var(--hud-en-color); 
    text-shadow: 0 0 12px var(--hud-en-glow);
  }

  .sep {
    display: block;
    width: 1px;
    height: 18px; /* Shorter separator */
    background: var(--hud-sep);
    align-self: center; /* Vertically centered */
    flex-shrink: 0;
  }

  .sub {
    width: 65%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    font-weight: 700;
    color: var(--hud-sub-color);
    line-height: 1;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    white-space: nowrap;
  }
</style>
