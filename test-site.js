/**
 * GBA Furniture — Prototype Verification Suite
 * Automated tests for HTML structure, CSS rules, catalog data integrity,
 * accessibility attributes, contact details, absence of unsupported claims
 * and banned provenance/placeholder language across HTML/JS/JSON/SVG,
 * honest form behaviour, and HTTP server delivery.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');
const vm = require('vm');
const crypto = require('crypto');

let totalTests = 0;
let passedTests = 0;
let failedTests = 0;

function assert(condition, message) {
  totalTests++;
  if (condition) {
    passedTests++;
    console.log(`  ✓ ${message}`);
  } else {
    failedTests++;
    console.error(`  ✗ FAIL: ${message}`);
  }
}

console.log('=== GBA Furniture Grounded Prototype Verification ===\n');

// 1. File existence checks
console.log('1. Checking File Existence:');
const svgFiles = [
  'assets/placeholders/bed-divan.svg',
  'assets/placeholders/wardrobe.svg',
  'assets/placeholders/chest.svg',
  'assets/placeholders/bed-frame.svg',
  'assets/placeholders/bunk.svg',
  'assets/placeholders/dining-table.svg',
  'assets/placeholders/sofa.svg',
  'assets/placeholders/coffee-table.svg',
  'assets/placeholders/appliance.svg',
  'assets/placeholders/van.svg'
];

const requiredFiles = [
  'index.html',
  'styles.css',
  'script.js',
  'README.md',
  'serve.js',
  'generate-placeholders.js',
  'data/products.json',
  'assets/gba-logo-official-transparent.png',
  'assets/gba-logo-web.png',
  'assets/gba-logo.png',
  'assets/current-banner.jpg',
  ...svgFiles
];

requiredFiles.forEach(file => {
  const filePath = path.join(__dirname, file);
  assert(fs.existsSync(filePath), `File exists: ${file}`);
});

// 2. Data Integrity & Synchronisation Checks
console.log('\n2. Checking Catalogue Data Integrity & Synchronisation:');
const rawData = fs.readFileSync(path.join(__dirname, 'data/products.json'), 'utf8');
const data = JSON.parse(rawData);
const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const js = fs.readFileSync(path.join(__dirname, 'script.js'), 'utf8');
const generatorJs = fs.readFileSync(path.join(__dirname, 'generate-placeholders.js'), 'utf8');
const svgContents = svgFiles.map(file => ({
  file,
  content: fs.readFileSync(path.join(__dirname, file), 'utf8')
}));

assert(Array.isArray(data.categories) && data.categories.length === 7, 'Exactly 7 furniture categories present in products.json');

const expectedCategories = [
  { id: 'beds-mattresses', name: 'Beds & Mattresses', shortName: 'Beds' },
  { id: 'bedroom-storage', name: 'Bedroom Storage', shortName: 'Storage' },
  { id: 'bed-frames-bunks', name: 'Bed Frames & Bunk Beds', shortName: 'Frames & Bunks' },
  { id: 'dining', name: 'Dining Furniture', shortName: 'Dining' },
  { id: 'sofas-living', name: 'Sofas & Living Room', shortName: 'Sofas & Living' },
  { id: 'appliances', name: 'Appliances', shortName: 'Appliances' },
  { id: 'removals', name: 'Furniture Removals', shortName: 'Removals' }
];

expectedCategories.forEach(expected => {
  const cat = data.categories.find(c => c.id === expected.id);
  assert(
    Boolean(cat) && cat.name === expected.name && cat.shortName === expected.shortName,
    `Category ${expected.id} has exact public name "${expected.name}" and shortName "${expected.shortName}"`
  );
});

assert(Array.isArray(data.products) && data.products.length === 26, `Catalogue has exactly 26 products (found ${data.products.length})`);

let allPricesValid = true;
let startingPricesMatchMin = true;
let totalVariants = 0;
let totalAddons = 0;
data.products.forEach(p => {
  if (typeof p.startingPrice !== 'number' || p.startingPrice <= 0) allPricesValid = false;
  if (!Array.isArray(p.variants) || p.variants.length === 0) {
    allPricesValid = false;
    startingPricesMatchMin = false;
  } else {
    const minVariantPrice = Math.min(...p.variants.map(v => v.price));
    if (p.startingPrice !== minVariantPrice) startingPricesMatchMin = false;
  }
  p.variants.forEach(v => {
    totalVariants++;
    if (typeof v.price !== 'number' || v.price <= 0) allPricesValid = false;
  });
  if (Array.isArray(p.addons)) {
    p.addons.forEach(a => {
      totalAddons++;
      if (typeof a.price !== 'number' || a.price <= 0) allPricesValid = false;
    });
  }
});

assert(totalVariants === 81, `Catalogue has exactly 81 price options / variants (found ${totalVariants})`);
assert(totalAddons === 16, `Catalogue has all 16 optional extras / add-ons preserved (found ${totalAddons})`);
assert(allPricesValid, `All ${totalVariants} product variants and ${totalAddons} add-ons have valid numeric GBP pricing`);
assert(startingPricesMatchMin, 'Every product startingPrice matches its minimum variant price');

// Extract embedded CATALOGUE_DATA from script.js and verify exact synchronisation with data/products.json
const EXPECTED_CACHE_BUST_QUERY = '?v=public-audit-20261020';
const EXPECTED_HERO_IMAGE_PATH = 'assets/current-banner.jpg';
const EXPECTED_HERO_CACHE_BUST_QUERY = '?v=hero-20261020-1677a163a5ca';
const EXPECTED_HERO_VERSIONED_REF = `${EXPECTED_HERO_IMAGE_PATH}${EXPECTED_HERO_CACHE_BUST_QUERY}`;
const EXPECTED_HERO_SHA256 = '1677a163a5cad2b7741a21877c059a7952faa6473f0ee7da92ade9878f831614';
const EXPECTED_HERO_BYTE_LENGTH = 79880;
const EXPECTED_HERO_WIDTH = 1238;
const EXPECTED_HERO_HEIGHT = 864;
const heroBannerBytes = fs.readFileSync(path.join(__dirname, EXPECTED_HERO_IMAGE_PATH));
const heroBannerSha256 = crypto.createHash('sha256').update(heroBannerBytes).digest('hex');

function parseJpegSofDimensions(buf) {
  if (
    !Buffer.isBuffer(buf) ||
    buf.length < 4 ||
    buf.subarray(0, 3).toString('hex') !== 'ffd8ff' ||
    buf.subarray(buf.length - 2).toString('hex') !== 'ffd9'
  ) {
    return null;
  }
  const sofMarkers = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
  let offset = 2;
  while (offset < buf.length) {
    if (buf[offset] !== 0xff) return null;
    while (offset < buf.length && buf[offset] === 0xff) offset++;
    if (offset >= buf.length) return null;
    const marker = buf[offset++];
    if (marker === 0xd9 || marker === 0xda) break;
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 2 > buf.length) return null;
    const segLen = buf.readUInt16BE(offset);
    if (segLen < 2 || offset + segLen > buf.length) return null;
    if (sofMarkers.has(marker)) {
      if (segLen < 8) return null;
      const precision = buf[offset + 2];
      const height = buf.readUInt16BE(offset + 3);
      const width = buf.readUInt16BE(offset + 5);
      const components = buf[offset + 7];
      return { width, height, precision, components };
    }
    offset += segLen;
  }
  return null;
}

const heroDimensions = parseJpegSofDimensions(heroBannerBytes);

function resolveAssetPathname(assetUrl) {
  return new URL(String(assetUrl || ''), 'http://127.0.0.1/').pathname.replace(/^\/+/, '');
}

assert(
  heroBannerBytes.length === EXPECTED_HERO_BYTE_LENGTH && heroBannerSha256 === EXPECTED_HERO_SHA256,
  `assets/current-banner.jpg matches exact supplied JPEG byte length (${EXPECTED_HERO_BYTE_LENGTH}) and SHA-256 (${EXPECTED_HERO_SHA256})`
);
assert(
  Boolean(heroDimensions) &&
    heroDimensions.width === EXPECTED_HERO_WIDTH &&
    heroDimensions.height === EXPECTED_HERO_HEIGHT &&
    heroDimensions.precision === 8 &&
    heroDimensions.components === 3,
  `assets/current-banner.jpg has valid JPEG SOF structure and exact ${EXPECTED_HERO_WIDTH}x${EXPECTED_HERO_HEIGHT} dimensions`
);
assert(
  html.includes(`src="${EXPECTED_HERO_VERSIONED_REF}"`) &&
    !html.includes('src="assets/current-banner.jpg"') &&
    (html.match(/assets\/current-banner\.jpg/g) || []).length === 1 &&
    (html.match(/assets\/current-banner\.jpg\?v=hero-20261020-1677a163a5ca/g) || []).length === 1 &&
    resolveAssetPathname(EXPECTED_HERO_VERSIONED_REF) === EXPECTED_HERO_IMAGE_PATH,
  `index.html references cache-busted hero image ${EXPECTED_HERO_VERSIONED_REF} with zero unversioned hero references`
);
assert(
  /<img\s+src="assets\/current-banner\.jpg\?v=hero-20261020-1677a163a5ca"[\s\S]*?alt="GBA Furniture furnished bedroom with upholstered bed, bedside drawers, chest of drawers and wardrobe"[\s\S]*?class="hero-image"[\s\S]*?width="1238"[\s\S]*?height="864"\s*>/.test(
    html
  ) && !html.includes('showroom living banner'),
  'index.html .hero-image <img> binds 1238x864 intrinsic dimensions and grounded bedroom alt description without invented product claims'
);

assert(
  html.includes('href="styles.css?v=public-audit-20261020"') && !html.includes('href="styles.css"'),
  'index.html references cache-busted stylesheet styles.css?v=public-audit-20261020'
);
assert(
  html.includes('src="script.js?v=public-audit-20261020"') && !html.includes('src="script.js"'),
  'index.html references cache-busted script script.js?v=public-audit-20261020'
);

const allJsonPlaceholdersVersionedAndExist =
  Array.isArray(data.products) &&
  data.products.length === 26 &&
  data.products.every(p => {
    if (typeof p.placeholder !== 'string' || !p.placeholder.endsWith(EXPECTED_CACHE_BUST_QUERY)) {
      return false;
    }
    const resolvedPath = resolveAssetPathname(p.placeholder);
    return svgFiles.includes(resolvedPath) && fs.existsSync(path.join(__dirname, resolvedPath));
  });
assert(
  allJsonPlaceholdersVersionedAndExist,
  `Every product placeholder URL in data/products.json ends with ${EXPECTED_CACHE_BUST_QUERY} and resolves its URL pathname to an existing SVG file`
);

const catalogueDataMatch = js.match(/const\s+CATALOGUE_DATA\s*=\s*(\{[\s\S]*?\n  \});/);
assert(Boolean(catalogueDataMatch), 'Embedded CATALOGUE_DATA object found in script.js');
if (catalogueDataMatch) {
  const embeddedData = new Function(`return ${catalogueDataMatch[1]};`)();
  assert(
    Array.isArray(embeddedData.categories) &&
      embeddedData.categories.length === 8 &&
      embeddedData.categories[0].id === 'all' &&
      embeddedData.categories[0].name === 'All Items',
    'Embedded CATALOGUE_DATA.categories starts with { id: "all", name: "All Items" } and has 8 total filter entries'
  );
  assert(
    JSON.stringify(embeddedData.categories.slice(1)) === JSON.stringify(data.categories),
    'Embedded CATALOGUE_DATA.categories (excluding "all") matches data/products.json categories exactly'
  );
  assert(
    Array.isArray(embeddedData.products) &&
      embeddedData.products.length === 26 &&
      JSON.stringify(embeddedData.products) === JSON.stringify(data.products),
    'Embedded CATALOGUE_DATA.products matches data/products.json products (all 26 products and 81 variants) exactly'
  );
  const allEmbeddedPlaceholdersVersionedAndExist =
    Array.isArray(embeddedData.products) &&
    embeddedData.products.length === 26 &&
    embeddedData.products.every(p => {
      if (typeof p.placeholder !== 'string' || !p.placeholder.endsWith(EXPECTED_CACHE_BUST_QUERY)) {
        return false;
      }
      const resolvedPath = resolveAssetPathname(p.placeholder);
      return svgFiles.includes(resolvedPath) && fs.existsSync(path.join(__dirname, resolvedPath));
    });
  assert(
    allEmbeddedPlaceholdersVersionedAndExist,
    `Every product placeholder URL in embedded CATALOGUE_DATA (script.js) ends with ${EXPECTED_CACHE_BUST_QUERY} and resolves its URL pathname to an existing SVG file`
  );
}

const resolvedPlaceholderPaths = Array.from(new Set(data.products.map(p => resolveAssetPathname(p.placeholder)))).sort();
assert(
  JSON.stringify(resolvedPlaceholderPaths) === JSON.stringify([...svgFiles].sort()),
  'Resolved product placeholder URL pathnames cover all 10 underlying SVG files in assets/placeholders/'
);

const { spawnSync } = require('child_process');
const smokeTestSh = fs.readFileSync(path.join(__dirname, 'scripts/smoke-test.sh'), 'utf8');
const remoteDeploySandboxSh = fs.readFileSync(path.join(__dirname, 'scripts/remote-deploy-sandbox.sh'), 'utf8');
const remoteDeployProdSh = fs.readFileSync(path.join(__dirname, 'scripts/remote-deploy-production.sh'), 'utf8');
const cssValidatorMatch = smokeTestSh.match(/def validate_css_stylesheet\(text\):[\s\S]*?\n    return clean\n/);
const cssValidatorBody = cssValidatorMatch ? cssValidatorMatch[0] : '';
const cssValidatorFixturesOk = (() => {
  if (!cssValidatorBody) return false;
  const pyRunner = `
import re, sys

def fail(msg):
    raise ValueError(msg)

${cssValidatorBody}

base = ":root { --color-petrol: #014660; }\\n"
must_fail = [
    base + ".bad { color: rgb([)]; }",
    base + ".bad[(]) { color: #014660; }",
    base + "<div> .bad { color: #014660; }",
    base + "</div> .bad { color: #014660; }",
    base + "<!foo> .bad { color: #014660; }",
    base + "<?foo?> .bad { color: #014660; }",
]
for sample in must_fail:
    try:
        validate_css_stylesheet(sample)
    except ValueError:
        pass
    else:
        sys.stderr.write(f"Expected failure for {sample!r}\\n")
        sys.exit(1)

must_pass = [
    base + '.ok::before { content: "rgb([)]"; }',
    base + '.ok::before { content: "[(])"; }',
    base + '.ok::before { content: "<div>"; }',
    base + '.ok::before { content: "</div>"; }',
    base + '.ok::before { content: "<!foo>"; }',
    base + '.ok::before { content: "<?foo?>"; }',
    base + '/* rgb([)] */ .ok { color: #014660; }',
    base + '/* [(]) */ .ok { color: #014660; }',
    base + '/* <div> */ .ok { color: #014660; }',
    base + '/* </div> */ .ok { color: #014660; }',
    base + '/* <!foo> */ .ok { color: #014660; }',
    base + '/* <?foo?> */ .ok { color: #014660; }',
]
for sample in must_pass:
    validate_css_stylesheet(sample)
`;
  const res = spawnSync('python3', ['-c', pyRunner], { encoding: 'utf8' });
  return res.status === 0;
})();
assert(
  smokeTestSh.includes('%{http_code}\\t%{content_type}') &&
    !smokeTestSh.includes("printf '000\\t'") &&
    smokeTestSh.includes('|| curl_rc=$?') &&
    smokeTestSh.includes('[ "${curl_rc}" -ne 0 ]') &&
    smokeTestSh.includes(
      'Mandatory trusted asset binding missing: both EXPECTED_METADATA_FILE and EXPECTED_ASSET_ROOT must be set'
    ) &&
    smokeTestSh.includes('validate_no_symlink_ancestors') &&
    smokeTestSh.includes('validate_no_nested_symlinks') &&
    smokeTestSh.includes('outside_strings_and_comments') &&
    !smokeTestSh.includes('validate_declarations') &&
    Boolean(cssValidatorBody) &&
    cssValidatorBody.includes('delimiter_stack = []') &&
    cssValidatorBody.includes('bool(delimiter_stack)') &&
    cssValidatorBody.includes('not delimiter_stack') &&
    cssValidatorBody.includes('r"<\\s*(?:/\\s*)?(?:[A-Za-z][A-Za-z0-9:_-]*\\b|[!?])"') &&
    !cssValidatorBody.includes('paren_depth') &&
    !cssValidatorBody.includes('bracket_depth') &&
    !cssValidatorBody.includes('!doctype\\b|html\\b') &&
    !cssValidatorBody.includes('svg\\b') &&
    cssValidatorFixturesOk &&
    smokeTestSh.includes("media_type != \"text/css\"") &&
    smokeTestSh.includes("(\"application/javascript\", \"text/javascript\")") &&
    smokeTestSh.includes('["node", "--check"]') &&
    smokeTestSh.includes('input=raw_bytes') &&
    smokeTestSh.includes("media_type != \"application/json\"") &&
    smokeTestSh.includes("media_type != \"image/svg+xml\"") &&
    smokeTestSh.includes("media_type != \"image/png\"") &&
    smokeTestSh.includes("89504e470d0a1a0a") &&
    smokeTestSh.includes("zlib.crc32") &&
    smokeTestSh.includes("media_type != \"image/jpeg\"") &&
    smokeTestSh.includes("ffd8ff") &&
    smokeTestSh.includes(`check_endpoint "/index.html" "200" "${EXPECTED_HERO_VERSIONED_REF}"`) &&
    smokeTestSh.includes('check_endpoint "/assets/current-banner.jpg" "200" ""') &&
    smokeTestSh.includes(`check_endpoint "/${EXPECTED_HERO_VERSIONED_REF}" "200" ""`) &&
    smokeTestSh.includes("ET.fromstring(raw_bytes)") &&
    smokeTestSh.includes("Trusted byte verification failed") &&
    remoteDeploySandboxSh.includes('EXPECTED_METADATA_FILE="${STAGE_DIR}/release-metadata.json"') &&
    remoteDeploySandboxSh.includes('EXPECTED_ASSET_ROOT="${STAGE_DIR}"') &&
    remoteDeploySandboxSh.includes(EXPECTED_HERO_VERSIONED_REF) &&
    remoteDeploySandboxSh.includes('node --check') &&
    remoteDeployProdSh.includes('EXPECTED_METADATA_FILE="${RELEASE_DIR}/release-metadata.json"') &&
    remoteDeployProdSh.includes('EXPECTED_ASSET_ROOT="${RELEASE_DIR}"') &&
    remoteDeployProdSh.includes(EXPECTED_HERO_VERSIONED_REF) &&
    remoteDeployProdSh.includes('node --check'),
  'scripts/smoke-test.sh and deploy scripts enforce mandatory trusted asset binding (STAGE_DIR/RELEASE_DIR), ancestor symlink rejection, preflight node --check, separate curl exit capture, fail-closed Content-Type & format checks, and exact trusted-byte verification (including underlying & cache-busted hero endpoints)'
);

// Check specific key catalogue items, names, collections, and variant labels
const oxford = data.products.find(p => p.id === 'oxford-divan-bed');
assert(oxford && oxford.variants.some(v => v.id === 'oxford-set-3ft' && v.label === '3ft Single — Set (Base & Mattress)' && v.price === 130), 'Oxford 3ft Single Set is £130');
assert(oxford && oxford.variants.some(v => v.id === 'oxford-matt-3ft' && v.label === '3ft Single — Mattress Only' && v.price === 95), 'Oxford 3ft Single Mattress Only is £95');
assert(oxford && oxford.variants.some(v => v.id === 'oxford-matt-4ft' && v.label === '4ft / 4ft6 — Mattress Only' && v.price === 125), 'Oxford 4ft / 4ft6 Mattress Only is £125');
assert(oxford && oxford.addons.some(a => a.name === 'Drawer' && a.price === 35), 'Divan Drawer extra is £35');
assert(oxford && oxford.addons.some(a => a.name === 'Headboard (4ft / 4ft6)' && a.price === 35), 'Headboard (4ft / 4ft6) extra is £35');

const wardrobeBudget2 = data.products.find(p => p.id === 'budget-wardrobe-2door');
assert(
  wardrobeBudget2 &&
    wardrobeBudget2.name === 'Budget 2-Door Wardrobe' &&
    wardrobeBudget2.variants.some(v => v.label === '2-Door Wardrobe' && v.price === 95) &&
    wardrobeBudget2.variants.some(v => v.label === '2-Door Wardrobe with 2 Drawers' && v.price === 120) &&
    wardrobeBudget2.addons.some(a => a.name === 'Wardrobe Mirror' && a.price === 20),
  'Budget 2-Door Wardrobe has updated name, variant labels, and Wardrobe Mirror extra'
);

const wardrobeAb = data.products.find(p => p.id === 'ab-wardrobe-2door');
assert(wardrobeAb && wardrobeAb.name === 'AB Range 2-Door Wardrobe' && wardrobeAb.variants.some(v => v.price === 150), 'AB Range 2-Door Wardrobe is £150');

const abChests = data.products.find(p => p.id === 'ab-chests-bedside');
assert(
  abChests &&
    abChests.name === 'AB Range Chests & Bedside Units' &&
    abChests.variants.some(v => v.label === '3-Drawer Bedside Unit' && v.price === 55) &&
    abChests.variants.some(v => v.label === '4-Drawer Chest' && v.price === 120) &&
    abChests.variants.some(v => v.label === '5-Drawer Chest' && v.price === 140),
  'AB Range Chests & Bedside Units has updated name and drawer variant labels'
);

const budgetDining = data.products.find(p => p.id === 'budget-dining-range');
assert(
  budgetDining &&
    budgetDining.collection === 'Dining Furniture' &&
    budgetDining.variants.some(v => v.label === 'Individual Dining Chair' && v.price === 30) &&
    budgetDining.variants.some(v => v.label === 'Small Dining Table' && v.price === 80) &&
    budgetDining.variants.some(v => v.label === 'Medium Dining Table' && v.price === 105) &&
    budgetDining.variants.some(v => v.label === 'Large Dining Table' && v.price === 140),
  'Budget Dining Range uses Dining Furniture collection and updated table/chair labels'
);

const boxSofa = data.products.find(p => p.id === 'box-sofa-suite');
assert(
  boxSofa &&
    boxSofa.collection === 'Sofas & Sofa Beds' &&
    boxSofa.variants.some(v => v.label === '1-Seater' && v.price === 170) &&
    boxSofa.variants.some(v => v.label === '2-Seater' && v.price === 220) &&
    boxSofa.variants.some(v => v.label === '3-Seater' && v.price === 270) &&
    boxSofa.variants.some(v => v.label === '3 + 2-Seater Combination' && v.price === 420),
  'Box Sofa uses Sofas & Sofa Beds collection and hyphenated seater labels'
);

const coffeeTable = data.products.find(p => p.id === 'living-coffee-table');
assert(coffeeTable && coffeeTable.collection === 'Living Room Furniture' && coffeeTable.startingPrice === 40, 'Coffee Table uses Living Room Furniture collection at £40');

const removals = data.products.find(p => p.id === 'furniture-removal-service');
assert(
  removals &&
    removals.name === 'Furniture Removal' &&
    removals.collection === 'Removal Services' &&
    removals.variants.some(v => v.label === 'Chest of Drawers' && v.price === 20) &&
    removals.variants.some(v => v.label === 'Single Divan Bed' && v.price === 25) &&
    removals.variants.some(v => v.label === 'Double Divan Bed' && v.price === 30) &&
    removals.variants.some(v => v.label === 'Sofa — Per Piece' && v.price === 30) &&
    removals.variants.some(v => v.label === 'Wardrobe' && v.price === 30),
  'Furniture Removal product has updated name, collection, and variant labels starting at £20'
);

// 3. Grounding & Audit Enforcement: Banned Public Language Across HTML, JS, JSON, Generator, and SVG
console.log('\n3. Enforcing Absence of Unsupported Claims & Banned Provenance/Placeholder Language (HTML/JS/JSON/Generator/SVG):');
const combinedSvgText = svgContents.map(s => s.content).join('\n');
const allPublicSourcesLower = `${html}\n${js}\n${rawData}\n${generatorJs}\n${combinedSvgText}`.toLowerCase();

const bannedTerms = [
  // Unsupported claims
  'tottenham',
  'north london',
  'm25',
  'room of choice',
  'room-of-choice',
  'free street parking',
  'free parking',
  'responsible disposal',
  'licensed disposal',
  'solid pine',
  'powder-coated',
  'hydraulic',
  'gas-lift',
  'back alignment',
  'pressure-relieving',
  'immediate dispatch',
  'immediate stock allocation',
  'verified store pricing',
  'official catalogue',
  // Provenance, placeholder, broken policy links & replaced audit wording
  'supplied price',
  'supplied store',
  'price sheet',
  'price list',
  'store sheet',
  'listed on sheet',
  'temporary placeholder',
  'real photography coming soon',
  'coming soon',
  'placeholder illustration',
  'delivery note (placeholder)',
  'delivery arrangements (placeholder)',
  'applicances',
  'colarado',
  'pvc/fabric storage',
  'living room other',
  'matt only',
  '4ft / 4ft6 double',
  '4 chest drawer',
  '5 chest drawer',
  '3 drawer bedside',
  'drawer add-on',
  'mirror on wardrobe',
  'removal charges',
  'dining sets & tables',
  'dining sets &amp; tables',
  'enquire / order',
  'select option / size',
  'live returns policy',
  'live privacy policy',
  'refund_returns',
  'privacy-policy',
  'no data is stored on a server',
  'backend server',
  'color can vary',
  'subject to store confirmation',
  'all collections',
  'all products',
  'showing products',
  'no matching items found',
  'prepare an email enquiry',
  'prepare email enquiry',
  're-open email app',
  'email enquiry drafted',
  'copied to clipboard!',
  'clear item',
  'selected item for enquiry',
  'general enquiry / multiple items',
  'direct store ordering notice',
  'public showroom hours',
  'map link to store location',
  'location map link',
  'enquire online',
  'store enquiries',
  '20 years family-run',
  'item-specific'
];

bannedTerms.forEach(term => {
  const present = allPublicSourcesLower.includes(term.toLowerCase());
  assert(!present, `Banned term absent across HTML/JS/JSON/SVG: "${term}"`);
});

// Verify SVG illustration text across all 10 SVG files and generator script
assert(
  generatorJs.includes('Illustration only — not a product photograph') &&
    generatorJs.includes('FURNITURE REMOVALS') &&
    generatorJs.includes('Furniture removal service') &&
    generatorJs.includes('DINING FURNITURE') &&
    generatorJs.includes('SOFAS & LIVING ROOM'),
  'generate-placeholders.js generates truthful SVG titles and captions so old wording cannot return'
);

svgContents.forEach(({ file, content }) => {
  if (path.basename(file) === 'van.svg') {
    assert(
      content.includes('FURNITURE REMOVALS') && content.includes('Furniture removal service'),
      `${file} contains "FURNITURE REMOVALS" and "Furniture removal service"`
    );
  } else {
    assert(
      content.includes('Illustration only — not a product photograph'),
      `${file} contains "Illustration only — not a product photograph"`
    );
  }
});

// 4. Checking Verified Contact Details & Audited Public Labels
console.log('\n4. Checking Public Contact Details, Store Facts & New Audited Labels:');
assert(html.includes('020 8888 0322'), 'Telephone 020 8888 0322 present');
assert(html.includes('tel:02088880322'), 'tel:02088880322 present');
assert(html.includes('info@gbafurniture.com'), 'Email info@gbafurniture.com present');
assert(html.includes('401 Lordship Lane, London, N17 6AE'), 'Address 401 Lordship Lane, London, N17 6AE present');

// Exact confirmed opening hours
assert(html.includes('9:30am–6:00pm'), 'Hours 9:30am–6:00pm present in HTML');
assert(html.includes('9:30am–5:00pm'), 'Hours 9:30am–5:00pm present in HTML');
assert(html.includes('Closed'), 'Sunday Closed present in HTML');

// Absence of obsolete hours wording
assert(!html.includes('9:00am'), 'Obsolete time "9:00am" absent from HTML');
assert(!html.includes('8:00pm'), 'Obsolete time "8:00pm" absent from HTML');
assert(!html.toLowerCase().includes('open daily'), 'Obsolete phrase "Open daily" absent from HTML');
assert(!html.includes('Monday – Sunday'), 'Obsolete phrase "Monday – Sunday" absent from HTML');
assert(!html.includes('Monday to Sunday'), 'Obsolete phrase "Monday to Sunday" absent from HTML');

// Audited business positioning, headings, CTAs, and conditional service copy
const htmlLower = html.toLowerCase();
assert(html.includes('<title>GBA Furniture | Furniture for Landlords &amp; Letting Agents</title>'), 'Audited page title present');
assert(html.includes('Family-run furniture specialists with 20 years’ experience serving landlords and letting agents. Explore packages and replacements, and contact us for a quote.'), 'Audited meta description present');
assert(
  html.includes(
    '<h1 class="hero-title" id="heroHeading">Landlords • Letting • HMOs • Care Homes • Airbnb • Temporary Housing — Your Complete Furniture Partner. Only One Call Away</h1>'
  ),
  'Hero H1 heading present with exact updated text'
);
assert(
  !html.includes('Furniture for <em>Landlords &amp; Letting Agents</em>'),
  'Obsolete hero H1 phrase "Furniture for <em>Landlords &amp; Letting Agents</em>" absent from HTML'
);
assert(htmlLower.includes('family-run'), 'Confirmed copy "family-run" present in HTML');
assert(htmlLower.includes('20 years'), 'Confirmed copy "20 years" present in HTML');
assert(htmlLower.includes('landlords'), 'Confirmed copy "landlords" present in HTML');
assert(htmlLower.includes('letting agents'), 'Confirmed copy "letting agents" present in HTML');
assert(htmlLower.includes('property managers'), 'Confirmed copy "property managers" present in HTML');
assert(htmlLower.includes('key collection by arrangement'), 'Confirmed copy "key collection by arrangement" present in HTML');
assert(htmlLower.includes('same-day delivery'), 'Confirmed copy "same-day delivery" present in HTML');
assert(html.includes('Ask About Same-Day Delivery'), 'Audited heading "Ask About Same-Day Delivery" present in HTML');
assert(html.includes('Same-day delivery is subject to stock, your location, our delivery route and a confirmed delivery slot.'), 'Audited conditional same-day delivery sentence present in HTML');
assert(html.includes('20 Years’ Experience') && html.includes('Family-run furniture specialists'), 'Audited hero highlight for 20 Years’ Experience present');
assert(html.includes('WhatsApp Our Team'), 'Audited hero WhatsApp CTA "WhatsApp Our Team" present');
assert(html.includes('Discuss Your Property’s Furniture Needs'), 'Audited hero floating card heading present');
assert(html.includes('Furniture Packages &amp; Replacements'), 'Audited packages service card heading present');
assert(html.includes('Furniture Removal Options'), 'Audited removal service card heading present');
assert(html.includes('Packages &amp; Individual Replacements') && html.includes('Browse by Category'), 'Audited category section headings present');
assert(html.includes('Furniture for Rental Properties') && html.includes('Browse Our Catalogue'), 'Audited catalogue section headings present');
assert(html.includes('placeholder="Search furniture, appliances or removals"'), 'Audited search placeholder present');
assert(html.includes('id="activeFilterLabel">All Items</span>') && html.includes('id="productCountLabel">Browse the catalogue</div>'), 'Audited initial filter and product count labels present');
assert(html.includes('Request a Quote or Visit Our Showroom') && html.includes('How to Order'), 'Audited contact section headings present');
assert(html.includes('Request a Quote by Email') && html.includes('Open Email Draft'), 'Audited enquiry form heading and button label present');
assert(html.includes('Selected Item') && html.includes('Remove Selection'), 'Audited selected item banner labels present');
assert(html.includes('Item or Enquiry Type') && html.includes('Your Requirements'), 'Audited enquiry form field labels present');
assert(
  html.includes('<label for="enquiryPostcode" class="form-label">Property Postcode</label>') &&
    html.includes('placeholder="Enter the property’s postcode"') &&
    !html.includes('Delivery Postcode / Area'),
  'Enquiry form postcode field uses label "Property Postcode" and clear postcode placeholder'
);
assert(html.includes('This form prepares an email draft. Your enquiry is not sent until you send it from your email app.'), 'Audited form note present');
assert(html.includes('Your Enquiry Is Ready to Send'), 'Audited enquiry feedback heading present');
assert(html.includes('Delivery Information') && html.includes('Furniture Removal Prices') && html.includes('How Email Enquiries Work') && html.includes('Find Our Showroom'), 'Audited footer policy and showroom links present');
assert(html.includes('Planning a Furniture Order?'), 'Audited footer enquiry heading present');

// Absence of unconditional same-day delivery guarantees
assert(!htmlLower.includes('guaranteed same-day delivery'), 'Unconditional claim "guaranteed same-day delivery" absent from HTML');
assert(!htmlLower.includes('always available'), 'Unconditional claim "always available" absent from HTML');
assert(!htmlLower.includes('unconditional same-day guarantee'), 'Unconditional claim "unconditional same-day guarantee" absent from HTML');

// Social & WhatsApp links and attributes
assert(html.includes('https://www.instagram.com/gba_furniture/'), 'Instagram exact URL present');
assert(html.includes('https://www.tiktok.com/@gbafurniture'), 'TikTok exact URL present');
assert(html.includes('https://wa.me/442088880322'), 'WhatsApp URL prefix wa.me/442088880322 present');
assert(html.includes('@gba_furniture'), 'Visible Instagram handle @gba_furniture present');
assert(html.includes('@gbafurniture'), 'Visible TikTok handle @gbafurniture present');

// Accessible and safe external links (enumerate every matching anchor individually)
const anchorTags = html.match(/<a\b[^>]*>/gi) || [];
function parseAnchorAttributes(tag) {
  const hrefMatch = tag.match(/\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i);
  const targetMatch = tag.match(/\btarget\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i);
  const relMatch = tag.match(/\brel\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i);
  const href = hrefMatch ? (hrefMatch[1] ?? hrefMatch[2] ?? hrefMatch[3] ?? '') : '';
  const target = targetMatch ? (targetMatch[1] ?? targetMatch[2] ?? targetMatch[3] ?? '') : '';
  const rel = relMatch ? (relMatch[1] ?? relMatch[2] ?? relMatch[3] ?? '') : '';
  const relTokens = rel.trim().toLowerCase().split(/\s+/).filter(Boolean);
  return { href, target, relTokens };
}

const parsedAnchors = anchorTags.map(parseAnchorAttributes);
const externalServices = [
  { name: 'Instagram', prefix: 'https://www.instagram.com/gba_furniture/' },
  { name: 'TikTok', prefix: 'https://www.tiktok.com/@gbafurniture' },
  { name: 'WhatsApp', prefix: 'https://wa.me/442088880322' }
];

externalServices.forEach(({ name, prefix }) => {
  const matches = parsedAnchors.filter(a => a.href.startsWith(prefix));
  assert(matches.length >= 1, `${name} has at least one matching anchor (${matches.length} found)`);
  matches.forEach((a, idx) => {
    const hasBlankTarget = a.target === '_blank';
    const hasNoopener = a.relTokens.includes('noopener');
    const hasNoreferrer = a.relTokens.includes('noreferrer');
    assert(
      hasBlankTarget && hasNoopener && hasNoreferrer,
      `${name} anchor #${idx + 1} (${a.href}) has target="_blank" and rel tokens "noopener" and "noreferrer"`
    );
  });
});

// 5. Checking Honest Form Behaviour & Dynamic JS Labels
console.log('\n5. Checking Honest Enquiry Form & Dynamic Catalogue Templates:');
assert(html.includes('enquiryFeedback'), 'On-page enquiry feedback container present');
assert(html.includes('copyEnquiryBtn'), 'Copy enquiry text button present');
assert(js.includes('mailto:info@gbafurniture.com'), 'Script generates mailto: to info@gbafurniture.com');
assert(!js.includes('Enquiry Reference: GBA-'), 'No fake server enquiry reference codes generated');
assert(!html.includes('Enquiry Reference: GBA-'), 'No fake server reference in HTML');
assert(js.includes('Furniture Package, Multiple Items or General Enquiry'), 'Default enquiry select option updated in script.js');
assert(js.includes('Choose an Item to Remove') && js.includes('Choose an Option'), 'Context-specific option selector labels present in script.js');
assert(js.includes('Optional Extras') && js.includes('Product Details:'), 'Updated card extras and details labels present in script.js');
assert(js.includes('Selected Option') && js.includes('Enquire About This Item'), 'Updated price prefix and action button labels present in script.js');
assert(js.includes('Illustration only; not a photograph of '), 'Updated accessible image alt template present in script.js');
assert(js.includes('Catalogue price: £'), 'Updated selected item price label present in script.js');
assert(js.includes('I would like to arrange removal of '), 'Removal-specific enquiry message template present in script.js');
assert(js.includes('Please provide a quote for '), 'Furniture/appliance quote enquiry message template present in script.js');
assert(js.includes('Enquiry Copied') && js.includes('We couldn’t copy the enquiry. Select the text below and copy it into your email.'), 'Clipboard success and failure messages present in script.js');
assert(
  js.includes('function updateContactMethodRequirements') &&
    js.includes('to prepare your email draft.') &&
    html.includes('id="enquiryPhoneReq"') &&
    html.includes('id="enquiryEmailReq"'),
  'Dynamic contact-method required indicators and validation summary helpers present in HTML and script.js'
);

// 6. Checking Accessibility & CSS
console.log('\n6. Checking Accessibility & CSS:');
const css = fs.readFileSync(path.join(__dirname, 'styles.css'), 'utf8');

assert(html.includes('class="skip-link"'), 'Accessible skip link exists');
assert(html.includes('aria-controls="mobileDrawer"'), 'Mobile drawer control attributes present');
assert(html.includes('aria-expanded="false"'), 'Mobile nav toggle has aria-expanded');
assert(css.includes(':focus-visible'), 'CSS contains :focus-visible styling');
assert(css.includes('prefers-reduced-motion'), 'CSS contains prefers-reduced-motion rules');

// Check responsive breakpoint blocks in styles.css
const media1399Match = css.match(/@media\s*\(max-width:\s*1399px\)\s*\{([\s\S]*?\})\s*\}/);
const media1024Match = css.match(/@media\s*\(max-width:\s*1024px\)\s*\{([\s\S]*?\})\s*\}/);
const media1399Body = media1399Match ? media1399Match[1] : '';
const media1024Body = media1024Match ? media1024Match[1] : '';

assert(
  Boolean(media1399Match) &&
    media1399Body.includes('.primary-nav') &&
    media1399Body.includes('.header-actions .btn-tel') &&
    media1399Body.includes('.header-actions .btn-whatsapp') &&
    media1399Body.includes('.mobile-nav-toggle') &&
    !media1399Body.includes('.hero-grid') &&
    !media1399Body.includes('.trust-grid') &&
    !media1399Body.includes('.showroom-grid') &&
    !media1399Body.includes('.footer-grid'),
  'styles.css contains a header-only @media (max-width: 1399px) block'
);
assert(
  Boolean(media1024Match) &&
    media1024Body.includes('.hero-grid') &&
    media1024Body.includes('.trust-grid') &&
    media1024Body.includes('.showroom-grid') &&
    media1024Body.includes('.footer-grid'),
  'styles.css contains the general @media (max-width: 1024px) block'
);

// Check customer-visible logo references to transparent PNG
const transparentLogoReferences = (html.match(/assets\/gba-logo-official-transparent\.png/g) || []).length;
const croppedLogoReferences = (html.match(/assets\/gba-logo-official-cropped\.jpg/g) || []).length;
const originalLogoReferences = (html.match(/assets\/gba-logo-replacement-original\.jpg/g) || []).length;
assert(transparentLogoReferences === 3, 'HTML contains exactly 3 references to transparent PNG logo (desktop header, drawer, footer)');
assert(croppedLogoReferences === 0, 'HTML contains zero references to cropped JPG logo');
assert(originalLogoReferences === 0, 'HTML contains zero references to original replacement JPG logo');
assert(!html.includes('assets/gba-logo-web.png'), 'Customer-visible HTML has no references to deprecated gba-logo-web.png');
assert(!html.includes('brand-tagline-text'), 'Desktop redundant brand-tagline-text block is removed');

// 6b. Phase 2 Source-Level & Runtime Behavioral Regression Suite
console.log('\n6b. Checking Phase 2 Layout, Touch Targets, Accessibility, Footer Filters & Enquiry Journey:');

// (1) Desktop header collapse & hit-target overlap prevention
assert(
  css.includes('.site-header.is-collapsed .primary-nav') &&
    css.includes('.site-header.is-collapsed .header-actions .btn-tel') &&
    css.includes('.site-header.is-collapsed .header-actions .btn-whatsapp') &&
    css.includes('.site-header.is-collapsed .mobile-nav-toggle'),
  'styles.css defines .site-header.is-collapsed rules to keep collapsed layout active whenever controls cannot fit'
);
assert(
  /\.primary-nav\s*\{[\s\S]*?flex-shrink:\s*0/.test(css) &&
    /\.header-actions\s+\.btn\s*\{[\s\S]*?white-space:\s*nowrap[\s\S]*?flex-shrink:\s*0/.test(css),
  'styles.css prevents primary-nav and header action buttons from shrinking into overlapping hit targets'
);
assert(
  js.includes('function rectsOverlapHorizontally') &&
    js.includes('function updateHeaderCollapseState') &&
    js.includes("window.addEventListener('resize', updateHeaderCollapseState)"),
  'script.js implements dynamic header fit & rectangle overlap detection (updateHeaderCollapseState)'
);

// (2) 320px overflow prevention, wrapping preferred-contact controls, long product selector & 44px touch targets
assert(
  /\.enquiry-form-card\s*\{[\s\S]*?min-width:\s*0[\s\S]*?max-width:\s*100%/.test(css) &&
    /#enquiryForm\s*\{[\s\S]*?min-width:\s*0[\s\S]*?max-width:\s*100%/.test(css) &&
    /\.showroom-info\s*\{[\s\S]*?min-width:\s*0[\s\S]*?max-width:\s*100%/.test(css) &&
    /\.contact-card-text\s*\{[\s\S]*?min-width:\s*0[\s\S]*?max-width:\s*100%/.test(css) &&
    /\.selected-product-banner\s*\{[\s\S]*?flex-wrap:\s*wrap[\s\S]*?min-width:\s*0[\s\S]*?max-width:\s*100%/.test(css),
  'styles.css enforces min-width: 0 and max-width: 100% across contact cards, form containers, and selected item banner'
);
assert(
  /\.catalogue-search-box\s*\{[\s\S]*?min-width:\s*min\(240px,\s*100%\)/.test(css) &&
    /\.product-grid\s*\{[\s\S]*?minmax\(min\(100%,\s*320px\),\s*1fr\)/.test(css) &&
    /\.category-tiles-grid\s*\{[\s\S]*?minmax\(min\(100%,\s*140px\),\s*1fr\)/.test(css),
  'styles.css eliminates rigid min-width overflow on search box, product grid, and category tiles at 320px'
);
assert(
  /\.form-select\s*\{[\s\S]*?overflow:\s*hidden[\s\S]*?text-overflow:\s*ellipsis[\s\S]*?white-space:\s*nowrap/.test(css) &&
    /\.variant-select\s*\{[\s\S]*?overflow:\s*hidden[\s\S]*?text-overflow:\s*ellipsis[\s\S]*?white-space:\s*nowrap/.test(css) &&
    /\.enquiry-summary-pre\s*\{[\s\S]*?overflow-wrap:\s*anywhere[\s\S]*?word-break:\s*break-word/.test(css),
  'styles.css constrains long product/variant selectors with ellipsis and wraps prepared email summary text at 320px'
);
assert(
  html.includes('<fieldset class="form-group form-group-full form-fieldset">') &&
    html.includes('<legend class="form-label">Preferred Contact Method</legend>') &&
    /\.form-radio-label\s*\{[\s\S]*?min-height:\s*44px/.test(css) &&
    /@media\s*\(max-width:\s*480px\)\s*\{[\s\S]*?\.form-radio-group\s*\{[\s\S]*?flex-direction:\s*column/.test(css),
  'Preferred Contact Method uses accessible fieldset/legend, 44px radio labels, and clean vertical stacking at <=480px'
);
assert(
  /\.mobile-nav-toggle\s*\{[\s\S]*?min-width:\s*44px[\s\S]*?min-height:\s*44px/.test(css) &&
    /\.mobile-drawer-close\s*\{[\s\S]*?min-width:\s*44px[\s\S]*?min-height:\s*44px/.test(css) &&
    /\.policy-modal-close\s*\{[\s\S]*?min-width:\s*44px[\s\S]*?min-height:\s*44px/.test(css) &&
    /\.btn-whatsapp\s*\{[\s\S]*?min-height:\s*44px[\s\S]*?min-width:\s*44px/.test(css) &&
    /\.top-bar-link\s*\{[\s\S]*?min-height:\s*44px[\s\S]*?min-width:\s*44px/.test(css) &&
    /\.btn-sm\s*\{[\s\S]*?min-height:\s*44px[\s\S]*?min-width:\s*44px/.test(css) &&
    /\.selected-badge-clear\s*\{[\s\S]*?min-height:\s*44px[\s\S]*?min-width:\s*44px/.test(css),
  'styles.css enforces >=44x44px touch targets on menu toggle, header/top-bar WhatsApp, dialog close buttons, and actions'
);
assert(
  /a\.contact-card-val\s*\{[\s\S]*?min-height:\s*44px[\s\S]*?min-width:\s*44px/.test(css) &&
    /\.contact-social-item\s*\{[\s\S]*?min-height:\s*44px[\s\S]*?min-width:\s*44px/.test(css) &&
    /\.footer-contact-summary\s+a\s*\{[\s\S]*?min-height:\s*44px[\s\S]*?min-width:\s*44px/.test(css) &&
    /\.footer-links-list\s+a,\s*\.footer-links-list\s+button\s*\{[\s\S]*?min-height:\s*44px[\s\S]*?min-width:\s*44px/.test(css),
  'styles.css enforces >=44x44px clickable targets on all contact-card and footer telephone/WhatsApp/email/social actions'
);
assert(
  /\.mobile-drawer-header\s+\.brand-logo--drawer\s*\{[\s\S]*?max-width:\s*calc\(100%\s*-\s*56px\)[\s\S]*?min-width:\s*0[\s\S]*?object-fit:\s*contain/.test(css) &&
    /\.mobile-drawer\s*\{[\s\S]*?overflow-x:\s*hidden/.test(css) &&
    /@media\s*\(max-width:\s*480px\)\s*\{[\s\S]*?\.mobile-drawer-header\s+\.brand-logo--drawer\s*\{[\s\S]*?max-width:\s*calc\(100%\s*-\s*56px\)/.test(css),
  'styles.css contains 320px mobile drawer logo and 44px close button without internal overflow or logo cropping'
);
assert(
  /\.mobile-drawer\.is-open,\s*\.mobile-drawer\.is-open\s+\*\s*\{[\s\S]*?visibility:\s*visible/.test(css) &&
    /@media\s*\(prefers-reduced-motion:\s*reduce\)\s*\{[\s\S]*?transition-duration:\s*0s\s*!important/.test(css) &&
    js.includes("mobileDrawer.style.visibility = 'visible'") &&
    js.includes("mobileDrawerClose.style.visibility = 'visible'"),
  'styles.css and script.js establish drawer visibility synchronously before focusing close control in both normal and reduced motion'
);
assert(
  html.includes('id="enquiryProductSelectLabel"') &&
    js.includes('class="variant-selected-label"') &&
    js.includes('function syncFormProductSelectLabel') &&
    /\.variant-selected-label,\s*\.form-select-selected-label\s*\{[\s\S]*?white-space:\s*normal[\s\S]*?overflow-wrap:\s*anywhere/.test(css),
  'HTML, CSS, and script.js expose wrapping full selected-option labels below card variant selectors and form item selector'
);
assert(
  !js.includes('GENERATED_TEMPLATE_PREFIX_RE') && js.includes('function findIntactGeneratedBlock'),
  'script.js tracks exact generated template block structurally without disposable prefix regex overwriting inline customer edits'
);

// (3) Footer category links
const footerCategoryLinkMatches = html.match(/<a\b[^>]*class="footer-category-link"[^>]*data-category="([^"]+)"[^>]*>/g) || [];
assert(
  footerCategoryLinkMatches.length === 7 && !html.includes("onclick=\"window.location.hash='category-"),
  'Footer has 7 semantic .footer-category-link[data-category] anchors without broken inline onclick handlers'
);
assert(
  js.includes('footerCategoryLinks.forEach') && js.includes("window.addEventListener('hashchange', checkUrlHash)"),
  'script.js binds footer category links and hashchange to apply actual filter state, count, and heading'
);

// (4) Modal and mobile drawer accessibility attributes in HTML
assert(
  html.includes('id="mobileDrawer" role="dialog" aria-modal="true" aria-label="Mobile Navigation" aria-hidden="true" inert') &&
    html.includes('id="policyModal" role="dialog" aria-modal="true" aria-labelledby="policyModalTitle" aria-hidden="true" inert'),
  'HTML initializes both #mobileDrawer and #policyModal with aria-hidden="true" and inert while closed'
);

// (5) Enquiry journey & catalogue status ARIA structure in HTML & CSS
assert(
  html.includes('role="status" aria-live="polite" aria-atomic="true" id="productCountLabel">Browse the catalogue</div>') &&
    !html.includes('id="productGrid" aria-live="polite"'),
  'Concise result announcements use #productCountLabel live status region instead of announcing the entire #productGrid'
);
assert(
  html.includes('id="enquiryFormError" role="alert"') &&
    html.includes('id="enquiryNameError" role="alert"') &&
    html.includes('id="enquiryPhoneError" role="alert"') &&
    html.includes('id="enquiryEmailError" role="alert"') &&
    html.includes('id="enquiryMessageError" role="alert"'),
  'Enquiry form provides accessible alert elements for field-level and summary validation feedback'
);
assert(
  /\.enquiry-form-card\s*\{[\s\S]*?scroll-margin-top:\s*calc\(var\(--header-height\)\s*\+\s*1rem\)/.test(css) &&
    /\.selected-product-banner\s*\{[\s\S]*?scroll-margin-top:\s*calc\(var\(--header-height\)\s*\+\s*1rem\)/.test(css),
  'Enquiry form card and selected product banner define scroll-margin-top clearing the sticky header'
);
assert(
  /@media\s*\(max-width:\s*480px\)\s*\{[\s\S]*?\.selected-product-banner\s*\{[\s\S]*?flex-direction:\s*column[\s\S]*?\}[\s\S]*?\.selected-product-banner\s*>\s*div[\s\S]*?\{[\s\S]*?flex:\s*0\s+1\s+auto\s*;[\s\S]*?width:\s*100%\s*;[\s\S]*?min-width:\s*0\s*;/.test(
    css
  ),
  'styles.css resets .selected-product-banner > div flex basis at <=480px (flex: 0 1 auto; width: 100%; min-width: 0;)'
);
const selectProductFnMatch = js.match(/function\s+selectProductForEnquiry\s*\([\s\S]*?\n  \}\n\n  function\s+clearProductSelection/);
const selectProductFnBody = selectProductFnMatch ? selectProductFnMatch[0] : '';
assert(
  Boolean(selectProductFnBody) &&
    selectProductFnBody.includes('const scrollTarget = selectedBanner || enquiryFormCard || contactSection;') &&
    selectProductFnBody.includes("behavior: 'auto'") &&
    selectProductFnBody.includes("block: 'start'") &&
    selectProductFnBody.includes("selectedBanner.setAttribute('tabindex', '-1')") &&
    selectProductFnBody.includes('!isMobileViewport') &&
    selectProductFnBody.includes('enquiryNameInput.getBoundingClientRect()') &&
    !selectProductFnBody.includes('smooth') &&
    !selectProductFnBody.includes('scrollend') &&
    !selectProductFnBody.includes('_cancelPendingFocus') &&
    !selectProductFnBody.includes('idleTimer') &&
    !selectProductFnBody.includes('maxTimer'),
  'script.js selectProductForEnquiry synchronously scrolls selectedBanner with behavior:"auto", block:"start" and has no smooth/timer/scroll-listener focus path'
);

// Runtime Behavioral Verification using VM & Synthetic DOM
(function runInteractiveDomRegressionTests() {
  class MockElement {
    constructor(tagName, id = '', className = '', attrs = {}) {
      this.tagName = tagName.toUpperCase();
      this.id = id;
      this._attrs = { ...attrs };
      if (id) this._attrs.id = id;
      if (className) this._attrs.class = className;
      this.children = [];
      this.parentElement = null;
      this.listeners = {};
      this.style = { display: attrs.style && attrs.style.includes('display: none') ? 'none' : '' };
      this.hidden = Boolean(attrs.hidden);
      this.inert = Boolean(attrs.inert);
      this.disabled = Boolean(attrs.disabled);
      this.value = attrs.value || '';
      this.checked = Boolean(attrs.checked);
      this.selected = Boolean(attrs.selected);
      this._textContent = '';
      this._innerHTML = '';
      this.scrollWidth = 1000;
      this.clientWidth = 1200;
      this._rect = { left: 0, top: 0, right: 100, bottom: 44, width: 100, height: 44 };
      this.customValidityMessage = '';
      this.lastFocusOptions = null;
      this.scrollIntoViewCalls = [];
      this.selectedIndex = 0;

      const self = this;
      this.classList = {
        _set: new Set((className || '').split(/\s+/).filter(Boolean)),
        add(...tokens) {
          tokens.forEach(t => { if (t) this._set.add(t); });
          self._attrs.class = Array.from(this._set).join(' ');
        },
        remove(...tokens) {
          tokens.forEach(t => this._set.delete(t));
          self._attrs.class = Array.from(this._set).join(' ');
        },
        toggle(token, force) {
          const shouldAdd = force === undefined ? !this._set.has(token) : Boolean(force);
          if (shouldAdd) this._set.add(token);
          else this._set.delete(token);
          self._attrs.class = Array.from(this._set).join(' ');
          return shouldAdd;
        },
        contains(token) {
          return this._set.has(token);
        }
      };
    }

    get className() {
      return Array.from(this.classList._set).join(' ');
    }
    set className(val) {
      this.classList._set = new Set((val || '').split(/\s+/).filter(Boolean));
      this._attrs.class = this.className;
    }

    get textContent() {
      if (this.children.length > 0 && !this._textContent) {
        return this.children.map(c => c.textContent).join('');
      }
      return this._textContent;
    }
    set textContent(val) {
      this._textContent = String(val ?? '');
      if (this.tagName === 'OPTION' && !this._attrs.value && !('value' in this._attrs)) {
        this.value = this._textContent;
      }
    }

    get text() {
      return this.textContent;
    }

    get innerHTML() {
      return this._innerHTML;
    }
    set innerHTML(val) {
      this._innerHTML = String(val ?? '');
      this.children = [];
      if (this._innerHTML.trim() !== '') {
        parseSimpleChildren(this, this._innerHTML);
      }
    }

    get options() {
      const opts = [];
      const walk = (node) => {
        node.children.forEach(child => {
          if (child.tagName === 'OPTION') opts.push(child);
          else walk(child);
        });
      };
      walk(this);
      return opts;
    }

    appendChild(child) {
      child.parentElement = this;
      this.children.push(child);
      if (this.tagName === 'SELECT' || this.tagName === 'OPTGROUP') {
        const selectEl = this.tagName === 'SELECT' ? this : this.parentElement;
        if (selectEl && selectEl.tagName === 'SELECT') {
          const opts = selectEl.options;
          if (child.tagName === 'OPTION' && (child.selected || opts.length === 1)) {
            selectEl.selectedIndex = opts.indexOf(child);
            selectEl.value = child.value;
          }
        }
      }
      return child;
    }

    setAttribute(name, val) {
      const strVal = String(val);
      this._attrs[name] = strVal;
      if (name === 'id') this.id = strVal;
      if (name === 'class') this.className = strVal;
      if (name === 'value') this.value = strVal;
      if (name === 'inert') this.inert = true;
      if (name === 'hidden') this.hidden = true;
    }

    getAttribute(name) {
      return Object.prototype.hasOwnProperty.call(this._attrs, name) ? this._attrs[name] : null;
    }

    removeAttribute(name) {
      delete this._attrs[name];
      if (name === 'inert') this.inert = false;
      if (name === 'hidden') this.hidden = false;
    }

    hasAttribute(name) {
      return Object.prototype.hasOwnProperty.call(this._attrs, name);
    }

    addEventListener(type, fn) {
      if (!this.listeners[type]) this.listeners[type] = [];
      this.listeners[type].push(fn);
    }

    dispatchEvent(event) {
      const evt = {
        type: event.type,
        target: event.target || this,
        currentTarget: this,
        key: event.key || '',
        shiftKey: Boolean(event.shiftKey),
        defaultPrevented: false,
        preventDefault() {
          this.defaultPrevented = true;
        }
      };
      const handlers = this.listeners[evt.type] || [];
      handlers.forEach(fn => fn(evt));
      return !evt.defaultPrevented;
    }

    click() {
      return this.dispatchEvent({ type: 'click', target: this });
    }

    focus(options) {
      this.lastFocusOptions = options || null;
      mockDocument.activeElement = this;
      mockDocument.dispatchEvent({ type: 'focusin', target: this });
    }

    scrollIntoView(options) {
      this.scrollIntoViewCalls.push(options || {});
    }

    getBoundingClientRect() {
      return this._rect;
    }

    setCustomValidity(msg) {
      this.customValidityMessage = String(msg || '');
    }

    checkValidity() {
      if (this.customValidityMessage) return false;
      const val = (this.value || '').trim();
      if (this.hasAttribute('required') && !val) return false;
      if (this.getAttribute('type') === 'email' && val) {
        return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(val);
      }
      return true;
    }

    contains(other) {
      let cur = other;
      while (cur) {
        if (cur === this) return true;
        cur = cur.parentElement;
      }
      return false;
    }

    querySelectorAll(selector) {
      const results = [];
      const selectors = selector.split(',').map(s => s.trim()).filter(Boolean);
      const visit = (node) => {
        node.children.forEach(child => {
          if ( selectors.some(sel => matchesCompoundSelector(child, sel)) ) {
            results.push(child);
          }
          visit(child);
        });
      };
      visit(this);
      return results;
    }

    querySelector(selector) {
      return this.querySelectorAll(selector)[0] || null;
    }
  }

  function decodeEntities(str) {
    return String(str || '')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .replace(/&rarr;/g, '→')
      .replace(/&nbsp;/g, ' ');
  }

  function parseAttrs(attrString) {
    const attrs = {};
    const re = /([a-zA-Z0-9_:-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
    let m;
    while ((m = re.exec(attrString)) !== null) {
      const key = m[1];
      const val = m[2] ?? m[3] ?? m[4] ?? '';
      attrs[key] = decodeEntities(val);
    }
    return attrs;
  }

  function parseSimpleChildren(parent, htmlFragment) {
    // Parse select, option, button, price-tag, and simple interactive elements inside product cards / modals
    const selectRegex = /<select\b([^>]*)>([\s\S]*?)<\/select>/gi;
    let sm;
    while ((sm = selectRegex.exec(htmlFragment)) !== null) {
      const sAttrs = parseAttrs(sm[1]);
      const selEl = new MockElement('select', sAttrs.id || '', sAttrs.class || '', sAttrs);
      const optRegex = /<option\b([^>]*)>([\s\S]*?)<\/option>/gi;
      let om;
      let idx = 0;
      while ((om = optRegex.exec(sm[2])) !== null) {
        const oAttrs = parseAttrs(om[1]);
        const optEl = new MockElement('option', oAttrs.id || '', oAttrs.class || '', oAttrs);
        optEl.value = oAttrs.value || '';
        optEl.textContent = decodeEntities(om[2].replace(/<[^>]+>/g, '').trim());
        optEl.selected = Object.prototype.hasOwnProperty.call(oAttrs, 'selected');
        if (optEl.selected) {
          selEl.selectedIndex = idx;
          selEl.value = optEl.value;
        }
        selEl.appendChild(optEl);
        idx++;
      }
      if (!selEl.value && selEl.options.length > 0) {
        selEl.selectedIndex = 0;
        selEl.value = selEl.options[0].value;
      }
      parent.appendChild(selEl);
    }

    const priceTagRegex = /<div\b([^>]*class="product-price-tag"[^>]*)>([\s\S]*?)<\/div>/gi;
    let pm;
    while ((pm = priceTagRegex.exec(htmlFragment)) !== null) {
      const pAttrs = parseAttrs(pm[1]);
      const tagEl = new MockElement('div', pAttrs.id || '', pAttrs.class || '', pAttrs);
      const prefixMatch = pm[2].match(/<span\b[^>]*class="product-price-prefix"[^>]*>([\s\S]*?)<\/span>/i);
      const valMatch = pm[2].match(/<span\b[^>]*class="price-val"[^>]*>([\s\S]*?)<\/span>/i);
      if (prefixMatch) {
        const prefEl = new MockElement('span', '', 'product-price-prefix');
        prefEl.textContent = decodeEntities(prefixMatch[1].trim());
        tagEl.appendChild(prefEl);
      }
      if (valMatch) {
        const valEl = new MockElement('span', '', 'price-val');
        valEl.textContent = decodeEntities(valMatch[1].trim());
        tagEl.appendChild(valEl);
      }
      parent.appendChild(tagEl);
    }

    const btnRegex = /<button\b([^>]*)>([\s\S]*?)<\/button>/gi;
    let bm;
    while ((bm = btnRegex.exec(htmlFragment)) !== null) {
      const bAttrs = parseAttrs(bm[1]);
      const btnEl = new MockElement('button', bAttrs.id || '', bAttrs.class || '', bAttrs);
      btnEl.textContent = decodeEntities(bm[2].replace(/<[^>]+>/g, '').trim());
      parent.appendChild(btnEl);
    }

    const selectedLabelRegex = /<div\b([^>]*class="variant-selected-label"[^>]*)>([\s\S]*?)<\/div>/gi;
    let slm;
    while ((slm = selectedLabelRegex.exec(htmlFragment)) !== null) {
      const slAttrs = parseAttrs(slm[1]);
      const slEl = new MockElement('div', slAttrs.id || '', slAttrs.class || '', slAttrs);
      slEl.textContent = decodeEntities(slm[2].replace(/<[^>]+>/g, '').trim());
      parent.appendChild(slEl);
    }
  }

  function matchesSimpleSelector(el, sel) {
    if (!sel) return false;
    let rest = sel;

    if (rest.includes(':not(')) {
      const notRe = /:not\(([^)]+)\)/g;
      let nm;
      while ((nm = notRe.exec(sel)) !== null) {
        if (matchesSimpleSelector(el, nm[1])) return false;
      }
      rest = rest.replace(notRe, '');
    }

    const attrRe = /\[([a-zA-Z0-9_:-]+)(?:="([^"]*)")?\]/g;
    let am;
    while ((am = attrRe.exec(rest)) !== null) {
      const attrName = am[1];
      const attrVal = am[2];
      if (attrName === 'disabled' && el.disabled) continue;
      if (!el.hasAttribute(attrName)) return false;
      if (attrVal !== undefined && el.getAttribute(attrName) !== attrVal) return false;
    }
    rest = rest.replace(attrRe, '');

    if (rest.includes(':checked')) {
      if (!el.checked) return false;
      rest = rest.replace(':checked', '');
    }

    const idMatch = rest.match(/#([a-zA-Z0-9_-]+)/);
    if (idMatch && el.id !== idMatch[1]) return false;
    rest = rest.replace(/#[a-zA-Z0-9_-]+/g, '');

    const classMatches = rest.match(/\.([a-zA-Z0-9_-]+)/g) || [];
    for (const cm of classMatches) {
      if (!el.classList.contains(cm.slice(1))) return false;
    }
    rest = rest.replace(/\.[a-zA-Z0-9_-]+/g, '').trim();

    if (rest && el.tagName !== rest.toUpperCase()) return false;
    return true;
  }

  function matchesCompoundSelector(el, sel) {
    const parts = sel.trim().split(/\s+/);
    if (!matchesSimpleSelector(el, parts[parts.length - 1])) return false;
    let cur = el.parentElement;
    for (let i = parts.length - 2; i >= 0; i--) {
      while (cur && !matchesSimpleSelector(cur, parts[i])) {
        cur = cur.parentElement;
      }
      if (!cur) return false;
      cur = cur.parentElement;
    }
    return true;
  }

  const root = new MockElement('body', 'top');
  const skipLinkEl = root.appendChild(new MockElement('a', '', 'skip-link', { href: '#catalogue' }));
  const topBarEl = root.appendChild(new MockElement('aside', '', 'top-bar'));
  const headerEl = root.appendChild(new MockElement('header', '', 'site-header'));
  const headerInnerEl = headerEl.appendChild(new MockElement('div', '', 'container header-inner'));
  const brandEl = headerInnerEl.appendChild(new MockElement('a', '', 'site-brand', { href: '#top' }));
  const primaryNavEl = headerInnerEl.appendChild(new MockElement('nav', '', 'primary-nav'));
  ['#catalogue', '#trust', '#categories'].forEach((href, idx) => {
    primaryNavEl.appendChild(new MockElement('a', `navLink${idx}`, 'nav-link', { href }));
  });
  const headerActionsEl = headerInnerEl.appendChild(new MockElement('div', '', 'header-actions'));
  const headerTelBtn = headerActionsEl.appendChild(new MockElement('a', '', 'btn btn-tel', { href: 'tel:02088880322' }));
  const headerWaBtn = headerActionsEl.appendChild(new MockElement('a', '', 'btn btn-whatsapp', { href: 'https://wa.me/442088880322' }));
  const headerQuoteBtn = headerActionsEl.appendChild(new MockElement('a', '', 'btn btn-primary', { href: '#contact' }));
  const mobileNavToggleEl = headerActionsEl.appendChild(
    new MockElement('button', 'mobileNavToggle', 'mobile-nav-toggle', { 'aria-controls': 'mobileDrawer', 'aria-expanded': 'false' })
  );

  const mobileBackdropEl = root.appendChild(new MockElement('div', 'mobileDrawerBackdrop', 'mobile-drawer-backdrop', { 'aria-hidden': 'true' }));
  const mobileDrawerEl = root.appendChild(new MockElement('aside', 'mobileDrawer', 'mobile-drawer', { 'aria-hidden': 'true', inert: true }));
  const mobileDrawerCloseEl = mobileDrawerEl.appendChild(new MockElement('button', 'mobileDrawerClose', 'mobile-drawer-close'));
  ['all', 'beds-mattresses', 'bedroom-storage', 'bed-frames-bunks', 'dining', 'sofas-living', 'appliances', 'removals'].forEach(cat => {
    mobileDrawerEl.appendChild(new MockElement('a', '', 'mobile-nav-item', { href: '#catalogue', 'data-category': cat }));
  });
  const mobileDrawerContactLink = mobileDrawerEl.appendChild(new MockElement('a', 'drawerContactLink', 'mobile-nav-item', { href: '#contact' }));

  const mainEl = root.appendChild(new MockElement('main', 'mainContent'));
  expectedCategories.forEach(c => {
    mainEl.appendChild(new MockElement('a', '', 'category-tile', { href: '#catalogue', 'data-category': c.id }));
  });
  const catalogueSectionEl = mainEl.appendChild(new MockElement('section', 'catalogue', 'catalogue-section'));
  const catalogueHeadingEl = catalogueSectionEl.appendChild(new MockElement('h2', 'catalogueHeading', 'section-title'));
  catalogueHeadingEl.textContent = 'Browse Our Catalogue';
  const filterPillsEl = catalogueSectionEl.appendChild(new MockElement('div', 'filterPills', 'filter-pills-scroll'));
  const searchInputEl = catalogueSectionEl.appendChild(new MockElement('input', 'catalogueSearch', 'catalogue-search-input', { type: 'search' }));
  const activeFilterLabelEl = catalogueSectionEl.appendChild(new MockElement('span', 'activeFilterLabel', 'catalogue-active-filter'));
  activeFilterLabelEl.textContent = 'All Items';
  const productCountLabelEl = catalogueSectionEl.appendChild(new MockElement('div', 'productCountLabel', 'catalogue-count-status'));
  productCountLabelEl.textContent = 'Browse the catalogue';
  const productGridEl = catalogueSectionEl.appendChild(new MockElement('div', 'productGrid', 'product-grid'));

  const contactSectionEl = mainEl.appendChild(new MockElement('section', 'contact', 'showroom-section'));
  const enquiryFormCardEl = contactSectionEl.appendChild(new MockElement('div', 'enquiryFormCard', 'enquiry-form-card'));
  const selectedBannerEl = enquiryFormCardEl.appendChild(new MockElement('div', 'selectedProductBanner', 'selected-product-banner', { style: 'display: none;' }));
  const selectedNameEl = selectedBannerEl.appendChild(new MockElement('span', 'selectedProductName', 'selected-badge-name'));
  const selectedPriceEl = selectedBannerEl.appendChild(new MockElement('span', 'selectedProductPrice', 'selected-badge-price'));
  const clearSelectionBtnEl = selectedBannerEl.appendChild(new MockElement('button', 'clearProductSelection', 'selected-badge-clear'));

  const enquiryFormEl = enquiryFormCardEl.appendChild(new MockElement('form', 'enquiryForm'));
  const enquiryFormErrorEl = enquiryFormEl.appendChild(new MockElement('div', 'enquiryFormError', 'form-error-summary', { hidden: true }));
  const formProductSelectEl = enquiryFormEl.appendChild(new MockElement('select', 'enquiryProductSelect', 'form-select'));
  const formProductSelectLabelEl = enquiryFormEl.appendChild(new MockElement('div', 'enquiryProductSelectLabel', 'form-select-selected-label'));
  const enquiryNameEl = enquiryFormEl.appendChild(new MockElement('input', 'enquiryName', 'form-input', { type: 'text', required: 'true', 'aria-required': 'true' }));
  const enquiryNameErrorEl = enquiryFormEl.appendChild(new MockElement('p', 'enquiryNameError', 'form-field-error', { hidden: true }));
  const enquiryPhoneReqEl = enquiryFormEl.appendChild(new MockElement('span', 'enquiryPhoneReq', 'req'));
  const enquiryPhoneEl = enquiryFormEl.appendChild(new MockElement('input', 'enquiryPhone', 'form-input', { type: 'tel', required: 'true', 'aria-required': 'true' }));
  const enquiryPhoneErrorEl = enquiryFormEl.appendChild(new MockElement('p', 'enquiryPhoneError', 'form-field-error', { hidden: true }));
  const enquiryEmailReqEl = enquiryFormEl.appendChild(new MockElement('span', 'enquiryEmailReq', 'req', { hidden: true }));
  const enquiryEmailEl = enquiryFormEl.appendChild(new MockElement('input', 'enquiryEmail', 'form-input', { type: 'email', 'aria-required': 'false' }));
  const enquiryEmailErrorEl = enquiryFormEl.appendChild(new MockElement('p', 'enquiryEmailError', 'form-field-error', { hidden: true }));
  const enquiryPostcodeEl = enquiryFormEl.appendChild(new MockElement('input', 'enquiryPostcode', 'form-input', { type: 'text' }));
  const radioTel = enquiryFormEl.appendChild(new MockElement('input', '', '', { type: 'radio', name: 'pref_contact', value: 'Telephone Call', checked: true }));
  const radioWa = enquiryFormEl.appendChild(new MockElement('input', '', '', { type: 'radio', name: 'pref_contact', value: 'WhatsApp', checked: false }));
  const radioEmail = enquiryFormEl.appendChild(new MockElement('input', '', '', { type: 'radio', name: 'pref_contact', value: 'Email', checked: false }));
  const enquiryMessageEl = enquiryFormEl.appendChild(new MockElement('textarea', 'enquiryMessage', 'form-textarea', { required: 'true', 'aria-required': 'true' }));
  const enquiryMessageErrorEl = enquiryFormEl.appendChild(new MockElement('p', 'enquiryMessageError', 'form-field-error', { hidden: true }));

  const enquiryFeedbackEl = enquiryFormCardEl.appendChild(new MockElement('div', 'enquiryFeedback', 'enquiry-feedback-box', { style: 'display: none;', hidden: true }));
  const feedbackSummaryTextEl = enquiryFeedbackEl.appendChild(new MockElement('pre', 'feedbackSummaryText', 'enquiry-summary-pre'));
  const copyEnquiryBtnEl = enquiryFeedbackEl.appendChild(new MockElement('button', 'copyEnquiryBtn', 'btn btn-secondary btn-sm'));
  const reOpenEmailBtnEl = enquiryFeedbackEl.appendChild(new MockElement('a', 'reOpenEmailBtn', 'btn btn-primary btn-sm', { href: '#' }));
  const copyFeedbackMsgEl = enquiryFeedbackEl.appendChild(new MockElement('p', 'copyFeedbackMessage', 'copy-feedback-msg', { style: 'display: none;' }));

  const footerEl = root.appendChild(new MockElement('footer', '', 'site-footer'));
  const footerCatLinks = expectedCategories.map(c =>
    footerEl.appendChild(new MockElement('a', `footerCat-${c.id}`, 'footer-category-link', { href: `#category-${c.id}`, 'data-category': c.id }))
  );
  const policyBtns = ['ordering', 'delivery', 'removals', 'privacy'].map(key =>
    footerEl.appendChild(new MockElement('button', `policyBtn-${key}`, '', { 'data-policy-trigger': key }))
  );

  const policyModalEl = root.appendChild(new MockElement('div', 'policyModal', 'policy-modal', { 'aria-hidden': 'true', inert: true }));
  const policyBackdropEl = policyModalEl.appendChild(new MockElement('div', 'policyModalBackdrop', 'policy-modal-backdrop'));
  const policyTitleEl = policyModalEl.appendChild(new MockElement('h3', 'policyModalTitle', 'policy-modal-title'));
  const policyCloseEl = policyModalEl.appendChild(new MockElement('button', 'policyModalClose', 'policy-modal-close'));
  const policyBodyEl = policyModalEl.appendChild(new MockElement('div', 'policyModalBody', 'policy-modal-content'));

  const mockDocument = {
    readyState: 'complete',
    body: root,
    activeElement: root,
    listeners: {},
    fonts: { ready: Promise.resolve() },
    createElement(tag) {
      return new MockElement(tag);
    },
    getElementById(id) {
      return root.querySelector(`#${id}`);
    },
    querySelector(sel) {
      return root.querySelector(sel);
    },
    querySelectorAll(sel) {
      return root.querySelectorAll(sel);
    },
    addEventListener(type, fn) {
      if (!this.listeners[type]) this.listeners[type] = [];
      this.listeners[type].push(fn);
    },
    dispatchEvent(event) {
      const evt = {
        type: event.type,
        target: event.target || this,
        defaultPrevented: false,
        preventDefault() {
          this.defaultPrevented = true;
        }
      };
      (this.listeners[evt.type] || []).forEach(fn => fn(evt));
      return !evt.defaultPrevented;
    }
  };

  const mockWindow = {
    innerWidth: 1025,
    innerHeight: 900,
    scrollY: 0,
    location: { hash: '', href: 'http://localhost/' },
    listeners: {},
    addEventListener(type, fn) {
      if (!this.listeners[type]) this.listeners[type] = [];
      this.listeners[type].push(fn);
    },
    removeEventListener(type, fn) {
      if (!this.listeners[type]) return;
      this.listeners[type] = this.listeners[type].filter(cb => cb !== fn);
    },
    dispatchEvent(event) {
      const evt = {
        type: event.type,
        key: event.key || '',
        shiftKey: Boolean(event.shiftKey),
        defaultPrevented: false,
        preventDefault() {
          this.defaultPrevented = true;
        }
      };
      (this.listeners[evt.type] || []).forEach(fn => fn(evt));
      return !evt.defaultPrevented;
    },
    matchMedia() {
      return { matches: false };
    },
    getComputedStyle(el) {
      return {
        display: el.style.display || 'block',
        visibility: el.hidden ? 'hidden' : 'visible'
      };
    }
  };

  const sandbox = {
    window: mockWindow,
    document: mockDocument,
    history: {
      replaceState(_state, _title, url) {
        if (typeof url === 'string' && url.startsWith('#')) {
          mockWindow.location.hash = url;
        }
      }
    },
    navigator: {
      clipboard: {
        writeText: () => Promise.resolve()
      }
    },
    HTMLElement: MockElement,
    setTimeout: (fn) => { fn(); return 1; },
    clearTimeout: () => {},
    encodeURIComponent,
    Number,
    String,
    Boolean,
    Array,
    Object,
    Math
  };

  vm.runInNewContext(js, sandbox);

  // Runtime Test 1: Desktop header collapse at 1025px and rectangle collision detection
  assert(
    headerEl.classList.contains('is-collapsed'),
    'Runtime: Header remains collapsed at 1025px viewport to prevent desktop nav/button hit-target overlap'
  );

  // Simulate 1440px viewport where navRect and actionsRect collide/overlap
  mockWindow.innerWidth = 1440;
  headerInnerEl.scrollWidth = 1380;
  headerInnerEl.clientWidth = 1380;
  headerInnerEl._rect = { left: 30, top: 0, right: 1410, bottom: 116, width: 1380, height: 116 };
  brandEl._rect = { left: 30, top: 20, right: 280, bottom: 96, width: 250, height: 76 };
  primaryNavEl._rect = { left: 320, top: 36, right: 920, bottom: 80, width: 600, height: 44 };
  headerActionsEl._rect = { left: 890, top: 36, right: 1410, bottom: 80, width: 520, height: 44 };
  mockWindow.dispatchEvent({ type: 'resize' });
  assert(
    headerEl.classList.contains('is-collapsed'),
    'Runtime: Header stays collapsed even above 1399px if primary-nav and header-actions bounding rectangles overlap'
  );

  // Simulate 1440px viewport where all header controls have non-overlapping rectangles
  primaryNavEl._rect = { left: 330, top: 36, right: 760, bottom: 80, width: 430, height: 44 };
  headerActionsEl._rect = { left: 860, top: 36, right: 1390, bottom: 80, width: 530, height: 44 };
  const navLinksInHeader = primaryNavEl.querySelectorAll('.nav-link');
  navLinksInHeader.forEach((lnk, idx) => {
    lnk._rect = { left: 330 + idx * 140, top: 36, right: 330 + idx * 140 + 130, bottom: 80, width: 130, height: 44 };
  });
  headerTelBtn._rect = { left: 860, top: 36, right: 1010, bottom: 80, width: 150, height: 44 };
  headerWaBtn._rect = { left: 1022, top: 36, right: 1162, bottom: 80, width: 140, height: 44 };
  headerQuoteBtn._rect = { left: 1174, top: 36, right: 1350, bottom: 80, width: 176, height: 44 };
  mockWindow.dispatchEvent({ type: 'resize' });
  assert(
    !headerEl.classList.contains('is-collapsed'),
    'Runtime: Header uncollapses at 1440px when all brand, nav, and action rectangles fit without overlap'
  );

  // Runtime Test 2: Footer category links apply actual filter state, count, and heading
  const storageFooterLink = footerCatLinks.find(l => l.getAttribute('data-category') === 'bedroom-storage');
  storageFooterLink.click();
  const activePillsAfterFooterClick = filterPillsEl.querySelectorAll('.filter-pill').filter(p => p.getAttribute('aria-pressed') === 'true');
  assert(
    activeFilterLabelEl.textContent === 'Bedroom Storage' &&
      catalogueHeadingEl.textContent === 'Bedroom Storage' &&
      productCountLabelEl.textContent === 'Showing 6 items in Bedroom Storage' &&
      productGridEl.children.length === 6 &&
      activePillsAfterFooterClick.length === 1 &&
      activePillsAfterFooterClick[0].getAttribute('data-category') === 'bedroom-storage' &&
      storageFooterLink.getAttribute('aria-current') === 'true',
    'Runtime: Clicking footer category link "Bedroom Storage" updates filter pill aria-pressed, heading, count (6 items), and cards'
  );

  const removalsFooterLink = footerCatLinks.find(l => l.getAttribute('data-category') === 'removals');
  removalsFooterLink.click();
  assert(
    activeFilterLabelEl.textContent === 'Furniture Removals' &&
      catalogueHeadingEl.textContent === 'Furniture Removals' &&
      productCountLabelEl.textContent === 'Showing 1 item in Furniture Removals' &&
      productGridEl.children.length === 1,
    'Runtime: Clicking footer category link "Furniture Removals" updates heading, singular count (1 item), and renders removal card'
  );

  // Reset back to All Items via filter pill
  const allFilterPill = filterPillsEl.querySelector('.filter-pill[data-category="all"]');
  allFilterPill.click();
  assert(
    activeFilterLabelEl.textContent === 'All Items' &&
      catalogueHeadingEl.textContent === 'Browse Our Catalogue' &&
      productCountLabelEl.textContent === 'Showing 26 items' &&
      productGridEl.children.length === 26,
    'Runtime: Clicking "All Items" filter pill restores full 26-item catalogue, count, and heading'
  );

  // Runtime Test 3: Modal & Mobile Drawer Accessibility (Focus Trap, Inert Background, Escape, No Simultaneous Overlays, Restore Focus)
  mobileNavToggleEl.focus();
  mobileNavToggleEl.click();
  assert(
    mobileDrawerEl.classList.contains('is-open') &&
      mobileDrawerEl.getAttribute('aria-hidden') === 'false' &&
      !mobileDrawerEl.inert &&
      mobileNavToggleEl.getAttribute('aria-expanded') === 'true' &&
      mainEl.inert === true &&
      headerEl.inert === true &&
      footerEl.inert === true &&
      mockDocument.activeElement === mobileDrawerCloseEl,
    'Runtime: Opening mobile drawer marks background regions inert, sets aria-expanded="true", and focuses #mobileDrawerClose'
  );

  // Reverse Shift+Tab on first focusable (#mobileDrawerClose) wraps to last focusable (#drawerContactLink)
  mockWindow.dispatchEvent({ type: 'keydown', key: 'Tab', shiftKey: true });
  assert(
    mockDocument.activeElement === mobileDrawerContactLink,
    'Runtime: Reverse Shift+Tab on first drawer element wraps focus to last focusable drawer item'
  );

  // Forward Tab on last focusable (#drawerContactLink) wraps to first focusable (#mobileDrawerClose)
  mockWindow.dispatchEvent({ type: 'keydown', key: 'Tab', shiftKey: false });
  assert(
    mockDocument.activeElement === mobileDrawerCloseEl,
    'Runtime: Forward Tab on last drawer element wraps focus to first focusable drawer item (#mobileDrawerClose)'
  );

  // Opening policy modal while drawer is open closes drawer first (prevents simultaneous overlays)
  const deliveryPolicyBtn = policyBtns.find(b => b.getAttribute('data-policy-trigger') === 'delivery');
  deliveryPolicyBtn.focus();
  deliveryPolicyBtn.click();
  assert(
    policyModalEl.classList.contains('is-open') &&
      !mobileDrawerEl.classList.contains('is-open') &&
      mobileDrawerEl.inert === true &&
      mainEl.inert === true &&
      policyTitleEl.textContent === 'Delivery Information' &&
      mockDocument.activeElement === policyCloseEl,
    'Runtime: Opening policy modal closes mobile drawer (no simultaneous overlays), keeps background inert, and focuses modal close button'
  );

  // Escape closes only the active policy modal and restores focus to the exact invoking policy trigger
  mockWindow.dispatchEvent({ type: 'keydown', key: 'Escape' });
  assert(
    !policyModalEl.classList.contains('is-open') &&
      policyModalEl.inert === true &&
      mainEl.inert === false &&
      headerEl.inert === false &&
      footerEl.inert === false &&
      mockDocument.activeElement === deliveryPolicyBtn,
    'Runtime: Escape closes policy modal, clears background inert state, and restores focus to exact invoking trigger button'
  );

  // Reduced-motion mobile drawer open/close focus timing & visibility verification
  mockWindow.matchMedia = (q) => ({ matches: q.includes('prefers-reduced-motion') });
  mobileNavToggleEl.focus();
  mobileNavToggleEl.click();
  assert(
    mobileDrawerEl.classList.contains('is-open') &&
      mobileDrawerEl.style.visibility === 'visible' &&
      mobileDrawerCloseEl.style.visibility === 'visible' &&
      mockDocument.activeElement === mobileDrawerCloseEl,
    'Runtime: With prefers-reduced-motion: reduce, opening mobile drawer establishes visibility before focusing #mobileDrawerClose'
  );
  mockWindow.dispatchEvent({ type: 'keydown', key: 'Escape' });
  assert(
    !mobileDrawerEl.classList.contains('is-open') &&
      mobileDrawerEl.inert === true &&
      mockDocument.activeElement === mobileNavToggleEl,
    'Runtime: With prefers-reduced-motion: reduce, closing mobile drawer restores focus to #mobileNavToggle'
  );
  mockWindow.matchMedia = () => ({ matches: false });

  // Runtime Test 4: Enquiry Journey (Authoritative Variant State, Wrapping Selected Labels, Multi-Dash Labels, Customer Requirement Preservation, Validation & Stale Feedback Invalidation)
  const oxfordCard = productGridEl.querySelector('.product-card[data-product-id="oxford-divan-bed"]');
  const oxfordSelect = oxfordCard.querySelector('.variant-select');
  const oxfordSelectedLabel = oxfordCard.querySelector('.variant-selected-label');
  const oxfordBtn = oxfordCard.querySelector('.enquire-action-btn');

  assert(
    oxfordSelectedLabel &&
      oxfordSelectedLabel.textContent === '3ft Single — Set (Base & Mattress) — £130' &&
      formProductSelectLabelEl.textContent === 'Furniture Package, Multiple Items or General Enquiry',
    'Runtime: Initial wrapping selected-option labels display full active option text on card and form selector'
  );

  // Switch Oxford card variant to "4ft / 4ft6 — Mattress Only" (£125)
  const matt4ftIdx = oxfordSelect.options.findIndex(o => o.value === 'oxford-matt-4ft');
  oxfordSelect.selectedIndex = matt4ftIdx;
  oxfordSelect.value = 'oxford-matt-4ft';
  oxfordSelect.dispatchEvent({ type: 'change' });

  assert(
    oxfordBtn.getAttribute('data-variant-label') === '4ft / 4ft6 — Mattress Only' &&
      oxfordBtn.getAttribute('data-price') === '125' &&
      oxfordSelectedLabel.textContent === '4ft / 4ft6 — Mattress Only — £125',
    'Runtime: Switching product card variant preserves complete multi-dash label "4ft / 4ft6 — Mattress Only", price £125, and updates wrapping selected-option label'
  );

  // Inline-edited generated sentence preservation test (e.g. customer inserts "TWO of " inside generated paragraph)
  enquiryMessageEl.value = '';
  oxfordBtn.click();
  assert(
    formProductSelectLabelEl.textContent === 'Oxford Divan Bed — 4ft / 4ft6 — Mattress Only (£125)',
    'Runtime: Selecting item updates wrapping form selector summary label with full product, variant, and price'
  );
  enquiryMessageEl.value = enquiryMessageEl.value.replace(
    'Please provide a quote for ',
    'Please provide a quote for TWO of '
  );
  const inlineEditedSentenceText = enquiryMessageEl.value;

  // Switching variant after customer edited generated sentence inline must preserve the inline-edited text
  const set5ftIdx = oxfordSelect.options.findIndex(o => o.value === 'oxford-set-5ft');
  oxfordSelect.selectedIndex = set5ftIdx;
  oxfordSelect.value = 'oxford-set-5ft';
  oxfordSelect.dispatchEvent({ type: 'change' });
  assert(
    enquiryMessageEl.value.includes('Please provide a quote for TWO of Oxford Divan Bed — 4ft / 4ft6 — Mattress Only, shown at £125 in your catalogue.') &&
      enquiryMessageEl.value.includes('Please provide a quote for Oxford Divan Bed — 5ft King — Set (Base & Mattress), shown at £200 in your catalogue.'),
    'Runtime: Switching variant after customer inline-edits a generated sentence preserves the edited text alongside the new selection template'
  );

  // Remove Selection after inline edit removes only the unedited system-generated block and preserves the inline-edited customer text
  clearSelectionBtnEl.click();
  assert(
    enquiryMessageEl.value === inlineEditedSentenceText &&
      formProductSelectLabelEl.textContent === 'Furniture Package, Multiple Items or General Enquiry',
    'Runtime: Remove Selection preserves customer inline-edited text byte-for-byte and resets form selector wrapping label'
  );

  // Reset Oxford card back to 4ft / 4ft6 — Mattress Only (£125) for subsequent tests
  oxfordSelect.selectedIndex = matt4ftIdx;
  oxfordSelect.value = 'oxford-matt-4ft';
  oxfordSelect.dispatchEvent({ type: 'change' });

  // Customer writes custom requirements BEFORE selecting an item
  const customCustomerNotes = 'Deliver 2 sets to 14 High Road next Tuesday; collect keys from letting agent.';
  enquiryMessageEl.value = customCustomerNotes;

  // Click "Enquire About This Item" on Oxford card (with timers deferred to prove synchronous scroll + focus without timers)
  const originalSetTimeout = sandbox.setTimeout;
  sandbox.setTimeout = () => 1;
  const scrollListenersBeforeClick = (mockWindow.listeners.scroll || []).length;
  const scrollEndListenersBeforeClick = (mockWindow.listeners.scrollend || []).length;
  selectedBannerEl.scrollIntoViewCalls = [];
  oxfordBtn.click();
  const scrollListenersAfterClick = (mockWindow.listeners.scroll || []).length;
  const scrollEndListenersAfterClick = (mockWindow.listeners.scrollend || []).length;
  assert(
    selectedBannerEl.style.display === 'flex' &&
      selectedBannerEl.getAttribute('tabindex') === '-1' &&
      selectedNameEl.textContent === 'Oxford Divan Bed — 4ft / 4ft6 — Mattress Only' &&
      selectedPriceEl.textContent === 'Catalogue price: £125' &&
      formProductSelectEl.value === 'oxford-divan-bed' &&
      enquiryMessageEl.value.includes('Please provide a quote for Oxford Divan Bed — 4ft / 4ft6 — Mattress Only, shown at £125 in your catalogue.') &&
      enquiryMessageEl.value.includes(customCustomerNotes) &&
      selectedBannerEl.scrollIntoViewCalls.length === 1 &&
      selectedBannerEl.scrollIntoViewCalls[0].behavior === 'auto' &&
      selectedBannerEl.scrollIntoViewCalls[0].block === 'start' &&
      scrollListenersAfterClick === scrollListenersBeforeClick &&
      scrollEndListenersAfterClick === scrollEndListenersBeforeClick &&
      enquiryNameEl.lastFocusOptions &&
      enquiryNameEl.lastFocusOptions.preventScroll === true,
    'Runtime: Selecting item populates banner, dropdown, and quote template while preserving customer-written requirements and synchronously scrolling (behavior:"auto", block:"start") and focusing without timers or scroll listeners'
  );

  // Wider screen with #enquiryName below viewport focuses selectedBanner synchronously with behavior:'auto', preventScroll (not #enquiryName) and avoids second scroll
  selectedBannerEl.scrollIntoViewCalls = [];
  selectedBannerEl.lastFocusOptions = null;
  enquiryNameEl.lastFocusOptions = null;
  enquiryNameEl._rect = { left: 0, top: 860, right: 320, bottom: 930, width: 320, height: 70 };
  oxfordBtn.click();
  assert(
    selectedBannerEl.scrollIntoViewCalls.length === 1 &&
      selectedBannerEl.scrollIntoViewCalls[0].behavior === 'auto' &&
      selectedBannerEl.scrollIntoViewCalls[0].block === 'start' &&
      mockDocument.activeElement === selectedBannerEl &&
      selectedBannerEl.lastFocusOptions &&
      selectedBannerEl.lastFocusOptions.preventScroll === true &&
      enquiryNameEl.lastFocusOptions === null,
    'Runtime: On wider screens, if #enquiryName is not fully within viewport after synchronous behavior:"auto" scroll, focus lands immediately on #selectedProductBanner with preventScroll'
  );

  // Mobile viewport (<=768px) focuses selectedBanner synchronously with behavior:'auto' and preventScroll and never focuses #enquiryName
  mockWindow.innerWidth = 375;
  mockWindow.innerHeight = 667;
  selectedBannerEl.scrollIntoViewCalls = [];
  selectedBannerEl.lastFocusOptions = null;
  enquiryNameEl.lastFocusOptions = null;
  enquiryNameEl._rect = { left: 16, top: 200, right: 340, bottom: 244, width: 324, height: 44 };
  oxfordBtn.click();
  assert(
    selectedBannerEl.scrollIntoViewCalls.length === 1 &&
      selectedBannerEl.scrollIntoViewCalls[0].behavior === 'auto' &&
      selectedBannerEl.scrollIntoViewCalls[0].block === 'start' &&
      mockDocument.activeElement === selectedBannerEl &&
      selectedBannerEl.lastFocusOptions &&
      selectedBannerEl.lastFocusOptions.preventScroll === true &&
      enquiryNameEl.lastFocusOptions === null,
    'Runtime: On mobile viewports, selecting an item synchronously scrolls (behavior:"auto", block:"start") and focuses #selectedProductBanner with preventScroll and never focuses #enquiryName'
  );
  // Reduced-motion preference uses identical synchronous behavior:'auto' scroll + preventScroll focus
  mockWindow.matchMedia = (q) => ({ matches: q.includes('prefers-reduced-motion') || q.includes('max-width: 768px') });
  selectedBannerEl.scrollIntoViewCalls = [];
  selectedBannerEl.lastFocusOptions = null;
  oxfordBtn.click();
  assert(
    selectedBannerEl.scrollIntoViewCalls.length === 1 &&
      selectedBannerEl.scrollIntoViewCalls[0].behavior === 'auto' &&
      selectedBannerEl.scrollIntoViewCalls[0].block === 'start' &&
      mockDocument.activeElement === selectedBannerEl &&
      selectedBannerEl.lastFocusOptions &&
      selectedBannerEl.lastFocusOptions.preventScroll === true,
    'Runtime: Reduced-motion and normal motion both use identical synchronous behavior:"auto" scroll and immediate preventScroll focus'
  );
  mockWindow.matchMedia = () => ({ matches: false });
  sandbox.setTimeout = originalSetTimeout;
  mockWindow.innerWidth = 1440;
  mockWindow.innerHeight = 900;
  enquiryNameEl._rect = { left: 0, top: 0, right: 100, bottom: 44, width: 100, height: 44 };

  // Switch dropdown to Furniture Removal and verify removal-specific template + customer notes still preserved
  formProductSelectEl.value = 'furniture-removal-service';
  formProductSelectEl.dispatchEvent({ type: 'change' });
  assert(
    selectedNameEl.textContent === 'Furniture Removal — Chest of Drawers' &&
      selectedPriceEl.textContent === 'Catalogue price: £20' &&
      enquiryMessageEl.value.includes('I would like to arrange removal of Chest of Drawers, shown at £20 in your catalogue.') &&
      enquiryMessageEl.value.includes(customCustomerNotes),
    'Runtime: Switching dropdown to Furniture Removal generates removal-specific message while still preserving customer-written notes'
  );

  // Clear selection and verify banner hides, dropdown resets to general, and customer notes remain intact
  clearSelectionBtnEl.click();
  assert(
    selectedBannerEl.style.display === 'none' &&
      formProductSelectEl.value === 'general' &&
      enquiryMessageEl.value === customCustomerNotes,
    'Runtime: Removing item selection clears banner and generated template while keeping customer-written requirements intact'
  );

  // Validation Test 1: Initial state (Telephone Call) requires Full Name, Telephone, and Requirements, while Email is optional
  assert(
    enquiryNameEl.getAttribute('aria-required') === 'true' &&
      enquiryMessageEl.getAttribute('aria-required') === 'true' &&
      enquiryPhoneEl.hasAttribute('required') &&
      enquiryPhoneEl.getAttribute('aria-required') === 'true' &&
      !enquiryPhoneReqEl.hidden &&
      !enquiryEmailEl.hasAttribute('required') &&
      enquiryEmailEl.getAttribute('aria-required') === 'false' &&
      enquiryEmailReqEl.hidden,
    'Runtime: Initial "Telephone Call" contact method requires Name, Telephone, and Requirements while leaving Email optional'
  );

  // Validation Test 2: Empty name & empty telephone (with blank optional email) when Telephone Call is selected -> marks Name & Phone invalid (not Email) and focuses #enquiryName
  enquiryNameEl.value = '';
  enquiryPhoneEl.value = '';
  enquiryEmailEl.value = '';
  enquiryFormEl.dispatchEvent({ type: 'submit' });
  assert(
    enquiryNameEl.getAttribute('aria-invalid') === 'true' &&
      enquiryPhoneEl.getAttribute('aria-invalid') === 'true' &&
      !enquiryEmailEl.hasAttribute('aria-invalid') &&
      !enquiryNameErrorEl.hidden &&
      !enquiryPhoneErrorEl.hidden &&
      enquiryEmailErrorEl.hidden &&
      !enquiryFormErrorEl.hidden &&
      enquiryFormErrorEl.textContent === 'Enter your full name and telephone number to prepare your email draft.' &&
      mockDocument.activeElement === enquiryNameEl &&
      enquiryFeedbackEl.style.display === 'none',
    'Runtime: Missing Name and Telephone (with blank Email) under "Telephone Call" marks only Name & Telephone invalid and focuses #enquiryName'
  );

  // Validation Test 3: Fix Name, supply invalid Phone and non-empty invalid optional Email -> validates optional Email format and focuses #enquiryPhone
  enquiryNameEl.value = 'Sarah Jenkins';
  enquiryNameEl.dispatchEvent({ type: 'input' });
  enquiryPhoneEl.value = 'invalid-phone';
  enquiryEmailEl.value = 'not-an-email';
  enquiryFormEl.dispatchEvent({ type: 'submit' });
  assert(
    !enquiryNameEl.hasAttribute('aria-invalid') &&
      enquiryPhoneEl.getAttribute('aria-invalid') === 'true' &&
      enquiryEmailEl.getAttribute('aria-invalid') === 'true' &&
      !enquiryPhoneErrorEl.hidden &&
      !enquiryEmailErrorEl.hidden &&
      mockDocument.activeElement === enquiryPhoneEl,
    'Runtime: Fixing Name clears its error, validates non-required filled Email format, and focuses first invalid field (#enquiryPhone)'
  );

  // Validation Test 4: Valid Telephone with blank Email under WhatsApp contact method succeeds
  radioTel.checked = false;
  radioWa.checked = true;
  radioWa.dispatchEvent({ type: 'change' });
  enquiryPhoneEl.value = '07123 456789';
  enquiryPhoneEl.dispatchEvent({ type: 'input' });
  enquiryEmailEl.value = '';
  enquiryEmailEl.dispatchEvent({ type: 'input' });
  oxfordBtn.click();
  enquiryFormEl.dispatchEvent({ type: 'submit' });
  assert(
    enquiryPhoneEl.hasAttribute('required') &&
      enquiryPhoneEl.getAttribute('aria-required') === 'true' &&
      !enquiryPhoneReqEl.hidden &&
      !enquiryEmailEl.hasAttribute('required') &&
      enquiryEmailEl.getAttribute('aria-required') === 'false' &&
      enquiryEmailReqEl.hidden &&
      enquiryFeedbackEl.style.display === 'block' &&
      !enquiryFeedbackEl.hidden &&
      feedbackSummaryTextEl.textContent.includes('Preferred Contact Method: WhatsApp') &&
      feedbackSummaryTextEl.textContent.includes('Oxford Divan Bed — 4ft / 4ft6 — Mattress Only (£125)') &&
      feedbackSummaryTextEl.textContent.includes(customCustomerNotes) &&
      mockWindow.location.href.startsWith('mailto:info@gbafurniture.com?subject='),
    'Runtime: "WhatsApp" contact method requires valid Telephone, allows blank Email, and prepares mailto draft'
  );

  // Validation Test 5: Switching to Email contact method flips required/aria-required & indicators, requires valid Email, and validates non-empty optional Telephone format
  radioWa.checked = false;
  radioEmail.checked = true;
  radioEmail.dispatchEvent({ type: 'change' });
  assert(
    !enquiryPhoneEl.hasAttribute('required') &&
      enquiryPhoneEl.getAttribute('aria-required') === 'false' &&
      enquiryPhoneReqEl.hidden &&
      enquiryEmailEl.hasAttribute('required') &&
      enquiryEmailEl.getAttribute('aria-required') === 'true' &&
      !enquiryEmailReqEl.hidden &&
      enquiryFeedbackEl.style.display === 'none',
    'Runtime: Switching to "Email" dynamically marks Email required, Telephone optional, updates required indicators, and invalidates stale draft feedback'
  );

  // Blank Phone + Blank Email under Email contact method -> requires Email (not Phone) and focuses #enquiryEmail
  enquiryPhoneEl.value = '';
  enquiryEmailEl.value = '';
  enquiryFormEl.dispatchEvent({ type: 'submit' });
  assert(
    !enquiryPhoneEl.hasAttribute('aria-invalid') &&
      enquiryEmailEl.getAttribute('aria-invalid') === 'true' &&
      !enquiryEmailErrorEl.hidden &&
      !enquiryFormErrorEl.hidden &&
      enquiryFormErrorEl.textContent === 'Enter your email address to prepare your email draft.' &&
      mockDocument.activeElement === enquiryEmailEl,
    'Runtime: Under "Email" contact method, blank Email and blank Telephone marks only Email invalid and focuses #enquiryEmail'
  );

  // Valid Email + non-empty invalid optional Telephone under Email contact method -> validates optional Telephone format and focuses #enquiryPhone
  enquiryEmailEl.value = 'sarah@agency.co.uk';
  enquiryEmailEl.dispatchEvent({ type: 'input' });
  enquiryPhoneEl.value = 'bad-phone';
  enquiryFormEl.dispatchEvent({ type: 'submit' });
  assert(
    !enquiryEmailEl.hasAttribute('aria-invalid') &&
      enquiryPhoneEl.getAttribute('aria-invalid') === 'true' &&
      !enquiryPhoneErrorEl.hidden &&
      mockDocument.activeElement === enquiryPhoneEl,
    'Runtime: Under "Email" contact method, non-empty invalid optional Telephone is format-validated and focused (#enquiryPhone)'
  );

  // Clear optional Telephone and submit valid Email enquiry -> succeeds without Telephone
  enquiryPhoneEl.value = '';
  enquiryPhoneEl.dispatchEvent({ type: 'input' });
  enquiryFormEl.dispatchEvent({ type: 'submit' });
  assert(
    enquiryFeedbackEl.style.display === 'block' &&
      !enquiryFeedbackEl.hidden &&
      feedbackSummaryTextEl.textContent.includes('Preferred Contact Method: Email') &&
      feedbackSummaryTextEl.textContent.includes('Email: sarah@agency.co.uk') &&
      mockWindow.location.href.startsWith('mailto:info@gbafurniture.com?subject='),
    'Runtime: Under "Email" contact method, valid Email with blank Telephone prepares mailto draft and reveals summary feedback'
  );

  // Edit a source field after submission -> stale prepared-email feedback is invalidated immediately
  enquiryPostcodeEl.value = 'N17 6AE';
  enquiryPostcodeEl.dispatchEvent({ type: 'input' });
  assert(
    enquiryFeedbackEl.style.display === 'none' &&
      enquiryFeedbackEl.hidden === true &&
      feedbackSummaryTextEl.textContent === '',
    'Runtime: Editing any form field immediately invalidates and hides stale prepared-email feedback'
  );
})();

// 7. Local HTTP Server Delivery Test
console.log('\n7. Checking Local HTTP Server Delivery:');
const server = http.createServer((req, res) => {
  const urlPath = new URL(req.url, 'http://127.0.0.1').pathname;
  let filePath = path.join(__dirname, urlPath === '/' ? 'index.html' : urlPath);

  if (!fs.existsSync(filePath)) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
    return;
  }

  const ext = path.extname(filePath).toLowerCase();
  const mimeTypes = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml'
  };

  const contentType = mimeTypes[ext] || 'application/octet-stream';
  res.writeHead(200, { 'Content-Type': contentType });
  fs.createReadStream(filePath).pipe(res);
});

server.listen(0, '127.0.0.1', () => {
  const port = server.address().port;
  console.log(`  Local test HTTP server running on port ${port}`);

  const uniqueVersionedPlaceholders = Array.from(new Set(data.products.map(p => `/${p.placeholder}`)));
  const endpointsToTest = [
    { path: '/', status: 200, type: 'text/html', checkBody: (buf) => buf.toString('utf8').includes('<!DOCTYPE html>') && buf.toString('utf8').includes('GBA Furniture') },
    { path: '/styles.css', status: 200, type: 'text/css', checkBody: (buf) => !buf.toString('utf8').trimStart().startsWith('<') && buf.toString('utf8').includes('--color-petrol') },
    { path: '/styles.css?v=public-audit-20261020', status: 200, type: 'text/css', checkBody: (buf) => !buf.toString('utf8').trimStart().startsWith('<') && buf.toString('utf8').includes('--color-petrol') },
    { path: '/script.js', status: 200, type: 'application/javascript', checkBody: (buf) => !buf.toString('utf8').trimStart().startsWith('<') && buf.toString('utf8').includes('CATALOGUE_DATA') },
    { path: '/script.js?v=public-audit-20261020', status: 200, type: 'application/javascript', checkBody: (buf) => !buf.toString('utf8').trimStart().startsWith('<') && buf.toString('utf8').includes('v=public-audit-20261020') },
    { path: '/data/products.json', status: 200, type: 'application/json', checkBody: (buf) => { try { const j = JSON.parse(buf.toString('utf8')); return Array.isArray(j.products) && j.products.length === 26; } catch (_e) { return false; } } },
    { path: '/assets/gba-logo-official-transparent.png', status: 200, type: 'image/png', checkBody: (buf) => buf.length >= 24 && buf.subarray(0, 8).toString('hex') === '89504e470d0a1a0a' },
    { path: '/assets/gba-logo-web.png', status: 200, type: 'image/png', checkBody: (buf) => buf.length >= 24 && buf.subarray(0, 8).toString('hex') === '89504e470d0a1a0a' },
    {
      path: '/assets/current-banner.jpg',
      status: 200,
      type: 'image/jpeg',
      checkBody: (buf) =>
        buf.length === EXPECTED_HERO_BYTE_LENGTH &&
        buf.subarray(0, 3).toString('hex') === 'ffd8ff' &&
        crypto.createHash('sha256').update(buf).digest('hex') === EXPECTED_HERO_SHA256 &&
        buf.equals(heroBannerBytes)
    },
    {
      path: `/${EXPECTED_HERO_VERSIONED_REF}`,
      status: 200,
      type: 'image/jpeg',
      checkBody: (buf) =>
        buf.length === EXPECTED_HERO_BYTE_LENGTH &&
        buf.subarray(0, 3).toString('hex') === 'ffd8ff' &&
        crypto.createHash('sha256').update(buf).digest('hex') === EXPECTED_HERO_SHA256 &&
        buf.equals(heroBannerBytes)
    },
    ...svgFiles.map(file => ({
      path: `/${file}`,
      status: 200,
      type: 'image/svg+xml',
      checkBody: (buf) => {
        const s = buf.toString('utf8').trim();
        const marker = path.basename(file) === 'van.svg' ? 'Furniture removal service' : 'Illustration only — not a product photograph';
        return s.startsWith('<svg') && s.endsWith('</svg>') && !s.toLowerCase().includes('<html') && s.includes(marker);
      }
    })),
    ...uniqueVersionedPlaceholders.map(placeholderPath => ({
      path: placeholderPath,
      status: 200,
      type: 'image/svg+xml',
      checkBody: (buf) => {
        const s = buf.toString('utf8').trim();
        const cleanFile = new URL(placeholderPath, 'http://127.0.0.1').pathname;
        const marker = path.basename(cleanFile) === 'van.svg' ? 'Furniture removal service' : 'Illustration only — not a product photograph';
        return s.startsWith('<svg') && s.endsWith('</svg>') && !s.toLowerCase().includes('<html') && s.includes(marker);
      }
    }))
  ];

  let completedRequests = 0;

  endpointsToTest.forEach(ep => {
    http.get(`http://127.0.0.1:${port}${ep.path}`, (res) => {
      assert(res.statusCode === ep.status, `HTTP GET ${ep.path} responded with ${res.statusCode}`);
      const ct = res.headers['content-type'] || '';
      assert(ct.includes(ep.type), `HTTP GET ${ep.path} returned content-type containing '${ep.type}'`);

      const chunks = [];
      res.on('data', (chunk) => { chunks.push(chunk); });
      res.on('end', () => {
        const bodyBuf = Buffer.concat(chunks);
        assert(ep.checkBody(bodyBuf), `HTTP GET ${ep.path} returned valid ${ep.type} format/signature and expected marker`);
        completedRequests++;
        if (completedRequests === endpointsToTest.length) {
          server.close(() => {
            console.log(`\n=== Verification Complete: ${passedTests} passed, ${failedTests} failed ===`);
            process.exit(failedTests > 0 ? 1 : 0);
          });
        }
      });
    }).on('error', (err) => {
      assert(false, `HTTP GET ${ep.path} failed with network error: ${err.message}`);
      completedRequests++;
      if (completedRequests === endpointsToTest.length) {
        server.close(() => process.exit(1));
      }
    });
  });
});
