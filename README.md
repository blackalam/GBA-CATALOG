# GBA Furniture — Public Catalogue Redesign Prototype

A responsive, editorial furniture catalogue prototype created for **GBA Furniture**, preserving existing branding while introducing a refined showroom aesthetic and a seamless category-browsing and ordering enquiry flow.

---

## 1. Project Overview & Intent

- **Brand Preservation:** Built around the authentic GBA Furniture identity (`#014660` Deep Petrol and `#046700` Forest Green), elevated with warm ivory (`#FAF8F5`), walnut accents (`#3E2D22`), restrained brass (`#C29B38`), and charcoal (`#181B1E`).
- **Catalogue & Pricing Source:** Sourced from `reference/product-price-list.pdf`. Obvious extraction typos were safely corrected (e.g. "draw" → drawer, "Applicances" → Appliances, "Colarado" → Colorado), but no specifications, materials, or features were invented.
- **Structural Reference:** Customer flow inspired by trade/landlord furniture supplier `whitefern.co.uk` (browse by room category, direct enquire/order action), with bespoke GBA branding, styling, and code.
- **Truthful Customer Flow:** No basket, account login, checkout, or online payments. Every "Enquire / Order" action carries the selected product and variant directly into the contact section, smoothly scrolling and focusing the enquiry field.
- **Public Contact Details:**
  - **Telephone & WhatsApp:** 020 8888 0322 (Call or WhatsApp: `https://wa.me/442088880322`)
  - **Email:** info@gbafurniture.com
  - **Showroom Address:** 401 Lordship Lane, London, N17 6AE
  - **Opening Hours:**
    - Monday to Friday: 9:30am–6:00pm
    - Saturday: 9:30am–5:00pm
    - Sunday: Closed
  - **Social Channels:**
    - Instagram: [@gba_furniture](https://www.instagram.com/gba_furniture/)
    - TikTok: [@gbafurniture](https://www.tiktok.com/@gbafurniture)

---

## 2. Architecture & File Structure

The project is a self-contained static site suitable for standard web hosting:

```
gba-furniture-website/
├── index.html                      # Semantic, accessible HTML5 structure
├── styles.css                      # Custom responsive CSS with custom properties & reduced-motion support
├── script.js                       # Vanilla JS catalogue rendering, variant switching, enquiry prefill & mailto
├── serve.js                        # Zero-dependency local development server (Node.js)
├── test-site.js                    # Automated verification test suite (127 checks)
├── generate-placeholders.js        # Generator script for vector SVG placeholders
├── data/
│   └── products.json               # Structured catalogue data sourced from reference price list
├── assets/
│   ├── gba-logo-official-transparent.png # Official transparent production brand logo (header, mobile drawer, footer)
│   ├── gba-logo-web.png            # Legacy web-optimized brand logo (retained for package compatibility)
│   ├── gba-logo.png                # Original high-resolution master logo
│   ├── current-banner.jpg          # Temporary showroom hero image
│   └── placeholders/               # 10 bespoke architectural line-art SVGs for product cards
└── reference/
    └── product-price-list.pdf      # Source price list document
```

---

## 3. Product Categories

The catalogue is organised into 7 categories matching the supplied price sheet:

1. **Beds & Mattresses** (`beds-mattresses`): Oxford, Silk Ortho, and Foam divan bed sets and mattress-only options (3ft, 4ft/4ft6, 5ft) with drawer and headboard options.
2. **Bedroom Storage** (`bedroom-storage`): 2-door & 3-door wardrobes (with optional drawers and mirrors), chests of drawers, and bedside units across Budget and AB ranges.
3. **Bed Frames & Bunk Beds** (`bed-frames-bunks`): Chester metal bed, Jersey metal bed, Colorado wooden bed, PVC/fabric storage bed, plus metal and wooden bunk beds (Single/Single and Trio Sleeper).
4. **Dining Sets & Tables** (`dining`): 2, 4, and 6-seater sets, individual tables (small, medium, large), and individual dining chairs across Budget and Wooden ranges.
5. **Sofas & Living Room** (`sofas-living`): Box sofa suite, Dylan sofa suite, Turkish sofa bed, ClickClac sofa bed, and coffee table.
6. **Appliances** (`appliances`): Full-height fridge/freezer, under-counter fridge/freezer, and washing machine.
7. **Removal Services** (`removals`): Item-specific removal charges (chest of drawers, single/double divan bed, 1-piece sofa, wardrobe) listed on the price sheet.

---

## 4. Local Serving Instructions

### Option A: Using the Included Node Server (Recommended)
```bash
node serve.js
```
Then navigate to:
```
http://127.0.0.1:3000/
```

### Option B: Using Python 3
```bash
python3 -m http.server 3000
```
Then open `http://localhost:3000/`.

### Option C: Direct File Opening
You can also open `index.html` directly in any modern browser:
```bash
open index.html
```
*(All data is bundled directly in `script.js` with zero dependencies, ensuring seamless operation even over `file:///` URLs).*

---

## 5. Running Automated Verification Checks

Run the automated test suite with Node.js:
```bash
node test-site.js
```
The test suite verifies:
- File existence and MIME delivery (including `assets/gba-logo-official-transparent.png`) over an ephemeral local HTTP server.
- All 7 categories and 26 catalogue products with numeric GBP (£) pricing.
- Complete absence of unsupported claims (no invented materials, dispatch guarantees, or unverified claims).
- Confirmed showroom opening hours (`Mon–Fri: 9:30am–6:00pm`, `Sat: 9:30am–5:00pm`, `Sun: Closed`), telephone & WhatsApp (`https://wa.me/442088880322`), Instagram (`@gba_furniture`), TikTok (`@gbafurniture`), and official transparent PNG logo (`assets/gba-logo-official-transparent.png`) usage across header, mobile drawer, and footer with zero legacy JPEG references.
- Semantic HTML landmarks, accessible skip links, and modal attributes.
- Honest client-side enquiry flow (prefills `mailto:` email, does not claim fake server logging).

---

## 6. Pre-Production Checklist (Status & Remaining Steps)

**Confirmed & Integrated in Current Release Candidate:**
- **Official Transparent Brand Logo:** `assets/gba-logo-official-transparent.png` integrated across desktop header, mobile navigation drawer, and footer (and added to all packaging/deployment allowlists).
- **Confirmed Showroom Opening Hours:** Monday to Friday `9:30am–6:00pm`, Saturday `9:30am–5:00pm`, Sunday `Closed`.
- **Direct WhatsApp & Social Channels:** Direct WhatsApp enquiry links (`https://wa.me/442088880322`), Instagram (`https://www.instagram.com/gba_furniture/`), and TikTok (`https://www.tiktok.com/@gbafurniture`) verified with safe external link attributes.

**Remaining Tasks Before / During Production Launch:**
1. **Real Product Photography:** Replace the temporary vector SVG placeholders with high-resolution photography of actual store inventory (product photography has not yet been supplied).
2. **Final Product & Price Verification:** Review all 26 product lines and 81 variants with GBA Furniture showroom management to ensure prices and specifications match current stock.
3. **Delivery & Removal Policy Confirmation:** Confirm delivery radius, charges, and removal conditions with showroom management before publishing.
4. **Official Policy Text:** Formalise customer returns, delivery terms, and privacy documentation with management to replace prototype notes.
5. **Production Hosting Deployment:** Execute the production deployment workflow to publish the static release package (`index.html`, `styles.css`, `script.js`, `data/`, `assets/`) to the production web server (deployment has not yet been executed).
