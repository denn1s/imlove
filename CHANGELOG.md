# Changelog

All notable changes to imlove are documented here. The format is loosely
[Keep a Changelog](https://keepachangelog.com/); the v1 API itself is a
contract — see [ROADMAP.md](ROADMAP.md) — so entries below are additions and
fixes, never breaking changes.

## Unreleased

## [1.3.0] - 2026-07-10

Overlays — the popup release: tooltips, popups, and modals, all drawn in a
new overlay layer above every regular window, plus `Combo`/`ListBox` built on
top of that same machinery. Every existing name and signature only gained
optional trailing arguments; nothing that worked in v1.2 changes behavior.

### Added

- `imlove.SetTooltip(fmt, ...)` / `imlove.BeginTooltip()` /
  `imlove.EndTooltip()` — a small auto-fit box that follows the mouse,
  drawn above absolutely everything (even an open popup), and never
  hit-testable. Calling `SetTooltip()` more than once in a frame is fine —
  the last call wins.
- `imlove.OpenPopup(strId)` / `imlove.BeginPopup(strId)` /
  `imlove.EndPopup()` — floating, auto-fit, no-title-bar popups, positioned
  at the mouse when opened, drawn above every regular window. `EndPopup()`
  must be called only when `BeginPopup()` returned `true`, enforced with an
  `error()` in both directions. A press outside the topmost open popup
  closes it (and everything stacked above whatever it did land on, for
  nested popups) and that dismissing press is consumed, exactly like a
  press landing on a widget. `imlove.CloseCurrentPopup()` closes whichever
  popup is currently being built — the usual way to wire an OK/Cancel/pick
  action.
- `imlove.BeginPopupContextItem(strId)` — opens a popup on a right-click
  over the last submitted item, the canonical right-click context menu.
- `imlove.BeginPopupModal(title)` — a centered, titled popup that dims and
  blocks input to everything else (`io.WantCaptureMouse` unconditionally
  `true` while it's open) and is dismissed only by `CloseCurrentPopup()`,
  never by an outside click.
- `imlove.Combo(label, value, items)` — a slider-width preview + arrow that
  opens a dropdown of `Selectable`s on click, built on the same popup
  machinery. `value` is a **1-based** index into `items`, matching Lua's
  array convention rather than ImGui's 0-based one; an out-of-range value
  just shows an empty preview. Returns `newValue, changed`; `changed` is
  `true` on any pick, including re-picking the item already selected —
  only opening it and dismissing without picking reports `changed = false`.
- `imlove.ListBox(label, value, items, heightInItems)` — an always-visible,
  scrollable list of `Selectable`s (a thin wrapper over `BeginChild`); same
  1-based `value` convention and changed-on-any-pick semantics as `Combo`.
  Defaults to 7 visible rows.
- A right mouse button one-frame press latch, feeding
  `BeginPopupContextItem()`.
- 18 new headless tests covering popup/tooltip open-close-dismiss
  lifecycle, id scoping, `EndPopup()`'s contract errors, nested-popup
  dismissal, `BeginPopupContextItem`, modal centering/blocking/dismiss
  rules, tooltip hit-testing and last-call-wins, `Combo`, `ListBox`, and the
  `WantCaptureMouse`/forwarder matrix while any popup is open
  (`tests/test_popups.lua`).
- `imlove.io.IniFilename` / `imlove.SaveIniSettings(filename)` /
  `imlove.LoadIniSettings(filename)` — settings persistence mirroring Dear
  ImGui's `imgui.ini`: each window's position, collapsed state, and (only if
  ever explicitly sized) its size survive across runs, keyed by window
  title, in a small ImGui-ini-flavored text file written via
  `love.filesystem`. Loaded automatically on the first `NewFrame()`, saved
  automatically whenever something worth persisting changes (a drag or
  resize ends, a collapse toggles, a new window appears); `IniFilename`
  defaults to `"imlove.ini"`, and `nil`/`false` disables persistence
  entirely. Popups, tooltips, children, and open/closed (close-button)
  state are never persisted.
- `imlove.CollapsingHeader(label, defaultOpen)` gained an optional
  `defaultOpen` argument — seeds the very first time this id is ever seen
  (like `ImGuiTreeNodeFlags_DefaultOpen`), and never overrides whatever the
  user has since clicked it to.
- `imlove_demo.lua` — a new companion file at the repo root, mirroring Dear
  ImGui's `imgui_demo.cpp`: `local ShowDemoWindow = require "imlove_demo"`
  returns a single function, `open = ShowDemoWindow(open)`, building a
  self-documenting "imlove Demo" window out of nothing but imlove's public
  API. Run it with `love . demo` (see the new `examples/demo.lua`, a thin
  driver showing the same open/reopen round trip any `Begin()` caller
  handles).
- 20 new headless tests: settings persistence lifecycle, ini text parsing,
  and load/save round trips (`tests/test_settings.lua`); and a full,
  clicks-and-all tour of `imlove_demo.lua` itself — every widget, every
  popup kind, and a second window, all driven headless
  (`tests/test_demo.lua`).

### Fixed

- The content clip rect from the previous frame could leak into the very
  start of the next frame's hit-testing, before the current frame's own
  clip was established.
- `LoadIniSettings()` truncated a window's saved `Size=w,h` line at the
  first `and`-like token boundary inside `parseIniText`, silently dropping
  the height half of the pair.
- A window closed via its title-bar close button and then reopened by the
  caller (`open = true` again — the exact round trip `imlove_demo.lua` and
  its own callers use) stayed reported as closed forever after:
  `win.closedThisFrame` was only ever reset with `... or false`, which
  patches away a `nil` but never clears a stale `true` left over from the
  frame the close button was actually clicked. It's now reset
  unconditionally at the top of `Begin()`, before the close button's own
  hit-test runs.

### Changed

- `_VERSION` is now `"1.3.0"`.

### Known deviations (documented, not planned for this release)

- No menu bar / `BeginMenu`/`MenuItem` — build a menu-like popup with
  `BeginPopup()` + `Selectable()`s instead.
- Popup and `Combo` dropdown content does not scroll if it's taller than
  the screen — keep it short, or use `ListBox`/`BeginChild` inside one if
  you need scrolling.

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
