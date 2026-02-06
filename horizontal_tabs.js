// Floorp Horizontal Tabs — JS
// Loaded by autoconfig bootstrap via Services.scriptloader.loadSubScript
// Scope: browser window (window, document available directly)

(function() {
  "use strict";

  var MAX_NORMAL_TABS = 18;

  var doc = document;
  var ptc = doc.getElementById("pinned-tabs-container");
  var tabs = doc.getElementById("tabbrowser-tabs");
  var box = doc.getElementById("tabbrowser-arrowscrollbox");
  var tabsToolbar = doc.getElementById("TabsToolbar");
  var verticalTabs = doc.getElementById("vertical-tabs");
  var newTabBtn = doc.getElementById("vertical-tabs-newtab-button");
  var sidebarMain = doc.getElementById("sidebar-main");

  // --- XUL orient attributes (CSS cannot override) ---

  if (ptc) ptc.setAttribute("orient", "horizontal");
  if (tabs) tabs.setAttribute("orient", "horizontal");
  if (box) box.setAttribute("orient", "horizontal");

  // --- Shadow DOM: disable scrollbox scrolling ---
  // scrollbox has no part attribute — CSS ::part() cannot reach it

  if (box && box.shadowRoot) {
    var scrollbox = box.shadowRoot.querySelector("scrollbox");
    if (scrollbox) {
      scrollbox.style.setProperty("overflow", "hidden", "important");
    }
  }

  // --- DOM relocation ---

  if (tabsToolbar && verticalTabs) {
    tabsToolbar.appendChild(verticalTabs);
  }

  if (newTabBtn && sidebarMain) {
    newTabBtn.after(sidebarMain);
  }

  // --- Filler element (bridges horizontal border gap near splitter) ---

  if (box && box.parentElement) {
    var filler = doc.createElement("div");
    filler.id = "htabs-grid-filler";
    box.parentElement.insertBefore(filler, box);
  }

  // --- Sidebar Shadow DOM styling ---

  if (sidebarMain) {
    var innerSidebar = sidebarMain.querySelector("sidebar-main");
    if (innerSidebar && innerSidebar.shadowRoot) {
      var wrapper = innerSidebar.shadowRoot.querySelector(".wrapper");
      if (wrapper) {
        var buttonsWrapper = wrapper.querySelector(".buttons-wrapper");
        if (buttonsWrapper) {
          buttonsWrapper.style.setProperty("flex-direction", "column", "important");
          buttonsWrapper.style.setProperty("margin-top", "8px", "important");
        }

        var buttonGroup = wrapper.querySelector("button-group");
        if (buttonGroup) {
          buttonGroup.style.setProperty("display", "grid", "important");
          buttonGroup.style.setProperty("grid-template-columns", "repeat(3, 38px)", "important");
          buttonGroup.style.setProperty("grid-template-rows", "repeat(2, 38px)", "important");
          buttonGroup.style.setProperty("gap", "0", "important");

          buttonGroup.querySelectorAll("moz-button").forEach(function(btn) {
            btn.style.cssText = "visibility: visible; width: 38px !important; height: 38px !important;";
            var inner = btn.shadowRoot && btn.shadowRoot.querySelector("button");
            if (inner) {
              inner.style.setProperty("height", "38px", "important");
              inner.style.setProperty("min-height", "38px", "important");
              inner.style.setProperty("padding", "1px", "important");
            }
          });
        }

        var splitter = wrapper.querySelector("splitter");
        if (splitter) {
          splitter.style.setProperty("display", "none", "important");
        }
      }
    }
  }

  // --- MutationObserver (single, debounced via rAF) ---

  if (tabs) {
    var rafPending = false;

    function scheduleUpdate() {
      if (rafPending) return;
      rafPending = true;
      requestAnimationFrame(function() {
        rafPending = false;

        // Remove ghost tabs
        doc.querySelectorAll(".tabbrowser-tab:not([pinned]):not([fadein])").forEach(function(t) {
          t.remove();
        });

        // Sync new-tab button visibility
        if (newTabBtn) {
          var count = doc.querySelectorAll(".tabbrowser-tab:not([pinned])[fadein]").length;
          if (count >= MAX_NORMAL_TABS) {
            newTabBtn.setAttribute("data-htabs-hidden", "");
          }
          else {
            newTabBtn.removeAttribute("data-htabs-hidden");
          }
        }

        // Sync pinned container min-width
        if (ptc) {
          var pinnedCount = doc.querySelectorAll(".tabbrowser-tab[pinned]").length;
          var columns = Math.ceil(pinnedCount / 3);
          var minWidth = Math.max(160, columns * 40);
          ptc.style.setProperty("min-width", minWidth + "px", "important");
        }
      });
    }

    scheduleUpdate();

    new MutationObserver(scheduleUpdate).observe(tabs, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["fadein", "pinned"]
    });
  }
})();
