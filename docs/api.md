# API reference

Every imlove function, grouped by area. This is the exhaustive reference; the
[README](../README.md) has the pitch, the quickstart, and the general
conventions these tables assume (labels double as identity, `value, changed =
Widget(...)` instead of pointer output params, and so on) — read those first
if you haven't.

Want to see all of this exercised at once? `imlove_demo.lua` (repo root) is a
companion file that builds a self-documenting "imlove Demo" window from
nothing but this public API — see its header comment, or run `love . demo`.

### Frame lifecycle

| Function | Description |
|---|---|
| `imlove.NewFrame()` | Start a UI frame. Call once per frame before any other imlove call — the top of `love.update` is the natural place. |
| `imlove.Render()` | Draw the UI. Call at the end of `love.draw`. Saves and restores the LÖVE graphics state around itself. |

### LÖVE callback forwards

Call each from the matching `love.*` callback. Every one returns `true` when
the UI consumed the event (= your game should ignore it).

| Function | Notes |
|---|---|
| `imlove.mousepressed(x, y, button)` | Required. |
| `imlove.mousereleased(x, y, button)` | Required. |
| `imlove.wheelmoved(dx, dy)` | Recommended: scrolls the window or `BeginChild()` region under the mouse, and reports the wheel as consumed over any window so your game doesn't zoom under the UI. |
| `imlove.keypressed(key, scancode, isrepeat)` | **Required as of v1.4** for `InputText`/`InputFloat`/`InputInt` (and ctrl-click-to-type on sliders/drags) to work at all — without it, a focused field can't see Backspace/Delete/arrows/Enter/Escape/Ctrl+C/Ctrl+V. LÖVE calls it with three arguments; the extra two are accepted and ignored. Returns `true` (consumed) whenever any field has keyboard focus, regardless of which key it is — check the return value (or `io.WantCaptureKeyboard`) before your game acts on a key, e.g. before Space pauses it. |
| `imlove.textinput(text)` | **Required as of v1.4**, same story as `keypressed` — this is what actually delivers typed characters. Returns `true` whenever any field has focus. |

| Flag | Meaning |
|---|---|
| `imlove.io.WantCaptureMouse` | After `NewFrame()`: the mouse is over/held by the UI this frame. Unconditionally `true` whenever any popup or modal is open, regardless of mouse position. A tooltip does **not** force this — like ImGui's, it's purely visual and never hit-testable, so showing one has no effect on input capture. |
| `imlove.io.WantCaptureKeyboard` | After `NewFrame()`: `true` while an `InputText`/`InputFloat`/`InputInt` — or a ctrl-clicked `SliderFloat`/`SliderInt`/`DragFloat`/`DragInt` — holds keyboard focus. `false` whenever nothing does, exactly as in v1-v1.3. |
| `imlove.io.FontDefault` | The default font for every widget, mirroring ImGui's `io.FontDefault`. `nil` (the default) means the library's own lazily-created 13px LÖVE font. Assign any LÖVE `Font` to replace it — the usual reason being symbol glyphs the built-in font lacks (▶, ⏸, ⏭ on debug buttons), via LÖVE's own `Font:setFallbacks`: create a base font, `setFallbacks` a symbol font onto it, and assign it here. Re-read (and validated) every `NewFrame()`, so it can be set or cleared at any time; `PushFont`/`PopFont` layer on top of it. The font is yours — don't `release()` it while the UI is using it. |

### Windows

| Function | Returns | Description |
|---|---|---|
| `imlove.Begin(title, open, flags)` | `notCollapsed, open` | Open a window. Draggable, collapsible, state persists by title. When it returns `false` the window is collapsed and widget calls are cheap no-ops — you may skip them, but you must **always** call `End()`. `open` is optional: `nil` (default) means no close button and a `nil` second return; a boolean adds an X to the title bar and the second return reports it back, possibly toggled to `false` the frame it's clicked (reassign it to your variable, like any other imlove value); passing `false` skips the window entirely for this frame — `Begin` returns `false, false` and every widget call inside becomes a no-op, but `End()` is still required. `flags` is a string or array of strings — see "Window flags" below; an unknown flag name is an error. |
| `imlove.End()` | — | Close the current window. Exactly one per `Begin`, collapsed or not. |
| `imlove.SetNextWindowPos(x, y, cond)` | — | Position the next `Begin`. `cond` is `"always"` (default) or `"once"` (only when the window is first created — use this for default layouts the user can still drag around). |
| `imlove.SetNextWindowSize(w, h, cond)` | — | Size the next `Begin` explicitly, taking it out of auto-fit mode: from then on the window keeps this size and overflowing content scrolls instead of growing it (see "Sizing model" below). `cond` is `"always"` (default) or `"once"`. Ignored by a window with the `"AlwaysAutoResize"` flag. |
| `imlove.SetNextWindowSnap(side, cond)` | — | Snap the next `Begin` to a screen edge: `side` is `"left"` or `"right"` — or `nil`, releasing a previous snap (see "Snapping" below). `cond` is `"always"` (default) or `"once"`, with the same meanings as `SetNextWindowPos`. Ignored by a window with the `"AlwaysAutoResize"` flag. |
| `imlove.GetWindowPos()` | `x, y` | Current window's position. |
| `imlove.GetWindowSize()` | `w, h` | Current window's size as of last frame (windows size themselves to their content at `End`, unless explicitly sized — see below). |
| `imlove.GetWindowSnap()` | `side` | Which edge the current window is snapped to: `"left"`, `"right"`, or `nil`. The programmatic counterpart to the drag gestures — the user may have snapped or freed the window themselves since your code last set it. |
| `imlove.BeginChild(idStr, w, h, border)` | `visible` | Begin a scrollable child region embedded at the cursor in the current window (or child): its own cursor, scroll position, and ID scope (pushes `idStr`), but no separate z-order — it draws into its root window's draw list. `w`/`h` &le; 0 mean, respectively, "remaining width" and a 200px default. `border`, if truthy, draws a border line around it. Must be matched by `EndChild()`; returns `false` only when an ancestor window/child is collapsed or otherwise skipping. |
| `imlove.EndChild()` | — | Close the current `BeginChild()` region. Exactly one per `BeginChild()` — `End()` errors if you forget it, and vice versa. |

#### Window flags

Passed to `Begin()` as a bare string or an array of strings, e.g. `imlove.Begin("Log", nil, "NoScrollbar")` or `imlove.Begin("HUD", nil, {"NoTitleBar", "NoMove"})`. An unknown flag name is an `error()`, not a silent no-op.

| Flag | Effect |
|---|---|
| `"NoTitleBar"` | No title bar: no drag region, no collapse arrow, no close button. Content starts at the window's top edge. |
| `"NoMove"` | The title bar no longer drags the window. |
| `"NoResize"` | No corner resize grip. |
| `"NoCollapse"` | No collapse arrow (the title bar still drags, if `"NoMove"` isn't also set). |
| `"AlwaysAutoResize"` | Always fits its content — no scrollbar, grip, or scrolling, ever. `SetNextWindowSize()` is ignored. This is the v1.1 behavior for every window. |
| `"NoScrollbar"` | Hides the scrollbar, but the mouse wheel still scrolls the window while it's hovered. |

#### Sizing model

A window auto-fits its content, exactly like v1.1, until it's given an explicit size — via `SetNextWindowSize()` or by the user dragging its resize grip. From that point on its size is sticky: it no longer grows or shrinks to fit content, and content taller than the window scrolls (by mouse wheel, or by dragging the scrollbar that appears automatically once content overflows). `"AlwaysAutoResize"` opts a window out of this permanently. `BeginChild()` regions are always fixed-size and scrollable — there's no auto-fit mode for a child.

#### Snapping

A **snapped** window (v1.6) is pinned to the left or right screen edge as a full-height side panel: `x`/`y` locked to the edge, height re-derived from the screen every frame (so an OS window resize is tracked for free), and only its width — the width it had the moment it snapped — stays its own. While snapped it has no collapse arrow and no resize grip, but its title bar still drags.

Two ways in, two ways out:

- **Gesture** — drag any window's title bar until the *mouse* is within `GetStyle().snapZone` (default 12) pixels of the left or right screen edge and release: it snaps there. While the mouse is inside a zone, a translucent full-height band (drawn under every window) previews where the window will pin; merely passing through the zone mid-drag does nothing until you release. Drag a snapped window's title bar away — once the mouse is outside the zone *and* has pulled more than `snapZone` pixels from where it grabbed, the window unsnaps immediately (restoring its pre-snap height, keeping its current width) and follows the drag. A plain click or sloppy wiggle on a snapped title bar leaves it snapped.
- **API** — `SetNextWindowSnap("left"/"right")` before `Begin()`, or `SetNextWindowSnap(nil)` to release. `cond = "once"` seeds a default the user can drag away for keeps; the default `"always"` re-asserts every frame, so a dragged-free window springs back on release — combine with the `"NoMove"` flag for a truly static side panel.

Snap state persists in the ini alongside position/size/collapsed (see "Settings persistence" below). This is deliberately edge *snapping*, not docking: no dock areas, no tabs, no splitters (see ROADMAP.md's non-goals).

### Widgets

| Function | Returns | Description |
|---|---|---|
| `imlove.Text(fmt, ...)` | — | Static text. Extra args go through `string.format`. `\n` makes multiple lines. |
| `imlove.TextColored(color, fmt, ...)` | — | Static text drawn in an explicit `{r, g, b, a}` color instead of the theme default. |
| `imlove.TextDisabled(fmt, ...)` | — | Static text dimmed to a muted gray, for de-emphasized captions. |
| `imlove.TextWrapped(fmt, ...)` | — | Static text that word-wraps to the window's available content width (one-frame lag, like the rest of layout). |
| `imlove.BulletText(fmt, ...)` | — | Static text prefixed with a small filled bullet. |
| `imlove.Button(label, w, h)` | `pressed` | `true` on the frame the button is clicked (mouse released over it). `w`/`h` are optional; 0 or nil on either axis auto-sizes that axis to the label. |
| `imlove.SmallButton(label)` | `pressed` | A `Button` with no vertical frame padding, for placing inline with a line of text. |
| `imlove.Checkbox(label, value)` | `value, changed` | Toggles on click. Assign the first return back to your variable. |
| `imlove.RadioButton(label, active)` | `pressed` | A circular Selectable. Pass whether it's the currently-chosen option (drawn with a filled dot); returns `true` on click. Switching the selection is up to you, same as `Selectable`. |
| `imlove.SliderFloat(label, value, min, max)` | `value, changed` | Horizontal slider; click or drag anywhere on the track. Assign the first return back. **Ctrl+click** turns it into a numeric text editor instead — type an exact value; Enter commits it (clamped to `min`/`max`), Escape reverts, clicking elsewhere just stops editing without committing. |
| `imlove.SliderInt(label, value, min, max)` | `value, changed` | Same contract as `SliderFloat`, stepped and displayed as `"%d"`, including ctrl-click-to-type (the committed value rounds to the nearest integer, same as dragging does). |
| `imlove.DragFloat(label, value, speed, min, max)` | `value, changed` | Click-and-drag horizontally to change the value by `speed` per pixel, instead of mapping the whole track to a fixed range. `speed` defaults to `1.0`; `min`/`max` are optional and independently nil-able (unbounded on that side). A click that doesn't move the mouse changes nothing — unlike `SliderFloat`, it never jumps to the clicked position. Ctrl+click turns it into a numeric text editor, exactly like `SliderFloat`, clamped only to whichever of `min`/`max` are given. |
| `imlove.DragInt(label, value, speed, min, max)` | `value, changed` | The integer counterpart of `DragFloat`; `speed` defaults to `1`, value rounds to the nearest integer. Ctrl+click-to-type rounds the same way. |
| `imlove.ProgressBar(fraction, w, h, overlay)` | — | A bar filled to `fraction` (clamped 0..1). `w`/`h` default to the slider width and frame height; `overlay` defaults to a centered `"NN%"` label. |
| `imlove.TreeNode(label)` | `open` | Collapsible node; open state persists. When `open`, children are indented and the label is pushed on the ID stack — call `TreePop()` after them. |
| `imlove.TreePop()` | — | Close the innermost open `TreeNode`. Call once per `TreeNode` that returned `true`. |
| `imlove.CollapsingHeader(label, defaultOpen)` | `open` | Like `TreeNode`, but full-width and framed, with no indent and no ID-stack push — no matching `TreePop()`. Open state persists. `defaultOpen` (optional, default `false`) only seeds the very first time this id is ever seen — like ImGui's `ImGuiTreeNodeFlags_DefaultOpen` — and never overrides whatever the user has since clicked it to. |
| `imlove.Selectable(label, selected)` | `clicked` | Full-width selectable row for pick-one-from-a-list UIs. You own the selection state. |
| `imlove.Separator()` | — | Horizontal line. |
| `imlove.Spacing()` | — | A blank vertical gap the size of one item spacing. |
| `imlove.NewLine()` | — | Forces the next widget onto a new row, even right after `SameLine()`. |
| `imlove.Dummy(w, h)` | — | Reserves a `w x h` blank rectangle in the layout — a spacer, or a stand-in for a widget you draw yourself. |
| `imlove.Indent(w)` | — | Shifts every following widget in this window right by `w` (default: the style's indent). A plain cursor shift, not an ID push — nests however you call it. |
| `imlove.Unindent(w)` | — | Undoes `Indent(w)`; pass the same `w`. |
| `imlove.SameLine(offsetFromStartX, spacing)` | — | Place the next widget on the same row as the previous one. With no arguments: right after the previous item plus one item spacing (v1 behavior, unchanged). `offsetFromStartX`, if non-zero, places it at that x offset from the window's content start instead. `spacing`, if given, overrides the default gap. |
| `imlove.PlotLines(label, values, scaleMin, scaleMax, w, h, overlay)` | — | A line-graph plot of `values` (a plain Lua array of numbers) — the canonical "FPS over time" widget. `scaleMin`/`scaleMax` default to the min/max found in `values`. `w`/`h` default to the slider width and three line-heights. `overlay`, if given, is centered on the plot instead of the label. |
| `imlove.PlotHistogram(label, values, scaleMin, scaleMax, w, h, overlay)` | — | Same signature and semantics as `PlotLines`, drawn as vertical bars instead of a connected line. |
| `imlove.Combo(label, value, items)` | `value, changed` | A slider-width preview box + arrow; click to open a dropdown of `Selectable`s built from `items` (a plain Lua array — its element order is the display order). **`value` is a 1-based index into `items`**, not a 0-based one — this is a deliberate deviation from ImGui, matching Lua's own array convention; assign the first return back. An out-of-range `value` (including `0` or `nil`) just shows an empty preview instead of erroring. |
| `imlove.ListBox(label, value, items, heightInItems)` | `value, changed` | An always-visible, scrollable list of `Selectable`s (a thin wrapper over `BeginChild`) — the alternative to `Combo` when you want every option visible without a click. Same 1-based `value` convention as `Combo`. `heightInItems` defaults to `7` visible rows; extra items scroll. |

### Text input

Requires wiring both `imlove.keypressed` and `imlove.textinput` to the
matching `love.*` callbacks (see "LÖVE callback forwards" above) — without
both, a focused field can't receive edits at all. A text/numeric field gains
keyboard focus when clicked, exactly like `activeId` but persistent across
frames until Enter (commit), Escape (revert), a click outside the field
(which is **not** consumed — it still reaches whatever it landed on), or the
field simply not being submitted for a frame (the same staleness rule that
closes a window/popup whose `Begin()`/`BeginPopup()` stops being called).
There is no selection in v1.4 — no shift-click, no double-click-to-select,
no partial copy — a deliberate, documented deviation from ImGui; see
`docs/imgui.md`.

| Function | Returns | Description |
|---|---|---|
| `imlove.InputText(label, text, flags)` | `text, changed` | A single-line text field. By default returns the live edit buffer with `changed = true` on every keystroke — assign it back like any other imlove value. Pass the `"EnterReturnsTrue"` flag for ImGui's other mode: keeps returning the OLD text (`changed = false`) while typing, and returns the new text with `changed = true` only once, the frame Enter commits it. Backspace/Delete/Left/Right/Home/End all work; text scrolls horizontally inside the frame so the cursor stays visible. Ctrl+V pastes at the cursor (`love.system.getClipboardText`); Ctrl+C copies the **whole field** — there's no selection, so no partial copy. `flags` is a string or array of strings. |
| `imlove.InputFloat(label, value, step)` | `value, changed` | `InputText` restricted to editing a float: the buffer parses on every keystroke — a successful `tonumber()` returns the parsed value with `changed = true`; an unparseable intermediate state (`""`, `"-"`, `"."`, ...) returns the last good value unchanged. Enter commits (parsing, or reverting if it doesn't parse); Escape always reverts. If `step` is given (and nonzero), small "-"/"+" buttons nudge the value by `step` directly, bypassing text parsing entirely — they work even while the field isn't focused. |
| `imlove.InputInt(label, value, step)` | `value, changed` | The integer counterpart of `InputFloat`: a typed value **floors** on commit (`"3.7"` commits as `3`, not rounds to `4`) — chosen so partial input like `"-"` or `"3."` never round-trips into visible jitter. Same `step` button behavior as `InputFloat`. |

### Popups & tooltips

Popups and modals draw in their own overlay layer, above every regular
window, and are hit-tested before them too — nothing you build in a normal
window can ever occlude or steal a click from one. Tooltips draw above even
that (see `SetTooltip()`), but are never hit-tested at all — they're purely
visual and never capture input.

| Function | Returns | Description |
|---|---|---|
| `imlove.SetTooltip(fmt, ...)` | — | A small auto-fit box with no title bar, positioned just past the mouse (clamped to stay on screen), that follows the mouse and is drawn above absolutely everything — including any open popup. Never hit-testable: hovering or clicking where it's drawn always reaches whatever is really underneath. Call it every frame you want it shown, typically right after `IsItemHovered()`. Calling it more than once in a frame replaces the previous call — only the last one shows. |
| `imlove.BeginTooltip()` / `imlove.EndTooltip()` | — | The manual form of `SetTooltip()`, for a tooltip with more than one widget in it. Must be paired with `EndTooltip()`; like `SetTooltip()`, calling this more than once in a frame is fine — "last call wins". |
| `imlove.OpenPopup(strId)` | — | Marks `strId`'s popup open. `strId` is resolved against the current ID stack exactly like a widget id, so call it from the same scope (window, `PushID`, or enclosing popup) as the matching `BeginPopup(strId)`. Typically called right after the button/item that should open it. |
| `imlove.BeginPopup(strId)` | `open` | Begin a popup opened with `OpenPopup(strId)`: a small floating, auto-fit, no-title-bar window, positioned where the mouse was when `OpenPopup()` was called (clamped to stay on screen). **Unlike `Begin()`/`End()`, call `EndPopup()` only when this returns `true`** — do not call it unconditionally. A press outside the topmost open popup closes it (and everything stacked above whatever it landed on, for nested popups) and that dismissing press is consumed — your game never sees it. |
| `imlove.EndPopup()` | — | Closes what a successful `BeginPopup()`/`BeginPopupModal()`/`BeginPopupContextItem()` opened. Calling it without a matching open popup is an `error()`, and so is leaving one open past `End()`/`EndChild()`/`Render()`. |
| `imlove.CloseCurrentPopup()` | — | Closes whichever popup's content is currently being built. Call it from inside a `BeginPopup()`/`BeginPopupModal()`/`BeginPopupContextItem()` block (e.g. a "Close"/"OK" `Button()`, or right after a `Selectable()` picks an option). A no-op outside a popup. |
| `imlove.BeginPopupContextItem(strId)` | `open` | Opens a popup on a right-click over the most recently submitted item (its rectangle — the same one `IsItemHovered()` reads) — the canonical right-click context menu. `strId` defaults to a fixed name scoped to the surrounding ID stack; wrap each row in `PushID()`/`PopID()` to keep separate rows' context menus independent, or pass an explicit `strId`. Otherwise behaves exactly like `BeginPopup()`. |
| `imlove.BeginPopupModal(title)` | `open` | Begin a modal popup opened with `OpenPopup(title)` (or the id portion of `"Label##id"`): has a title bar showing `title`, is always centered on screen, and dims + blocks input to everything else — regular windows stop being hit-testable and `io.WantCaptureMouse` is unconditionally `true` while it's open. Unlike `BeginPopup()`, an outside press does **not** dismiss it — only `CloseCurrentPopup()` does (wire it to your own OK/Cancel buttons). Pair with `EndPopup()` only when this returns `true`. |

### ID stack

| Function | Description |
|---|---|
| `imlove.PushID(id)` | Push a string or number onto the ID stack. Wrap list items in `PushID(i)`/`PopID()` so identical labels don't collide. |
| `imlove.PopID()` | Pop it. `End()` will error if you forget. |

### Item queries

| Function | Returns | Description |
|---|---|---|
| `imlove.GetItemRectMin()` | `x, y` | Top-left of the last widget's rectangle. |
| `imlove.GetItemRectMax()` | `x, y` | Bottom-right of the last widget's rectangle. |
| `imlove.IsItemHovered()` | `bool` | Was the most recent item hovered by the mouse this frame? Works for any item, including non-interactive ones like `Text()` (computed from its rectangle rather than a stored hot-state). |
| `imlove.IsItemActive()` | `bool` | Is the most recent item currently held down by the mouse? Always `false` for non-interactive items. |
| `imlove.IsItemClicked()` | `bool` | Was the most recent item clicked this frame — its own notion of a completed click (e.g. `Button`'s release-over-it, `TreeNode`'s toggle). Always `false` for non-interactive items. |

### Style

`GetStyle()` returns the one live `style` table every widget already reads
from; `PushStyleColor`/`PushStyleVar` are the frame-safe way to override a
piece of it temporarily — both are a single global stack each (not
per-window), so a themed span is free to cross window boundaries within a
frame, but every push must be popped by the time `Render()` runs, exactly
like an unbalanced `PushID()`/`BeginChild()` is caught by `End()`. Unlike
those, an unbalanced push here doesn't take the whole UI down for the rest of
the process: `Render()` fully unwinds every remaining `PushStyleColor`/
`PushStyleVar`/`PushFont` entry (restoring the colors/vars/font they
shadowed, in LIFO order) *before* erroring, so a caller that wraps `Render()`
in `pcall` gets a loud error every frame the mistake is present, but the UI
and its theme keep working meanwhile. See `docs/imgui.md` for the full
color-name and style-var-name tables.

`windowPadding` specifically is sampled once, by `Begin()` — not re-read for
the rest of that window's life. Push it *before* `Begin()` to pad a window;
pushing it after `Begin()` (even if popped again before the matching `End()`,
so `Render()` never complains) has no effect on that window at all, since its
margin and auto-fit size were already locked in.

| Function | Returns | Description |
|---|---|---|
| `imlove.PushStyleColor(name, color)` | — | Push a `{r, g, b, a}` override for `GetStyle().colors[name]` — e.g. `"button"`, `"text"`, `"frameBg"`. An unknown `name` is an `error()`. |
| `imlove.PopStyleColor(count)` | — | Pop `count` (default `1`) color overrides, restoring each one. |
| `imlove.PushStyleVar(name, value)` | — | Push an override for one of `GetStyle()`'s scalar/pair fields: a plain number for `windowPadding`, `innerSpacing`, `indent`, `rounding`, `sliderWidth`, `grabWidth`, `snapZone`; a `{x, y}` table for `framePadding`/`itemSpacing`. An unknown `name`, or a `value` of the wrong shape, is an `error()`. |
| `imlove.PopStyleVar(count)` | — | Pop `count` (default `1`) style var overrides, restoring each one. |
| `imlove.GetStyle()` | `style` | The live style table (scalar fields at the top level, a `colors` sub-table underneath) — the same one every widget reads from. Mutating it directly takes effect immediately and is **not** caught by `Render()`'s balance check if you forget to undo it; reach for this only for a one-time theme setup (e.g. right after `require "imlove"`), and use `PushStyleColor`/`PushStyleVar` for anything scoped to part of a frame. |
| `imlove.ColorEdit3(label, color)` | `color, changed` | The 3-channel (`{r, g, b}`) version of `ColorEdit4` below — same swatch + popup, only R/G/B sliders. A 4th channel on the table passed in, if any, always passes through untouched (never edited, never dropped). |
| `imlove.ColorEdit4(label, color)` | `color, changed` | A color-swatch button + label; click it to open a popup with a `SliderFloat` (0..1) per channel (R, G, B, A) and a live preview swatch. `color` is `{r, g, b, a}`. Returns a **new** table when changed — never mutates the one passed in, the same "no mutation" convention every table-valued widget in this library follows — and the same reference back, unchanged, otherwise. No HSV wheel, no hex input, no right-click "copy as..." menu — just the four sliders. |
| `imlove.PushFont(font)` | — | Push a LÖVE `Font` object (e.g. `love.graphics.newFont(...)`): every `GetItemRect*`-visible measurement and every widget drawn until the matching `PopFont()` uses it instead of the library's own default font. `font` must look like a `Font` (non-nil, with `getWidth`/`getHeight`) — anything else is an `error()` immediately, rather than crashing frames later inside `textSize()`. |
| `imlove.PopFont()` | — | Pop the font pushed by `PushFont()`, restoring whichever font was active before it. |

### Settings persistence

Mirrors Dear ImGui's `imgui.ini`: each window's position, collapsed state,
and — only if it was ever explicitly sized — its size, survive across runs,
keyed by window title, in a small ImGui-ini-flavored text file written via
`love.filesystem`. A snapped window (see "Snapping" above) also persists a
`Snap=` line, and its `Size=` line carries its *pre-snap* height rather than
the pinned screen height, so unsnapping after a restart still restores it.
Popups, tooltips, children, and the open/closed (close-button) state are
never persisted.

| Flag / Function | Description |
|---|---|
| `imlove.io.IniFilename` | Default `"imlove.ini"`. Set to `nil` or `false` (any time, including before the first `NewFrame()`) to disable persistence entirely — nothing is ever read or written. |
| `imlove.SaveIniSettings(filename)` | Write current settings now. `filename` defaults to `imlove.io.IniFilename`. Mostly for manual control (e.g. an explicit "Save Layout" button); imlove already calls this on your behalf whenever something worth persisting changes (a drag ends, a resize ends, a window is collapsed/uncollapsed, or a new window is created). |
| `imlove.LoadIniSettings(filename)` | Read and apply settings now. `filename` defaults to `imlove.io.IniFilename`. imlove already calls this once, automatically, the first time `NewFrame()` runs — you only need this for a manual reload (e.g. a "Reset Layout" button that first deletes the file and then calls `LoadIniSettings()` to clear in-memory state — or, more simply, restart). |

A loaded position/size beats a window's cascading default placement, and
beats a `SetNextWindowPos()`/`SetNextWindowSize()` whose `cond` is `"once"`
(the ini entry already counts as "the window has been placed once"); an
explicit `"always"` still wins over the ini, every frame, same as it wins
over a `"once"` call. A loaded `Snap=` entry follows the same rule against
`SetNextWindowSnap()`.
