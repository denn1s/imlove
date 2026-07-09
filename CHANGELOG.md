# Changelog

All notable changes to imlove are documented here. The format is loosely
[Keep a Changelog](https://keepachangelog.com/); the v1 API itself is a
contract — see [ROADMAP.md](ROADMAP.md) — so entries below are additions and
fixes, never breaking changes.

## Unreleased

## [1.1.0] - 2026-07-09

More widgets, zero new machinery — everything below reuses the existing
`behavior()` + `itemAdd()` core as-is.

### Added

- `SliderInt(label, value, min, max)` — the integer counterpart of
  `SliderFloat`, stepped and displayed as `"%d"`.
- `DragFloat(label, value, speed, min, max)` and `DragInt(label, value,
  speed, min, max)` — click-and-drag horizontally to change a value by
  `speed` per pixel instead of mapping a fixed range, ImGui's unbounded
  workhorse editors. `min`/`max` are independently optional.
- `RadioButton(label, active)` — a circular Selectable; returns `pressed`,
  you own the selection, same as `Selectable`.
- `ProgressBar(fraction, w, h, overlay)` — a fill bar with a centered
  percentage overlay by default.
- `CollapsingHeader(label)` — like `TreeNode` but full-width, framed, no
  indent, and no ID-stack push (no matching `TreePop()`). The go-to widget
  for organizing a debug panel.
- Text variants: `TextColored`, `TextDisabled`, `TextWrapped` (word-wraps to
  the window's available width), `BulletText`.
- Layout fillers: `Spacing()`, `NewLine()`, `Indent(w)`/`Unindent(w)`,
  `Dummy(w, h)`; `SameLine()` gained optional `offsetFromStartX`/`spacing`
  arguments (the no-arg form is unchanged).
- Item queries: `IsItemHovered()`, `IsItemActive()`, `IsItemClicked()` —
  work for non-interactive items too (e.g. `Text()`'s hover is computed from
  its rectangle).
- `Button(label, w, h)` gained optional explicit size arguments (0/nil still
  auto-sizes, per axis); `SmallButton(label)` — a button with no vertical
  frame padding, for inline use.
- `PlotLines`/`PlotHistogram(label, values, scaleMin, scaleMax, w, h,
  overlay)` — the canonical FPS/frame-time graph, with auto-ranging when
  `scaleMin`/`scaleMax` are nil.
- A `circle` draw-list primitive (used by `RadioButton` and `BulletText`).
- 37 new headless tests covering every widget above (`tests/test_widgets_v11.lua`).

## [1.0.1] - 2026-07-09

### Fixed

- The UI now lazily creates and owns its own font instead of grabbing
  `love.graphics.getFont()` every `NewFrame()`. v1.0.0 crashed with "Cannot
  use object after it has been released" if the game `release()`d the font
  it happened to be using when a scene unloaded its resources.

## [1.0.0] - 2026-07-09

Initial release: the v1 API contract is now frozen — names and signatures
only gain things from here, they never change.

### Added

- Single-file library (`imlove.lua`) mirroring Dear ImGui's API: windows
  (drag, collapse, click-to-raise), `Text`/`Button`/`Checkbox`/`SliderFloat`/
  `TreeNode`/`Selectable`/`Separator`/`SameLine`, `PushID`/`PopID` with the
  `##` suffix convention, and `WantCaptureMouse`/`WantCaptureKeyboard`
  input-capture flags.
- Kitchen-sink demo (`main.lua`) featuring an entity-inspector panel.
- Headless test suite (`luajit tests/run.lua`) that stubs the LÖVE API — 37
  tests covering widget interaction, ID stacking, window state persistence,
  and input capture.
