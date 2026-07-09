# Changelog

All notable changes to imlove are documented here. The format is loosely
[Keep a Changelog](https://keepachangelog.com/); the v1 API itself is a
contract — see [ROADMAP.md](ROADMAP.md) — so entries below are additions and
fixes, never breaking changes.

## Unreleased

## [1.2.0] - 2026-07-09

Windows grow up: clipping, scrolling, explicit sizing, and child regions —
the library's first architectural change since v1.0's freeze. Every existing
name and signature only gained optional trailing arguments; nothing that
worked in v1.1 changes behavior.

### Added

- A clip/scissor stack in the draw list (`love.graphics.setScissor`, saved
  and restored around `Render()` like the color/font state already was).
  Fixed-size windows and `BeginChild()` regions clip their content so it
  can't paint outside its own bounds, and scrolled-out-of-view widgets stop
  being clickable.
- Window scrolling: a fixed-size window's content taller than its visible
  area scrolls by mouse wheel or by dragging a slim scrollbar on the right
  edge (hidden with the `"NoScrollbar"` flag, but the wheel still works).
  Auto-fit windows never overflow — scrolling only applies once a window has
  an explicit size (see below).
- `imlove.SetNextWindowSize(w, h, cond)` and a manual resize grip (bottom-
  right corner) — either takes a window out of auto-fit mode into a sticky,
  explicit size, mirroring ImGui's sizing model. The `"AlwaysAutoResize"`
  flag opts a window out of this permanently (the exact v1.1 behavior).
- `imlove.Begin(title, open, flags)` gained two optional arguments: `open`
  adds a close button and reports it back (possibly toggled to `false`),
  same convention as ImGui's `p_open` but by value instead of by pointer;
  passing `open == false` skips the window (and every widget call inside)
  entirely for that frame. `flags` is a string or array of strings:
  `"NoTitleBar"`, `"NoMove"`, `"NoResize"`, `"NoCollapse"`,
  `"AlwaysAutoResize"`, `"NoScrollbar"` — an unknown flag name is an
  `error()`, not a silent no-op.
- `imlove.BeginChild(idStr, w, h, border)` / `imlove.EndChild()` — a
  fixed-size scrollable region embedded at the cursor, with its own cursor,
  scroll position, and ID scope, drawing into its root window's draw list
  (no separate z-order). Nested children route the mouse wheel to the
  innermost hovered one.
- `imlove.wheelmoved(dx, dy)` now latches `dy` and applies it to whatever
  window or `BeginChild()` region is under the mouse at the next
  `NewFrame()` — same latch-then-apply pattern as mouse press/release, so no
  event delivered between frames is dropped. Its return value (consumed
  whenever the mouse is over any window) is unchanged.
- 32 new headless tests covering the clip stack, scroll clamping, wheel
  latching, the scrollbar's click-to-position mapping, the `Begin` open-
  param return-value matrix, every window flag, sizing-model transitions,
  `BeginChild`/`EndChild` layout, scrolling, ID scoping, and mismatched
  Begin/BeginChild error cases, plus regressions for the resize grip/close
  button/collapse arrow releasing their claim when disabled mid-hold,
  per-nesting-path child scroll state, the resize grip no longer swallowing
  the scrollbar's bottom, `availWidth()` reserving the scrollbar gutter, and
  `EndChild()`'s resting bottom padding (`tests/test_windows_v12.lua`).

### Changed

- `_VERSION` is now `"1.2.0"`.

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
