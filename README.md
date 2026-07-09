# imlove

An immediate-mode debug UI for [LÖVE](https://love2d.org) 11.5, in one pure-Lua
file, with an API that deliberately mirrors
[Dear ImGui](https://github.com/ocornut/imgui).

It exists so you can bolt debug tooling onto your game in minutes — entity
inspectors, pause/step controls, value tweakers — and so that everything you
learn using it (`Begin`/`End`, the ID stack, `WantCaptureMouse`, …) transfers
directly to real Dear ImGui in C++ or any other binding.

- **Pure Lua.** No FFI, no native libraries, no dependencies. Runs anywhere
  LÖVE 11.5 runs.
- **One file.** Copy `imlove.lua` into your project and `require` it. Done.
- **No globals.** `require("imlove")` returns the module table; nothing leaks.
- **MIT licensed.**

To see it in action, run `love .` in this repo for the kitchen-sink demo.

## Quickstart

1. Copy `imlove.lua` into your project.
2. Wire it into your game — this is the whole integration:

```lua
local imlove = require "imlove"

function love.mousepressed(x, y, button)  imlove.mousepressed(x, y, button)  end
function love.mousereleased(x, y, button) imlove.mousereleased(x, y, button) end
function love.wheelmoved(dx, dy)          imlove.wheelmoved(dx, dy)          end

function love.update(dt)
  imlove.NewFrame()   -- first imlove call of the frame
  -- your game update; build UI anywhere after NewFrame
end

function love.draw()
  -- your game rendering
  imlove.Render()     -- last: draws the UI on top
end
```

If your game already defines those callbacks, add the `imlove.*` line at the
top of each existing one instead.

3. Build a window (anywhere after `NewFrame()`, before `Render()`):

```lua
if imlove.Begin("Debug") then
  imlove.Text("FPS: %d", love.timer.getFPS())
  if imlove.Button("Reset") then resetGame() end
  volume = imlove.SliderFloat("volume", volume, 0, 1)
end
imlove.End()  -- ALWAYS call End, even when Begin returned false
```

Windows are draggable by their title bar, collapsible via the arrow, and
remember their position and collapsed state across frames, keyed by title.

### Letting the game and the UI share the mouse

Your game also reads the mouse. To keep it from reacting to clicks the UI
consumed, check the return value of the forwarding functions (`true` means
"the UI took this event"):

```lua
function love.mousepressed(x, y, button)
  if imlove.mousepressed(x, y, button) then return end
  -- safe: this click was NOT on the UI
  game:handleClick(x, y)
end
```

For polled input (`love.mouse.isDown` in `update`), check the ImGui-style
flags instead, valid after `NewFrame()`:

```lua
if not imlove.io.WantCaptureMouse and love.mouse.isDown(1) then
  -- drag your camera, fire your gun, ...
end
```

`imlove.io.WantCaptureKeyboard` also exists; it is always `false` in v1
(there are no keyboard widgets yet) but wiring it now means your integration
stays correct when text fields arrive.

### A real example: an entity inspector

The primary use case, in full — a browsable tree of entities where selecting
one exposes its fields as live-editable widgets. `entities` is any array of
plain tables:

```lua
local selectedEntity = nil

local function entityInspector()
  if imlove.Begin("Entity Inspector") then
    if imlove.TreeNode("Entities") then
      for i, e in ipairs(entities) do
        imlove.PushID(i)  -- entities may share names; keep IDs unique
        if imlove.Selectable(e.name, selectedEntity == e) then
          selectedEntity = e
        end
        imlove.PopID()
      end
      imlove.TreePop()
    end
    imlove.Separator()
    if selectedEntity then
      selectedEntity.x     = imlove.SliderFloat("x", selectedEntity.x, 0, 900)
      selectedEntity.y     = imlove.SliderFloat("y", selectedEntity.y, 0, 600)
      selectedEntity.hp    = imlove.SliderFloat("hp", selectedEntity.hp, 0, 100)
      selectedEntity.alive = imlove.Checkbox("alive", selectedEntity.alive)
    end
  end
  imlove.End()
end
```

See `main.lua` for this running inside an actual game loop (`love .` in this
repo runs the kitchen-sink demo).

## API reference

General conventions:

- All functions live on the module table and use ImGui's PascalCase names.
- Where C++ ImGui writes results through pointers (`bool*`, `float*`), imlove
  returns the new value instead — assign it back yourself:
  `value, changed = imlove.SliderFloat("x", value, 0, 1)`.
- Labels double as identity. Two widgets with the same label in the same
  scope are the same widget. Disambiguate with `"Label##anything"` (the part
  after `##` is invisible but part of the ID) or with `PushID`/`PopID`.

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

## Dear ImGui equivalence table

| imlove | Dear ImGui | Semantic differences |
|---|---|---|
| `NewFrame()` | `ImGui::NewFrame()` | Also polls the mouse; no separate backend. |
| `Render()` | `ImGui::Render()` + backend render | One call does both. |
| `mousepressed(...)` etc. | backend event handlers | Return `true` when consumed — per-event `WantCaptureMouse`. |
| `io.WantCaptureMouse` | `ImGuiIO::WantCaptureMouse` | Same meaning; valid after `NewFrame()`. |
| `io.WantCaptureKeyboard` | `ImGuiIO::WantCaptureKeyboard` | Always `false` in v1 (no keyboard widgets). |
| `Begin(title)` | `ImGui::Begin(name, bool* p_open, flags)` | No close button, no flags. Windows behave as if `ImGuiWindowFlags_AlwaysAutoResize` were set: they fit their content, no manual resize, no scrolling. |
| `End()` | `ImGui::End()` | Identical rule: always call it. |
| `SetNextWindowPos(x, y, cond)` | `ImGui::SetNextWindowPos(pos, cond)` | `cond` is a string: `"always"` / `"once"` (≈ `ImGuiCond_FirstUseEver`). |
| `GetWindowPos()` / `GetWindowSize()` | same | Return `x, y` / `w, h` instead of `ImVec2`. |
| `Text(fmt, ...)` | `ImGui::Text(fmt, ...)` | `string.format` semantics rather than printf (same `%` specifiers). |
| `Button(label)` | `ImGui::Button(label, size)` | No size argument; sized to the label. |
| `Checkbox(label, v)` | `ImGui::Checkbox(label, bool* v)` | Returns `newValue, changed` instead of mutating `v`. |
| `SliderFloat(label, v, min, max)` | `ImGui::SliderFloat(label, float* v, min, max, fmt, flags)` | Returns `newValue, changed`; fixed `%.3f` display; no format/flags/ctrl-click-to-type. Chosen over `DragFloat` because a bounded slider is what tuning panels want. |
| `TreeNode(label)` / `TreePop()` | same | Identical contract, including the implicit ID push while open. |
| `Selectable(label, selected)` | `ImGui::Selectable(label, selected)` | No size/flags. |
| `Separator()` / `SameLine()` | same | `SameLine()` takes no offset/spacing arguments. |
| `PushID(id)` / `PopID()` | same | Accepts strings and numbers. |
| `"Label##id"` | same | Identical convention, including in window titles. |
| `GetItemRectMin/Max()` | same | Return `x, y` instead of `ImVec2`. |

Other deviations worth knowing:

- **IDs are compared as strings**, not hashed — `PushID(7)` and `PushID("7")`
  are the same ID. In practice this never matters for debug UIs.
- **One built-in color scheme.** There is no styling API.
- **Coordinates are LÖVE screen pixels.** No ImVec2 anywhere; functions take
  and return plain `x, y` pairs.

## Non-goals (v1)

Deliberately not included, to keep the library one small readable file:
docking, menus/menu bars, tables/columns, text input fields, images,
styling/theming beyond the built-in scheme, window scrolling or manual
resizing, multi-window z-reordering beyond click-to-raise, touch input,
gamepad/keyboard navigation.

The v1 API is a contract: after the `v1.0.0` tag, names and signatures only
gain things, they never change.

## Running the demo and the tests

```sh
love .                  # kitchen-sink demo (needs LÖVE 11.5)
luajit tests/run.lua    # headless test suite (no LÖVE needed)
```

The tests stub the `love` API (see `tests/stub_love.lua`) — the library only
touches LÖVE at runtime, never at `require` time, which is also what makes it
safe to require in your own headless tooling.

## License

MIT — see [LICENSE](LICENSE).
