const fs = require('fs');
const path = require('path');

const placeholders = [
  {
    filename: 'bed-divan.svg',
    title: 'DIVAN BED & MATTRESS',
    caption: 'Illustration only — not a product photograph',
    icon: `
      <path d="M120 340 h560 v30 h-560 z" fill="#014660" opacity="0.85"/>
      <path d="M130 280 h540 v60 h-540 z" fill="#D8D2C5" stroke="#014660" stroke-width="3"/>
      <path d="M120 180 h100 v160 h-100 z" fill="#E8E3DA" stroke="#014660" stroke-width="3"/>
      <line x1="220" y1="280" x2="670" y2="280" stroke="#014660" stroke-width="3"/>
      <path d="M240 250 c20 -20 60 -20 80 0 v30 h-80 z" fill="#C29B38" opacity="0.6"/>
      <path d="M340 250 c20 -20 60 -20 80 0 v30 h-80 z" fill="#C29B38" opacity="0.6"/>
      <line x1="300" y1="340" x2="300" y2="370" stroke="#014660" stroke-width="4"/>
      <line x1="500" y1="340" x2="500" y2="370" stroke="#014660" stroke-width="4"/>
    `
  },
  {
    filename: 'wardrobe.svg',
    title: 'BEDROOM WARDROBE',
    caption: 'Illustration only — not a product photograph',
    icon: `
      <rect x="250" y="140" width="300" height="260" rx="4" fill="#EAE5DC" stroke="#014660" stroke-width="4"/>
      <line x1="400" y1="140" x2="400" y2="340" stroke="#014660" stroke-width="3"/>
      <line x1="250" y1="340" x2="550" y2="340" stroke="#014660" stroke-width="3"/>
      <line x1="400" y1="340" x2="400" y2="400" stroke="#014660" stroke-width="3"/>
      <circle cx="380" cy="240" r="5" fill="#C29B38"/>
      <circle cx="420" cy="240" r="5" fill="#C29B38"/>
      <circle cx="325" cy="370" r="4" fill="#C29B38"/>
      <circle cx="475" cy="370" r="4" fill="#C29B38"/>
      <line x1="260" y1="400" x2="260" y2="415" stroke="#014660" stroke-width="5"/>
      <line x1="540" y1="400" x2="540" y2="415" stroke="#014660" stroke-width="5"/>
    `
  },
  {
    filename: 'chest.svg',
    title: 'CHEST OF DRAWERS',
    caption: 'Illustration only — not a product photograph',
    icon: `
      <rect x="270" y="160" width="260" height="240" rx="4" fill="#EAE5DC" stroke="#014660" stroke-width="4"/>
      <line x1="270" y1="220" x2="530" y2="220" stroke="#014660" stroke-width="3"/>
      <line x1="270" y1="280" x2="530" y2="280" stroke="#014660" stroke-width="3"/>
      <line x1="270" y1="340" x2="530" y2="340" stroke="#014660" stroke-width="3"/>
      <rect x="370" y="185" width="60" height="8" rx="3" fill="#C29B38"/>
      <rect x="370" y="245" width="60" height="8" rx="3" fill="#C29B38"/>
      <rect x="370" y="305" width="60" height="8" rx="3" fill="#C29B38"/>
      <rect x="370" y="365" width="60" height="8" rx="3" fill="#C29B38"/>
      <line x1="285" y1="400" x2="285" y2="415" stroke="#014660" stroke-width="5"/>
      <line x1="515" y1="400" x2="515" y2="415" stroke="#014660" stroke-width="5"/>
    `
  },
  {
    filename: 'bed-frame.svg',
    title: 'BED FRAME',
    caption: 'Illustration only — not a product photograph',
    icon: `
      <line x1="160" y1="160" x2="160" y2="380" stroke="#014660" stroke-width="5"/>
      <line x1="640" y1="240" x2="640" y2="380" stroke="#014660" stroke-width="5"/>
      <rect x="160" y="300" width="480" height="20" fill="#C29B38" opacity="0.8"/>
      <line x1="160" y1="180" x2="260" y2="180" stroke="#014660" stroke-width="4"/>
      <line x1="160" y1="230" x2="260" y2="230" stroke="#014660" stroke-width="4"/>
      <line x1="200" y1="160" x2="200" y2="300" stroke="#014660" stroke-width="3"/>
      <line x1="230" y1="160" x2="230" y2="300" stroke="#014660" stroke-width="3"/>
      <line x1="560" y1="240" x2="640" y2="240" stroke="#014660" stroke-width="4"/>
      <line x1="600" y1="240" x2="600" y2="300" stroke="#014660" stroke-width="3"/>
      <path d="M220 280 l400 0" stroke="#014660" stroke-width="4"/>
    `
  },
  {
    filename: 'bunk.svg',
    title: 'BUNK BED',
    caption: 'Illustration only — not a product photograph',
    icon: `
      <line x1="200" y1="130" x2="200" y2="410" stroke="#014660" stroke-width="5"/>
      <line x1="600" y1="130" x2="600" y2="410" stroke="#014660" stroke-width="5"/>
      <rect x="200" y="200" width="400" height="18" fill="#D8D2C5" stroke="#014660" stroke-width="3"/>
      <rect x="200" y="340" width="400" height="18" fill="#D8D2C5" stroke="#014660" stroke-width="3"/>
      <line x1="200" y1="160" x2="600" y2="160" stroke="#C29B38" stroke-width="4"/>
      <line x1="200" y1="300" x2="600" y2="300" stroke="#C29B38" stroke-width="4"/>
      <line x1="530" y1="140" x2="530" y2="400" stroke="#014660" stroke-width="3"/>
      <line x1="570" y1="140" x2="570" y2="400" stroke="#014660" stroke-width="3"/>
      <line x1="530" y1="170" x2="570" y2="170" stroke="#014660" stroke-width="3"/>
      <line x1="530" y1="220" x2="570" y2="220" stroke="#014660" stroke-width="3"/>
      <line x1="530" y1="270" x2="570" y2="270" stroke="#014660" stroke-width="3"/>
      <line x1="530" y1="320" x2="570" y2="320" stroke="#014660" stroke-width="3"/>
      <line x1="530" y1="370" x2="570" y2="370" stroke="#014660" stroke-width="3"/>
    `
  },
  {
    filename: 'dining-table.svg',
    title: 'DINING FURNITURE',
    caption: 'Illustration only — not a product photograph',
    icon: `
      <rect x="220" y="240" width="360" height="20" rx="3" fill="#C29B38" stroke="#014660" stroke-width="3"/>
      <line x1="250" y1="260" x2="250" y2="390" stroke="#014660" stroke-width="6"/>
      <line x1="550" y1="260" x2="550" y2="390" stroke="#014660" stroke-width="6"/>
      <path d="M160 210 h40 v90 h-40 z" fill="#EAE5DC" stroke="#014660" stroke-width="3"/>
      <line x1="160" y1="300" x2="160" y2="390" stroke="#014660" stroke-width="4"/>
      <line x1="200" y1="300" x2="200" y2="390" stroke="#014660" stroke-width="4"/>
      <path d="M600 210 h40 v90 h-40 z" fill="#EAE5DC" stroke="#014660" stroke-width="3"/>
      <line x1="600" y1="300" x2="600" y2="390" stroke="#014660" stroke-width="4"/>
      <line x1="640" y1="300" x2="640" y2="390" stroke="#014660" stroke-width="4"/>
    `
  },
  {
    filename: 'sofa.svg',
    title: 'SOFAS & LIVING ROOM',
    caption: 'Illustration only — not a product photograph',
    icon: `
      <path d="M170 240 c0 -30 20 -50 50 -50 h360 c30 0 50 20 50 50 v110 h-460 z" fill="#E3DFD5" stroke="#014660" stroke-width="4"/>
      <rect x="150" y="250" width="70" height="110" rx="10" fill="#014660" opacity="0.9"/>
      <rect x="580" y="250" width="70" height="110" rx="10" fill="#014660" opacity="0.9"/>
      <rect x="220" y="290" width="360" height="70" rx="6" fill="#FAF8F5" stroke="#014660" stroke-width="3"/>
      <line x1="340" y1="290" x2="340" y2="360" stroke="#014660" stroke-width="2"/>
      <line x1="460" y1="290" x2="460" y2="360" stroke="#014660" stroke-width="2"/>
      <line x1="200" y1="360" x2="190" y2="390" stroke="#C29B38" stroke-width="5"/>
      <line x1="600" y1="360" x2="610" y2="390" stroke="#C29B38" stroke-width="5"/>
    `
  },
  {
    filename: 'coffee-table.svg',
    title: 'COFFEE TABLE',
    caption: 'Illustration only — not a product photograph',
    icon: `
      <rect x="220" y="250" width="360" height="18" rx="4" fill="#C29B38" stroke="#014660" stroke-width="3"/>
      <rect x="260" y="320" width="280" height="10" rx="2" fill="#E3DFD5" stroke="#014660" stroke-width="2"/>
      <line x1="250" y1="268" x2="240" y2="380" stroke="#014660" stroke-width="5"/>
      <line x1="550" y1="268" x2="560" y2="380" stroke="#014660" stroke-width="5"/>
    `
  },
  {
    filename: 'appliance.svg',
    title: 'APPLIANCES',
    caption: 'Illustration only — not a product photograph',
    icon: `
      <rect x="270" y="140" width="260" height="260" rx="8" fill="#F4F2EC" stroke="#014660" stroke-width="4"/>
      <line x1="270" y1="240" x2="530" y2="240" stroke="#014660" stroke-width="3"/>
      <rect x="290" y="170" width="12" height="40" rx="3" fill="#C29B38"/>
      <rect x="290" y="270" width="12" height="50" rx="3" fill="#C29B38"/>
      <circle cx="480" cy="180" r="8" fill="#046700" opacity="0.7"/>
    `
  },
  {
    filename: 'van.svg',
    title: 'FURNITURE REMOVALS',
    caption: 'Furniture removal service',
    icon: `
      <path d="M180 230 h250 v110 h-250 z" fill="#EAE5DC" stroke="#014660" stroke-width="4"/>
      <path d="M430 260 h80 l40 40 v40 h-120 z" fill="#014660" stroke="#014660" stroke-width="3"/>
      <rect x="445" y="270" width="55" height="30" rx="3" fill="#FAF8F5"/>
      <circle cx="260" cy="350" r="28" fill="#333" stroke="#C29B38" stroke-width="4"/>
      <circle cx="260" cy="350" r="10" fill="#FAF8F5"/>
      <circle cx="480" cy="350" r="28" fill="#333" stroke="#C29B38" stroke-width="4"/>
      <circle cx="480" cy="350" r="10" fill="#FAF8F5"/>
      <line x1="310" y1="280" x2="390" y2="280" stroke="#046700" stroke-width="4"/>
      <line x1="310" y1="300" x2="370" y2="300" stroke="#046700" stroke-width="4"/>
    `
  }
];

placeholders.forEach(p => {
  const safeTitle = p.title.replace(/&/g, '&amp;');
  const safeCaption = p.caption.replace(/&/g, '&amp;');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 560" width="800" height="560">
  <defs>
    <linearGradient id="bgGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#FBF9F5"/>
      <stop offset="100%" stop-color="#EFEAE1"/>
    </linearGradient>
    <pattern id="archGrid" width="40" height="40" patternUnits="userSpaceOnUse">
      <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#E6E0D5" stroke-width="0.8"/>
    </pattern>
  </defs>

  <!-- Background Canvas -->
  <rect width="800" height="560" fill="url(#bgGrad)"/>
  <rect width="800" height="560" fill="url(#archGrid)" opacity="0.75"/>

  <!-- Elegant Inner Border -->
  <rect x="24" y="24" width="752" height="512" fill="none" stroke="#DCD6CA" stroke-width="1.5"/>
  <rect x="32" y="32" width="736" height="496" fill="none" stroke="#ECE7DE" stroke-width="1"/>

  <!-- Corner Brass Accents -->
  <path d="M 24 44 L 24 24 L 44 24" fill="none" stroke="#C29B38" stroke-width="2.5"/>
  <path d="M 776 44 L 776 24 L 756 24" fill="none" stroke="#C29B38" stroke-width="2.5"/>
  <path d="M 24 516 L 24 536 L 44 536" fill="none" stroke="#C29B38" stroke-width="2.5"/>
  <path d="M 776 516 L 776 536 L 756 536" fill="none" stroke="#C29B38" stroke-width="2.5"/>

  <!-- Top Brand Watermark -->
  <text x="50" y="68" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="11" font-weight="700" letter-spacing="3" fill="#014660">GBA FURNITURE</text>
  <text x="750" y="68" text-anchor="end" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="11" font-weight="600" letter-spacing="1" fill="#8C7A58">401 LORDSHIP LANE, N17 6AE</text>

  <!-- Central Illustrated Silhouette -->
  <g id="illustration">
${p.icon}
  </g>

  <!-- Bottom Editorial Caption Badge -->
  <rect x="160" y="440" width="480" height="56" rx="4" fill="#FFFFFF" fill-opacity="0.94" stroke="#DCD6CA" stroke-width="1.5"/>
  <text x="400" y="463" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="12" font-weight="700" letter-spacing="2" fill="#014660">${safeTitle}</text>
  <text x="400" y="482" text-anchor="middle" font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif" font-size="11" font-weight="500" fill="#7A746B">${safeCaption}</text>
</svg>`;

  const cleanSvg = svg.replace(/[ \t]+$/gm, '').trim();
  fs.writeFileSync(path.join(__dirname, 'assets/placeholders', p.filename), cleanSvg);
  console.log('Generated:', p.filename);
});
