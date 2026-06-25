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
    <!-- Circular clip path for the flag content -->
    <clipPath id="circleClip">
      <circle cx="50" cy="50" r="46" />
    </clipPath>
    <!-- Background / Shadow -->
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="125%" filterUnits="userSpaceOnUse">
      <feDropShadow dx="0" dy="1.5" stdDeviation="1.2" flood-opacity="0.25"/>
    </filter>
    <!-- Blue Canton Gradient -->
    <linearGradient id="cantonBg" x1="0" y1="0" x2="0" y2="50" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#1e3c72"/>
      <stop offset="100%" stop-color="#0a1931"/>
    </linearGradient>
    <!-- Red Stripe Gradient -->
    <linearGradient id="redStripe" x1="0" y1="0" x2="0" y2="100" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#ff3b30"/>
      <stop offset="100%" stop-color="#d60000"/>
    </linearGradient>
    <!-- Gloss Overlay -->
    <linearGradient id="gloss" x1="0" y1="0" x2="0" y2="100" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#ffffff" stop-opacity="0.35"/>
      <stop offset="40%" stop-color="#ffffff" stop-opacity="0.05"/>
      <stop offset="100%" stop-color="#000000" stop-opacity="0.1"/>
    </linearGradient>
  </defs>

  <!-- Outer Shadow Circle -->
  <circle cx="50" cy="50" r="46" fill="#ffffff" filter="url(#shadow)" stroke="rgba(255,255,255,0.15)" stroke-width="2"/>

  <!-- Flag Content Clipped to Circle -->
  <g clip-path="url(#circleClip)">
    <!-- White background for white stripes -->
    <rect width="100" height="100" fill="#ffffff" />
    
    <!-- Red Stripes (7 stripes) -->
    <rect y="0" width="100" height="7.7" fill="url(#redStripe)"/>
    <rect y="15.4" width="100" height="7.7" fill="url(#redStripe)"/>
    <rect y="30.8" width="100" height="7.7" fill="url(#redStripe)"/>
    <rect y="46.2" width="100" height="7.7" fill="url(#redStripe)"/>
    <rect y="61.5" width="100" height="7.7" fill="url(#redStripe)"/>
    <rect y="76.9" width="100" height="7.7" fill="url(#redStripe)"/>
    <rect y="92.3" width="100" height="7.7" fill="url(#redStripe)"/>

    <!-- Blue Canton -->
    <rect x="0" y="0" width="52" height="53.8" fill="url(#cantonBg)" />

    <!-- Stylized Stars -->
    <polygon points="26,23 27.5,27.5 32,27.5 28.3,30.3 29.7,34.8 26,32 22.3,34.8 23.7,30.3 20,27.5 24.5,27.5" fill="#ffffff" />
    <polygon points="14,12 15.2,15.6 18.8,15.6 15.8,17.8 17,21.4 14,19.2 11,21.4 12.2,17.8 9.2,15.6 12.8,15.6" fill="#ffffff" />
    <polygon points="38,12 39.2,15.6 42.8,15.6 39.8,17.8 41,21.4 38,19.2 35,21.4 36.2,17.8 33.2,15.6 36.8,15.6" fill="#ffffff" />
    <polygon points="14,36 15.2,39.6 18.8,39.6 15.8,41.8 17,45.4 14,43.2 11,45.4 12.2,41.8 9.2,39.6 12.8,39.6" fill="#ffffff" />
    <polygon points="38,36 39.2,39.6 42.8,39.6 39.8,41.8 41,45.4 38,43.2 35,45.4 36.2,41.8 33.2,39.6 36.8,39.6" fill="#ffffff" />
  </g>

  <!-- Glossy Reflection -->
  <circle cx="50" cy="50" r="46" fill="url(#gloss)" pointer-events="none"/>
</svg>
