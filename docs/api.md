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
| `imlove.wheelmoved(dx, dy)` | Recommended: v1 has no scrolling, but this reports the wheel as consumed over a window so your game doesn't zoom under the UI. |
| `imlove.keypressed(key)` | Optional in v1 (always returns `false`); wire it for forward compatibility. |
| `imlove.textinput(text)` | Optional in v1; same story. |

| Flag | Meaning |
|---|---|
| `imlove.io.WantCaptureMouse` | After `NewFrame()`: the mouse is over/held by the UI this frame. |
| `imlove.io.WantCaptureKeyboard` | Always `false` in v1. |

### Windows

| Function | Returns | Description |
|---|---|---|
| `imlove.Begin(title)` | `notCollapsed` | Open a window. Draggable, collapsible, state persists by title. When it returns `false` the window is collapsed and widget calls are cheap no-ops — you may skip them, but you must **always** call `End()`. |
| `imlove.End()` | — | Close the current window. Exactly one per `Begin`, collapsed or not. |
| `imlove.SetNextWindowPos(x, y, cond)` | — | Position the next `Begin`. `cond` is `"always"` (default) or `"once"` (only when the window is first created — use this for default layouts the user can still drag around). |
| `imlove.GetWindowPos()` | `x, y` | Current window's position. |
| `imlove.GetWindowSize()` | `w, h` | Current window's size as of last frame (windows size themselves to their content at `End`). |

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
