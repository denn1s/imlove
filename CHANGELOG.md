# Changelog

All notable changes to imlove are documented here. The format is loosely
[Keep a Changelog](https://keepachangelog.com/); the v1 API itself is a
contract — see [ROADMAP.md](ROADMAP.md) — so entries below are additions and
fixes, never breaking changes.

## Unreleased

## [1.5.0] - 2026-07-10

Style & polish — the final v1 roadmap release. imlove's one built-in theme
stops being fixed: every color and layout constant that drives the existing
widgets is now reachable and temporarily overridable, and widgets can draw
with a font other than the library's own default. Every existing name and
signature only gained optional trailing arguments; nothing renders or
behaves differently unless you reach for one of the functions below.

### Added

- `imlove.PushStyleColor(name, color)` / `imlove.PopStyleColor(count)` —
  temporarily override one of `GetStyle().colors`'s fields (`"button"`,
  `"text"`, `"frameBgHovered"`, ...) for everything drawn until the matching
  pop. `name` is a string, not an enum — an unknown one is an `error()`,
  the same typo protection as `Begin()`'s window flags. A single **global**
  stack, not per-window, since a themed span is free to cross window
  boundaries within a frame; must be balanced by the time `Render()` runs
  (checked there, with the same "N left unpopped" wording as an unclosed
  window) — and if it isn't, `Render()` fully unwinds the leftover entries
  (restoring every shadowed color) *before* erroring, so a forgotten pop
  never bricks the UI or its theme for the rest of the process, only the
  offending frame. Draw commands capture a *reference* to whichever color
  table is live when a widget is drawn, so a push/pop pair wrapped tightly
  around one widget affects only that widget, never its neighbors.
- `imlove.PushStyleVar(name, value)` / `imlove.PopStyleVar(count)` — the
  same push/pop pattern (including the unwind-before-error recovery above)
  for `GetStyle()`'s scalar/pair layout fields: `windowPadding`,
  `innerSpacing`, `indent`, `rounding`, `sliderWidth`, `grabWidth` (plain
  numbers) and `framePadding`, `itemSpacing` (`{x, y}` tables). An unknown
  name, or a value of the wrong shape, is an `error()`. Also a global stack,
  balanced the same way. `windowPadding` specifically is sampled once, by
  `Begin()` — push it *before* `Begin()` to pad a window; pushing it
  *after* `Begin()` (even if popped again before the matching `End()`) has
  no effect on that already-open window, since its margin and auto-fit size
  were already locked in.
- `imlove.GetStyle()` — returns the *live* style table every widget already
  reads from (mutate it at your own risk before `NewFrame()`; `PushStyleColor`/
  `PushStyleVar` are the frame-safe way to make a temporary change).
- `imlove.ColorEdit3(label, color)` / `imlove.ColorEdit4(label, color)` — a
  color-swatch button + label; click it to open a popup with a `SliderFloat`
  (0..1) per channel and a live preview swatch. Returns a *new* table when
  changed (never mutates the one passed in, the same convention every
  table-valued imlove widget already follows) and the same reference back
  otherwise. Deliberately modest next to ImGui's: no HSV wheel, no hex
  input, no right-click "copy as..." menu — just the sliders. `ColorEdit3`
  never touches a 4th channel already on the table you pass it.
- `imlove.PushFont(font)` / `imlove.PopFont()` — push any LÖVE `Font` object
  (`love.graphics.newFont(...)`): every measurement (`GetItemRect*`, layout)
  and every widget drawn until the matching pop uses it instead of the
  library's own lazily-created default font. Also a global stack, balanced
  the same way as the style stacks above (including the unwind-before-error
  recovery). `font` must look like a `Font` (non-nil, with `getWidth`/
  `getHeight`) — anything else is an `error()` immediately, rather than
  crashing frames later inside `textSize()`.
- 24 new headless tests (`tests/test_style.lua`) covering: the color-stack's
  draw-list reference semantics (a push/pop pair affects only the wrapped
  widget), nested pushes, `PopStyleColor(count)`, unknown-name and
  wrong-shape errors, unbalanced-push detection at `Render()` for all three
  stacks (color, var, font) *and* that `Render()` fully recovers from each
  (theme/font restored, next frame works normally), `PushStyleVar` actually
  changing `Button` geometry and cursor spacing, `windowPadding` being
  locked at `Begin()` (pushing it after `Begin()` has no effect; pushing it
  before pads symmetrically), `GetStyle()`'s live-table semantics,
  `ColorEdit4`'s full open-popup/drag-slider/new-table/original-untouched
  cycle, `ColorEdit3`'s alpha passthrough, `PushFont` changing both measured
  layout and which font a text draw command carries, and `PushFont` rejecting
  a non-Font argument immediately.

## [1.4.0] - 2026-07-10

Keyboard & text input — `io.WantCaptureKeyboard` becomes real. Every
existing name and signature only gained optional trailing arguments; nothing
that worked in v1.3 changes rendered output or public behavior when a field
isn't focused.

### Added

- `imlove.InputText(label, text, flags)` — a single-line text field. Click to
  gain keyboard focus (a blinking cursor appears); Backspace/Delete/Left/
  Right/Home/End all work, and the text scrolls horizontally inside the frame
  so the cursor stays visible. By default returns the live edit buffer with
  `changed = true` on every keystroke, matching every other imlove widget;
  pass the `"EnterReturnsTrue"` flag for ImGui's other mode instead (keeps
  returning the old text until Enter commits it once). Enter commits and
  defocuses; Escape reverts to the text the field had when it gained focus
  and defocuses; a click outside the field also defocuses it, without
  consuming that click — it still reaches whatever it landed on. Ctrl+V
  pastes at the cursor (`love.system.getClipboardText`); Ctrl+C copies the
  *whole* field — there is no selection (and so no partial copy, no
  word-left/word-right) in v1.4, a documented deviation from ImGui.
- `imlove.InputFloat(label, value, step)` / `imlove.InputInt(label, value,
  step)` — `InputText` restricted to numeric editing. The buffer parses on
  every keystroke: a successful `tonumber()` returns the parsed value with
  `changed = true`; an unparseable intermediate state (`""`, `"-"`, `"."`,
  ...) keeps the last good value instead of committing garbage. Enter
  commits (parsing, or reverting if it doesn't parse); Escape always
  reverts. `InputInt` floors rather than rounds a typed float (`"3.7"`
  commits as `3`). If `step` is given (and nonzero), small "-"/"+" buttons
  nudge the value by `step` directly, bypassing text parsing entirely — they
  work even while the field isn't focused.
- Ctrl+click on `SliderFloat`/`SliderInt`/`DragFloat`/`DragInt` turns the
  widget into a temporary numeric text editor until Enter commits (clamped
  to the widget's own min/max, or whichever of a Drag's bounds exist),
  Escape reverts, or a click elsewhere just stops editing. Rendered output
  and public behavior are unchanged when a widget isn't ctrl-clicked.
- `imlove.io.WantCaptureKeyboard` is now real: `true` after `NewFrame()`
  whenever any of the above holds keyboard focus, `false` otherwise —
  exactly like `WantCaptureMouse` already worked for the mouse.
- `imlove.keypressed(key, scancode, isrepeat)` / `imlove.textinput(text)` are
  now real forwarders instead of always-`false` stubs: wiring both is
  **required** for the widgets above to receive any edits. Both return
  `true` (consumed) whenever any field holds focus, regardless of the key,
  so a game can keep checking the same return value it always has.
  `keypressed` recognizes Backspace, Delete, Left, Right, Home, End, Return/
  KPEnter (commit), Escape (revert), and Ctrl+C/Ctrl+V (copy/paste, checked
  via `love.keyboard.isDown("lctrl", "rctrl")` at the moment the key lands);
  anything else it doesn't queue for editing, but still reports consumed.
- A UTF-8-aware cursor: positions are tracked in characters, not bytes
  (`local utf8ok, utf8lib = pcall(require, "utf8")`, with a pure-Lua
  lead-byte-counting fallback for plain LuaJIT, which is what the headless
  tests run under) — typing, arrow keys, Backspace, and Delete all work
  correctly on multi-byte input.
- 23 new headless tests covering the focus lifecycle and
  `WantCaptureKeyboard`/forwarder matrix, typing and editing keys, UTF-8
  multi-byte input, Enter/Escape commit-and-revert (both `InputText` and the
  numeric editors), the `EnterReturnsTrue` flag, click-away defocus, the
  submitted-for-a-frame staleness rule, `InputFloat`/`InputInt` parsing,
  step buttons, ctrl-click-to-type on all four slider/drag widgets
  (commit-and-clamp, revert, plain-click-still-works), clipboard copy/paste,
  a field inside an open popup, and a field under an open modal failing to
  focus (`tests/test_input.lua`).

### Changed

- Internal refactor: `SliderFloat`/`SliderInt`/`DragFloat`/`DragInt` now
  share layout (`sliderSetup`) and frame/grab/label rendering
  (`sliderFrame`) helpers, plus the same edit-buffer machinery `InputText`
  uses, to support ctrl-click-to-type without duplicating it four times.
  Purely internal — no observable behavior change for any existing caller.

### Fixed

- `SliderFloat`/`SliderInt`/`DragFloat`/`DragInt` now correctly report
  `changed = true` on the frame a ctrl-click-to-type edit is committed with
  Enter (it was silently always `false`, an artifact of the refactor above
  computing "changed" against a value it had already overwritten).

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
