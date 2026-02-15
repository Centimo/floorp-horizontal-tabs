# Architecture (variant-2-system)

[Документация на русском / Russian version](ARCHITECTURE.ru.md)

## Why autoconfig.cfg instead of userChrome.css / WebExtension

| Approach | Problem |
|---|---|
| **userChrome.css** | Cannot change the XUL `orient` attribute, relocate DOM elements, or style Shadow DOM internals directly |
| **WebExtension** | API does not provide access to the browser's XUL DOM. Cannot modify `#tabbrowser-tabs`, `#pinned-tabs-container`, or other chrome elements |
| **autoconfig.cfg** | Runs in privileged chrome context with full access to DOM, XPCOM, and Services. The only approach without forking the browser |

## Loading mechanism

```
[Floorp startup]
  │
  ├─ Reads /usr/lib/floorp/defaults/pref/autoconfig.js
  │    └─ pref("general.config.filename", "autoconfig.cfg")
  │
  ├─ Executes /usr/lib/floorp/autoconfig.cfg (once, globally)
  │    ├─ Reads horizontal_tabs.css into a variable
  │    └─ Registers observer for "chrome-document-global-created"
  │
  └─ [Each browser window opening]
       │
       ├─ Observer fires
       ├─ waitForElement(#tabbrowser-tabs, 5s)
       └─ initHorizontalTabs(doc, win)
            ├─ Feature detection (sidebar.verticalTabs)
            ├─ Runs 8 modules sequentially
            └─ Registers unload cleanup
```

## Modules

Each module is a standalone function `module*(doc, win, cleanup)`. A failure in one module (try/catch) does not affect the others. Modules that create MutationObservers or event listeners register cleanup callbacks that run when the window closes.

### 1. moduleInjectCSS

Injects the contents of `horizontal_tabs.css` as a `<style id="htabs-styles">` element in `document.head`. Checks for duplicates before insertion.

### 2. moduleOrientFix

Sets `orient="horizontal"` on four containers (`pinned-tabs-container`, `tabbrowser-tabs`, `tabbrowser-arrowscrollbox`, `vertical-pinned-tabs-splitter`).

**Problem:** Floorp resets `orient` back to `"vertical"` after our initialization.
**Solution:** MutationObserver on the `orient` attribute — forces `"horizontal"` on any change.

### 3. moduleInlineStyles

Sets `height` and `max-height` via `style.setProperty()` on tab containers. Necessary because Firefox/Floorp applies its own inline styles with high priority that CSS `!important` from a `<style>` element cannot override.

### 4. moduleShadowScrollbox

Sets `overflow: hidden` on the `<scrollbox>` element inside the Shadow DOM of `#tabbrowser-arrowscrollbox` and `#pinned-tabs-container`. The `<scrollbox>` element has no `part` attribute, so CSS `::part()` cannot reach it.

### 5. moduleDomRelocation

Relocates DOM elements:
- `#vertical-tabs` → inside `#TabsToolbar` (from sidebar to top)
- `#sidebar-main` → after `#vertical-tabs-newtab-button` (extension buttons next to "+")

### 6. moduleStyleSidebar

Styles the Shadow DOM of `#sidebar-main`:

```
#sidebar-main (Light DOM)
  └─ sidebar-main (Custom Element)
       └─ shadowRoot
            ├─ <style id="htabs-sidebar-style">  ← injected by us
            └─ .wrapper
                 ├─ .buttons-wrapper
                 │    └─ button-group
                 │         └─ moz-button × N
                 │              └─ shadowRoot
                 │                   └─ <button>  ← styled via CSS custom properties
                 └─ splitter  ← hidden
```

**Problem:** The inner `<button>` inside `moz-button` has padding from CSS custom properties (`--button-outer-padding-*`) defined in `chrome://global/content/elements/moz-button.css`.
**Solution:** Zero out these custom properties on `moz-button` — they inherit into its Shadow DOM.

**Problem:** Floorp sets `hidden=true` on `#sidebar-main` after our initialization.
**Solution:** MutationObserver on the `hidden` attribute.

**Problem:** The sidebar Shadow DOM may not be ready when the module runs.
**Solution:** `tryApply()` — retries up to 15 times at 200ms intervals (3 seconds total).

### 7. moduleTabObserver

MutationObserver + resize listener for dynamic tasks:

- **Ghost tab removal** — tabs without the `[fadein]` attribute (closed but not yet removed from DOM by Floorp)
- **First column marking** — `[data-htabs-firstcol]` attribute for the CSS gradient on the left border
- **Last row marking** — `[data-htabs-lastrow]` attribute for hiding the bottom border
- **"+" button visibility** — hidden when `normalTabs.length >= cols × 3`
- **Pinned container min-width** — adjusts to the number of pinned tabs

`:nth-child()` selectors don't work for the first column and last row with `grid-auto-flow: row dense` (column count is dynamic), so JS-managed data attributes are used instead.

### 8. moduleTabDragFix

Monkey-patch on `tabsEl.tabDragAndDrop` for drag-and-drop in a 2D grid.

Firefox natively supports 2D drag-and-drop only for pinned tabs in expanded grid mode (`_animateExpandedPinnedTabMove`). Regular tabs use 1D `_animateTabMove`, which doesn't work in our grid.

**What gets patched:**

| Method | Purpose |
|---|---|
| `_isContainerVerticalPinnedGrid` | Returns `true` for regular (non-pinned) tabs too — enables 2D handling |
| `startTabDrag` | Stores `_maxTabsPerRow` at drag start |
| `_animateExpandedPinnedTabMove` | Custom 2D drag implementation for regular tabs |

**Drop position algorithm:**

1. Compute cursor coordinates relative to grid origin (screenX/Y of the first tab)
2. Determine grid cell: `col = floor(dx / tabWidth)`, `row = floor(dy / tabHeight)`
3. Convert to index: `newDropIdx = row * maxPerRow + col`
4. Convert virtual index to `dropFilteredIdx` (accounting for the dragged tab's slot)
5. Calculate neighbor tab shifts (`getTabShift`) with row wrapping
6. Set `dropElement` / `dropBefore` for Firefox's final `moveTabs()`

## CSS layout

### Regular tabs

```css
#tabbrowser-arrowscrollbox::part(items-wrapper) {
  display: grid;
  grid-template-rows: repeat(3, 40px);
  grid-template-columns: repeat(auto-fill, 150px);
  grid-auto-flow: row dense;
}
```

`auto-fill` — column count is determined by available width.
`row dense` — tabs fill left-to-right, top-to-bottom.

### Pinned tabs

```css
#pinned-tabs-container::part(items-wrapper) {
  display: grid;
  grid-template-rows: repeat(3, 40px);
  grid-template-columns: repeat(auto-fill, 40px);
  grid-auto-flow: column dense;
}
```

`column dense` — column-first fill (more intuitive for pinned tabs).

### Visual panel structure

```
┌──────────────────────────────────────────────────────────────────────┐
│ #TabsToolbar                                                         │
│ ┌─────────┬───┬────────────────────────────┬───┬──────┬─────────────┐│
│ │ Pinned  │ S │     Normal tabs grid       │ + │ Side │ ⎯ □ ✕     ││
│ │ tabs    │ p │  [tab1] [tab2] [tab3] ...  │   │ bar  │            ││
│ │ grid    │ l │  [tab4] [tab5] [tab6] ...  │   │ btns │            ││
│ │ (icons) │ i │  [tab7] [tab8] [tab9] ...  │   │      │            ││
│ │         │ t │                             │   │      │            ││
│ └─────────┴───┴────────────────────────────┴───┴──────┴─────────────┘│
└──────────────────────────────────────────────────────────────────────┘
```

## Resource cleanup

All MutationObservers and event listeners are registered in a `cleanup[]` array passed to modules. When the window closes (`win.addEventListener("unload")`), all callbacks are invoked, preventing memory leaks.

## Debugging

### Browser Console

`Ctrl+Shift+J` — all module errors are logged with the `htabs` prefix.

### Remote debugging

Launch Floorp with a debug port:

```bash
floorp --remote-debugging-port=6000
```

Execute JS in chrome context via `run_js.py` script (not included in the project):

```bash
python3 run_js.py "document.getElementById('tabbrowser-tabs').getAttribute('orient')"
```

### Diagnostic prefs

In `about:config`, filter by `htabs.diag` to see initialization stages (described in README.md).
