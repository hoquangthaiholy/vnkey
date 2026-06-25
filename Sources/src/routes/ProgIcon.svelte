<script lang="ts">
  export let size = 24;
</script>

<svg
  xmlns="http://www.w3.org/2000/svg"
  width={size}
  height={size}
  viewBox="0 0 100 100"
  fill="none"
>
  <defs>
    <!-- Background Gradient (Indigo/Violet Tech theme) -->
    <linearGradient id="progBg" x1="0" y1="0" x2="0" y2="100" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#4f46e5"/>
      <stop offset="100%" stop-color="#2a1b6d"/>
    </linearGradient>
    
    <!-- Code Symbol Gradient (Cyan Glow) -->
    <linearGradient id="codeGrad" x1="0" y1="30" x2="0" y2="70" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#67e8f9"/>
      <stop offset="100%" stop-color="#06b6d4"/>
    </linearGradient>

    <!-- Shadow for Depth -->
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="125%" filterUnits="userSpaceOnUse">
      <feDropShadow dx="0" dy="1.5" stdDeviation="1.2" flood-opacity="0.25"/>
    </filter>
    
    <!-- Symbol Glow -->
    <filter id="glow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="1.5" result="blur" />
      <feComposite in="SourceGraphic" in2="blur" operator="over" />
    </filter>

    <!-- Gloss Overlay -->
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="100" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.35"/>
      <stop offset="40%" stop-color="#ffffff" stop-opacity="0.05"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0.1"/>
    </linearGradient>
  </defs>

  <!-- Circular Badge Shadow & Background -->
  <circle cx="50" cy="50" r="46" fill="url(#progBg)" filter="url(#shadow)" stroke="rgba(255,255,255,0.15)" stroke-width="2"/>
  
  <!-- Code brackets </> in the center -->
  <g filter="url(#glow)">
    <!-- Left bracket < -->
    <path d="M36 34 L22 50 L36 66" stroke="url(#codeGrad)" stroke-width="6.5" stroke-linecap="round" stroke-linejoin="round" />
    <!-- Slash / -->
    <path d="M56 30 L44 70" stroke="url(#codeGrad)" stroke-width="6.5" stroke-linecap="round" stroke-linejoin="round" />
    <!-- Right bracket > -->
    <path d="M64 34 L78 50 L64 66" stroke="url(#codeGrad)" stroke-width="6.5" stroke-linecap="round" stroke-linejoin="round" />
  </g>

  <!-- Glossy Reflection -->
  <circle cx="50" cy="50" r="46" fill="url(#gloss)" pointer-events="none"/>
</svg>
