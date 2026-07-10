# API reference

Every imlove function, grouped by area. This is the exhaustive reference; the
[README](../README.md) has the pitch, the quickstart, and the general
conventions these tables assume (labels double as identity, `value, changed =
Widget(...)` instead of pointer output params, and so on) — read those first
if you haven't.

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
| `imlove.keypressed(key)` | Optional in v1 (always returns `false`); wire it for forward compatibility. |
| `imlove.textinput(text)` | Optional in v1; same story. |

| Flag | Meaning |
|---|---|
| `imlove.io.WantCaptureMouse` | After `NewFrame()`: the mouse is over/held by the UI this frame. Unconditionally `true` whenever any popup or modal is open, regardless of mouse position. A tooltip does **not** force this — like ImGui's, it's purely visual and never hit-testable, so showing one has no effect on input capture. |
| `imlove.io.WantCaptureKeyboard` | Always `false` in v1. |

### Windows

| Function | Returns | Description |
|---|---|---|
| `imlove.Begin(title, open, flags)` | `notCollapsed, open` | Open a window. Draggable, collapsible, state persists by title. When it returns `false` the window is collapsed and widget calls are cheap no-ops — you may skip them, but you must **always** call `End()`. `open` is optional: `nil` (default) means no close button and a `nil` second return; a boolean adds an X to the title bar and the second return reports it back, possibly toggled to `false` the frame it's clicked (reassign it to your variable, like any other imlove value); passing `false` skips the window entirely for this frame — `Begin` returns `false, false` and every widget call inside becomes a no-op, but `End()` is still required. `flags` is a string or array of strings — see "Window flags" below; an unknown flag name is an error. |
| `imlove.End()` | — | Close the current window. Exactly one per `Begin`, collapsed or not. |
| `imlove.SetNextWindowPos(x, y, cond)` | — | Position the next `Begin`. `cond` is `"always"` (default) or `"once"` (only when the window is first created — use this for default layouts the user can still drag around). |
| `imlove.SetNextWindowSize(w, h, cond)` | — | Size the next `Begin` explicitly, taking it out of auto-fit mode: from then on the window keeps this size and overflowing content scrolls instead of growing it (see "Sizing model" below). `cond` is `"always"` (default) or `"once"`. Ignored by a window with the `"AlwaysAutoResize"` flag. |
| `imlove.GetWindowPos()` | `x, y` | Current window's position. |
| `imlove.GetWindowSize()` | `w, h` | Current window's size as of last frame (windows size themselves to their content at `End`, unless explicitly sized — see below). |
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
| `imlove.SliderFloat(label, value, min, max)` | `value, changed` | Horizontal slider; click or drag anywhere on the track. Assign the first return back. |
| `imlove.SliderInt(label, value, min, max)` | `value, changed` | Same contract as `SliderFloat`, stepped and displayed as `"%d"`. |
| `imlove.DragFloat(label, value, speed, min, max)` | `value, changed` | Click-and-drag horizontally to change the value by `speed` per pixel, instead of mapping the whole track to a fixed range. `speed` defaults to `1.0`; `min`/`max` are optional and independently nil-able (unbounded on that side). A click that doesn't move the mouse changes nothing — unlike `SliderFloat`, it never jumps to the clicked position. |
| `imlove.DragInt(label, value, speed, min, max)` | `value, changed` | The integer counterpart of `DragFloat`; `speed` defaults to `1`, value rounds to the nearest integer. |
| `imlove.ProgressBar(fraction, w, h, overlay)` | — | A bar filled to `fraction` (clamped 0..1). `w`/`h` default to the slider width and frame height; `overlay` defaults to a centered `"NN%"` label. |
| `imlove.TreeNode(label)` | `open` | Collapsible node; open state persists. When `open`, children are indented and the label is pushed on the ID stack — call `TreePop()` after them. |
| `imlove.TreePop()` | — | Close the innermost open `TreeNode`. Call once per `TreeNode` that returned `true`. |
| `imlove.CollapsingHeader(label)` | `open` | Like `TreeNode`, but full-width and framed, with no indent and no ID-stack push — no matching `TreePop()`. Open state persists. |
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
