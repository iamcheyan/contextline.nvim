# Hierarchy menu left alignment

Clicking a breadcrumb segment in the winbar opens a borderless dropdown
under that segment. The dropdown's left edge must sit on the left edge of
the chip above it — always flush left, never nudged to "fit" the screen.

This note records why that alignment kept failing, and why the current
code no longer measures the screen cell by cell.

## Symptom

The winbar shows a path of clickable segments, for example:

```text
[icon] WS-OUT-COUNT  >  [icon] PIC 9(05)  >  [icon] 5 B
```

After a click, the active segment is redrawn as a `Pmenu`-coloured chip
(`ContextlineActiveMenu`). The dropdown should share that chip's left
edge:

```text
        ┌──────────────── chip ────────────────┐
  …  >  │ [icon] WS-EOF-FLAG                   │  >  …
        ├──────────────────────────────────────┤
        │ [icon] 01 INPUT-LINE            :19  │
        │ [icon] 01 WS-EOF-FLAG           :25  │
        └──────────────────────────────────────┘
```

What actually happened:

- the first segment was often off by a column or two (Heirline's leading
  pad, plus a leading space inside the dropdown);
- a middle segment such as `WS-EOF-FLAG` opened a menu that sat near the
  **window's** left edge, not under the chip.

The offset grew with how far right the clicked segment was. ASCII-only
fixtures hid the bug; Nerd Font icons made it obvious.

## What "flush left" means

The visual object above the menu is the highlighted chip, not the icon
glyph and not the mouse cursor.

`format()` wraps the active segment as:

```text
" " .. icon .. " " .. text .. " "
```

with highlight group `ContextlineActiveMenu`. The dropdown lines also
start with one space. Aligning the float to the chip's first cell lines
the two leading spaces up, so the icons line up as well.

The float uses `relative = "win"`, `row = 0`, `col = <chip start>`.
`col` is 0-based and measured in **display cells** from the left of the
window, which is also where the winbar starts (over the number/sign
column, not after `textoff`).

## Why the earlier approaches failed

Several patches tried to lock the column by inspecting the already-drawn
winbar. They failed for independent reasons that stacked.

### 1. Byte index used as a screen column

The keyboard path built a string from `screenchar()` / `nr2char()` per
cell, then:

```lua
local p = row_text:find(search_text, 1, true)  -- byte index
local c = p                                   -- treated as a column
```

Lua `string.find` returns a **byte** offset. A Nerd Font icon such as
`󰅪` (U+F016A) is 4 UTF-8 bytes and 1 display cell. The separator ``
is 3 bytes and 1 cell. Each icon to the left of the click added 2–3
phantom columns.

Worked example, clicking segment 2 (`TWO`) with a one-cell Heirline pad:

```text
display:  [pad][󰅪 ONE][  ][󰆧 TWO][  ][󰎠 THREE]
bytes:    1 + 4+1+3 + 1+3+1 + 4+1+3 ...
```

`find("TWO")` landed several cells to the right of the real glyph. The
backward scan then hit the **following** separator and parked the menu
under the next segment — or, if the match failed, returned column 0.

ASCII icons (`A`, `B`, `C`) keep byte length equal to display width
except for the separator, so a short name like `TWO` still sat inside
the same segment and the test stayed green. Production icons do not.

### 2. `getmousepos().wincol` is the wrong origin for this job

The click handler stored `getmousepos().wincol` and scanned backward
until a separator code point.

That path is fragile even when `screenchar()` returns a full Unicode
value (Neovim does; classic Vim returned only the first byte):

- a winbar click is not on buffer text; `line` / `column` are 0, and
  `wincol` may not share the same origin as `nvim_open_win` `relative=win`;
- Heirline draws a pad cell before the first segment, so a scan that
  never sees a separator walks to column 1 and reports 0;
- the active chip is redrawn **after** the click, adding a leading
  space, so a click near the left of a segment can land on the previous
  separator after redraw.

The mouse path therefore either returned 0 (menu glued to the window
left — the `WS-EOF-FLAG` screenshot) or the start of a neighbouring
segment.

### 3. Overflow moved `col` instead of shrinking width

```lua
if col_offset + win_width > vim.o.columns - 2 then
  col_offset = math.max(0, vim.o.columns - win_width - 2)
end
```

Two mistakes:

- `col_offset` is window-relative; `vim.o.columns` is the editor width.
  A right split compared the wrong origin.
- `win_width` was derived from `#line` (bytes). Inflated width triggered
  the clamp even when the menu visually fitted, and the clamp **broke
  left alignment** to keep the right edge on screen.

The required behaviour is: keep the left edge; if the menu would run
off the screen, reduce `width` only.

### 4. Summing `strdisplaywidth` of preceding segments

An earlier version added the display width of every piece before the
clicked index. That ignores:

- Heirline / lualine cells to the left of the contextline component;
- `%<` truncation from the left when the path is too long;
- the extra spaces the active chip inserts on redraw.

It is a model of our format string, not of the pixels the user sees.

## Current fix

Do not read the screen grid. Ask Neovim for the winbar's evaluated
layout, then take the display column of the highlight the user can see.

Entry point: `menu.win_col_for_segment(src_win)` in
`lua/contextline/menu.lua`.

### Primary path

1. `M.open` sets `_active_menu_segment` / `_active_menu_win` and
   redraws, so `format()` emits `%#ContextlineActiveMenu# … %*` on the
   clicked piece.
2. Evaluate the window's actual `'winbar'` with
   `nvim_eval_statusline(..., { use_winbar = true, highlights = true })`.
3. Find the first highlight whose `groups` contain
   `ContextlineActiveMenu`.
4. `start` is a 0-based **byte** index into the evaluated `str`. Convert
   with `strdisplaywidth(str:sub(1, start))`. That number is the
   0-based display column of the chip, including any pad Heirline drew
   before the component.

`nvim_eval_statusline` is the same pipeline Neovim uses to paint the
winbar. Clickable `%@...@` wrappers and `%#...#` codes take no width.
This works in headless tests.

### Fallback path

Heirline components with an `update = { "CursorMoved", ... }` list may
return a cached winbar that does not yet contain
`ContextlineActiveMenu`. Then:

1. Evaluate `contextline.get({ winid = src_win })` ourselves (we control
   the active flag) and read the chip column inside that string
   (`inner`).
2. Temporarily clear the active flag and evaluate both the plain
   contextline string and the full `'winbar'`.
3. `stridx(full, plain)` finds where the component sits; the display
   width of that prefix is Heirline's pad (and anything else to the
   left).
4. Return `prefix + inner`.

Matching against the **inactive** rendering is required: the active chip
inserts extra spaces, so a substring search for the active string would
miss a cached inactive winbar.

### Overflow and menu width

```lua
screen_left = (wininfo.wincol - 1) + col_offset
if screen_left + win_width > vim.o.columns - 2 then
  win_width = math.max(8, vim.o.columns - 2 - screen_left)
end
```

`col_offset` is never rewritten. Menu line length uses
`strdisplaywidth`, not `#`, so the float is not several cells too wide
from 4-byte icons.

## First click vs second click

A later failure looked like this:

1. First click: the dropdown opens, but the winbar segment is **not**
   drawn as a chip, and the menu column may be off.
2. Second click on the same segment: the chip appears and the menu
   snaps flush left.

Two independent stale-state bugs stacked. Both only show up when the
winbar is a cached Heirline component (`update = { "CursorMoved", ... }`)
and the dropdown float takes focus.

### Heirline cache

Heirline stores the last evaluated winbar per window until one of the
`update` events fires. A mouse click on the winbar is **not**
`CursorMoved`. `redraw` / `redrawstatus` therefore repaint the **cached
inactive string**. `nvim_eval_statusline` of `'winbar'` goes through
`heirline.eval_winbar()`, hits the same cache, and does not see
`ContextlineActiveMenu`. Placement then falls back; the chip never
paints.

Opening the float (`nvim_open_win(..., enter = true)`) fires `BufEnter`
on the menu buffer, which **does** clear Heirline's `_win_cache`. The
second click therefore rebuilds the winbar with the active flag set, so
the chip and the column are both correct.

`menu.open` / `menu.close` now call `refresh_winbar()`: broadcast
`self._win_cache = nil` on Heirline's winbar tree (if Heirline is
loaded), then `redrawstatus`. The first click rebuilds immediately.

### `get()` used the float, not the source window

Heirline's provider is `contextline.get({ separator = ... })` with no
`winid`. After the float is entered, `nvim_get_current_win()` is the
dropdown. Then:

- `get_info()` read the menu's `nofile` buffer and returned nothing;
- `format()` compared `_active_menu_win` to the float, so `is_active`
  was false even when the source winbar was being drawn.

Neovim sets `g:statusline_winid` to the window whose winbar is being
evaluated. `get_info()` and `format()` now resolve the drawing window
as: explicit `opts.winid`, else `g:statusline_winid`, else the current
window. The source window's chip stays on while the float is focused,
and other windows do not inherit it.

## Coordinates (keep these distinct)

| Value | Origin | Unit |
| --- | --- | --- |
| `nvim_eval_statusline` `highlights[].start` | evaluated winbar string | UTF-8 bytes, 0-based |
| `strdisplaywidth(prefix)` | same string | display cells |
| `nvim_open_win` `relative="win"` `col` | window left, including number/sign columns | display cells, 0-based |
| `getmousepos().wincol` | window; not used for placement | display cells, 1-based |
| `getwininfo().wincol` / `winrow` | screen | 1-based |
| Lua `#s` / `string.find` | string | bytes |

The winbar spans the full window width. `textoff` must **not** be added
on top of this `col`; that would shift the menu into the text area and
away from the chip.

## Tests

`tests/menu_align_spec.lua` (run from `tests/test.sh`):

- fake COBOL provider with real Nerd Font icons and a one-cell pad in
  `'winbar'`, matching Heirline;
- opens the menu on segments 1, 2, and 3 and asserts
  `nvim_win_get_config(menu).col` equals the `ContextlineActiveMenu`
  display column;
- a second case feeds a static inactive winbar (cached-component
  fallback) and asserts `win_col_for_segment` still reports that column;
- after `menu.open` (current window is the float), `get()` with no
  `winid` and `g:statusline_winid` set to the source window still emits
  `ContextlineActiveMenu`; another window's id does not.

A fixture that uses single-byte icons will not catch a byte/column mixup.
Keep the Nerd Font icons in this spec.

## If alignment regresses

1. Do not go back to `screenchar()` scanning or `string.find` as a
   column.
2. Check whether `'winbar'` still evaluates `contextline.get()` (or
   Heirline's wrapper around it). A different statusline plugin that
   puts other components after the breadcrumbs changes only the
   fallback prefix search, not the highlight path.
3. Confirm `ContextlineActiveMenu` is still applied before
   `nvim_open_win`. `M.open` must set `_active_menu_segment` first;
   `M.close` at the start of `open` clears it, then it is set again.
4. If the menu is left-aligned with the **window** rather than the chip,
   the helper returned 0: either the highlight was missing or the
   prefix search failed. Inspect `nvim_eval_statusline(vim.wo.winbar,
   { use_winbar = true, highlights = true })`.
5. If the menu is flush with the chip but the icons look one cell off,
   the dropdown's leading space and the chip's leading space have
   diverged — that is a format change in `format()` / menu line
   building, not a column bug.
6. If the **first** click has no chip and the **second** click does,
   Heirline is serving a cached winbar. Confirm `refresh_winbar()` still
   nils `_win_cache`, and that `get()` / `format()` still honour
   `g:statusline_winid` instead of the current window.
