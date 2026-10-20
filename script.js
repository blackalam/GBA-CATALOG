/**
 * GBA Furniture — Public Catalogue Redesign
 * Core JavaScript: Product catalog rendering, live variant switching,
 * smooth enquiry population & scrolling, accessible mobile drawer & modals.
 * Strictly source-grounded: no invented specifications, claims, or fake server submissions.
 */

(function () {
  'use strict';

  // --- Embedded Catalogue Data (Matching data/products.json) ---
  const CATALOGUE_DATA = {
    categories: [
      { id: "all", name: "All Items", shortName: "All" },
      {
        id: "beds-mattresses",
        name: "Beds & Mattresses",
        shortName: "Beds",
        tagline: "Divan bed sets and replacement mattresses for rental properties",
        icon: "bed"
      },
      {
        id: "bedroom-storage",
        name: "Bedroom Storage",
        shortName: "Storage",
        tagline: "Wardrobes, chests of drawers and bedside units in the Budget and AB ranges",
        icon: "wardrobe"
      },
      {
        id: "bed-frames-bunks",
        name: "Bed Frames & Bunk Beds",
        shortName: "Frames & Bunks",
        tagline: "Metal and wooden bed frames, storage beds and bunk beds",
        icon: "frame"
      },
      {
        id: "dining",
        name: "Dining Furniture",
        shortName: "Dining",
        tagline: "Dining sets, individual tables and chairs in the Budget and Wooden ranges",
        icon: "dining"
      },
      {
        id: "sofas-living",
        name: "Sofas & Living Room",
        shortName: "Sofas & Living",
        tagline: "Sofas, sofa beds and coffee tables for rental living rooms",
        icon: "sofa"
      },
      {
        id: "appliances",
        name: "Appliances",
        shortName: "Appliances",
        tagline: "Fridge/freezer and washing machine options for your property",
        icon: "appliance"
      },
      {
        id: "removals",
        name: "Furniture Removals",
        shortName: "Removals",
        tagline: "Removal prices for divan beds, sofas, wardrobes and chests of drawers",
        icon: "van"
      }
    ],
    products: [
      {
        id: "oxford-divan-bed",
        name: "Oxford Divan Bed",
        category: "beds-mattresses",
        collection: "Divan Beds",
        description: "Choose an Oxford base-and-mattress set or a replacement mattress. Drawers and headboards are priced separately.",
        startingPrice: 95,
        placeholder: "assets/placeholders/bed-divan.svg?v=public-audit-20261020",
        variants: [
          { id: "oxford-set-3ft", label: "3ft Single — Set (Base & Mattress)", price: 130 },
          { id: "oxford-set-4ft", label: "4ft / 4ft6 — Set (Base & Mattress)", price: 170 },
          { id: "oxford-set-5ft", label: "5ft King — Set (Base & Mattress)", price: 200 },
          { id: "oxford-matt-3ft", label: "3ft Single — Mattress Only", price: 95 },
          { id: "oxford-matt-4ft", label: "4ft / 4ft6 — Mattress Only", price: 125 },
          { id: "oxford-matt-5ft", label: "5ft King — Mattress Only", price: 155 }
        ],
        addons: [
          { name: "Drawer", price: 35, unit: "per drawer" },
          { name: "Headboard (3ft Single)", price: 25, unit: "each" },
          { name: "Headboard (4ft / 4ft6)", price: 35, unit: "each" },
          { name: "Headboard (5ft King)", price: 45, unit: "each" }
        ],
        specNotes: ""
      },
      {
        id: "silk-ortho-divan-bed",
        name: "Silk Ortho Divan Bed",
        category: "beds-mattresses",
        collection: "Divan Beds",
        description: "Choose a Silk Ortho base-and-mattress set or a replacement mattress. Drawers and headboards are priced separately.",
        startingPrice: 120,
        placeholder: "assets/placeholders/bed-divan.svg?v=public-audit-20261020",
        variants: [
          { id: "silk-set-3ft", label: "3ft Single — Set (Base & Mattress)", price: 155 },
          { id: "silk-set-4ft", label: "4ft / 4ft6 — Set (Base & Mattress)", price: 200 },
          { id: "silk-set-5ft", label: "5ft King — Set (Base & Mattress)", price: 240 },
          { id: "silk-matt-3ft", label: "3ft Single — Mattress Only", price: 120 },
          { id: "silk-matt-4ft", label: "4ft / 4ft6 — Mattress Only", price: 150 },
          { id: "silk-matt-5ft", label: "5ft King — Mattress Only", price: 195 }
        ],
        addons: [
          { name: "Drawer", price: 35, unit: "per drawer" },
          { name: "Headboard (3ft Single)", price: 25, unit: "each" },
          { name: "Headboard (4ft / 4ft6)", price: 35, unit: "each" },
          { name: "Headboard (5ft King)", price: 45, unit: "each" }
        ],
        specNotes: ""
      },
      {
        id: "foam-divan-bed",
        name: "Foam Divan Bed",
        category: "beds-mattresses",
        collection: "Divan Beds",
        description: "Choose a Foam Divan Bed base-and-mattress set or a replacement mattress. Drawers and headboards are priced separately.",
        startingPrice: 120,
        placeholder: "assets/placeholders/bed-divan.svg?v=public-audit-20261020",
        variants: [
          { id: "foam-set-3ft", label: "3ft Single — Set (Base & Mattress)", price: 155 },
          { id: "foam-set-4ft", label: "4ft / 4ft6 — Set (Base & Mattress)", price: 200 },
          { id: "foam-set-5ft", label: "5ft King — Set (Base & Mattress)", price: 240 },
          { id: "foam-matt-3ft", label: "3ft Single — Mattress Only", price: 120 },
          { id: "foam-matt-4ft", label: "4ft / 4ft6 — Mattress Only", price: 150 },
          { id: "foam-matt-5ft", label: "5ft King — Mattress Only", price: 195 }
        ],
        addons: [
          { name: "Drawer", price: 35, unit: "per drawer" },
          { name: "Headboard (3ft Single)", price: 25, unit: "each" },
          { name: "Headboard (4ft / 4ft6)", price: 35, unit: "each" },
          { name: "Headboard (5ft King)", price: 45, unit: "each" }
        ],
        specNotes: ""
      },
      {
        id: "budget-wardrobe-2door",
        name: "Budget 2-Door Wardrobe",
        category: "bedroom-storage",
        collection: "Budget Range",
        description: "Budget Range two-door wardrobe, with a choice of models with or without two drawers.",
        startingPrice: 95,
        placeholder: "assets/placeholders/wardrobe.svg?v=public-audit-20261020",
        variants: [
          { id: "budget-2door-plain", label: "2-Door Wardrobe", price: 95 },
          { id: "budget-2door-2draw", label: "2-Door Wardrobe with 2 Drawers", price: 120 }
        ],
        addons: [
          { name: "Wardrobe Mirror", price: 20, unit: "optional" }
        ],
        specNotes: "Colours may vary. Ask us about the current colour options."
      },
      {
        id: "budget-wardrobe-3door",
        name: "Budget 3-Door Wardrobe",
        category: "bedroom-storage",
        collection: "Budget Range",
        description: "Budget Range three-door wardrobe, with a choice of models with or without two drawers.",
        startingPrice: 170,
        placeholder: "assets/placeholders/wardrobe.svg?v=public-audit-20261020",
        variants: [
          { id: "budget-3door-plain", label: "3-Door Wardrobe", price: 170 },
          { id: "budget-3door-2draw", label: "3-Door Wardrobe with 2 Drawers", price: 195 }
        ],
        addons: [
          { name: "Wardrobe Mirror", price: 20, unit: "optional" }
        ],
        specNotes: "Colours may vary. Ask us about the current colour options."
      },
      {
        id: "budget-chests-bedside",
        name: "Budget Chests & Bedside Units",
        category: "bedroom-storage",
        collection: "Budget Range",
        description: "Choose a three-drawer bedside unit or a four-drawer chest from the Budget Range.",
        startingPrice: 40,
        placeholder: "assets/placeholders/chest.svg?v=public-audit-20261020",
        variants: [
          { id: "budget-bedside-3draw", label: "3-Drawer Bedside Unit", price: 40 },
          { id: "budget-chest-4draw", label: "4-Drawer Chest", price: 70 }
        ],
        addons: [],
        specNotes: "Colours may vary. Ask us about the current colour options."
      },
      {
        id: "ab-wardrobe-2door",
        name: "AB Range 2-Door Wardrobe",
        category: "bedroom-storage",
        collection: "AB Range",
        description: "AB Range two-door wardrobe, with a choice of models with or without two drawers.",
        startingPrice: 150,
        placeholder: "assets/placeholders/wardrobe.svg?v=public-audit-20261020",
        variants: [
          { id: "ab-2door-plain", label: "2-Door Wardrobe", price: 150 },
          { id: "ab-2door-2draw", label: "2-Door Wardrobe with 2 Drawers", price: 180 }
        ],
        addons: [
          { name: "Wardrobe Mirror", price: 35, unit: "optional" }
        ],
        specNotes: "Finish options: white, oak, grey, walnut and black. Ask us which finishes are currently available."
      },
      {
        id: "ab-wardrobe-3door",
        name: "AB Range 3-Door Wardrobe",
        category: "bedroom-storage",
        collection: "AB Range",
        description: "AB Range three-door wardrobe, with a choice of models with or without two drawers.",
        startingPrice: 250,
        placeholder: "assets/placeholders/wardrobe.svg?v=public-audit-20261020",
        variants: [
          { id: "ab-3door-plain", label: "3-Door Wardrobe", price: 250 },
          { id: "ab-3door-2draw", label: "3-Door Wardrobe with 2 Drawers", price: 280 }
        ],
        addons: [
          { name: "Wardrobe Mirror", price: 35, unit: "optional" }
        ],
        specNotes: "Finish options: white, oak, grey, walnut and black. Ask us which finishes are currently available."
      },
      {
        id: "ab-chests-bedside",
        name: "AB Range Chests & Bedside Units",
        category: "bedroom-storage",
        collection: "AB Range",
        description: "Choose a three-drawer bedside unit, four-drawer chest or five-drawer chest from the AB Range.",
        startingPrice: 55,
        placeholder: "assets/placeholders/chest.svg?v=public-audit-20261020",
        variants: [
          { id: "ab-bedside-3draw", label: "3-Drawer Bedside Unit", price: 55 },
          { id: "ab-chest-4draw", label: "4-Drawer Chest", price: 120 },
          { id: "ab-chest-5draw", label: "5-Drawer Chest", price: 140 }
        ],
        addons: [],
        specNotes: "Finish options: white, oak, grey, walnut and black. Ask us which finishes are currently available."
      },
      {
        id: "chester-metal-bed",
        name: "Chester Metal Bed",
        category: "bed-frames-bunks",
        collection: "Bed Frames",
        description: "Chester Metal Bed frame with 3ft and 4ft / 4ft6 size options.",
        startingPrice: 110,
        placeholder: "assets/placeholders/bed-frame.svg?v=public-audit-20261020",
        variants: [
          { id: "chester-3ft", label: "3ft Single Frame", price: 110 },
          { id: "chester-4ft", label: "4ft / 4ft6 Frame", price: 130 }
        ],
        addons: [],
        specNotes: "Ask us for the frame dimensions before ordering."
      },
      {
        id: "jersey-metal-bed",
        name: "Jersey Metal Bed",
        category: "bed-frames-bunks",
        collection: "Bed Frames",
        description: "Jersey Metal Bed frame with 3ft, 4ft / 4ft6 and 5ft size options.",
        startingPrice: 180,
        placeholder: "assets/placeholders/bed-frame.svg?v=public-audit-20261020",
        variants: [
          { id: "jersey-3ft", label: "3ft Single Frame", price: 180 },
          { id: "jersey-4ft", label: "4ft / 4ft6 Frame", price: 200 },
          { id: "jersey-5ft", label: "5ft King Frame", price: 220 }
        ],
        addons: [],
        specNotes: "Ask us for the frame dimensions before ordering."
      },
      {
        id: "colorado-wooden-bed",
        name: "Colorado Wooden Bed",
        category: "bed-frames-bunks",
        collection: "Bed Frames",
        description: "Colorado Wooden Bed frame with 3ft, 4ft / 4ft6 and 5ft size options.",
        startingPrice: 150,
        placeholder: "assets/placeholders/bed-frame.svg?v=public-audit-20261020",
        variants: [
          { id: "colorado-3ft", label: "3ft Single Frame", price: 150 },
          { id: "colorado-4ft", label: "4ft / 4ft6 Frame", price: 180 },
          { id: "colorado-5ft", label: "5ft King Frame", price: 200 }
        ],
        addons: [],
        specNotes: "Ask us for the frame dimensions before ordering."
      },
      {
        id: "storage-bed-frame",
        name: "PVC / Fabric Storage Bed",
        category: "bed-frames-bunks",
        collection: "Bed Frames",
        description: "Storage bed with 3ft, 4ft / 4ft6 and 5ft size options.",
        startingPrice: 240,
        placeholder: "assets/placeholders/bed-frame.svg?v=public-audit-20261020",
        variants: [
          { id: "storage-3ft", label: "3ft Single Storage Bed", price: 240 },
          { id: "storage-4ft", label: "4ft / 4ft6 Storage Bed", price: 270 },
          { id: "storage-5ft", label: "5ft King Storage Bed", price: 290 }
        ],
        addons: [],
        specNotes: "Ask us about PVC or fabric covering options and the bed’s dimensions."
      },
      {
        id: "metal-bunk-bed",
        name: "Metal Bunk Bed",
        category: "bed-frames-bunks",
        collection: "Bunk Beds",
        description: "Metal Bunk Bed with Single / Single and Trio Sleeper options.",
        startingPrice: 250,
        placeholder: "assets/placeholders/bunk.svg?v=public-audit-20261020",
        variants: [
          { id: "metal-bunk-single", label: "Single / Single", price: 250 },
          { id: "metal-bunk-trio", label: "Trio Sleeper", price: 290 }
        ],
        addons: [],
        specNotes: "Ask us for dimensions and details of your chosen bunk-bed option."
      },
      {
        id: "wooden-bunk-bed",
        name: "Wooden Bunk Bed",
        category: "bed-frames-bunks",
        collection: "Bunk Beds",
        description: "Wooden Bunk Bed with Single / Single and Trio Sleeper options.",
        startingPrice: 320,
        placeholder: "assets/placeholders/bunk.svg?v=public-audit-20261020",
        variants: [
          { id: "wooden-bunk-single", label: "Single / Single", price: 320 },
          { id: "wooden-bunk-trio", label: "Trio Sleeper", price: 390 }
        ],
        addons: [],
        specNotes: "Ask us for dimensions and details of your chosen bunk-bed option."
      },
      {
        id: "budget-dining-range",
        name: "Budget Dining Range",
        category: "dining",
        collection: "Dining Furniture",
        description: "Choose a dining set or individual tables and chairs from the Budget Dining Range.",
        startingPrice: 30,
        placeholder: "assets/placeholders/dining-table.svg?v=public-audit-20261020",
        variants: [
          { id: "budget-dining-chair", label: "Individual Dining Chair", price: 30 },
          { id: "budget-dining-tbl-sm", label: "Small Dining Table", price: 80 },
          { id: "budget-dining-tbl-md", label: "Medium Dining Table", price: 105 },
          { id: "budget-dining-tbl-lg", label: "Large Dining Table", price: 140 },
          { id: "budget-dining-set-2", label: "Dining Set of 2", price: 150 },
          { id: "budget-dining-set-4", label: "Dining Set of 4", price: 190 },
          { id: "budget-dining-set-6", label: "Dining Set of 6", price: 240 }
        ],
        addons: [],
        specNotes: "Ask us to confirm the items included in your chosen set and the table dimensions."
      },
      {
        id: "wooden-dining-range",
        name: "Wooden Dining Range",
        category: "dining",
        collection: "Dining Furniture",
        description: "Choose a dining set or individual tables and chairs from the Wooden Dining Range.",
        startingPrice: 50,
        placeholder: "assets/placeholders/dining-table.svg?v=public-audit-20261020",
        variants: [
          { id: "wood-dining-chair", label: "Individual Dining Chair", price: 50 },
          { id: "wood-dining-tbl-sm", label: "Small Dining Table", price: 120 },
          { id: "wood-dining-tbl-md", label: "Medium Dining Table", price: 150 },
          { id: "wood-dining-tbl-lg", label: "Large Dining Table", price: 190 },
          { id: "wood-dining-set-2", label: "Dining Set of 2", price: 180 },
          { id: "wood-dining-set-4", label: "Dining Set of 4", price: 250 },
          { id: "wood-dining-set-6", label: "Dining Set of 6", price: 360 }
        ],
        addons: [],
        specNotes: "Ask us to confirm the items included in your chosen set and the table dimensions."
      },
      {
        id: "box-sofa-suite",
        name: "Box Sofa",
        category: "sofas-living",
        collection: "Sofas & Sofa Beds",
        description: "Box Sofa options include a one-seater, two-seater, three-seater and a three-plus-two-seater combination.",
        startingPrice: 170,
        placeholder: "assets/placeholders/sofa.svg?v=public-audit-20261020",
        variants: [
          { id: "box-sofa-1s", label: "1-Seater", price: 170 },
          { id: "box-sofa-2s", label: "2-Seater", price: 220 },
          { id: "box-sofa-3s", label: "3-Seater", price: 270 },
          { id: "box-sofa-combo", label: "3 + 2-Seater Combination", price: 420 }
        ],
        addons: [],
        specNotes: "Ask us about current colours and the dimensions of your chosen option."
      },
      {
        id: "dylan-sofa-suite",
        name: "Dylan Sofa Suite",
        category: "sofas-living",
        collection: "Sofas & Sofa Beds",
        description: "Choose a Dylan two-seater, three-seater or three-plus-two-seater combination.",
        startingPrice: 240,
        placeholder: "assets/placeholders/sofa.svg?v=public-audit-20261020",
        variants: [
          { id: "dylan-sofa-2s", label: "2-Seater", price: 240 },
          { id: "dylan-sofa-3s", label: "3-Seater", price: 290 },
          { id: "dylan-sofa-combo", label: "3 + 2-Seater Combination", price: 480 }
        ],
        addons: [],
        specNotes: "Ask us about current colours and the dimensions of your chosen option."
      },
      {
        id: "turkish-sofa-bed",
        name: "Turkish Sofa Bed",
        category: "sofas-living",
        collection: "Sofas & Sofa Beds",
        description: "Turkish Sofa Bed options include a two-seater, three-seater and a three-plus-two-seater combination.",
        startingPrice: 320,
        placeholder: "assets/placeholders/sofa.svg?v=public-audit-20261020",
        variants: [
          { id: "turkish-sb-2s", label: "2-Seater", price: 320 },
          { id: "turkish-sb-3s", label: "3-Seater", price: 350 },
          { id: "turkish-sb-combo", label: "3 + 2-Seater Combination", price: 650 }
        ],
        addons: [],
        specNotes: "Ask us about current colours and the dimensions of your chosen option."
      },
      {
        id: "click-clack-sofa-bed",
        name: "ClickClac Sofa Bed",
        category: "sofas-living",
        collection: "Sofas & Sofa Beds",
        description: "Choose a two-seater or three-seater ClickClac Sofa Bed.",
        startingPrice: 170,
        placeholder: "assets/placeholders/sofa.svg?v=public-audit-20261020",
        variants: [
          { id: "clickclack-2s", label: "2-Seater", price: 170 },
          { id: "clickclack-3s", label: "3-Seater", price: 190 }
        ],
        addons: [],
        specNotes: "Ask us about current colours and the dimensions of your chosen option."
      },
      {
        id: "living-coffee-table",
        name: "Coffee Table",
        category: "sofas-living",
        collection: "Living Room Furniture",
        description: "A coffee table for your rental property’s living room.",
        startingPrice: 40,
        placeholder: "assets/placeholders/coffee-table.svg?v=public-audit-20261020",
        variants: [
          { id: "coffee-table-std", label: "Coffee Table", price: 40 }
        ],
        addons: [],
        specNotes: "Ask us about the finish and table dimensions."
      },
      {
        id: "fridge-freezer-tall",
        name: "Fridge/Freezer",
        category: "appliances",
        collection: "Appliances",
        description: "Enquire about a fridge/freezer for your property.",
        startingPrice: 420,
        placeholder: "assets/placeholders/appliance.svg?v=public-audit-20261020",
        variants: [
          { id: "app-fridge-freezer", label: "Fridge/Freezer", price: 420 }
        ],
        addons: [],
        specNotes: "Ask us to confirm the appliance type, brand, model and dimensions before ordering."
      },
      {
        id: "fridge-freezer-undercounter",
        name: "Under Counter Fridge/Freezer",
        category: "appliances",
        collection: "Appliances",
        description: "Enquire about under-counter refrigeration for your property.",
        startingPrice: 290,
        placeholder: "assets/placeholders/appliance.svg?v=public-audit-20261020",
        variants: [
          { id: "app-undercounter", label: "Under Counter Fridge/Freezer", price: 290 }
        ],
        addons: [],
        specNotes: "Ask us to confirm whether this option is a fridge, freezer or combined unit, along with the brand, model and dimensions."
      },
      {
        id: "washing-machine",
        name: "Washing Machine",
        category: "appliances",
        collection: "Appliances",
        description: "Enquire about a washing machine for your property.",
        startingPrice: 360,
        placeholder: "assets/placeholders/appliance.svg?v=public-audit-20261020",
        variants: [
          { id: "app-washer", label: "Washing Machine", price: 360 }
        ],
        addons: [],
        specNotes: "Ask us to confirm the brand, model, load capacity and dimensions before ordering."
      },
      {
        id: "furniture-removal-service",
        name: "Furniture Removal",
        category: "removals",
        collection: "Removal Services",
        description: "Removal options for chests of drawers, single and double divan beds, sofas and wardrobes.",
        startingPrice: 20,
        placeholder: "assets/placeholders/van.svg?v=public-audit-20261020",
        variants: [
          { id: "rem-chest", label: "Chest of Drawers", price: 20 },
          { id: "rem-bed-single", label: "Single Divan Bed", price: 25 },
          { id: "rem-bed-double", label: "Double Divan Bed", price: 30 },
          { id: "rem-sofa", label: "Sofa — Per Piece", price: 30 },
          { id: "rem-wardrobe", label: "Wardrobe", price: 30 }
        ],
        addons: [],
        specNotes: "Bed removal is for divan beds only. Contact us to discuss your items and arrange collection."
      }
    ]
  };

  // --- State Variables ---
  let currentCategory = 'all';
  let searchQuery = '';
  let selectedProductItem = null;
  let lastGeneratedTemplate = '';
  const variantStateByProduct = {};
  CATALOGUE_DATA.products.forEach(prod => {
    if (Array.isArray(prod.variants) && prod.variants.length > 0) {
      variantStateByProduct[prod.id] = prod.variants[0].id;
    }
  });
  let drawerReturnFocusElem = null;
  let modalReturnFocusElem = null;

  // --- DOM References ---
  const skipLink = document.querySelector('.skip-link');
  const topBar = document.querySelector('.top-bar');
  const header = document.querySelector('.site-header');
  const mainContent = document.getElementById('mainContent');
  const footer = document.querySelector('.site-footer');
  const productGrid = document.getElementById('productGrid');
  const filterPillsContainer = document.getElementById('filterPills');
  const searchInput = document.getElementById('catalogueSearch');
  const catalogueHeading = document.getElementById('catalogueHeading');
  const activeFilterLabel = document.getElementById('activeFilterLabel');
  const productCountLabel = document.getElementById('productCountLabel');
  const categoryTiles = document.querySelectorAll('.category-tile');
  const footerCategoryLinks = document.querySelectorAll('.footer-category-link');

  // Contact / Enquiry Elements
  const contactSection = document.getElementById('contact');
  const enquiryFormCard = document.getElementById('enquiryFormCard') || document.querySelector('.enquiry-form-card');
  const selectedBanner = document.getElementById('selectedProductBanner');
  const selectedNameElem = document.getElementById('selectedProductName');
  const selectedPriceElem = document.getElementById('selectedProductPrice');
  const clearSelectionBtn = document.getElementById('clearProductSelection');
  const formProductSelect = document.getElementById('enquiryProductSelect');
  const formProductSelectLabel = document.getElementById('enquiryProductSelectLabel');
  const enquiryForm = document.getElementById('enquiryForm');
  const enquiryFormError = document.getElementById('enquiryFormError');
  const enquiryNameInput = document.getElementById('enquiryName');
  const enquiryPhoneInput = document.getElementById('enquiryPhone');
  const enquiryEmailInput = document.getElementById('enquiryEmail');
  const enquiryPostcodeInput = document.getElementById('enquiryPostcode');
  const enquiryMessage = document.getElementById('enquiryMessage');
  const enquiryFeedback = document.getElementById('enquiryFeedback');
  const feedbackSummaryText = document.getElementById('feedbackSummaryText');
  const copyEnquiryBtn = document.getElementById('copyEnquiryBtn');
  const copyFeedbackMessage = document.getElementById('copyFeedbackMessage');
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
        <p>Browse the catalogue and choose the items you need, or contact us about a landlord furniture package.</p>
        <ol style="padding-left: 1.25rem; display: flex; flex-direction: column; gap: 0.5rem;">
          <li>Select an item and choose “Enquire About This Item” to add it to your enquiry.</li>
          <li>Call, WhatsApp or email our team, or visit the showroom, to discuss your requirements.</li>
          <li>Confirm your quote, stock and delivery arrangements directly with us.</li>
        </ol>
        <p>There is no online checkout.</p>
        <p><em>Store Address: 401 Lordship Lane, London, N17 6AE. Open Monday–Friday 9:30am–6:00pm, Saturday 9:30am–5:00pm, Sunday Closed.</em></p>
      `
    },
    delivery: {
      title: "Delivery Information",
      content: `
        <p>Contact us with your delivery postcode, required items and preferred date to discuss delivery options and charges.</p>
        <p>Same-day delivery is subject to stock, your location, our delivery route and a confirmed delivery slot.</p>
        <p>Key collection and property access can be coordinated by arrangement.</p>
        <p>Call or WhatsApp 020 8888 0322.</p>
      `
    },
    removals: {
      title: "Furniture Removal Prices",
      content: `
        <ul style="padding-left: 1.25rem; display: flex; flex-direction: column; gap: 0.4rem;">
          <li>Chest of drawers: £20</li>
          <li>Single divan bed: £25</li>
          <li>Double divan bed: £30</li>
          <li>Sofa: £30 per piece</li>
          <li>Wardrobe: £30</li>
        </ul>
        <p>Bed removal is for divan beds only. Contact our team to discuss your items and arrange collection.</p>
      `
    },
    privacy: {
      title: "How Email Enquiries Work",
      content: `
        <p>The form adds your details to an email draft addressed to <strong>info@gbafurniture.com</strong>. Review and send the draft from your email app. The form does not send your enquiry automatically.</p>
        <p>If your email app does not open, copy the enquiry text into an email or contact us by phone or WhatsApp.</p>
      `
    }
  };

  // ==========================================================================
  // INITIALIZATION
  // ==========================================================================
  function init() {
    renderFilterPills();
    populateFormProductSelect();
    updateContactMethodRequirements();
    renderProducts();
    updateCategoryNavigationState();
    updateHeaderCollapseState();
    bindEvents();
    checkUrlHash();
    if (document.fonts && document.fonts.ready && typeof document.fonts.ready.then === 'function') {
      document.fonts.ready.then(updateHeaderCollapseState).catch(() => {});
    }
  }

  // ==========================================================================
  // HEADER COLLAPSE & HIT-TARGET OVERLAP PREVENTION
  // ==========================================================================
  function rectsOverlapHorizontally(a, b, minGap = 4) {
    if (!a || !b) return false;
    if (a.width <= 0 || a.height <= 0 || b.width <= 0 || b.height <= 0) return false;
    const verticalOverlap = a.bottom > b.top && b.bottom > a.top;
    if (!verticalOverlap) return false;
    return (a.right + minGap > b.left) && (b.right + minGap > a.left);
  }

  function updateHeaderCollapseState() {
    if (!header) return;
    const headerInner = header.querySelector('.header-inner');
    const viewportWidth = typeof window.innerWidth === 'number' ? window.innerWidth : 1400;

    if (viewportWidth <= 1399) {
      header.classList.add('is-collapsed');
      return;
    }

    header.classList.remove('is-collapsed');
    if (!headerInner) return;

    let shouldCollapse = false;
    if (headerInner.scrollWidth > headerInner.clientWidth + 1) {
      shouldCollapse = true;
    } else {
      const innerRect = typeof headerInner.getBoundingClientRect === 'function' ? headerInner.getBoundingClientRect() : null;
      const brand = headerInner.querySelector('.site-brand');
      const nav = headerInner.querySelector('.primary-nav');
      const actions = headerInner.querySelector('.header-actions');
      const brandRect = brand && typeof brand.getBoundingClientRect === 'function' ? brand.getBoundingClientRect() : null;
      const navRect = nav && typeof nav.getBoundingClientRect === 'function' ? nav.getBoundingClientRect() : null;
      const actionsRect = actions && typeof actions.getBoundingClientRect === 'function' ? actions.getBoundingClientRect() : null;

      if (
        rectsOverlapHorizontally(brandRect, navRect, 8) ||
        rectsOverlapHorizontally(navRect, actionsRect, 8) ||
        rectsOverlapHorizontally(brandRect, actionsRect, 8)
      ) {
        shouldCollapse = true;
      }

      if (!shouldCollapse && innerRect && innerRect.width > 0) {
        const controls = Array.from(
          headerInner.querySelectorAll(
            '.site-brand, .primary-nav .nav-link, .header-actions .btn-tel, .header-actions .btn-whatsapp, .header-actions .btn-primary'
          )
        );
        const rects = controls
          .map(el => (typeof el.getBoundingClientRect === 'function' ? el.getBoundingClientRect() : null))
          .filter(r => r && r.width > 0 && r.height > 0);

        for (let i = 0; i < rects.length; i++) {
          if (rects[i].left < innerRect.left - 1 || rects[i].right > innerRect.right + 1) {
            shouldCollapse = true;
            break;
          }
          for (let j = i + 1; j < rects.length; j++) {
            if (rectsOverlapHorizontally(rects[i], rects[j], 2)) {
              shouldCollapse = true;
              break;
            }
          }
          if (shouldCollapse) break;
        }
      }
    }

    if (shouldCollapse) {
      header.classList.add('is-collapsed');
    } else if (isMobileDrawerOpen()) {
      closeMobileDrawer({ restoreFocus: false });
    }
  }

  // ==========================================================================
  // FILTER PILLS RENDERING
  // ==========================================================================
  function renderFilterPills() {
    if (!filterPillsContainer) return;
    filterPillsContainer.innerHTML = '';

    CATALOGUE_DATA.categories.forEach(cat => {
      const isActive = cat.id === currentCategory;
      const button = document.createElement('button');
      button.type = 'button';
      button.className = `filter-pill ${isActive ? 'is-active' : ''}`;
      button.setAttribute('data-category', cat.id);
      button.setAttribute('aria-pressed', String(isActive));
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
    defaultOpt.textContent = 'Furniture Package, Multiple Items or General Enquiry';
    formProductSelect.appendChild(defaultOpt);

    CATALOGUE_DATA.categories.filter(c => c.id !== 'all').forEach(cat => {
      const group = document.createElement('optgroup');
      group.label = cat.name;

      const catProducts = CATALOGUE_DATA.products.filter(p => p.category === cat.id);
      catProducts.forEach(prod => {
        const opt = document.createElement('option');
        opt.value = prod.id;
        const defaultText = prod.variants.length > 1
          ? `${prod.name} (from £${prod.startingPrice})`
          : `${prod.name} (£${prod.startingPrice})`;
        opt.textContent = defaultText;
        opt.setAttribute('data-default-text', defaultText);
        group.appendChild(opt);
      });

      formProductSelect.appendChild(group);
    });

    syncFormProductSelectLabel();
  }

  function resetFormProductSelectLabels() {
    if (!formProductSelect) return;
    for (let i = 0; i < formProductSelect.options.length; i++) {
      const opt = formProductSelect.options[i];
      const defaultText = opt.getAttribute('data-default-text');
      if (defaultText) {
        opt.textContent = defaultText;
      }
    }
  }

  function syncFormProductSelectLabel() {
    if (!formProductSelect || !formProductSelectLabel) return;
    const opts = formProductSelect.options || [];
    let selectedOpt = opts[formProductSelect.selectedIndex] || null;
    if (!selectedOpt && formProductSelect.value) {
      for (let i = 0; i < opts.length; i++) {
        if (opts[i].value === formProductSelect.value) {
          selectedOpt = opts[i];
          break;
        }
      }
    }
    if (selectedOpt && selectedOpt.textContent) {
      formProductSelectLabel.textContent = selectedOpt.textContent.trim();
    } else if (selectedProductItem) {
      formProductSelectLabel.textContent = `${formatSelectedItemLabel(selectedProductItem)} (£${selectedProductItem.price})`;
    } else {
      formProductSelectLabel.textContent = 'Furniture Package, Multiple Items or General Enquiry';
    }
  }

  // ==========================================================================
  // AUTHORITATIVE PRODUCT / VARIANT RESOLUTION
  // ==========================================================================
  function resolveProductSelection(productId, preferredVariantId) {
    const prod = CATALOGUE_DATA.products.find(p => p.id === productId);
    if (!prod || !Array.isArray(prod.variants) || prod.variants.length === 0) {
      return null;
    }
    const targetVariantId = preferredVariantId || variantStateByProduct[prod.id] || prod.variants[0].id;
    const variantObj = prod.variants.find(v => v.id === targetVariantId) || prod.variants[0];
    variantStateByProduct[prod.id] = variantObj.id;

    return {
      id: prod.id,
      name: prod.name,
      category: prod.category,
      variantId: variantObj.id,
      variant: variantObj.label,
      price: variantObj.price
    };
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

    const trimmedQuery = searchQuery.trim();
    if (trimmedQuery !== '') {
      const q = trimmedQuery.toLowerCase();
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
    const categoryName = currentCatObj ? currentCatObj.name : 'All Items';
    if (activeFilterLabel) {
      activeFilterLabel.textContent = categoryName;
    }
    if (catalogueHeading) {
      catalogueHeading.textContent = currentCategory === 'all' ? 'Browse Our Catalogue' : categoryName;
    }
    if (productCountLabel) {
      const countText = `${filtered.length} item${filtered.length === 1 ? '' : 's'}`;
      if (trimmedQuery !== '' && currentCategory !== 'all') {
        productCountLabel.textContent = `Showing ${countText} in ${categoryName} for “${trimmedQuery}”`;
      } else if (trimmedQuery !== '') {
        productCountLabel.textContent = `Showing ${countText} for “${trimmedQuery}”`;
      } else if (currentCategory !== 'all') {
        productCountLabel.textContent = `Showing ${countText} in ${categoryName}`;
      } else {
        productCountLabel.textContent = `Showing ${countText}`;
      }
    }

    productGrid.innerHTML = '';

    if (filtered.length === 0) {
      const emptyDiv = document.createElement('div');
      emptyDiv.className = 'catalogue-empty-state';
      emptyDiv.innerHTML = `
        <h3>No Matching Items</h3>
        <p>Try a different search or browse all items. For help finding furniture for your property, call 020 8888 0322.</p>
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

      const activeVariantId = variantStateByProduct[product.id] || product.variants[0].id;
      const activeVariant = product.variants.find(v => v.id === activeVariantId) || product.variants[0];
      variantStateByProduct[product.id] = activeVariant.id;
      const hasMultipleVariants = product.variants.length > 1;

      let variantSelectHtml = '';
      if (hasMultipleVariants) {
        const variantPrompt = product.category === 'removals' ? 'Choose an Item to Remove' : 'Choose an Option';
        const options = product.variants.map(v => `
          <option value="${v.id}" data-price="${v.price}" data-label="${escapeHtml(v.label)}" ${v.id === activeVariant.id ? 'selected' : ''}>
            ${escapeHtml(v.label)} — £${v.price}
          </option>
        `).join('');

        variantSelectHtml = `
          <div class="variant-selector-wrapper">
            <label for="variant-${product.id}" class="variant-label">${variantPrompt}</label>
            <select id="variant-${product.id}" class="variant-select" data-card-id="${product.id}" aria-describedby="variant-selected-${product.id}">
              ${options}
            </select>
            <div class="variant-selected-label" id="variant-selected-${product.id}">${escapeHtml(activeVariant.label)} — £${activeVariant.price}</div>
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
            <div class="product-addons-title">Optional Extras</div>
            <ul class="product-addons-list">
              ${addonItems}
            </ul>
          </div>
        `;
      }

      card.innerHTML = `
        <div class="product-card-media">
          <img src="${product.placeholder}" alt="Illustration only; not a photograph of ${escapeHtml(product.name)}" class="product-card-img" loading="lazy">
          <div class="product-price-tag" id="price-tag-${product.id}">
            <span class="product-price-prefix">${hasMultipleVariants ? 'Selected Option' : 'Price'}</span>
            <span class="price-val">£${activeVariant.price}</span>
          </div>
        </div>
        <div class="product-card-body">
          <span class="product-collection-eyebrow">${product.collection}</span>
          <h3 class="product-card-title">${product.name}</h3>
          <p class="product-card-desc">${product.description}</p>

          ${product.specNotes ? `
            <div class="product-spec-strip">
              <strong>Product Details:</strong> ${product.specNotes}
            </div>
          ` : ''}

          ${variantSelectHtml}
          ${addonsHtml}

          <div class="product-card-actions">
            <button type="button"
                    class="btn btn-primary enquire-action-btn"
                    data-product-id="${product.id}"
                    data-product-name="${escapeHtml(product.name)}"
                    data-product-category="${escapeHtml(product.category)}"
                    data-variant-id="${activeVariant.id}"
                    data-variant-label="${escapeHtml(activeVariant.label)}"
                    data-price="${activeVariant.price}">
              <svg viewBox="0 0 24 24" fill="currentColor">
                <path d="M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4l-8 5-8-5V6l8 5 8-5v2z"/>
              </svg>
              <span>Enquire About This Item</span>
            </button>
          </div>
        </div>
      `;

      productGrid.appendChild(card);

      if (hasMultipleVariants) {
        const select = card.querySelector('.variant-select');
        const selectedLabelElem = card.querySelector('.variant-selected-label');
        const priceTagVal = card.querySelector(`#price-tag-${product.id} .price-val`);
        const pricePrefix = card.querySelector(`#price-tag-${product.id} .product-price-prefix`);
        const actionBtn = card.querySelector('.enquire-action-btn');

        if (select) {
          select.addEventListener('change', () => {
            const selectedOpt = select.options[select.selectedIndex];
            const canonicalVariant = product.variants.find(v => v.id === select.value);
            const newPrice = canonicalVariant
              ? canonicalVariant.price
              : Number(selectedOpt ? selectedOpt.getAttribute('data-price') : activeVariant.price);
            const newLabel = canonicalVariant
              ? canonicalVariant.label
              : (selectedOpt && selectedOpt.getAttribute('data-label')) ||
                (selectedOpt ? selectedOpt.text.replace(/\s+—\s+£\d+(?:\.\d+)?$/, '').trim() : activeVariant.label);

            variantStateByProduct[product.id] = select.value;

            if (selectedLabelElem) selectedLabelElem.textContent = `${newLabel} — £${newPrice}`;
            if (priceTagVal) priceTagVal.textContent = `£${newPrice}`;
            if (pricePrefix) pricePrefix.textContent = 'Selected Option';

            if (actionBtn) {
              actionBtn.setAttribute('data-variant-id', select.value);
              actionBtn.setAttribute('data-variant-label', newLabel);
              actionBtn.setAttribute('data-price', String(newPrice));
            }

            if (selectedProductItem && selectedProductItem.id === product.id) {
              selectProductForEnquiry(
                resolveProductSelection(product.id, select.value),
                { scroll: false }
              );
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
        const variantId = btn.getAttribute('data-variant-id');
        const resolved = resolveProductSelection(prodId, variantId);
        if (resolved) {
          selectProductForEnquiry(resolved, { scroll: true });
        } else {
          selectProductForEnquiry({
            id: prodId,
            name: btn.getAttribute('data-product-name'),
            category: btn.getAttribute('data-product-category'),
            variantId: variantId,
            variant: btn.getAttribute('data-variant-label'),
            price: Number(btn.getAttribute('data-price'))
          }, { scroll: true });
        }
      });
    });
  }

  // ==========================================================================
  // ENQUIRY SELECTION, CUSTOMER REQUIREMENT PRESERVATION & SCROLL
  // ==========================================================================
  function formatSelectedItemLabel(item) {
    if (!item) return '';
    if (item.variant && item.variant !== item.name) {
      return `${item.name} — ${item.variant}`;
    }
    return item.name;
  }

  function buildEnquiryTemplateMessage(item) {
    if (!item) return '';
    const isRemoval = item.category === 'removals' || item.id === 'furniture-removal-service';
    if (isRemoval) {
      return `Hello GBA Furniture,\n\nI would like to arrange removal of ${item.variant}, shown at £${item.price} in your catalogue.\n\nPlease confirm collection arrangements. I will include the quantity, property postcode and access details below.`;
    }
    const itemLabel = formatSelectedItemLabel(item);
    return `Hello GBA Furniture,\n\nPlease provide a quote for ${itemLabel}, shown at £${item.price} in your catalogue.\n\nPlease confirm stock and delivery options. I will include the quantity, property postcode and preferred delivery date below.`;
  }

  function findIntactGeneratedBlock(text, template) {
    if (!text || !template) return null;
    if (text === template) {
      return { start: 0, end: text.length };
    }
    let idx = text.indexOf(template);
    while (idx !== -1) {
      const prevChar = idx === 0 ? '\n' : text[idx - 1];
      const afterIdx = idx + template.length;
      const nextChar = afterIdx === text.length ? '\n' : text[afterIdx];
      if ((prevChar === '\n' || prevChar === '\r') && (nextChar === '\n' || nextChar === '\r')) {
        return { start: idx, end: afterIdx };
      }
      idx = text.indexOf(template, idx + 1);
    }
    return null;
  }

  function updateRequirementsMessageForSelection(newTemplate) {
    if (!enquiryMessage) return;
    const current = enquiryMessage.value;
    const trimmed = current.trim();

    if (!newTemplate) {
      if (!trimmed) {
        enquiryMessage.value = '';
      } else {
        const block = findIntactGeneratedBlock(current, lastGeneratedTemplate);
        if (block) {
          const before = current.slice(0, block.start).replace(/(?:\r?\n)+$/, '');
          const after = current.slice(block.end).replace(/^(?:\r?\n)+/, '');
          if (before && after) {
            enquiryMessage.value = `${before}\n\n${after}`;
          } else {
            enquiryMessage.value = before || after;
          }
        }
      }
      lastGeneratedTemplate = '';
      return;
    }

    if (!trimmed) {
      enquiryMessage.value = newTemplate;
    } else {
      const block = findIntactGeneratedBlock(current, lastGeneratedTemplate);
      if (block) {
        const before = current.slice(0, block.start);
        const after = current.slice(block.end);
        enquiryMessage.value = `${before}${newTemplate}${after}`;
      } else if (!findIntactGeneratedBlock(current, newTemplate)) {
        enquiryMessage.value = `${newTemplate}\n\n${trimmed}`;
      }
    }

    lastGeneratedTemplate = newTemplate;

    if (enquiryMessage.getAttribute('aria-invalid') === 'true' && enquiryMessage.value.trim() !== '') {
      validateSingleField(enquiryMessage);
      syncFormErrorSummary();
    }
  }

  function invalidatePreparedEnquiryFeedback() {
    if (enquiryFeedback) {
      enquiryFeedback.style.display = 'none';
      enquiryFeedback.hidden = true;
    }
    if (feedbackSummaryText) {
      feedbackSummaryText.textContent = '';
    }
    if (reOpenEmailBtn) {
      reOpenEmailBtn.href = '#';
    }
    if (copyEnquiryBtn) {
      copyEnquiryBtn.textContent = 'Copy Enquiry Text';
    }
    if (copyFeedbackMessage) {
      copyFeedbackMessage.textContent = '';
      copyFeedbackMessage.style.display = 'none';
    }
  }

  function selectProductForEnquiry(item, options = {}) {
    if (!item) return;
    const shouldScroll = options.scroll !== false;
    const normalized = resolveProductSelection(item.id, item.variantId) || item;
    if (item.variant && item.price !== undefined) {
      normalized.variant = item.variant;
      normalized.price = Number(item.price);
      if (item.variantId) {
        normalized.variantId = item.variantId;
        variantStateByProduct[normalized.id] = item.variantId;
      }
    }

    selectedProductItem = normalized;
    const itemLabel = formatSelectedItemLabel(normalized);

    const card = productGrid ? productGrid.querySelector(`.product-card[data-product-id="${normalized.id}"]`) : null;
    if (card) {
      const cardSelect = card.querySelector('.variant-select');
      const selectedLabelElem = card.querySelector('.variant-selected-label');
      const priceTagVal = card.querySelector(`#price-tag-${normalized.id} .price-val`);
      const actionBtn = card.querySelector('.enquire-action-btn');
      if (cardSelect && normalized.variantId && cardSelect.value !== normalized.variantId) {
        cardSelect.value = normalized.variantId;
      }
      if (selectedLabelElem) selectedLabelElem.textContent = `${normalized.variant} — £${normalized.price}`;
      if (priceTagVal) priceTagVal.textContent = `£${normalized.price}`;
      if (actionBtn) {
        if (normalized.variantId) actionBtn.setAttribute('data-variant-id', normalized.variantId);
        actionBtn.setAttribute('data-variant-label', normalized.variant);
        actionBtn.setAttribute('data-price', String(normalized.price));
      }
    }

    if (selectedBanner) {
      selectedBanner.style.display = 'flex';
      selectedBanner.hidden = false;
      selectedBanner.classList.add('is-highlighted');
      setTimeout(() => selectedBanner.classList.remove('is-highlighted'), 1600);
    }

    if (selectedNameElem) {
      selectedNameElem.textContent = itemLabel;
    }

    if (selectedPriceElem) {
      selectedPriceElem.textContent = `Catalogue price: £${normalized.price}`;
    }

    if (formProductSelect) {
      resetFormProductSelectLabels();
      let optionExists = false;
      for (let i = 0; i < formProductSelect.options.length; i++) {
        if (formProductSelect.options[i].value === normalized.id) {
          formProductSelect.options[i].textContent = `${itemLabel} (£${normalized.price})`;
          formProductSelect.selectedIndex = i;
          formProductSelect.value = normalized.id;
          optionExists = true;
          break;
        }
      }
      if (!optionExists) {
        const newOpt = document.createElement('option');
        newOpt.value = normalized.id;
        newOpt.textContent = `${itemLabel} (£${normalized.price})`;
        newOpt.selected = true;
        formProductSelect.appendChild(newOpt);
        formProductSelect.value = normalized.id;
      }
      syncFormProductSelectLabel();
    }

    updateRequirementsMessageForSelection(buildEnquiryTemplateMessage(normalized));
    invalidatePreparedEnquiryFeedback();

    if (shouldScroll) {
      if (selectedBanner && !selectedBanner.hasAttribute('tabindex')) {
        selectedBanner.setAttribute('tabindex', '-1');
      }

      const scrollTarget = selectedBanner || enquiryFormCard || contactSection;
      if (scrollTarget && typeof scrollTarget.scrollIntoView === 'function') {
        const hasRootStyle = Boolean(document.documentElement && document.documentElement.style);
        const prevScrollBehavior = hasRootStyle ? document.documentElement.style.scrollBehavior : '';
        if (hasRootStyle) {
          document.documentElement.style.scrollBehavior = 'auto';
        }
        try {
          scrollTarget.scrollIntoView({
            behavior: 'auto',
            block: 'start'
          });
        } finally {
          if (hasRootStyle) {
            document.documentElement.style.scrollBehavior = prevScrollBehavior;
          }
        }
      }

      const viewportWidth =
        typeof window.innerWidth === 'number'
          ? window.innerWidth
          : (document.documentElement && document.documentElement.clientWidth) || 1024;
      const viewportHeight =
        typeof window.innerHeight === 'number'
          ? window.innerHeight
          : (document.documentElement && document.documentElement.clientHeight) || 900;
      const isMobileViewport =
        viewportWidth <= 768 ||
        Boolean(window.matchMedia && window.matchMedia('(max-width: 768px)').matches);

      let canFocusName = false;
      if (
        !isMobileViewport &&
        enquiryNameInput &&
        !enquiryNameInput.value.trim() &&
        typeof enquiryNameInput.getBoundingClientRect === 'function'
      ) {
        const rect = enquiryNameInput.getBoundingClientRect();
        canFocusName = Boolean(
          rect &&
            rect.width > 0 &&
            rect.height > 0 &&
            rect.top >= 0 &&
            rect.left >= 0 &&
            rect.bottom <= viewportHeight &&
            rect.right <= viewportWidth
        );
      }

      const focusTarget =
        (canFocusName ? enquiryNameInput : null) ||
        selectedBanner ||
        formProductSelect ||
        enquiryMessage;

      if (focusTarget && typeof focusTarget.focus === 'function') {
        try {
          focusTarget.focus({ preventScroll: true });
        } catch (_) {
          if (focusTarget === selectedBanner) {
            focusTarget.focus();
          }
        }
      }
    }
  }

  function clearProductSelection() {
    selectedProductItem = null;
    if (selectedBanner) {
      selectedBanner.style.display = 'none';
      selectedBanner.hidden = true;
    }
    if (selectedNameElem) {
      selectedNameElem.textContent = '';
    }
    if (selectedPriceElem) {
      selectedPriceElem.textContent = '';
    }
    if (formProductSelect) {
      resetFormProductSelectLabels();
      formProductSelect.value = 'general';
      formProductSelect.selectedIndex = 0;
      syncFormProductSelectLabel();
    }
    updateRequirementsMessageForSelection('');
    invalidatePreparedEnquiryFeedback();
  }

  // ==========================================================================
  // CATEGORY SWITCHING & NAVIGATION ARIA STATE
  // ==========================================================================
  function updateCategoryNavigationState() {
    const pills = document.querySelectorAll('.filter-pill');
    pills.forEach(p => {
      const isActive = p.getAttribute('data-category') === currentCategory;
      p.classList.toggle('is-active', isActive);
      p.setAttribute('aria-pressed', String(isActive));
    });

    const allCategoryLinks = document.querySelectorAll('.category-tile[data-category], .footer-category-link[data-category], .mobile-nav-item[data-category]');
    allCategoryLinks.forEach(link => {
      const isActive = link.getAttribute('data-category') === currentCategory;
      link.classList.toggle('is-active', isActive);
      if (isActive) {
        link.setAttribute('aria-current', 'true');
      } else {
        link.removeAttribute('aria-current');
      }
    });
  }

  function setCategory(categoryId, options = {}) {
    const valid = CATALOGUE_DATA.categories.some(c => c.id === categoryId);
    currentCategory = valid ? categoryId : 'all';

    updateCategoryNavigationState();
    renderProducts();

    if (options.updateHistory !== false && typeof history !== 'undefined' && history.replaceState) {
      history.replaceState(null, null, `#category-${currentCategory}`);
    }
  }

  function scrollToCatalogueSection() {
    const catalogueAnchor = document.getElementById('catalogue');
    if (catalogueAnchor && typeof catalogueAnchor.scrollIntoView === 'function') {
      const prefersReducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      catalogueAnchor.scrollIntoView({
        behavior: prefersReducedMotion ? 'auto' : 'smooth',
        block: 'start'
      });
    }
  }

  function checkUrlHash() {
    const hash = window.location.hash;
    if (hash && hash.startsWith('#category-')) {
      const catId = hash.replace('#category-', '');
      const valid = CATALOGUE_DATA.categories.some(c => c.id === catId);
      if (valid) {
        if (searchInput && searchQuery.trim() !== '') {
          searchInput.value = '';
          searchQuery = '';
        }
        setCategory(catId, { updateHistory: false });
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

    window.addEventListener('resize', updateHeaderCollapseState);
    window.addEventListener('hashchange', checkUrlHash);

    const handleCategoryJumpClick = (link, e) => {
      e.preventDefault();
      const cat = link.getAttribute('data-category');
      if (cat) {
        if (searchInput && searchQuery.trim() !== '') {
          searchInput.value = '';
          searchQuery = '';
        }
        setCategory(cat);
        scrollToCatalogueSection();
      }
    };

    categoryTiles.forEach(tile => {
      tile.addEventListener('click', (e) => handleCategoryJumpClick(tile, e));
    });

    footerCategoryLinks.forEach(link => {
      link.addEventListener('click', (e) => handleCategoryJumpClick(link, e));
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

    if (formProductSelect) {
      formProductSelect.addEventListener('change', () => {
        const selectedVal = formProductSelect.value;
        if (selectedVal === 'general') {
          clearProductSelection();
          return;
        }
        const resolved = resolveProductSelection(selectedVal);
        if (!resolved) return;
        selectProductForEnquiry(resolved, { scroll: false });
      });
    }

    if (mobileNavToggle) {
      mobileNavToggle.addEventListener('click', (e) => openMobileDrawer(e.currentTarget));
    }
    if (mobileDrawerClose) {
      mobileDrawerClose.addEventListener('click', () => closeMobileDrawer());
    }
    if (mobileBackdrop) {
      mobileBackdrop.addEventListener('click', () => closeMobileDrawer());
    }
    mobileNavLinks.forEach(link => {
      link.addEventListener('click', (e) => {
        const cat = link.getAttribute('data-category');
        if (cat) {
          e.preventDefault();
          if (searchInput && searchQuery.trim() !== '') {
            searchInput.value = '';
            searchQuery = '';
          }
          setCategory(cat);
          closeMobileDrawer({ restoreFocus: false });
          scrollToCatalogueSection();
          return;
        }
        closeMobileDrawer({ restoreFocus: false });
      });
    });

    policyTriggers.forEach(btn => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        const policyKey = btn.getAttribute('data-policy-trigger');
        openPolicyModal(policyKey, btn);
      });
    });

    if (policyModalClose) {
      policyModalClose.addEventListener('click', () => closePolicyModal());
    }
    if (policyModalBackdrop) {
      policyModalBackdrop.addEventListener('click', () => closePolicyModal());
    }

    window.addEventListener('keydown', handleGlobalKeydown);
    document.addEventListener('focusin', handleOverlayFocusIn);

    if (enquiryForm) {
      enquiryForm.addEventListener('submit', handleFormSubmit);

      const trackedFields = [
        enquiryNameInput,
        enquiryPhoneInput,
        enquiryEmailInput,
        enquiryPostcodeInput,
        enquiryMessage
      ].filter(Boolean);

      trackedFields.forEach(field => {
        const onFieldEdit = () => {
          invalidatePreparedEnquiryFeedback();
          if (field.getAttribute('aria-invalid') === 'true' || (enquiryFormError && !enquiryFormError.hidden)) {
            validateSingleField(field);
            syncFormErrorSummary();
          }
        };
        field.addEventListener('input', onFieldEdit);
        field.addEventListener('change', onFieldEdit);
      });

      const radioInputs = enquiryForm.querySelectorAll('input[name="pref_contact"]');
      radioInputs.forEach(radio => {
        radio.addEventListener('change', () => {
          updateContactMethodRequirements();
          invalidatePreparedEnquiryFeedback();
          const summaryVisible = Boolean(enquiryFormError && !enquiryFormError.hidden);
          if (summaryVisible) {
            [enquiryNameInput, enquiryPhoneInput, enquiryEmailInput, enquiryMessage]
              .filter(Boolean)
              .forEach(field => validateSingleField(field));
            syncFormErrorSummary();
          } else {
            if (enquiryPhoneInput && enquiryPhoneInput.getAttribute('aria-invalid') === 'true') {
              validateSingleField(enquiryPhoneInput);
            }
            if (enquiryEmailInput && enquiryEmailInput.getAttribute('aria-invalid') === 'true') {
              validateSingleField(enquiryEmailInput);
            }
            syncFormErrorSummary();
          }
        });
      });
    }
  }

  // ==========================================================================
  // OVERLAY ACCESSIBILITY: FOCUS TRAP, INERT BACKGROUND, ESCAPE & RESTORE FOCUS
  // ==========================================================================
  function isMobileDrawerOpen() {
    return Boolean(mobileDrawer && mobileDrawer.classList.contains('is-open'));
  }

  function isPolicyModalOpen() {
    return Boolean(policyModal && policyModal.classList.contains('is-open'));
  }

  function getActiveOverlay() {
    if (isPolicyModalOpen()) return policyModal;
    if (isMobileDrawerOpen()) return mobileDrawer;
    return null;
  }

  function setBackgroundInert(isInert) {
    const backgroundRegions = [skipLink, topBar, header, mainContent, footer].filter(Boolean);
    backgroundRegions.forEach(region => {
      if (isInert) {
        region.inert = true;
        region.setAttribute('inert', '');
        region.setAttribute('aria-hidden', 'true');
      } else {
        region.inert = false;
        region.removeAttribute('inert');
        region.removeAttribute('aria-hidden');
      }
    });
  }

  function getFocusableElements(container) {
    if (!container) return [];
    const candidates = Array.from(
      container.querySelectorAll(
        'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
      )
    );
    return candidates.filter(el => {
      if (el.disabled || el.hidden) return false;
      if (el.getAttribute('aria-hidden') === 'true') return false;
      if (el.inert || el.hasAttribute('inert')) return false;
      if (typeof window.getComputedStyle === 'function') {
        const style = window.getComputedStyle(el);
        if (style && (style.display === 'none' || style.visibility === 'hidden')) return false;
      }
      return true;
    });
  }

  function handleGlobalKeydown(e) {
    if (e.key === 'Escape') {
      if (isPolicyModalOpen()) {
        e.preventDefault();
        closePolicyModal();
        return;
      }
      if (isMobileDrawerOpen()) {
        e.preventDefault();
        closeMobileDrawer();
        return;
      }
      return;
    }

    if (e.key === 'Tab') {
      const activeOverlay = getActiveOverlay();
      if (!activeOverlay) return;

      const focusables = getFocusableElements(activeOverlay);
      if (focusables.length === 0) {
        e.preventDefault();
        return;
      }

      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      const active = document.activeElement;

      if (e.shiftKey) {
        if (active === first || !activeOverlay.contains(active)) {
          e.preventDefault();
          last.focus();
        }
      } else {
        if (active === last || !activeOverlay.contains(active)) {
          e.preventDefault();
          first.focus();
        }
      }
    }
  }

  function handleOverlayFocusIn(e) {
    const activeOverlay = getActiveOverlay();
    if (!activeOverlay || !e.target) return;
    if (!activeOverlay.contains(e.target)) {
      const focusables = getFocusableElements(activeOverlay);
      if (focusables.length > 0) {
        focusables[0].focus();
      }
    }
  }

  function openMobileDrawer(triggerElem) {
    if (!mobileDrawer || !mobileBackdrop) return;
    if (isPolicyModalOpen()) {
      closePolicyModal({ restoreFocus: false });
    }

    drawerReturnFocusElem =
      (triggerElem && typeof triggerElem.focus === 'function' ? triggerElem : null) ||
      (document.activeElement && typeof document.activeElement.focus === 'function' ? document.activeElement : null) ||
      mobileNavToggle;

    mobileDrawer.inert = false;
    mobileDrawer.removeAttribute('inert');
    mobileDrawer.setAttribute('aria-hidden', 'false');
    mobileDrawer.style.visibility = 'visible';
    if (mobileDrawerClose) {
      mobileDrawerClose.style.visibility = 'visible';
    }
    mobileDrawer.classList.add('is-open');
    mobileBackdrop.classList.add('is-open');
    if (mobileNavToggle) mobileNavToggle.setAttribute('aria-expanded', 'true');
    setBackgroundInert(true);
    document.body.style.overflow = 'hidden';

    if (typeof mobileDrawer.getBoundingClientRect === 'function') {
      mobileDrawer.getBoundingClientRect();
    }

    const focusDrawerTarget = () => {
      if (!isMobileDrawerOpen()) return;
      if (mobileDrawerClose) {
        mobileDrawerClose.focus();
      } else {
        const focusables = getFocusableElements(mobileDrawer);
        if (focusables.length > 0) focusables[0].focus();
      }
    };

    focusDrawerTarget();
    if (typeof window.requestAnimationFrame === 'function' && document.activeElement !== mobileDrawerClose) {
      window.requestAnimationFrame(focusDrawerTarget);
    }
  }

  function closeMobileDrawer(options = {}) {
    if (!mobileDrawer || !mobileBackdrop || !isMobileDrawerOpen()) return;
    const shouldRestoreFocus = options.restoreFocus !== false;
    const targetToFocus = drawerReturnFocusElem || mobileNavToggle;
    drawerReturnFocusElem = null;

    mobileDrawer.classList.remove('is-open');
    mobileBackdrop.classList.remove('is-open');
    mobileDrawer.style.visibility = '';
    if (mobileDrawerClose) {
      mobileDrawerClose.style.visibility = '';
    }
    mobileDrawer.inert = true;
    mobileDrawer.setAttribute('inert', '');
    mobileDrawer.setAttribute('aria-hidden', 'true');
    if (mobileNavToggle) {
      mobileNavToggle.setAttribute('aria-expanded', 'false');
    }

    if (!isPolicyModalOpen()) {
      setBackgroundInert(false);
      document.body.style.overflow = '';
    }

    if (shouldRestoreFocus && targetToFocus && typeof targetToFocus.focus === 'function') {
      targetToFocus.focus();
    }
  }

  // ==========================================================================
  // POLICY MODAL
  // ==========================================================================
  function openPolicyModal(policyKey, triggerElem) {
    const policy = POLICIES[policyKey];
    if (!policy || !policyModal) return;

    if (isMobileDrawerOpen()) {
      closeMobileDrawer({ restoreFocus: false });
    }

    modalReturnFocusElem =
      (triggerElem && typeof triggerElem.focus === 'function' ? triggerElem : null) ||
      (document.activeElement && typeof document.activeElement.focus === 'function' ? document.activeElement : null);

    if (policyModalTitle) policyModalTitle.textContent = policy.title;
    if (policyModalBody) policyModalBody.innerHTML = policy.content;

    policyModal.inert = false;
    policyModal.removeAttribute('inert');
    policyModal.setAttribute('aria-hidden', 'false');
    policyModal.classList.add('is-open');
    setBackgroundInert(true);
    document.body.style.overflow = 'hidden';

    if (policyModalClose) {
      policyModalClose.focus();
    } else {
      const focusables = getFocusableElements(policyModal);
      if (focusables.length > 0) focusables[0].focus();
    }
  }

  function closePolicyModal(options = {}) {
    if (!policyModal || !isPolicyModalOpen()) return;
    const shouldRestoreFocus = options.restoreFocus !== false;
    const targetToFocus = modalReturnFocusElem;
    modalReturnFocusElem = null;

    policyModal.classList.remove('is-open');
    policyModal.inert = true;
    policyModal.setAttribute('inert', '');
    policyModal.setAttribute('aria-hidden', 'true');

    if (!isMobileDrawerOpen()) {
      setBackgroundInert(false);
      document.body.style.overflow = '';
    }

    if (shouldRestoreFocus && targetToFocus && typeof targetToFocus.focus === 'function') {
      targetToFocus.focus();
    }
  }

  // ==========================================================================
  // ACCESSIBLE FORM VALIDATION (DYNAMIC CONTACT REQUIREMENTS & FORMAT VALIDITY)
  // ==========================================================================
  function getPreferredContactMethod() {
    const checkedRadio = enquiryForm
      ? enquiryForm.querySelector('input[name="pref_contact"]:checked')
      : document.querySelector('input[name="pref_contact"]:checked');
    return checkedRadio && checkedRadio.value ? checkedRadio.value : 'Telephone Call';
  }

  function isTelephoneRequired(contactMethod = getPreferredContactMethod()) {
    return contactMethod === 'Telephone Call' || contactMethod === 'WhatsApp';
  }

  function isEmailRequired(contactMethod = getPreferredContactMethod()) {
    return contactMethod === 'Email';
  }

  function setRequiredAttributeAndIndicator(inputElem, indicatorElem, isRequired) {
    if (inputElem) {
      inputElem.required = isRequired;
      if (isRequired) {
        inputElem.setAttribute('required', '');
        inputElem.setAttribute('aria-required', 'true');
      } else {
        inputElem.removeAttribute('required');
        inputElem.setAttribute('aria-required', 'false');
      }
    }
    if (indicatorElem) {
      if (isRequired) {
        indicatorElem.hidden = false;
        indicatorElem.removeAttribute('hidden');
        indicatorElem.style.display = '';
      } else {
        indicatorElem.hidden = true;
        indicatorElem.setAttribute('hidden', '');
        indicatorElem.style.display = 'none';
      }
    }
  }

  function updateContactMethodRequirements() {
    const contactMethod = getPreferredContactMethod();
    const phoneReq = isTelephoneRequired(contactMethod);
    const emailReq = isEmailRequired(contactMethod);

    setRequiredAttributeAndIndicator(enquiryNameInput, null, true);
    setRequiredAttributeAndIndicator(enquiryMessage, null, true);

    const phoneReqIndicator =
      document.getElementById('enquiryPhoneReq') ||
      (enquiryForm && enquiryForm.querySelector('label[for="enquiryPhone"] .req'));
    setRequiredAttributeAndIndicator(enquiryPhoneInput, phoneReqIndicator, phoneReq);

    const emailReqIndicator =
      document.getElementById('enquiryEmailReq') ||
      (enquiryForm && enquiryForm.querySelector('label[for="enquiryEmail"] .req'));
    setRequiredAttributeAndIndicator(enquiryEmailInput, emailReqIndicator, emailReq);
  }

  function isValidTelephone(val) {
    const trimmed = (val || '').trim();
    if (!trimmed) return false;
    if (!/^[+\d()\s.\-]+$/.test(trimmed)) return false;
    const digits = trimmed.replace(/\D/g, '');
    return digits.length >= 7 && digits.length <= 15;
  }

  function isValidEmailAddress(val, inputElem) {
    const trimmed = (val || '').trim();
    if (!trimmed) return false;
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(trimmed)) return false;
    if (inputElem && typeof inputElem.checkValidity === 'function') {
      inputElem.setCustomValidity('');
      if (!inputElem.checkValidity()) return false;
    }
    return true;
  }

  function setFieldValidationState(field, errorId, errorMessage) {
    if (!field) return true;
    const errorElem = errorId ? document.getElementById(errorId) : null;
    const isInvalid = Boolean(errorMessage);

    if (typeof field.setCustomValidity === 'function') {
      field.setCustomValidity(errorMessage || '');
    }

    if (isInvalid) {
      field.classList.add('is-invalid');
      field.setAttribute('aria-invalid', 'true');
      if (errorElem) {
        errorElem.textContent = errorMessage;
        errorElem.hidden = false;
        errorElem.style.display = 'block';
      }
    } else {
      field.classList.remove('is-invalid');
      field.removeAttribute('aria-invalid');
      if (errorElem) {
        errorElem.textContent = '';
        errorElem.hidden = true;
        errorElem.style.display = 'none';
      }
    }
    return !isInvalid;
  }

  function evaluateFieldValidity(field) {
    if (!field) return { valid: true, missing: false, fieldName: '', errorId: '', message: '' };
    const val = (field.value || '').trim();
    const contactMethod = getPreferredContactMethod();

    if (field === enquiryNameInput) {
      if (!val) {
        return {
          valid: false,
          missing: true,
          fieldName: 'full name',
          errorId: 'enquiryNameError',
          message: 'Enter your full name.'
        };
      }
      return { valid: true, missing: false, fieldName: 'full name', errorId: 'enquiryNameError', message: '' };
    }

    if (field === enquiryPhoneInput) {
      const phoneReq = isTelephoneRequired(contactMethod);
      if (!val) {
        if (phoneReq) {
          return {
            valid: false,
            missing: true,
            fieldName: 'telephone number',
            errorId: 'enquiryPhoneError',
            message: 'Enter your telephone number.'
          };
        }
        return { valid: true, missing: false, fieldName: 'telephone number', errorId: 'enquiryPhoneError', message: '' };
      }
      if (!isValidTelephone(val)) {
        return {
          valid: false,
          missing: false,
          fieldName: 'telephone number',
          errorId: 'enquiryPhoneError',
          message: 'Enter a valid telephone number, for example 020 8888 0322 or 07123 456789.'
        };
      }
      return { valid: true, missing: false, fieldName: 'telephone number', errorId: 'enquiryPhoneError', message: '' };
    }

    if (field === enquiryEmailInput) {
      const emailReq = isEmailRequired(contactMethod);
      if (!val) {
        if (emailReq) {
          return {
            valid: false,
            missing: true,
            fieldName: 'email address',
            errorId: 'enquiryEmailError',
            message: 'Enter your email address.'
          };
        }
        return { valid: true, missing: false, fieldName: 'email address', errorId: 'enquiryEmailError', message: '' };
      }
      if (!isValidEmailAddress(val, field)) {
        return {
          valid: false,
          missing: false,
          fieldName: 'email address',
          errorId: 'enquiryEmailError',
          message: 'Enter a valid email address, for example name@example.co.uk.'
        };
      }
      return { valid: true, missing: false, fieldName: 'email address', errorId: 'enquiryEmailError', message: '' };
    }

    if (field === enquiryMessage) {
      if (!val) {
        return {
          valid: false,
          missing: true,
          fieldName: 'requirements',
          errorId: 'enquiryMessageError',
          message: 'Enter your requirements.'
        };
      }
      return { valid: true, missing: false, fieldName: 'requirements', errorId: 'enquiryMessageError', message: '' };
    }

    return { valid: true, missing: false, fieldName: '', errorId: '', message: '' };
  }

  function validateSingleField(field) {
    const result = evaluateFieldValidity(field);
    if (field && result.errorId) {
      setFieldValidationState(field, result.errorId, result.message);
    }
    return result;
  }

  function formatMissingFieldsSummary(missingNames) {
    if (!missingNames || missingNames.length === 0) return '';
    if (missingNames.length === 1) {
      return `Enter your ${missingNames[0]} to prepare your email draft.`;
    }
    if (missingNames.length === 2) {
      return `Enter your ${missingNames[0]} and ${missingNames[1]} to prepare your email draft.`;
    }
    const allButLast = missingNames.slice(0, -1).join(', ');
    const last = missingNames[missingNames.length - 1];
    return `Enter your ${allButLast} and ${last} to prepare your email draft.`;
  }

  function buildErrorSummaryText(results) {
    const missingNames = [];
    const formatErrors = [];
    results.forEach(res => {
      if (!res.valid) {
        if (res.missing && res.fieldName) {
          missingNames.push(res.fieldName);
        } else if (res.message) {
          formatErrors.push(res.message);
        }
      }
    });
    const summaryParts = [];
    if (missingNames.length > 0) {
      summaryParts.push(formatMissingFieldsSummary(missingNames));
    }
    if (formatErrors.length > 0) {
      summaryParts.push(formatErrors.join(' '));
    }
    return summaryParts.join(' ');
  }

  function syncFormErrorSummary() {
    if (!enquiryFormError) return;
    const fields = [enquiryNameInput, enquiryPhoneInput, enquiryEmailInput, enquiryMessage].filter(Boolean);
    const invalidFields = fields.filter(f => f.getAttribute('aria-invalid') === 'true');
    if (invalidFields.length === 0) {
      enquiryFormError.textContent = '';
      enquiryFormError.hidden = true;
      enquiryFormError.style.display = 'none';
      return;
    }
    if (!enquiryFormError.hidden) {
      const activeInvalidResults = invalidFields.map(f => evaluateFieldValidity(f)).filter(r => !r.valid);
      const summaryText = buildErrorSummaryText(activeInvalidResults);
      if (summaryText) {
        enquiryFormError.textContent = summaryText;
      } else {
        enquiryFormError.textContent = '';
        enquiryFormError.hidden = true;
        enquiryFormError.style.display = 'none';
      }
    }
  }

  function validateEnquiryForm() {
    updateContactMethodRequirements();
    const fields = [enquiryNameInput, enquiryPhoneInput, enquiryEmailInput, enquiryMessage].filter(Boolean);
    let firstInvalidField = null;
    const results = [];

    fields.forEach(field => {
      const result = validateSingleField(field);
      results.push(result);
      if (!result.valid && !firstInvalidField) {
        firstInvalidField = field;
      }
    });

    if (firstInvalidField) {
      const summaryText = buildErrorSummaryText(results);

      if (enquiryFormError) {
        enquiryFormError.textContent = summaryText;
        enquiryFormError.hidden = false;
        enquiryFormError.style.display = 'block';
      }

      if (typeof firstInvalidField.focus === 'function') {
        firstInvalidField.focus();
      }
      return false;
    }

    if (enquiryFormError) {
      enquiryFormError.textContent = '';
      enquiryFormError.hidden = true;
      enquiryFormError.style.display = 'none';
    }
    return true;
  }

  // ==========================================================================
  // TRUTHFUL ENQUIRY SUBMISSION: OPENS PREFILLED MAILTO & SHOWS TEXT SUMMARY
  // ==========================================================================
  function handleFormSubmit(e) {
    e.preventDefault();

    if (!validateEnquiryForm()) {
      invalidatePreparedEnquiryFeedback();
      return;
    }

    const name = enquiryNameInput ? enquiryNameInput.value.trim() : '';
    const phone = enquiryPhoneInput ? enquiryPhoneInput.value.trim() : '';
    const email = enquiryEmailInput ? enquiryEmailInput.value.trim() : '';
    const addressArea = enquiryPostcodeInput ? enquiryPostcodeInput.value.trim() : '';
    const message = enquiryMessage ? enquiryMessage.value.trim() : '';
    const contactMethod = getPreferredContactMethod();

    let itemInfo = 'Furniture Package, Multiple Items or General Enquiry';
    if (selectedProductItem) {
      itemInfo = `${formatSelectedItemLabel(selectedProductItem)} (£${selectedProductItem.price})`;
    } else if (formProductSelect && formProductSelect.value !== 'general') {
      const resolved = resolveProductSelection(formProductSelect.value);
      if (resolved) {
        selectedProductItem = resolved;
        itemInfo = `${formatSelectedItemLabel(resolved)} (£${resolved.price})`;
      }
    }

    // Compose email body
    const emailBody = [
      `Enquiry for GBA Furniture (401 Lordship Lane, London, N17 6AE)`,
      `--------------------------------------------------`,
      `Customer Name: ${name}`,
      `Telephone: ${phone || 'Not provided'}`,
      `Email: ${email || 'Not provided'}`,
      `Property Postcode: ${addressArea || 'Not specified'}`,
      `Preferred Contact Method: ${contactMethod}`,
      `Item of Interest: ${itemInfo}`,
      ``,
      `Message / Requirements:`,
      message
    ].join('\n');

    const subject = `Catalogue Enquiry: ${itemInfo} - ${name}`;
    const mailtoUrl = `mailto:info@gbafurniture.com?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(emailBody)}`;

    // Show honest feedback section
    if (feedbackSummaryText) {
      feedbackSummaryText.textContent = emailBody;
    }

    if (enquiryFeedback) {
      enquiryFeedback.hidden = false;
      enquiryFeedback.style.display = 'block';
      const prefersReducedMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      if (typeof enquiryFeedback.scrollIntoView === 'function') {
        enquiryFeedback.scrollIntoView({ behavior: prefersReducedMotion ? 'auto' : 'smooth', block: 'nearest' });
      }
    }

    const showCopyFailure = () => {
      const failureText = 'We couldn’t copy the enquiry. Select the text below and copy it into your email.';
      if (copyFeedbackMessage) {
        copyFeedbackMessage.textContent = failureText;
        copyFeedbackMessage.style.display = 'block';
      } else if (copyEnquiryBtn) {
        copyEnquiryBtn.textContent = failureText;
      }
    };

    if (copyEnquiryBtn) {
      copyEnquiryBtn.textContent = 'Copy Enquiry Text';
      if (copyFeedbackMessage) {
        copyFeedbackMessage.textContent = '';
        copyFeedbackMessage.style.display = 'none';
      }
      copyEnquiryBtn.onclick = () => {
        if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
          navigator.clipboard.writeText(emailBody).then(() => {
            if (copyFeedbackMessage) {
              copyFeedbackMessage.textContent = '';
              copyFeedbackMessage.style.display = 'none';
            }
            copyEnquiryBtn.textContent = 'Enquiry Copied';
            setTimeout(() => {
              copyEnquiryBtn.textContent = 'Copy Enquiry Text';
            }, 2500);
          }).catch(() => {
            showCopyFailure();
          });
        } else {
          showCopyFailure();
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
