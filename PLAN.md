# imlove — an immediate-mode debug UI for LÖVE, in pure Lua

## What this is

A small, self-contained immediate-mode GUI library for [LÖVE](https://love2d.org)
11.5, written in pure Lua (LuaJIT / Lua 5.1 compatible), with an API that
deliberately mirrors [Dear ImGui](https://github.com/ocornut/imgui)'s naming
and semantics.

It is a **teaching tool** for a university Game Engine Architecture course.
Students clone (or vendor a single file from) this repo and use it to build
debug tooling for their own LÖVE games — entity inspectors, pause/step
controls, value tweakers. They use it as a *product*: they read the README,
integrate it, and get on with their game. They do not study its internals in
class. Some students follow the course in C++ or Odin with real Dear ImGui,
so API vocabulary compatibility matters: what they learn here should transfer.

## Hard constraints

- **Pure Lua, zero native dependencies.** No FFI, no compiled libraries, no
  external Lua modules. Must run anywhere LÖVE 11.5 runs (Windows/macOS/Linux
  student laptops).
- **Vendorable as a single file.** The entire library ships as one
  `imlove.lua` that users drop into their project and `require`. The repo may
  contain more (demo, tests, docs), but the library itself is one file.
- **No globals.** `require("imlove")` returns the module table. Nothing leaks.
- **License: MIT.** Include the LICENSE file.
- **The API is a contract.** Course lesson material will be written against
  it. After v1.0 is tagged, names and signatures must not change; additions
  only.

## API surface (required)

Follow Dear ImGui naming (PascalCase functions on the module, e.g.
`imlove.Begin(...)`). Semantics should match ImGui's where it's reasonable in
Lua; where ImGui uses out-params or ImVec2, choose idiomatic Lua returns
(document any deviation in the README).

**Frame lifecycle & LÖVE integration** — the library must slot into a LÖVE
game without owning the game loop:

- a per-frame begin (ImGui's `NewFrame` equivalent) called from `love.update`
  or at the top of UI code,
- a render call the game invokes at the end of `love.draw`,
- forwarding functions for the LÖVE callbacks the library needs
  (`mousepressed`, `mousereleased`, `wheelmoved`, `keypressed`, `textinput` —
  whichever are actually required),
- ImGui-style input-capture flags (the equivalent of `io.WantCaptureMouse` /
  `io.WantCaptureKeyboard`) so the game can ignore clicks/keys that the UI
  consumed. This is essential: the host game also reads the mouse/keyboard.

**Windows:**

- `Begin(title)` / `End()` — movable (drag by title bar), collapsible windows
  that remember position/size/collapsed state across frames by title.

**Widgets** (the complete v1 budget — enough for an entity inspector and a
tuning panel, and nothing more):

- `Text(fmt, ...)`
- `Button(label)` → pressed:boolean
- `Checkbox(label, value)` → newValue, changed
- `SliderFloat(label, value, min, max)` → newValue, changed (or `DragFloat`;
  pick one, document it)
- `TreeNode(label)` → open:boolean, with `TreePop()`
- `Selectable(label, selected)` → clicked (for pick-one-from-a-list UIs)
- `Separator()`, `SameLine()`
- `PushID(id)` / `PopID()` and support for ImGui's `"visible##unique"` label
  convention — lists of similar items (e.g. entities) must be able to
  generate stable, non-colliding widget IDs.

**Explicit non-goals for v1** (state these in the README): docking, menus,
tables/columns, text input fields, images, styling/theming beyond one
built-in color scheme, multi-window z-reordering beyond basics, touch input.

## Quality bar / deliverables

1. `imlove.lua` — the library.
2. `README.md` — quickstart (copy file, five-line integration into an
   existing game), full API reference, a table mapping each function to its
   Dear ImGui equivalent (and any semantic differences), and the non-goals.
3. `main.lua` + `conf.lua` — a runnable kitchen-sink demo (LÖVE 11.5): every
   widget exercised, plus one realistic panel that fakes a small "entity
   inspector" (a tree of ~10 fake entities; selecting one shows its fields
   with sliders) — that's the course's primary use case, and it must be
   expressible in well under 50 lines of user code.
4. Automated tests runnable headlessly with `luajit` (stub the `love` API —
   the library must not call LÖVE at require time, only at runtime). Cover at
   least: widget interaction logic (hover/click/drag state transitions), ID
   stacking/collisions, window state persistence across frames, and
   input-capture flag correctness.
5. Git repo with a tagged `v1.0.0` once the above passes.

## Acceptance test (the course's litmus)

A user with an existing LÖVE game must be able to: copy `imlove.lua`, add
~5 lines (require + 3–4 callback forwards + render call), and then write an
entity-inspector window against a list of tables — tree of entities,
selectable, live-editable numeric fields — following only the README. If any
step needs knowledge of imlove's internals, the library has failed its
purpose.
