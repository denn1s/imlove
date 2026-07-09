# Roadmap

Where imlove goes after v1.0.0, staying deliberately close to
[Dear ImGui](https://github.com/ocornut/imgui): same names, same call
patterns, so everything learned here keeps transferring to the real thing.

Two guiding constraints shape the ordering below:

1. **Most missing features are cheap incremental widgets**, but two are real
   architectural steps — **clipping/scrolling** and an **overlay draw
   layer** — and several other features are gated behind them. Each gets its
   own release so the library grows one subsystem at a time.
2. **The v1 API is a contract.** Names and signatures only gain things, they
   never change. Every new widget keeps the established Lua-isms:
   `value, changed = Widget(...)` returns instead of mutating, and
   `cond`/flags are strings.

## v1.1 — More widgets, zero new machinery

Everything here reuses the existing `behavior()` + `itemAdd()` core as-is.

- `SliderInt`, `DragFloat`, `DragInt` — variants of `SliderFloat`;
  `DragFloat` is the unbounded workhorse in real ImGui.
- `RadioButton`, `ProgressBar`.
- `CollapsingHeader` — like `TreeNode` but full-width and framed, no
  indent/ID push. The go-to widget for organizing a debug panel.
- Text variants: `TextColored`, `TextDisabled`, `TextWrapped`, `BulletText`.
- Layout fillers: `Spacing()`, `NewLine()`, `Indent()`/`Unindent()`,
  `Dummy(w, h)`, and the `SameLine(offset, spacing)` arguments.
- Item queries: `IsItemHovered()`, `IsItemActive()`, `IsItemClicked()` —
  the state is already tracked; exposing it unlocks tooltip-style patterns
  in user code.
- `Button(label, w, h)` size arguments and `SmallButton`.
- `PlotLines` / `PlotHistogram` — an FPS/frame-time graph is *the* canonical
  debug-UI feature and needs no new machinery.

## v1.2 — Windows grow up (the clipping release)

The architectural step: a scissor/clip stack in the draw list
(`love.graphics.setScissor` does the heavy lifting). Once it exists:

- **Window scrolling** — `wheelmoved` already consumes the event; make it do
  something. Removes v1's biggest practical limit: a long entity list
  growing off-screen.
- `SetNextWindowSize` + a manual resize grip — auto-sizing stops being
  implicit and becomes the `"AlwaysAutoResize"` flag, like ImGui.
- Close button: `visible, open = imlove.Begin(title, open)` mirroring
  ImGui's `bool* p_open` with the established return-the-value convention.
- Window flags (`"NoTitleBar"`, `"NoMove"`, `"NoResize"`,
  `"AlwaysAutoResize"`, …) as strings.
- `BeginChild` / `EndChild` — scrollable sub-regions, built directly on the
  clip stack.

## v1.3 — Overlays (the popup release)

The second architectural step: draw commands that render above all windows,
plus focus/dismiss rules. Then, in dependency order:

- Tooltips: `SetTooltip`, `BeginTooltip` / `EndTooltip`.
- Popups: `OpenPopup`, `BeginPopup` / `EndPopup`,
  `BeginPopupContextItem` (right-click menus are huge for entity
  inspectors), `BeginPopupModal`.
- `Combo` and `ListBox` — Combo is probably the single most-requested
  missing widget, and it is just a Selectable list inside a popup once
  popups exist.
- Menus (`BeginMainMenuBar` / `BeginMenu` / `MenuItem`) — popup machinery
  reused; may slip to a later release.

## v1.4 — Keyboard & text input

- `InputText` — the big one; finally makes `io.WantCaptureKeyboard` real.
  The `keypressed`/`textinput` forwarders have been wired since v1 exactly
  so existing integrations keep working when this lands.
- `InputFloat` / `InputInt`.
- Ctrl-click on a slider to type an exact value — the ImGui behavior people
  miss most in tuning panels.

## v1.5 — Style & polish

- `PushStyleColor` / `PopStyleColor`, `PushStyleVar` / `PopStyleVar`,
  `GetStyle()` — ImGui's styling model rather than a bespoke theme system.
- `ColorEdit3` / `ColorEdit4` — very LÖVE-relevant: tweak `{r, g, b, a}`
  tables live.
- `PushFont` / `PopFont`.

## Anytime, any release

Not gated on any subsystem; land whenever they're ready:

- `imlove.ShowDemoWindow()` — the most ImGui feature there is: a
  self-documenting demo built from the library itself, doubling as the
  kitchen-sink test and a teaching tool.
- Settings persistence — ImGui's `.ini` behavior via `love.filesystem`:
  window positions and collapsed state surviving restarts.
- Tables/columns (`BeginTable` or legacy `Columns`) — deliberately late:
  it's a lot of layout code, and `SameLine` covers most debug-UI cases.

## Continued non-goals

To keep the one-file, pure-Lua promise honest, these stay out of scope:
docking, multi-viewport, gamepad/keyboard navigation, DPI scaling, custom
draw callbacks, touch input.
