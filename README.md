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

To see it in action, run `love .` in this repo for the kitchen-sink demo, or
`love . demo` for imlove's own self-documenting tour of every widget
(`imlove_demo.lua`, at the repo root, mirrors Dear ImGui's `imgui_demo.cpp`).

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

See `examples/kitchensink.lua` for this running inside an actual game loop
(`love .` in this repo runs the kitchen-sink example).

## API conventions

- All functions live on the module table and use ImGui's PascalCase names.
- Where C++ ImGui writes results through pointers (`bool*`, `float*`), imlove
  returns the new value instead — assign it back yourself:
  `value, changed = imlove.SliderFloat("x", value, 0, 1)`.
- Labels double as identity. Two widgets with the same label in the same
  scope are the same widget. Disambiguate with `"Label##anything"` (the part
  after `##` is invisible but part of the ID) or with `PushID`/`PopID`.

## Documentation

- [docs/api.md](docs/api.md) — the full function-by-function reference.
- [docs/imgui.md](docs/imgui.md) — for people coming from Dear ImGui: what
  transfers directly and what's different.
- [imlove_demo.lua](imlove_demo.lua) — a self-documenting tour of the widgets
  above, built from nothing but the public API. Run it with `love . demo`.
- [ROADMAP.md](ROADMAP.md) — what's planned past v1, and what's a deliberate
  non-goal.
- [CHANGELOG.md](CHANGELOG.md) — release history.

## Non-goals (v1)

Deliberately not included, to keep the library one small readable file. See
[ROADMAP.md](ROADMAP.md) for what's planned and the full, current list of
continued non-goals.

The v1 API is a contract: after the `v1.0.0` tag, names and signatures only
gain things, they never change.

## Running the demo and the tests

```sh
love .                   # kitchen-sink example (needs LÖVE 11.5)
love . game              # a small real-game integration example
love . demo              # imlove's own demo window (imlove_demo.lua)
love . <name>            # any examples/<name>.lua
luajit tests/run.lua     # headless test suite (no LÖVE needed)
```

`main.lua` is a small dispatcher: it loads `examples/<name>.lua` (default
`kitchensink`) and installs whatever LÖVE callbacks that module defines. Each
example does its own imlove integration end to end — `require`, `NewFrame`/
`Render`, input forwarding — so the `examples/` directory doubles as
integration documentation. See `examples/kitchensink.lua` for the full
widget gallery and `examples/game.lua` for the WantCaptureMouse pattern
inside an actual game loop.

The tests stub the `love` API (see `tests/stub_love.lua`) — the library only
touches LÖVE at runtime, never at `require` time, which is also what makes it
safe to require in your own headless tooling.

## License

MIT — see [LICENSE](LICENSE).
