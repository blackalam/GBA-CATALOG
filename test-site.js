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
assert(html.includes('info@gbafurniture.com'), 'Email info@gbafurniture.com present');
assert(html.includes('401 Lordship Lane, London, N17 6AE'), 'Address 401 Lordship Lane, London, N17 6AE present');
assert(html.includes('9:00am – 8:00pm') || html.includes('9:00am - 8:00pm'), 'Hours Monday–Sunday 9:00am–8:00pm present');

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
    { path: '/assets/gba-logo-web.png', status: 200, type: 'image/png' },
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
