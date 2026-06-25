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
    <!-- Background Gradient -->
    <linearGradient id="vnBg" x1="0" y1="0" x2="0" y2="100" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#ff3b30"/>
      <stop offset="100%" stop-color="#d60000"/>
    </linearGradient>
    <!-- Gold Gradient for Star -->
    <linearGradient id="starGold" x1="50" y1="20" x2="50" y2="80" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#ffe600"/>
      <stop offset="100%" stop-color="#ffb300"/>
    </linearGradient>
    <!-- Shadow for Depth -->
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="125%" filterUnits="userSpaceOnUse">
      <feDropShadow dx="0" dy="1.5" stdDeviation="1.2" flood-opacity="0.25"/>
    </filter>
    <filter id="starShadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="1" stdDeviation="1" flood-color="#000" flood-opacity="0.3"/>
    </filter>
    <!-- Gloss Overlay -->
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="100" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.35"/>
      <stop offset="40%" stop-color="#ffffff" stop-opacity="0.05"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0.1"/>
    </linearGradient>
  </defs>

  <!-- Circular Badge Shadow & Background -->
  <circle cx="50" cy="50" r="46" fill="url(#vnBg)" filter="url(#shadow)" stroke="rgba(255,255,255,0.15)" stroke-width="2"/>
  
  <!-- Centered Gold Star with shadow -->
  <polygon 
    points="50,22 58.5,45.5 83.5,45.5 63.3,60.5 71.2,84 50,69.5 28.8,84 36.7,60.5 16.5,45.5 41.5,45.5" 
    fill="url(#starGold)" 
    filter="url(#starShadow)"
  />

  <!-- Glossy Reflection -->
  <circle cx="50" cy="50" r="46" fill="url(#gloss)" pointer-events="none"/>
</svg>
