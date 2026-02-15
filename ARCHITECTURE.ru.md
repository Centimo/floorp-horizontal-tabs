# Архитектура (variant-2-system)

## Почему autoconfig.cfg, а не userChrome.css / WebExtension

| Подход | Проблема |
|---|---|
| **userChrome.css** | Не может менять XUL-атрибут `orient`, переносить элементы в DOM, стилизовать внутренности Shadow DOM напрямую |
| **WebExtension** | API не предоставляет доступ к XUL DOM браузера. Невозможно модифицировать `#tabbrowser-tabs`, `#pinned-tabs-container` и другие chrome-элементы |
| **autoconfig.cfg** | Выполняется в привилегированном chrome-контексте с полным доступом к DOM, XPCOM, Services. Единственный способ без форка браузера |

## Механизм загрузки

```
[Старт Floorp]
  │
  ├─ Читает /usr/lib/floorp/defaults/pref/autoconfig.js
  │    └─ pref("general.config.filename", "autoconfig.cfg")
  │
  ├─ Выполняет /usr/lib/floorp/autoconfig.cfg (однократно, глобально)
  │    ├─ Читает horizontal_tabs.css в переменную
  │    └─ Регистрирует observer на "chrome-document-global-created"
  │
  └─ [Открытие каждого окна браузера]
       │
       ├─ Observer получает событие
       ├─ waitForElement(#tabbrowser-tabs, 5s)
       └─ initHorizontalTabs(doc, win)
            ├─ Feature detection (sidebar.verticalTabs)
            ├─ Запуск 8 модулей последовательно
            └─ Регистрация unload-очистки
```

## Модули

Каждый модуль — отдельная функция `module*(doc, win, cleanup)`. Падение одного модуля (try/catch) не затрагивает остальные. Модули, создающие MutationObserver или event listener, регистрируют cleanup-callback для очистки при закрытии окна.

### 1. moduleInjectCSS

Инжектирует содержимое `horizontal_tabs.css` как элемент `<style id="htabs-styles">` в `document.head`. Проверяет дубликат перед вставкой.

### 2. moduleOrientFix

Устанавливает `orient="horizontal"` на четырёх контейнерах (`pinned-tabs-container`, `tabbrowser-tabs`, `tabbrowser-arrowscrollbox`, `vertical-pinned-tabs-splitter`).

**Проблема:** Floorp сбрасывает `orient` обратно в `"vertical"` после нашей инициализации.
**Решение:** MutationObserver на атрибуте `orient` — при изменении принудительно возвращает `"horizontal"`.

### 3. moduleInlineStyles

Устанавливает `height` и `max-height` через `style.setProperty()` на контейнерах вкладок. Необходимо потому, что Firefox/Floorp применяет собственные inline-стили с высоким приоритетом, которые CSS `!important` из `<style>` не может переопределить.

### 4. moduleShadowScrollbox

Устанавливает `overflow: hidden` на элементе `<scrollbox>` внутри Shadow DOM контейнеров `#tabbrowser-arrowscrollbox` и `#pinned-tabs-container`. Элемент `<scrollbox>` не имеет атрибута `part`, поэтому CSS `::part()` до него не дотянется.

### 5. moduleDomRelocation

Переносит DOM-элементы:
- `#vertical-tabs` → внутрь `#TabsToolbar` (из sidebar наверх)
- `#sidebar-main` → после `#vertical-tabs-newtab-button` (кнопки расширений рядом с "+" )

### 6. moduleStyleSidebar

Стилизует Shadow DOM элемента `#sidebar-main`:

```
#sidebar-main (Light DOM)
  └─ sidebar-main (Custom Element)
       └─ shadowRoot
            ├─ <style id="htabs-sidebar-style">  ← мы инжектируем
            └─ .wrapper
                 ├─ .buttons-wrapper
                 │    └─ button-group
                 │         └─ moz-button × N
                 │              └─ shadowRoot
                 │                   └─ <button>  ← стилизуем через CSS custom properties
                 └─ splitter  ← скрываем
```

**Проблема:** Inner `<button>` внутри `moz-button` имеет padding из CSS custom properties (`--button-outer-padding-*`), установленных в `chrome://global/content/elements/moz-button.css`.
**Решение:** Обнуляем эти custom properties на `moz-button` — они наследуются внутрь его Shadow DOM.

**Проблема:** Floorp устанавливает `hidden=true` на `#sidebar-main` после нашей инициализации.
**Решение:** MutationObserver на атрибуте `hidden`.

**Проблема:** Shadow DOM sidebar может быть не готов к моменту вызова модуля.
**Решение:** `tryApply()` — retry до 15 раз с интервалом 200мс (3 секунды).

### 7. moduleTabObserver

MutationObserver + resize listener для динамических задач:

- **Удаление ghost tabs** — вкладки без атрибута `[fadein]` (закрытые, но не убранные из DOM Floorp'ом)
- **Разметка первого столбца** — атрибут `[data-htabs-firstcol]` для CSS-градиента на левой границе
- **Разметка последней строки** — атрибут `[data-htabs-lastrow]` для скрытия нижней границы
- **Видимость кнопки «+»** — скрывается когда `normalTabs.length >= cols × 3`
- **min-width pinned-контейнера** — подстраивается под количество закреплённых вкладок

Селекторы `:nth-child()` не работают для первого столбца и последней строки в `grid-auto-flow: row dense` (количество колонок динамическое), поэтому используются JS-управляемые data-атрибуты.

### 8. moduleTabDragFix

Monkey-patch на `tabsEl.tabDragAndDrop` для drag-and-drop в 2D-сетке.

Firefox нативно поддерживает 2D drag-and-drop только для pinned tabs в расширенном grid-режиме (`_animateExpandedPinnedTabMove`). Для обычных вкладок используется 1D `_animateTabMove`, который не работает в нашей сетке.

**Что патчится:**

| Метод | Зачем |
|---|---|
| `_isContainerVerticalPinnedGrid` | Возвращает `true` и для обычных (не pinned) вкладок — включает 2D обработку |
| `startTabDrag` | Запоминает `_maxTabsPerRow` при начале drag |
| `_animateExpandedPinnedTabMove` | Для обычных вкладок — собственная реализация 2D drag |

**Алгоритм drop-позиции:**

1. Вычислить координаты курсора относительно grid origin (screenX/Y первой вкладки)
2. Определить ячейку сетки: `col = floor(dx / tabWidth)`, `row = floor(dy / tabHeight)`
3. Преобразовать в индекс: `newDropIdx = row * maxPerRow + col`
4. Конвертировать виртуальный индекс в `dropFilteredIdx` (с учётом слота dragged tab)
5. Вычислить сдвиги соседних вкладок (`getTabShift`) с учётом переноса строк
6. Установить `dropElement` / `dropBefore` для финального `moveTabs()` Firefox

## CSS-раскладка

### Обычные вкладки

```css
#tabbrowser-arrowscrollbox::part(items-wrapper) {
  display: grid;
  grid-template-rows: repeat(3, 40px);
  grid-template-columns: repeat(auto-fill, 150px);
  grid-auto-flow: row dense;
}
```

`auto-fill` — количество колонок определяется доступной шириной.
`row dense` — вкладки заполняются по строкам (слева направо, сверху вниз).

### Закреплённые вкладки

```css
#pinned-tabs-container::part(items-wrapper) {
  display: grid;
  grid-template-rows: repeat(3, 40px);
  grid-template-columns: repeat(auto-fill, 40px);
  grid-auto-flow: column dense;
}
```

`column dense` — заполнение по столбцам (для pinned оно интуитивнее).

### Визуальная структура панели

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

## Очистка ресурсов

Все MutationObservers и event listeners регистрируются в массиве `cleanup[]`, который передаётся модулям. При закрытии окна (`win.addEventListener("unload")`) все callbacks вызываются, предотвращая memory leaks.

## Отладка

### Browser Console

`Ctrl+Shift+J` — все ошибки модулей выводятся с префиксом `htabs`.

### Remote debugging

Запуск Floorp с debug-портом:

```bash
floorp --remote-debugging-port=6000
```

Выполнение JS в chrome-контексте через скрипт `run_js.py` (не входит в проект):

```bash
python3 run_js.py "document.getElementById('tabbrowser-tabs').getAttribute('orient')"
```

### Диагностические prefs

В `about:config` по фильтру `htabs.diag` видны стадии инициализации (описаны в README.md).
