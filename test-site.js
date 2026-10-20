/**
 * GBA Furniture — Prototype Verification Suite
 * Automated tests for HTML structure, CSS rules, catalog data integrity,
 * accessibility attributes, contact details, absence of unsupported claims,
 * honest form behaviour, and HTTP server delivery.
 */

const fs = require('fs');
const path = require('path');
const http = require('http');

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
const requiredFiles = [
  'index.html',
  'styles.css',
  'script.js',
  'README.md',
  'serve.js',
  'data/products.json',
  'assets/gba-logo-official-transparent.png',
  'assets/gba-logo-web.png',
  'assets/gba-logo.png',
  'assets/current-banner.jpg',
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

requiredFiles.forEach(file => {
  const filePath = path.join(__dirname, file);
  assert(fs.existsSync(filePath), `File exists: ${file}`);
});

// 2. Data Integrity Checks
console.log('\n2. Checking Catalogue Data Integrity:');
const rawData = fs.readFileSync(path.join(__dirname, 'data/products.json'), 'utf8');
const data = JSON.parse(rawData);

assert(Array.isArray(data.categories) && data.categories.length === 7, 'Exactly 7 furniture categories present in products.json');

const expectedCategories = [
  'beds-mattresses',
  'bedroom-storage',
  'bed-frames-bunks',
  'dining',
  'sofas-living',
  'appliances',
  'removals'
];

expectedCategories.forEach(catId => {
  const exists = data.categories.some(c => c.id === catId);
  assert(exists, `Required category present: ${catId}`);
});

assert(Array.isArray(data.products) && data.products.length >= 25, `Catalogue has ${data.products.length} products (expected >= 25)`);

let allPricesValid = true;
let totalVariants = 0;
data.products.forEach(p => {
  if (typeof p.startingPrice !== 'number' || p.startingPrice <= 0) allPricesValid = false;
  if (!Array.isArray(p.variants) || p.variants.length === 0) allPricesValid = false;
  p.variants.forEach(v => {
    totalVariants++;
    if (typeof v.price !== 'number' || v.price <= 0) allPricesValid = false;
  });
});
assert(allPricesValid, `All ${totalVariants} product variants have valid numeric GBP pricing`);

// Check specific key price list items
const oxford = data.products.find(p => p.id === 'oxford-divan-bed');
assert(oxford && oxford.variants.some(v => v.price === 130), 'Oxford 3ft Single Set is £130');
assert(oxford && oxford.variants.some(v => v.price === 95), 'Oxford 3ft Single Matt Only is £95');

const wardrobeAb = data.products.find(p => p.id === 'ab-wardrobe-2door');
assert(wardrobeAb && wardrobeAb.variants.some(v => v.price === 150), 'AB 2-Door Wardrobe is £150');

const removals = data.products.find(p => p.id === 'furniture-removal-service');
assert(removals && removals.variants.some(v => v.price === 20), 'Removal service starts at £20');

// 3. Grounding Enforcement: Checking Absence of Unsupported Claims
console.log('\n3. Enforcing Truthfulness & Absence of Unsupported Claims:');
const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const js = fs.readFileSync(path.join(__dirname, 'script.js'), 'utf8');

const bannedTerms = [
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
  'official catalogue'
];

bannedTerms.forEach(term => {
  const inHtml = html.toLowerCase().includes(term);
  const inJs = js.toLowerCase().includes(term);
  const inData = rawData.toLowerCase().includes(term);
  assert(!inHtml && !inJs && !inData, `Unsupported claim/term absent: "${term}"`);
});

// 4. Checking Verified Contact Details
console.log('\n4. Checking Public Contact Details & Store Facts:');
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

// Newly confirmed business positioning & service copy
const htmlLower = html.toLowerCase();
assert(htmlLower.includes('family-run'), 'Confirmed copy "family-run" present in HTML');
assert(htmlLower.includes('20 years'), 'Confirmed copy "20 years" present in HTML');
assert(htmlLower.includes('landlords'), 'Confirmed copy "landlords" present in HTML');
assert(htmlLower.includes('letting agents'), 'Confirmed copy "letting agents" present in HTML');
assert(htmlLower.includes('property managers'), 'Confirmed copy "property managers" present in HTML');
assert(htmlLower.includes('key collection by arrangement'), 'Confirmed copy "key collection by arrangement" present in HTML');
assert(htmlLower.includes('same-day delivery'), 'Confirmed copy "same-day delivery" present in HTML');
assert(htmlLower.includes('subject to') && htmlLower.includes('stock') && htmlLower.includes('delivery-slot confirmation'), 'Conditional qualifier language including "subject to", "stock", and "delivery-slot confirmation" present in HTML');
assert(html.includes('same-day delivery subject to stock, location/route and delivery-slot confirmation'), 'Exact conditional same-day delivery qualifier phrase present in HTML');

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

// 5. Checking Honest Form Behaviour
console.log('\n5. Checking Honest Enquiry Form Implementation:');
assert(html.includes('enquiryFeedback'), 'On-page enquiry feedback container present');
assert(html.includes('copyEnquiryBtn'), 'Copy enquiry text button present');
assert(js.includes('mailto:info@gbafurniture.com'), 'Script generates mailto: to info@gbafurniture.com');
assert(!js.includes('Enquiry Reference: GBA-'), 'No fake server enquiry reference codes generated');
assert(!html.includes('Enquiry Reference: GBA-'), 'No fake server reference in HTML');

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

// 7. Local HTTP Server Delivery Test
console.log('\n7. Checking Local HTTP Server Delivery:');
const server = http.createServer((req, res) => {
  const urlPath = req.url.split('?')[0];
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

  const endpointsToTest = [
    { path: '/', status: 200, type: 'text/html' },
    { path: '/styles.css', status: 200, type: 'text/css' },
    { path: '/script.js', status: 200, type: 'application/javascript' },
    { path: '/data/products.json', status: 200, type: 'application/json' },
    { path: '/assets/gba-logo-official-transparent.png', status: 200, type: 'image/png' },
    { path: '/assets/current-banner.jpg', status: 200, type: 'image/jpeg' },
    { path: '/assets/placeholders/bed-divan.svg', status: 200, type: 'image/svg+xml' }
  ];

  let completedRequests = 0;

  endpointsToTest.forEach(ep => {
    http.get(`http://127.0.0.1:${port}${ep.path}`, (res) => {
      assert(res.statusCode === ep.status, `HTTP GET ${ep.path} responded with ${res.statusCode}`);
      const ct = res.headers['content-type'] || '';
      assert(ct.includes(ep.type), `HTTP GET ${ep.path} returned content-type containing '${ep.type}'`);

      res.on('data', () => {});
      res.on('end', () => {
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
