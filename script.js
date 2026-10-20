/**
 * GBA Furniture — Public Catalogue Redesign
 * Core JavaScript: Product catalog rendering, live variant switching,
 * smooth enquiry population & scrolling, accessible mobile drawer & modals.
 * Strictly source-grounded: no invented specifications, claims, or fake backend submissions.
 */

(function () {
  'use strict';

  // --- Embedded Catalogue Data (Matching data/products.json) ---
  const CATALOGUE_DATA = {
    categories: [
      { id: "all", name: "All Collections", shortName: "All" },
      { id: "beds-mattresses", name: "Beds & Mattresses", shortName: "Beds" },
      { id: "bedroom-storage", name: "Bedroom Storage", shortName: "Storage" },
      { id: "bed-frames-bunks", name: "Bed Frames & Bunks", shortName: "Frames & Bunks" },
      { id: "dining", name: "Dining Sets & Tables", shortName: "Dining" },
      { id: "sofas-living", name: "Sofas & Living Room", shortName: "Sofas & Living" },
      { id: "appliances", name: "Appliances", shortName: "Appliances" },
      { id: "removals", name: "Removal Services", shortName: "Removals" }
    ],
    products: [
      {
        id: "oxford-divan-bed",
        name: "Oxford Divan Bed",
        category: "beds-mattresses",
        collection: "Divan Beds",
        description: "Oxford divan bed available as a full set (base and mattress) or mattress only, based on supplied store price list. Contact store to confirm specifications and availability.",
        startingPrice: 95,
        placeholder: "assets/placeholders/bed-divan.svg",
        variants: [
          { id: "oxford-set-3ft", label: "3ft Single — Set (Base & Mattress)", price: 130 },
          { id: "oxford-set-4ft", label: "4ft / 4ft6 Double — Set (Base & Mattress)", price: 170 },
          { id: "oxford-set-5ft", label: "5ft King — Set (Base & Mattress)", price: 200 },
          { id: "oxford-matt-3ft", label: "3ft Single — Matt Only", price: 95 },
          { id: "oxford-matt-4ft", label: "4ft / 4ft6 Double — Matt Only", price: 125 },
          { id: "oxford-matt-5ft", label: "5ft King — Matt Only", price: 155 }
        ],
        addons: [
          { name: "Drawer Add-on", price: 35, unit: "per drawer" },
          { name: "Headboard (3ft Single)", price: 25, unit: "each" },
          { name: "Headboard (4ft / 4ft6 Double)", price: 35, unit: "each" },
          { name: "Headboard (5ft King)", price: 45, unit: "each" }
        ],
        specNotes: "Prices from supplied store price list. Contact store to confirm current stock and details."
      },
      {
        id: "silk-ortho-divan-bed",
        name: "Silk Ortho Divan Bed",
        category: "beds-mattresses",
        collection: "Divan Beds",
        description: "Silk Ortho divan bed available as a full set (base and mattress) or mattress only, based on supplied store price list. Contact store to confirm specifications and availability.",
        startingPrice: 120,
        placeholder: "assets/placeholders/bed-divan.svg",
        variants: [
          { id: "silk-set-3ft", label: "3ft Single — Set (Base & Mattress)", price: 155 },
          { id: "silk-set-4ft", label: "4ft / 4ft6 Double — Set (Base & Mattress)", price: 200 },
          { id: "silk-set-5ft", label: "5ft King — Set (Base & Mattress)", price: 240 },
          { id: "silk-matt-3ft", label: "3ft Single — Matt Only", price: 120 },
          { id: "silk-matt-4ft", label: "4ft / 4ft6 Double — Matt Only", price: 150 },
          { id: "silk-matt-5ft", label: "5ft King — Matt Only", price: 195 }
        ],
        addons: [
          { name: "Drawer Add-on", price: 35, unit: "per drawer" },
          { name: "Headboard (3ft Single)", price: 25, unit: "each" },
          { name: "Headboard (4ft / 4ft6 Double)", price: 35, unit: "each" },
          { name: "Headboard (5ft King)", price: 45, unit: "each" }
        ],
        specNotes: "Prices from supplied store price list. Contact store to confirm current stock and details."
      },
      {
        id: "foam-divan-bed",
        name: "Foam Divan Bed",
        category: "beds-mattresses",
        collection: "Divan Beds",
        description: "Foam divan bed available as a full set (base and mattress) or mattress only, based on supplied store price list. Contact store to confirm specifications and availability.",
        startingPrice: 120,
        placeholder: "assets/placeholders/bed-divan.svg",
        variants: [
          { id: "foam-set-3ft", label: "3ft Single — Set (Base & Mattress)", price: 155 },
          { id: "foam-set-4ft", label: "4ft / 4ft6 Double — Set (Base & Mattress)", price: 200 },
          { id: "foam-set-5ft", label: "5ft King — Set (Base & Mattress)", price: 240 },
          { id: "foam-matt-3ft", label: "3ft Single — Matt Only", price: 120 },
          { id: "foam-matt-4ft", label: "4ft / 4ft6 Double — Matt Only", price: 150 },
          { id: "foam-matt-5ft", label: "5ft King — Matt Only", price: 195 }
        ],
        addons: [
          { name: "Drawer Add-on", price: 35, unit: "per drawer" },
          { name: "Headboard (3ft Single)", price: 25, unit: "each" },
          { name: "Headboard (4ft / 4ft6 Double)", price: 35, unit: "each" },
          { name: "Headboard (5ft King)", price: 45, unit: "each" }
        ],
        specNotes: "Prices from supplied store price list. Contact store to confirm current stock and details."
      },
      {
        id: "budget-wardrobe-2door",
        name: "Budget 2 Door Wardrobe",
        category: "bedroom-storage",
        collection: "Budget Range",
        description: "Two-door wardrobe from the budget bedroom storage list. Available in standard 2-door or 2-door 2-drawer configuration.",
        startingPrice: 95,
        placeholder: "assets/placeholders/wardrobe.svg",
        variants: [
          { id: "budget-2door-plain", label: "2 Door Wardrobe", price: 95 },
          { id: "budget-2door-2draw", label: "2 Door 2 Drawer Wardrobe", price: 120 }
        ],
        addons: [
          { name: "Mirror on Wardrobe", price: 20, unit: "optional" }
        ],
        specNotes: "Price list note: 'Color can vary' (colours may vary by batch; confirm with store)."
      },
      {
        id: "budget-wardrobe-3door",
        name: "Budget 3 Door Wardrobe",
        category: "bedroom-storage",
        collection: "Budget Range",
        description: "Three-door wardrobe from the budget bedroom storage list. Available in standard 3-door or 3-door 2-drawer configuration.",
        startingPrice: 170,
        placeholder: "assets/placeholders/wardrobe.svg",
        variants: [
          { id: "budget-3door-plain", label: "3 Door Wardrobe", price: 170 },
          { id: "budget-3door-2draw", label: "3 Door 2 Drawer Wardrobe", price: 195 }
        ],
        addons: [
          { name: "Mirror on Wardrobe", price: 20, unit: "optional" }
        ],
        specNotes: "Price list note: 'Color can vary' (colours may vary by batch; confirm with store)."
      },
      {
        id: "budget-chests-bedside",
        name: "Budget Chest & Bedside",
        category: "bedroom-storage",
        collection: "Budget Range",
        description: "Drawer storage items from the budget bedroom storage list.",
        startingPrice: 40,
        placeholder: "assets/placeholders/chest.svg",
        variants: [
          { id: "budget-bedside-3draw", label: "3 Drawer Bedside", price: 40 },
          { id: "budget-chest-4draw", label: "4 Chest Drawer (4-Drawer Chest)", price: 70 }
        ],
        addons: [],
        specNotes: "Price list note: 'Color can vary' (colours may vary by batch; confirm with store)."
      },
      {
        id: "ab-wardrobe-2door",
        name: "AB Range 2 Door Wardrobe",
        category: "bedroom-storage",
        collection: "AB Range",
        description: "Two-door wardrobe from the AB storage range. Available in standard 2-door or 2-door 2-drawer configuration.",
        startingPrice: 150,
        placeholder: "assets/placeholders/wardrobe.svg",
        variants: [
          { id: "ab-2door-plain", label: "2 Door Wardrobe", price: 150 },
          { id: "ab-2door-2draw", label: "2 Door 2 Drawer Wardrobe", price: 180 }
        ],
        addons: [
          { name: "Mirror on Wardrobe", price: 35, unit: "optional" }
        ],
        specNotes: "Finishes listed on price sheet: White, Oak, Grey, Walnut, Black (confirm availability with store)."
      },
      {
        id: "ab-wardrobe-3door",
        name: "AB Range 3 Door Wardrobe",
        category: "bedroom-storage",
        collection: "AB Range",
        description: "Three-door wardrobe from the AB storage range. Available in standard 3-door or 3-door 2-drawer configuration.",
        startingPrice: 250,
        placeholder: "assets/placeholders/wardrobe.svg",
        variants: [
          { id: "ab-3door-plain", label: "3 Door Wardrobe", price: 250 },
          { id: "ab-3door-2draw", label: "3 Door 2 Drawer Wardrobe", price: 280 }
        ],
        addons: [
          { name: "Mirror on Wardrobe", price: 35, unit: "optional" }
        ],
        specNotes: "Finishes listed on price sheet: White, Oak, Grey, Walnut, Black (confirm availability with store)."
      },
      {
        id: "ab-chests-bedside",
        name: "AB Range Chests & Bedside",
        category: "bedroom-storage",
        collection: "AB Range",
        description: "Chests of drawers and bedside units from the AB storage range.",
        startingPrice: 55,
        placeholder: "assets/placeholders/chest.svg",
        variants: [
          { id: "ab-bedside-3draw", label: "3 Drawer Bedside", price: 55 },
          { id: "ab-chest-4draw", label: "4 Chest Drawer (4-Drawer Chest)", price: 120 },
          { id: "ab-chest-5draw", label: "5 Chest Drawer (5-Drawer Chest)", price: 140 }
        ],
        addons: [],
        specNotes: "Finishes listed on price sheet: White, Oak, Grey, Walnut, Black (confirm availability with store)."
      },
      {
        id: "chester-metal-bed",
        name: "Chester Metal Bed",
        category: "bed-frames-bunks",
        collection: "Bed Frames",
        description: "Chester metal bed frame listed on store price sheet. Available in 3ft and 4ft/4ft6 sizes.",
        startingPrice: 110,
        placeholder: "assets/placeholders/bed-frame.svg",
        variants: [
          { id: "chester-3ft", label: "3ft Single Frame", price: 110 },
          { id: "chester-4ft", label: "4ft / 4ft6 Double Frame", price: 130 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm dimensions and details."
      },
      {
        id: "jersey-metal-bed",
        name: "Jersey Metal Bed",
        category: "bed-frames-bunks",
        collection: "Bed Frames",
        description: "Jersey metal bed frame listed on store price sheet. Available in 3ft, 4ft/4ft6, and 5ft sizes.",
        startingPrice: 180,
        placeholder: "assets/placeholders/bed-frame.svg",
        variants: [
          { id: "jersey-3ft", label: "3ft Single Frame", price: 180 },
          { id: "jersey-4ft", label: "4ft / 4ft6 Double Frame", price: 200 },
          { id: "jersey-5ft", label: "5ft King Frame", price: 220 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm dimensions and details."
      },
      {
        id: "colorado-wooden-bed",
        name: "Colorado Wooden Bed",
        category: "bed-frames-bunks",
        collection: "Bed Frames",
        description: "Wooden bed frame listed on store price sheet (listed as Colarado Wooden Bed). Available in 3ft, 4ft/4ft6, and 5ft sizes.",
        startingPrice: 150,
        placeholder: "assets/placeholders/bed-frame.svg",
        variants: [
          { id: "colorado-3ft", label: "3ft Single Frame", price: 150 },
          { id: "colorado-4ft", label: "4ft / 4ft6 Double Frame", price: 180 },
          { id: "colorado-5ft", label: "5ft King Frame", price: 200 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm dimensions and details."
      },
      {
        id: "storage-bed-frame",
        name: "PVC / Fabric Storage Bed",
        category: "bed-frames-bunks",
        collection: "Bed Frames",
        description: "Storage bed listed as 'pvc/fabric storage' on store price sheet. Available in 3ft, 4ft/4ft6, and 5ft sizes.",
        startingPrice: 240,
        placeholder: "assets/placeholders/bed-frame.svg",
        variants: [
          { id: "storage-3ft", label: "3ft Single Storage Bed", price: 240 },
          { id: "storage-4ft", label: "4ft / 4ft6 Double Storage Bed", price: 270 },
          { id: "storage-5ft", label: "5ft King Storage Bed", price: 290 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm covering options (PVC/fabric) and dimensions."
      },
      {
        id: "metal-bunk-bed",
        name: "Metal Bunk Bed",
        category: "bed-frames-bunks",
        collection: "Bunk Bed",
        description: "Metal bunk bed listed on store price sheet. Available in Single / Single and Trio Sleeper options.",
        startingPrice: 250,
        placeholder: "assets/placeholders/bunk.svg",
        variants: [
          { id: "metal-bunk-single", label: "Single / Single", price: 250 },
          { id: "metal-bunk-trio", label: "Trio Sleeper", price: 290 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm dimensions and specifications."
      },
      {
        id: "wooden-bunk-bed",
        name: "Wooden Bunk Bed",
        category: "bed-frames-bunks",
        collection: "Bunk Bed",
        description: "Wooden bunk bed listed on store price sheet. Available in Single / Single and Trio Sleeper options.",
        startingPrice: 320,
        placeholder: "assets/placeholders/bunk.svg",
        variants: [
          { id: "wooden-bunk-single", label: "Single / Single", price: 320 },
          { id: "wooden-bunk-trio", label: "Trio Sleeper", price: 390 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm dimensions and specifications."
      },
      {
        id: "budget-dining-range",
        name: "Budget Dining Range",
        category: "dining",
        collection: "Dining Set",
        description: "Dining sets and individual tables and chairs from the Budget Range section of the price list.",
        startingPrice: 30,
        placeholder: "assets/placeholders/dining-table.svg",
        variants: [
          { id: "budget-dining-chair", label: "Dining Chair (Individual)", price: 30 },
          { id: "budget-dining-tbl-sm", label: "Dining Table Small", price: 80 },
          { id: "budget-dining-tbl-md", label: "Dining Table Medium", price: 105 },
          { id: "budget-dining-tbl-lg", label: "Dining Table Large", price: 140 },
          { id: "budget-dining-set-2", label: "Dining Set of 2", price: 150 },
          { id: "budget-dining-set-4", label: "Dining Set of 4", price: 190 },
          { id: "budget-dining-set-6", label: "Dining Set of 6", price: 240 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm dimensions and details."
      },
      {
        id: "wooden-dining-range",
        name: "Wooden Dining Range",
        category: "dining",
        collection: "Dining Set",
        description: "Dining sets and individual tables and chairs from the Wooden Range section of the price list.",
        startingPrice: 50,
        placeholder: "assets/placeholders/dining-table.svg",
        variants: [
          { id: "wood-dining-chair", label: "Dining Chair (Individual)", price: 50 },
          { id: "wood-dining-tbl-sm", label: "Dining Table Small", price: 120 },
          { id: "wood-dining-tbl-md", label: "Dining Table Medium", price: 150 },
          { id: "wood-dining-tbl-lg", label: "Dining Table Large", price: 190 },
          { id: "wood-dining-set-2", label: "Dining Set of 2", price: 180 },
          { id: "wood-dining-set-4", label: "Dining Set of 4", price: 250 },
          { id: "wood-dining-set-6", label: "Dining Set of 6", price: 360 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm dimensions and details."
      },
      {
        id: "box-sofa-suite",
        name: "Box Sofa",
        category: "sofas-living",
        collection: "Living Room Sofa",
        description: "Box sofa options listed on store price sheet. Available in 1 Seater, 2 Seater, 3 Seater, and 3+2 Seater options.",
        startingPrice: 170,
        placeholder: "assets/placeholders/sofa.svg",
        variants: [
          { id: "box-sofa-1s", label: "1 Seater", price: 170 },
          { id: "box-sofa-2s", label: "2 Seater", price: 220 },
          { id: "box-sofa-3s", label: "3 Seater", price: 270 },
          { id: "box-sofa-combo", label: "3+2 Seater", price: 420 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm available colours and dimensions."
      },
      {
        id: "dylan-sofa-suite",
        name: "Dylan Sofa Suite",
        category: "sofas-living",
        collection: "Living Room Sofa",
        description: "Dylan sofa suite options listed on store price sheet. Available in 2 Seater, 3 Seater, and 3+2 Seater options.",
        startingPrice: 240,
        placeholder: "assets/placeholders/sofa.svg",
        variants: [
          { id: "dylan-sofa-2s", label: "2 Seater", price: 240 },
          { id: "dylan-sofa-3s", label: "3 Seater", price: 290 },
          { id: "dylan-sofa-combo", label: "3+2 Seater", price: 480 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm available colours and dimensions."
      },
      {
        id: "turkish-sofa-bed",
        name: "Turkish Sofa Bed",
        category: "sofas-living",
        collection: "Living Room Sofa",
        description: "Turkish sofa bed options listed on store price sheet. Available in 2 Seater, 3 Seater, and 3+2 Seater options.",
        startingPrice: 320,
        placeholder: "assets/placeholders/sofa.svg",
        variants: [
          { id: "turkish-sb-2s", label: "2 Seater", price: 320 },
          { id: "turkish-sb-3s", label: "3 Seater", price: 350 },
          { id: "turkish-sb-combo", label: "3+2 Seater", price: 650 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm available colours and dimensions."
      },
      {
        id: "click-clack-sofa-bed",
        name: "ClickClac Sofa Bed",
        category: "sofas-living",
        collection: "Living Room Sofa",
        description: "Sofa bed listed as 'ClickClac Sofa Bed' on store price sheet. Available in 2 Seater and 3 Seater options.",
        startingPrice: 170,
        placeholder: "assets/placeholders/sofa.svg",
        variants: [
          { id: "clickclack-2s", label: "2 Seater", price: 170 },
          { id: "clickclack-3s", label: "3 Seater", price: 190 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm available colours and dimensions."
      },
      {
        id: "living-coffee-table",
        name: "Coffee Table",
        category: "sofas-living",
        collection: "Living Room Other",
        description: "Coffee table listed under 'Living Room Other' on store price sheet.",
        startingPrice: 40,
        placeholder: "assets/placeholders/coffee-table.svg",
        variants: [
          { id: "coffee-table-std", label: "Coffee Table", price: 40 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm finish and dimensions."
      },
      {
        id: "fridge-freezer-tall",
        name: "Fridge/Freezer",
        category: "appliances",
        collection: "Appliances",
        description: "Fridge/Freezer listed under 'Applicances' on store price sheet.",
        startingPrice: 420,
        placeholder: "assets/placeholders/appliance.svg",
        variants: [
          { id: "app-fridge-freezer", label: "Fridge/Freezer", price: 420 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm dimensions, brand and model details."
      },
      {
        id: "fridge-freezer-undercounter",
        name: "Under Counter Fridge/Freezer",
        category: "appliances",
        collection: "Appliances",
        description: "Under counter fridge/freezer unit listed under 'Applicances' on store price sheet.",
        startingPrice: 290,
        placeholder: "assets/placeholders/appliance.svg",
        variants: [
          { id: "app-undercounter", label: "Under Counter Fridge/Freezer", price: 290 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm dimensions, brand and model details."
      },
      {
        id: "washing-machine",
        name: "Washing Machine",
        category: "appliances",
        collection: "Appliances",
        description: "Washing machine unit listed under 'Applicances' on store price sheet.",
        startingPrice: 360,
        placeholder: "assets/placeholders/appliance.svg",
        variants: [
          { id: "app-washer", label: "Washing Machine", price: 360 }
        ],
        addons: [],
        specNotes: "Prices from supplied store price list. Contact store to confirm brand, load capacity and model details."
      },
      {
        id: "furniture-removal-service",
        name: "Removal Charges",
        category: "removals",
        collection: "Removal Charges",
        description: "Item removal charges listed on the supplied store price sheet.",
        startingPrice: 20,
        placeholder: "assets/placeholders/van.svg",
        variants: [
          { id: "rem-chest", label: "Chest of Drawers", price: 20 },
          { id: "rem-bed-single", label: "Any Bed (Single) (Divan Only)", price: 25 },
          { id: "rem-bed-double", label: "Any Bed (Double) (Divan Only)", price: 30 },
          { id: "rem-sofa", label: "Any Sofa (1 piece)", price: 30 },
          { id: "rem-wardrobe", label: "Wardrobe", price: 30 }
        ],
        addons: [],
        specNotes: "Charges from supplied price sheet. Bed removal note: '(Divan Only)'. Contact store to confirm removal arrangements and conditions."
      }
    ]
  };

  // --- State Variables ---
  let currentCategory = 'all';
  let searchQuery = '';
  let selectedProductItem = null;

  // --- DOM References ---
  const header = document.querySelector('.site-header');
  const productGrid = document.getElementById('productGrid');
  const filterPillsContainer = document.getElementById('filterPills');
  const searchInput = document.getElementById('catalogueSearch');
  const activeFilterLabel = document.getElementById('activeFilterLabel');
  const productCountLabel = document.getElementById('productCountLabel');
  const categoryTiles = document.querySelectorAll('.category-tile');

  // Contact / Enquiry Elements
  const contactSection = document.getElementById('contact');
  const selectedBanner = document.getElementById('selectedProductBanner');
  const selectedNameElem = document.getElementById('selectedProductName');
  const selectedPriceElem = document.getElementById('selectedProductPrice');
  const clearSelectionBtn = document.getElementById('clearProductSelection');
  const formProductSelect = document.getElementById('enquiryProductSelect');
  const enquiryForm = document.getElementById('enquiryForm');
  const enquiryMessage = document.getElementById('enquiryMessage');
  const enquiryFeedback = document.getElementById('enquiryFeedback');
  const feedbackSummaryText = document.getElementById('feedbackSummaryText');
  const copyEnquiryBtn = document.getElementById('copyEnquiryBtn');
  const reOpenEmailBtn = document.getElementById('reOpenEmailBtn');

  // Mobile Navigation Elements
  const mobileNavToggle = document.getElementById('mobileNavToggle');
  const mobileDrawer = document.getElementById('mobileDrawer');
  const mobileBackdrop = document.getElementById('mobileDrawerBackdrop');
  const mobileDrawerClose = document.getElementById('mobileDrawerClose');
  const mobileNavLinks = document.querySelectorAll('.mobile-nav-item');

  // Policy Modal Elements
  const policyModal = document.getElementById('policyModal');
  const policyModalBackdrop = document.getElementById('policyModalBackdrop');
  const policyModalClose = document.getElementById('policyModalClose');
  const policyModalTitle = document.getElementById('policyModalTitle');
  const policyModalBody = document.getElementById('policyModalBody');
  const policyTriggers = document.querySelectorAll('[data-policy-trigger]');

  // --- Grounded Policy / Store Notes Registry ---
  const POLICIES = {
    ordering: {
      title: "How Ordering Works",
      content: `
        <p><strong>Direct In-Store & Telephone Orders:</strong> GBA Furniture is a physical showroom. There is no automated online shopping basket, user account, or card payment on this website.</p>
        <p><strong>Confirmation Process:</strong></p>
        <ol style="padding-left: 1.25rem; display: flex; flex-direction: column; gap: 0.5rem;">
          <li>Browse products and variants from the supplied price list.</li>
          <li>Click "Enquire / Order" to draft an enquiry email or telephone 020 8888 0322.</li>
          <li>Staff at the store will confirm current stock, finishes, delivery availability, any applicable charges, and final prices.</li>
        </ol>
        <p><em>Store Address: 401 Lordship Lane, London, N17 6AE. Open Monday–Friday 9:30am–6:00pm, Saturday 9:30am–5:00pm, Sunday Closed.</em></p>
      `
    },
    delivery: {
      title: "Delivery Arrangements (Placeholder)",
      content: `
        <p><strong>Store Delivery Terms:</strong> Delivery availability, schedules, and costs are confirmed directly with the store.</p>
        <p>Please contact staff at 401 Lordship Lane, London, N17 6AE or call 020 8888 0322 to check delivery options for your area before ordering.</p>
        <p><em>This catalogue does not establish guaranteed delivery zones, assembly services, or free delivery thresholds.</em></p>
      `
    },
    removals: {
      title: "Removal Charges Information",
      content: `
        <p><strong>Price Sheet Charges:</strong> The supplied price list quotes the following item charges for removals:</p>
        <ul style="padding-left: 1.25rem; display: flex; flex-direction: column; gap: 0.4rem;">
          <li>Chest of Drawers: £20</li>
          <li>Any Bed (Divan Only, Single): £25</li>
          <li>Any Bed (Divan Only, Double): £30</li>
          <li>Any Sofa (1 piece): £30</li>
          <li>Wardrobe: £30</li>
        </ul>
        <p><strong>Important Note:</strong> The price list notes that bed removal applies to divans only. Timing, feasibility, and specific collection arrangements must be confirmed directly with the store.</p>
      `
    },
    privacy: {
      title: "Privacy & Data Notice",
      content: `
        <p>This website does not store or process your personal details on a backend server.</p>
        <p>When you click submit on the enquiry form, your default email client opens a pre-composed message to <strong>info@gbafurniture.com</strong>. You retain full control over sending the message.</p>
        <p>For official privacy policy information on the live site, visit <a href="https://gbafurniture.com/privacy-policy/" target="_blank" rel="noopener noreferrer">gbafurniture.com/privacy-policy/</a>.</p>
      `
    }
  };

  // ==========================================================================
  // INITIALIZATION
  // ==========================================================================
  function init() {
    renderFilterPills();
    populateFormProductSelect();
    renderProducts();
    bindEvents();
    checkUrlHash();
  }

  // ==========================================================================
  // FILTER PILLS RENDERING
  // ==========================================================================
  function renderFilterPills() {
    if (!filterPillsContainer) return;
    filterPillsContainer.innerHTML = '';

    CATALOGUE_DATA.categories.forEach(cat => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = `filter-pill ${cat.id === currentCategory ? 'is-active' : ''}`;
      button.setAttribute('data-category', cat.id);
      button.textContent = cat.name;
      button.addEventListener('click', () => {
        setCategory(cat.id);
      });
      filterPillsContainer.appendChild(button);
    });
  }

  // ==========================================================================
  // FORM PRODUCT SELECT POPULATION
  // ==========================================================================
  function populateFormProductSelect() {
    if (!formProductSelect) return;
    formProductSelect.innerHTML = '';

    const defaultOpt = document.createElement('option');
    defaultOpt.value = 'general';
    defaultOpt.textContent = 'General Enquiry / Multiple Items';
    formProductSelect.appendChild(defaultOpt);

    CATALOGUE_DATA.categories.filter(c => c.id !== 'all').forEach(cat => {
      const group = document.createElement('optgroup');
      group.label = cat.name;

      const catProducts = CATALOGUE_DATA.products.filter(p => p.category === cat.id);
      catProducts.forEach(prod => {
        const opt = document.createElement('option');
        opt.value = prod.id;
        opt.textContent = `${prod.name} (from £${prod.startingPrice})`;
        group.appendChild(opt);
      });

      formProductSelect.appendChild(group);
    });
  }

  // ==========================================================================
  // CATALOGUE RENDERING WITH LIVE VARIANTS
  // ==========================================================================
  function renderProducts() {
    if (!productGrid) return;

    let filtered = CATALOGUE_DATA.products.filter(p => {
      if (currentCategory === 'all') return true;
      return p.category === currentCategory;
    });

    if (searchQuery.trim() !== '') {
      const q = searchQuery.toLowerCase().trim();
      filtered = filtered.filter(p => {
        const inName = p.name.toLowerCase().includes(q);
        const inDesc = p.description.toLowerCase().includes(q);
        const inCollection = p.collection.toLowerCase().includes(q);
        const inNotes = (p.specNotes || '').toLowerCase().includes(q);
        const inVariants = p.variants.some(v => v.label.toLowerCase().includes(q));
        return inName || inDesc || inCollection || inNotes || inVariants;
      });
    }

    const currentCatObj = CATALOGUE_DATA.categories.find(c => c.id === currentCategory);
    if (activeFilterLabel) {
      activeFilterLabel.textContent = currentCatObj ? currentCatObj.name : 'All Products';
    }
    if (productCountLabel) {
      productCountLabel.textContent = `Showing ${filtered.length} product${filtered.length === 1 ? '' : 's'}`;
    }

    productGrid.innerHTML = '';

    if (filtered.length === 0) {
      const emptyDiv = document.createElement('div');
      emptyDiv.className = 'catalogue-empty-state';
      emptyDiv.innerHTML = `
        <h3>No matching items found</h3>
        <p>No products found matching "<strong>${escapeHtml(searchQuery)}</strong>" in this category.</p>
        <button type="button" class="btn btn-primary" id="resetFiltersBtn">View All Items</button>
      `;
      productGrid.appendChild(emptyDiv);

      const resetBtn = document.getElementById('resetFiltersBtn');
      if (resetBtn) {
        resetBtn.addEventListener('click', () => {
          if (searchInput) searchInput.value = '';
          searchQuery = '';
          setCategory('all');
        });
      }
      return;
    }

    filtered.forEach(product => {
      const card = document.createElement('article');
      card.className = 'product-card';
      card.setAttribute('data-product-id', product.id);

      const defaultVariant = product.variants[0];
      const hasMultipleVariants = product.variants.length > 1;

      let variantSelectHtml = '';
      if (hasMultipleVariants) {
        const options = product.variants.map((v, idx) => `
          <option value="${v.id}" data-price="${v.price}" ${idx === 0 ? 'selected' : ''}>
            ${v.label} — £${v.price}
          </option>
        `).join('');

        variantSelectHtml = `
          <div class="variant-selector-wrapper">
            <label for="variant-${product.id}" class="variant-label">Select Option / Size</label>
            <select id="variant-${product.id}" class="variant-select" data-card-id="${product.id}">
              ${options}
            </select>
          </div>
        `;
      }

      let addonsHtml = '';
      if (product.addons && product.addons.length > 0) {
        const addonItems = product.addons.map(a => `
          <li class="product-addon-item">
            <span>+ ${a.name} (${a.unit || 'optional'})</span>
            <span class="product-addon-price">${typeof a.price === 'number' ? '£' + a.price : a.price}</span>
          </li>
        `).join('');

        addonsHtml = `
          <div class="product-addons-wrapper">
            <div class="product-addons-title">Add-ons Listed on Sheet</div>
            <ul class="product-addons-list">
              ${addonItems}
            </ul>
          </div>
        `;
      }

      card.innerHTML = `
        <div class="product-card-media">
          <img src="${product.placeholder}" alt="${product.name} placeholder illustration" class="product-card-img" loading="lazy">
          <span class="product-card-badge">Price List Item</span>
          <div class="product-price-tag" id="price-tag-${product.id}">
            <span class="product-price-prefix">${hasMultipleVariants ? 'From' : 'Price'}</span>
            <span class="price-val">£${defaultVariant.price}</span>
          </div>
        </div>
        <div class="product-card-body">
          <span class="product-collection-eyebrow">${product.collection}</span>
          <h3 class="product-card-title">${product.name}</h3>
          <p class="product-card-desc">${product.description}</p>

          ${product.specNotes ? `
            <div class="product-spec-strip">
              <strong>Price List Note:</strong> ${product.specNotes}
            </div>
          ` : ''}

          ${variantSelectHtml}
          ${addonsHtml}

          <div class="product-card-actions">
            <button type="button"
                    class="btn btn-primary enquire-action-btn"
                    data-product-id="${product.id}"
                    data-product-name="${escapeHtml(product.name)}"
                    data-variant-id="${defaultVariant.id}"
                    data-variant-label="${escapeHtml(defaultVariant.label)}"
                    data-price="${defaultVariant.price}">
              <svg viewBox="0 0 24 24" fill="currentColor">
                <path d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4l-8 5-8-5V6l8 5 8-5v2z"/>
              </svg>
              <span>Enquire / Order</span>
            </button>
          </div>
        </div>
      `;

      productGrid.appendChild(card);

      if (hasMultipleVariants) {
        const select = card.querySelector('.variant-select');
        const priceTagVal = card.querySelector(`#price-tag-${product.id} .price-val`);
        const pricePrefix = card.querySelector(`#price-tag-${product.id} .product-price-prefix`);
        const actionBtn = card.querySelector('.enquire-action-btn');

        if (select) {
          select.addEventListener('change', () => {
            const selectedOpt = select.options[select.selectedIndex];
            const newPrice = selectedOpt.getAttribute('data-price');
            const newLabel = selectedOpt.text.split(' — ')[0];

            if (priceTagVal) priceTagVal.textContent = `£${newPrice}`;
            if (pricePrefix) pricePrefix.textContent = 'Selected';

            if (actionBtn) {
              actionBtn.setAttribute('data-variant-id', select.value);
              actionBtn.setAttribute('data-variant-label', newLabel);
              actionBtn.setAttribute('data-price', newPrice);
            }
          });
        }
      }
    });

    bindEnquiryButtons();
  }

  // ==========================================================================
  // BIND ENQUIRY BUTTONS
  // ==========================================================================
  function bindEnquiryButtons() {
    const actionBtns = document.querySelectorAll('.enquire-action-btn');
    actionBtns.forEach(btn => {
      btn.addEventListener('click', () => {
        const prodId = btn.getAttribute('data-product-id');
        const prodName = btn.getAttribute('data-product-name');
        const variantLabel = btn.getAttribute('data-variant-label');
        const price = btn.getAttribute('data-price');

        selectProductForEnquiry({
          id: prodId,
          name: prodName,
          variant: variantLabel,
          price: price
        });
      });
    });
  }

  // ==========================================================================
  // ENQUIRY SELECTION & SCROLL
  // ==========================================================================
  function selectProductForEnquiry(item) {
    selectedProductItem = item;

    if (selectedBanner) {
      selectedBanner.style.display = 'flex';
      selectedBanner.classList.add('is-highlighted');
      setTimeout(() => selectedBanner.classList.remove('is-highlighted'), 1600);
    }

    if (selectedNameElem) {
      selectedNameElem.textContent = `${item.name} (${item.variant})`;
    }

    if (selectedPriceElem) {
      selectedPriceElem.textContent = `Listed Price: £${item.price} (subject to store confirmation)`;
    }

    if (formProductSelect) {
      let optionExists = false;
      for (let i = 0; i < formProductSelect.options.length; i++) {
        if (formProductSelect.options[i].value === item.id) {
          formProductSelect.selectedIndex = i;
          optionExists = true;
          break;
        }
      }
      if (!optionExists) {
        const newOpt = document.createElement('option');
        newOpt.value = item.id;
        newOpt.textContent = `${item.name} — £${item.price}`;
        newOpt.selected = true;
        formProductSelect.appendChild(newOpt);
      }
    }

    if (enquiryMessage) {
      enquiryMessage.value = `Hello GBA Furniture,\n\nI am enquiring about the ${item.name} (${item.variant}), listed at £${item.price} on the price sheet.\n\nPlease confirm availability, current colours/finishes, and delivery arrangements to my address.`;
    }

    if (contactSection) {
      const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      contactSection.scrollIntoView({
        behavior: prefersReducedMotion ? 'auto' : 'smooth',
        block: 'start'
      });

      setTimeout(() => {
        if (enquiryMessage) {
          enquiryMessage.focus();
        }
      }, 400);
    }
  }

  function clearProductSelection() {
    selectedProductItem = null;
    if (selectedBanner) {
      selectedBanner.style.display = 'none';
    }
    if (formProductSelect) {
      formProductSelect.value = 'general';
    }
    if (enquiryMessage) {
      enquiryMessage.value = '';
    }
  }

  // ==========================================================================
  // CATEGORY SWITCHING
  // ==========================================================================
  function setCategory(categoryId) {
    currentCategory = categoryId;

    const pills = document.querySelectorAll('.filter-pill');
    pills.forEach(p => {
      p.classList.toggle('is-active', p.getAttribute('data-category') === categoryId);
    });

    renderProducts();

    if (history.replaceState) {
      history.replaceState(null, null, `#category-${categoryId}`);
    }
  }

  function checkUrlHash() {
    const hash = window.location.hash;
    if (hash && hash.startsWith('#category-')) {
      const catId = hash.replace('#category-', '');
      const valid = CATALOGUE_DATA.categories.some(c => c.id === catId);
      if (valid) {
        setCategory(catId);
      }
    }
  }

  // ==========================================================================
  // EVENT BINDINGS
  // ==========================================================================
  function bindEvents() {
    window.addEventListener('scroll', () => {
      if (header) {
        if (window.scrollY > 40) {
          header.classList.add('is-scrolled');
        } else {
          header.classList.remove('is-scrolled');
        }
      }
    }, { passive: true });

    categoryTiles.forEach(tile => {
      tile.addEventListener('click', (e) => {
        e.preventDefault();
        const cat = tile.getAttribute('data-category');
        if (cat) {
          setCategory(cat);
          const catalogueAnchor = document.getElementById('catalogue');
          if (catalogueAnchor) {
            catalogueAnchor.scrollIntoView({ behavior: 'smooth' });
          }
        }
      });
    });

    if (searchInput) {
      searchInput.addEventListener('input', (e) => {
        searchQuery = e.target.value;
        renderProducts();
      });
    }

    if (clearSelectionBtn) {
      clearSelectionBtn.addEventListener('click', clearProductSelection);
    }

    if (mobileNavToggle) {
      mobileNavToggle.addEventListener('click', openMobileDrawer);
    }
    if (mobileDrawerClose) {
      mobileDrawerClose.addEventListener('click', closeMobileDrawer);
    }
    if (mobileBackdrop) {
      mobileBackdrop.addEventListener('click', closeMobileDrawer);
    }
    mobileNavLinks.forEach(link => {
      link.addEventListener('click', () => {
        const cat = link.getAttribute('data-category');
        if (cat) {
          setCategory(cat);
        }
        closeMobileDrawer();
      });
    });

    policyTriggers.forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        const policyKey = btn.getAttribute('data-policy-trigger');
        openPolicyModal(policyKey);
      });
    });

    if (policyModalClose) {
      policyModalClose.addEventListener('click', closePolicyModal);
    }
    if (policyModalBackdrop) {
      policyModalBackdrop.addEventListener('click', closePolicyModal);
    }

    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        closeMobileDrawer();
        closePolicyModal();
      }
    });

    if (enquiryForm) {
      enquiryForm.addEventListener('submit', handleFormSubmit);
    }
  }

  // ==========================================================================
  // MOBILE DRAWER
  // ==========================================================================
  function openMobileDrawer() {
    if (!mobileDrawer || !mobileBackdrop) return;
    mobileDrawer.classList.add('is-open');
    mobileBackdrop.classList.add('is-open');
    if (mobileNavToggle) mobileNavToggle.setAttribute('aria-expanded', 'true');
    document.body.style.overflow = 'hidden';
    if (mobileDrawerClose) mobileDrawerClose.focus();
  }

  function closeMobileDrawer() {
    if (!mobileDrawer || !mobileBackdrop) return;
    mobileDrawer.classList.remove('is-open');
    mobileBackdrop.classList.remove('is-open');
    if (mobileNavToggle) {
      mobileNavToggle.setAttribute('aria-expanded', 'false');
      mobileNavToggle.focus();
    }
    document.body.style.overflow = '';
  }

  // ==========================================================================
  // POLICY MODAL
  // ==========================================================================
  function openPolicyModal(policyKey) {
    const policy = POLICIES[policyKey];
    if (!policy || !policyModal) return;

    if (policyModalTitle) policyModalTitle.textContent = policy.title;
    if (policyModalBody) policyModalBody.innerHTML = policy.content;

    policyModal.classList.add('is-open');
    document.body.style.overflow = 'hidden';
    if (policyModalClose) policyModalClose.focus();
  }

  function closePolicyModal() {
    if (!policyModal) return;
    policyModal.classList.remove('is-open');
    document.body.style.overflow = '';
  }

  // ==========================================================================
  // TRUTHFUL ENQUIRY SUBMISSION: OPENS PREFILLED MAILTO & SHOWS TEXT SUMMARY
  // ==========================================================================
  function handleFormSubmit(e) {
    e.preventDefault();

    const name = document.getElementById('enquiryName')?.value.trim();
    const phone = document.getElementById('enquiryPhone')?.value.trim();
    const email = document.getElementById('enquiryEmail')?.value.trim();
    const addressArea = document.getElementById('enquiryPostcode')?.value.trim();
    const message = document.getElementById('enquiryMessage')?.value.trim();
    const contactMethod = document.querySelector('input[name="pref_contact"]:checked')?.value || 'Telephone Call';

    if (!name || !phone || !email || !message) {
      alert('Please fill in the required fields (Full Name, Phone Number, Email Address, and Message) before preparing your email.');
      return;
    }

    let itemInfo = 'General Enquiry';
    if (selectedProductItem) {
      itemInfo = `${selectedProductItem.name} — ${selectedProductItem.variant} (£${selectedProductItem.price})`;
    } else if (formProductSelect && formProductSelect.value !== 'general') {
      const selectedOption = formProductSelect.options[formProductSelect.selectedIndex];
      itemInfo = selectedOption ? selectedOption.text : 'Catalogue Item';
    }

    // Compose email body
    const emailBody = [
      `Enquiry for GBA Furniture (401 Lordship Lane, London, N17 6AE)`,
      `--------------------------------------------------`,
      `Customer Name: ${name}`,
      `Telephone: ${phone}`,
      `Email: ${email}`,
      `Delivery Area / Postcode: ${addressArea || 'Not specified'}`,
      `Preferred Contact Method: ${contactMethod}`,
      `Item of Interest: ${itemInfo}`,
      ``,
      `Message / Requirements:`,
      message,
      `--------------------------------------------------`,
      `Note: Sourced from GBA Furniture price list. Final details and prices to be confirmed directly with store.`
    ].join('\n');

    const subject = `Catalogue Enquiry: ${itemInfo} - ${name}`;
    const mailtoUrl = `mailto:info@gbafurniture.com?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(emailBody)}`;

    // Show honest feedback section
    if (feedbackSummaryText) {
      feedbackSummaryText.textContent = emailBody;
    }

    if (enquiryFeedback) {
      enquiryFeedback.style.display = 'block';
      enquiryFeedback.scrollIntoView({ behavior: 'smooth' });
    }

    if (copyEnquiryBtn) {
      copyEnquiryBtn.onclick = () => {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(emailBody).then(() => {
            copyEnquiryBtn.textContent = 'Copied to Clipboard!';
            setTimeout(() => {
              copyEnquiryBtn.textContent = 'Copy Enquiry Text';
            }, 2500);
          });
        }
      };
    }

    if (reOpenEmailBtn) {
      reOpenEmailBtn.href = mailtoUrl;
    }

    // Trigger user's email client
    window.location.href = mailtoUrl;
  }

  function escapeHtml(str) {
    if (!str) return '';
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
