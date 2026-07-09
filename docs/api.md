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
| `imlove.Button(label)` | `pressed` | `true` on the frame the button is clicked (mouse released over it). |
| `imlove.Checkbox(label, value)` | `value, changed` | Toggles on click. Assign the first return back to your variable. |
| `imlove.SliderFloat(label, value, min, max)` | `value, changed` | Horizontal slider; click or drag anywhere on the track. Assign the first return back. |
| `imlove.TreeNode(label)` | `open` | Collapsible node; open state persists. When `open`, children are indented and the label is pushed on the ID stack — call `TreePop()` after them. |
| `imlove.TreePop()` | — | Close the innermost open `TreeNode`. Call once per `TreeNode` that returned `true`. |
| `imlove.Selectable(label, selected)` | `clicked` | Full-width selectable row for pick-one-from-a-list UIs. You own the selection state. |
| `imlove.Separator()` | — | Horizontal line. |
| `imlove.SameLine()` | — | Place the next widget on the same row as the previous one. |

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
