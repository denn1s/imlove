# Coming from Dear ImGui

For anyone who already knows [Dear ImGui](https://github.com/ocornut/imgui)
and wants to know how much of that knowledge transfers directly, and where
imlove's Lua/LÖVE-flavored API departs from the C++ original. If you've never
used ImGui, skip this — the [README](../README.md) and [API
reference](api.md) are the complete story on their own.

## Dear ImGui equivalence table

| imlove | Dear ImGui | Semantic differences |
|---|---|---|
| `NewFrame()` | `ImGui::NewFrame()` | Also polls the mouse; no separate backend. |
| `Render()` | `ImGui::Render()` + backend render | One call does both. |
| `mousepressed(...)` etc. | backend event handlers | Return `true` when consumed — per-event `WantCaptureMouse`. |
| `keypressed(key, scancode, isrepeat)` / `textinput(text)` | backend event handlers | As of v1.4, wiring both is **required** for `InputText`/`InputFloat`/`InputInt`/ctrl-click-to-type to receive any edits at all — they were forwarders-only (always returning `false`) through v1.3. Return `true` per-event, same `WantCaptureKeyboard`-per-event idea as the mouse forwarders. |
| `io.WantCaptureMouse` | `ImGuiIO::WantCaptureMouse` | Same meaning; valid after `NewFrame()`. |
| `io.WantCaptureKeyboard` | `ImGuiIO::WantCaptureKeyboard` | Same meaning as of v1.4: `true` while a text/numeric field (or a ctrl-clicked slider/drag) has keyboard focus, valid after `NewFrame()`. Requires wiring `keypressed`/`textinput` (see below) — without them it's always `false`, same as v1-v1.3. |
| `Begin(title, open, flags)` | `ImGui::Begin(name, bool* p_open, flags)` | `open` is a plain value, not a pointer: pass a boolean to get a close button, and reassign the returned second value back to your variable (`nil` in, `nil` back = no close button, matching a `NULL p_open`). `flags` is a string or array of strings, not a bitmask — see [api.md](api.md#window-flags) for the list; there is no full parity with `ImGuiWindowFlags` (e.g. no `NoBackground`, `MenuBar`, `HorizontalScrollbar`). Windows auto-fit their content until explicitly sized (`SetNextWindowSize()` or a grip drag), same spirit as ImGui but framed as an explicit mode switch rather than a flag combination. |
| `End()` | `ImGui::End()` | Identical rule: always call it. |
| `SetNextWindowPos(x, y, cond)` | `ImGui::SetNextWindowPos(pos, cond)` | `cond` is a string: `"always"` / `"once"` (≈ `ImGuiCond_FirstUseEver`). |
| `SetNextWindowSize(w, h, cond)` | `ImGui::SetNextWindowSize(size, cond)` | `w, h` instead of an `ImVec2 size`; `cond` is the same string convention as `SetNextWindowPos`. |
| `GetWindowPos()` / `GetWindowSize()` | same | Return `x, y` / `w, h` instead of `ImVec2`. |
| `BeginChild(idStr, w, h, border)` / `EndChild()` | `ImGui::BeginChild(str_id, size, border/flags)` / `ImGui::EndChild()` | `w, h` instead of an `ImVec2 size`; `border` is a plain boolean, not a bitmask overload. No separate z-order/window: a child shares its root window's draw list, so it always draws inline with the rest of the window's content rather than as an independently-clipped sub-window. Always scrollable — there's no ImGui-style `NoScrollWithMouse`/`AlwaysUseWindowPadding` flag set. |
| `Text(fmt, ...)` | `ImGui::Text(fmt, ...)` | `string.format` semantics rather than printf (same `%` specifiers). |
| `TextColored(color, fmt, ...)` | `ImGui::TextColored(col, fmt, ...)` | `color` is a plain `{r, g, b, a}` table (0..1) instead of `ImVec4`. |
| `TextDisabled(fmt, ...)` | same | Identical contract; uses the one built-in theme's disabled gray. |
| `TextWrapped(fmt, ...)` | same | Wraps to the window's available width, computed with the same one-frame lag as every other layout query in imlove. |
| `BulletText(fmt, ...)` | same | Identical contract. |
| `Button(label, w, h)` | `ImGui::Button(label, size)` | `w, h` instead of an `ImVec2 size`; 0 or nil on either axis auto-sizes that axis, matching `ImVec2(0, 0)`. |
| `SmallButton(label)` | same | Identical contract. |
| `Checkbox(label, v)` | `ImGui::Checkbox(label, bool* v)` | Returns `newValue, changed` instead of mutating `v`. |
| `RadioButton(label, active)` | `ImGui::RadioButton(label, active)` | Same bool form (there's no `int* v, v_button` overload) — returns `pressed`; you decide what "select this one" means, exactly like `Selectable`. |
| `SliderFloat(label, v, min, max)` | `ImGui::SliderFloat(label, float* v, min, max, fmt, flags)` | Returns `newValue, changed`; fixed `%.3f` display; no format string/flags. Ctrl+click-to-type (v1.4) matches ImGui's own behavior — Enter commits (clamped), Escape reverts. Chosen over `DragFloat` because a bounded slider is what tuning panels want. |
| `SliderInt(label, v, min, max)` | `ImGui::SliderInt(label, int* v, min, max, fmt, flags)` | Same deviations as `SliderFloat`; fixed `%d` display. |
| `DragFloat(label, v, speed, min, max)` | `ImGui::DragFloat(label, float* v, speed, min, max, fmt, flags)` | Returns `newValue, changed`; fixed `%.3f` display, no format string/flags. `min`/`max` are independently optional (nil = unbounded on that side) instead of ImGui's `0, 0` "no bound" sentinel. Implemented with a drag-anchor (captures value + mouse x when the drag begins) rather than ImGui's internal per-frame accumulator — same externally-visible behavior: a click alone never changes the value. Ctrl+click-to-type (v1.4) clamps only to whichever of `min`/`max` are given. |
| `DragInt(label, v, speed, min, max)` | `ImGui::DragInt(label, int* v, speed, min, max, fmt, flags)` | Same deviations as `DragFloat`; `speed` defaults to `1`; fixed `%d` display. |
| `InputText(label, text, flags)` | `ImGui::InputText(label, char* buf, size, flags, callback, user_data)` | No fixed buffer size (Lua strings), no `ImGuiInputTextCallback`. **No selection at all** — no shift-click, no double-click-to-select, no partial copy, and so no word-left/word-right either; a substantial, deliberate deviation from real ImGui. Ctrl+C copies the *whole* field instead of a selection. `flags` supports only `ImGuiInputTextFlags_EnterReturnsTrue` (as the string `"EnterReturnsTrue"`) — no `CharsDecimal`/`Password`/`ReadOnly`/etc. Default mode (no flag) returns the live buffer with `changed = true` on every keystroke, matching how every other imlove widget already works — ImGui's default is closer to `EnterReturnsTrue`'s "only on commit" shape, flipped here for consistency with `Checkbox`/`SliderFloat`/etc. |
| `InputFloat(label, v, step)` | `ImGui::InputFloat(label, float* v, step, step_fast, fmt, flags)` | Returns `newValue, changed`; no `step_fast`, no format string, no flags. Live-parses on every keystroke rather than only on Enter/Tab/focus-loss like ImGui's default. |
| `InputInt(label, v, step)` | `ImGui::InputInt(label, int* v, step, step_fast)` | Same deviations as `InputFloat`. **Floors rather than rounds**: typing `"3.7"` commits as `3`, not `4` — chosen so intermediate typing states never jitter visibly. |
| `ProgressBar(fraction, w, h, overlay)` | `ImGui::ProgressBar(fraction, size, overlay)` | `w, h` instead of an `ImVec2 size`; `overlay` defaults to a centered `"NN%"` string instead of ImGui's `NULL` (which shows nothing). |
| `TreeNode(label)` / `TreePop()` | same | Identical contract, including the implicit ID push while open. |
| `CollapsingHeader(label, defaultOpen)` | `ImGui::CollapsingHeader(label, flags)` | Returns just `open` (no `p_open`/close-button form). `defaultOpen` is a plain boolean seed for the *first* time this id is ever seen, equivalent to passing `ImGuiTreeNodeFlags_DefaultOpen` — not a bitmask. Simplified relative to real ImGui: always full-width, no indent, and — unlike `TreeNode` — no ID-stack push, so no matching `TreePop()`. |
| `Selectable(label, selected)` | `ImGui::Selectable(label, selected)` | No size/flags. |
| `Separator()` | same | Identical contract. |
| `Spacing()` / `NewLine()` / `Dummy(w, h)` | same | Identical contracts. |
| `Indent(w)` / `Unindent(w)` | `ImGui::Indent(w)` / `ImGui::Unindent(w)` | Identical contract; `w` defaults to the style's indent, same as ImGui's `0`. |
| `SameLine(offsetFromStartX, spacing)` | `ImGui::SameLine(offset_from_start_x, spacing)` | Identical contract and defaults; with no arguments, unchanged from v1. |
| `PlotLines(label, values, scaleMin, scaleMax, w, h, overlay)` | `ImGui::PlotLines(label, values, count, offset, overlay, min, max, size, stride)` | `values` is a plain Lua array (no separate `count`/`stride`/ring-buffer `offset`); `w, h` instead of an `ImVec2 size`; `scaleMin`/`scaleMax` default to nil (auto-range from `values`), matching ImGui's `FLT_MAX` sentinel. |
| `PlotHistogram(...)` | `ImGui::PlotHistogram(...)` | Same deviations as `PlotLines`. |
| `Combo(label, value, items)` | `ImGui::Combo(label, int* current_item, items, count)` / `BeginCombo`+`Selectable` loop | `items` is a plain Lua array (no separate `count`); **`value` is a 1-based index**, not 0-based — matches Lua array convention rather than ImGui's C convention. Returns `newValue, changed` instead of mutating a pointer. An out-of-range `value` just shows an empty preview instead of asserting. `changed` is `true` on any pick — including re-picking the item already selected — matching ImGui (it sets `value_changed` on the click itself, not on whether the index moved). Only "opened it, picked nothing, dismissed it" reports `changed = false`. |
| `ListBox(label, value, items, heightInItems)` | `ImGui::ListBox(label, int* current_item, items, count, height_in_items)` | Same `items`/1-based-`value` deviations as `Combo`, including the same "`changed` is true on any pick, even the already-selected row" rule. Implemented as a thin wrapper over `BeginChild`, so it scrolls the same way any other child does. |
| `SetTooltip(fmt, ...)` | `ImGui::SetTooltip(fmt, ...)` | `string.format` semantics instead of printf. Drawn in imlove's overlay layer, above every window *and* every open popup (ImGui tooltips are also topmost, so behavior matches). |
| `BeginTooltip()` / `EndTooltip()` | same | Identical contract. |
| `OpenPopup(strId)` | `ImGui::OpenPopup(str_id)` | Identical id-scoping rule (resolved against the current ID stack, same as a widget id) — no `ImGuiPopupFlags` overload. |
| `BeginPopup(strId)` / `EndPopup()` | `ImGui::BeginPopup(str_id)` / `ImGui::EndPopup()` | Identical contract: call `EndPopup()` only when `BeginPopup()` returned `true`. imlove enforces this with an `error()` in both directions (calling it without a successful open, and leaving one open past `End()`/`EndChild()`/`Render()`) rather than leaving it as a documented-but-unchecked convention. No `ImGuiWindowFlags` argument — popups are always auto-fit, no title bar. Tall popup content does not scroll (no internal `BeginChild()`) — a documented deviation; keep popup content short. |
| `CloseCurrentPopup()` | same | Identical contract. Takes effect for the *next* `BeginPopup()`/`BeginPopupModal()` check — same one-frame lag as every other state change in imlove, so don't expect a local variable capturing an earlier `BeginPopup()` call's return to flip within the same frame you call this. |
| `BeginPopupContextItem(strId)` | `ImGui::BeginPopupContextItem(str_id)` | Same right-click-over-the-last-item trigger and id-scoping default. No `ImGuiPopupFlags` (e.g. no alternate mouse-button selection — always the right mouse button). |
| `BeginPopupModal(title)` / `EndPopup()` | `ImGui::BeginPopupModal(name, p_open, flags)` | No `p_open`/close-button form — wire your own Cancel button to `CloseCurrentPopup()`. Always centered (no manual positioning); no `ImGuiWindowFlags`. Otherwise identical semantics: dims and blocks all other input, an outside click does not dismiss it. |
| `PushID(id)` / `PopID()` | same | Accepts strings and numbers. |
| `"Label##id"` | same | Identical convention, including in window titles. |
| `GetItemRectMin/Max()` | same | Return `x, y` instead of `ImVec2`. |
| `IsItemHovered()` / `IsItemActive()` / `IsItemClicked()` | same | Identical contracts; also well-defined for non-interactive items like `Text()` (`IsItemHovered` is geometric there; `IsItemActive`/`IsItemClicked` are always `false`). |
| `PushStyleColor(name, color)` / `PopStyleColor(count)` | `ImGui::PushStyleColor(ImGuiCol idx, ImVec4 col)` / `ImGui::PopStyleColor(count)` | `name` is a **string** — one of `GetStyle().colors`'s own field names (camelCase, e.g. `"button"`, `"frameBgHovered"`, `"checkMark"`) — instead of an `ImGuiCol_*` enum constant; see the name table below. An unknown name is an `error()`, ImGui-style typo protection rather than an out-of-range enum. Both are a single **global** stack, not per-window, and must be balanced by `Render()` time (checked there, the same way an unclosed window is), not scoped to `End()`. |
| `PushStyleVar(name, value)` / `PopStyleVar(count)` | `ImGui::PushStyleVar(ImGuiStyleVar idx, float/ImVec2 val)` / `ImGui::PopStyleVar(count)` | Same string-name-instead-of-enum deviation as `PushStyleColor`. `value`'s shape (plain number vs. `{x, y}` table) must match the field — see the shape table below; several imlove style vars have no exact ImGui counterpart (see notes below). Also a single global stack, balanced by `Render()`. |
| `GetStyle()` | `ImGui::GetStyle()` | Returns the actual live table every widget reads from (scalars at the top level, `colors` nested underneath) rather than a copy of an internal struct — mutating it directly works, immediately, and is not frame-scoped or balance-checked; that's what `PushStyleVar`/`PushStyleColor` are for. |
| `ColorEdit3(label, color)` / `ColorEdit4(label, color)` | `ImGui::ColorEdit3(label, float col[3])` / `ImGui::ColorEdit4(label, float col[4])` | `color` is a plain `{r, g, b(, a)}` table (0..1), not a `float[]`; returns a **new** table plus `changed`, instead of mutating in place — same "no mutation" convention as every other table-valued imlove widget. Deliberately modest next to ImGui's: no HSV wheel, no hex `#RRGGBB` input, no right-click "copy as..." menu, no alpha bar/checkerboard preview — just a swatch button that opens a popup with one 0..1 `SliderFloat` per channel and a live preview. `ColorEdit3` never touches a 4th channel already on the table you pass it (kept, not stripped) but never adds one either. |
| `PushFont(font)` / `PopFont()` | `ImGui::PushFont(ImFont*)` / `ImGui::PopFont()` | Takes a real LÖVE `Font` object (`love.graphics.newFont(...)`) instead of an atlas-baked `ImFont*` — there's no font atlas/glyph-range system to configure, LÖVE's own font loading does that job. Affects measuring (`GetItemRect*`, layout) and drawing identically and immediately, like ImGui's. Also a global stack, balanced by `Render()`. |
| `io.IniFilename` | `io.IniFilename` | A plain string (default `"imlove.ini"`), not `.ini`-suffix-checked; set `nil`/`false` to disable, same idea as ImGui's `nullptr`. Written via `love.filesystem` (lands in LÖVE's sandboxed save directory), not raw `fopen`. |
| `SaveIniSettings(filename)` / `LoadIniSettings(filename)` | `ImGui::SaveIniSettingsToDisk`/`LoadIniSettingsFromDisk` (`...ToMemory`/`...FromMemory` have no imlove equivalent) | Same manual-control escape hatch, but imlove already calls the disk-backed forms itself: once from the first `NewFrame()` (load), and write-on-change from `Render()` (a title-drag ending, a resize-grip drag ending, a collapse toggle, or a brand-new window) — not ImGui's periodic timer-based autosave. Persists position, size (only if ever explicit), and collapsed state per window title; never popups/tooltips/children, and never the open/closed (close-button) state. A loaded entry beats a window's cascade default and a `"once"` `SetNextWindowPos()`/`SetNextWindowSize()`, but loses to an explicit `"always"`. |
| `imlove_demo.lua` / `ShowDemoWindow(open)` | `imgui_demo.cpp` / `ImGui::ShowDemoWindow(p_open)` | Same idea (a self-documenting tour of every widget), but shipped as a separate companion file you `require` yourself — `local ShowDemoWindow = require "imlove_demo"` — rather than a function baked into the library, mirroring how `imgui_demo.cpp` ships as its own translation unit rather than living inside `imgui.cpp`. `open` follows the same value-in/value-out convention as `Begin()`'s. Run it with `love . demo`. |

## Other deviations worth knowing

- **IDs are compared as strings**, not hashed — `PushID(7)` and `PushID("7")`
  are the same ID. In practice this never matters for debug UIs.
- **One built-in color scheme, but it's fully mutable as of v1.5.** There's
  no separate style-editor demo (ImGui ships one), but `GetStyle()` /
  `PushStyleColor()` / `PushStyleVar()` reach the exact same data ImGui's
  `ImGuiStyle` does — see the equivalence table above and the name/shape
  tables just below.
- **Style color names are strings, camelCase, and match `GetStyle().colors`
  exactly** — not the `ImGuiCol_*` enum. The mapping (imlove name →
  closest `ImGuiCol_*`):

  | imlove | ImGuiCol |
  |---|---|
  | `"text"` | `ImGuiCol_Text` |
  | `"textDisabled"` | `ImGuiCol_TextDisabled` |
  | `"windowBg"` | `ImGuiCol_WindowBg` |
  | `"border"` | `ImGuiCol_Border` |
  | `"titleBg"` | `ImGuiCol_TitleBg` |
  | `"titleBgActive"` | `ImGuiCol_TitleBgActive` |
  | `"frameBg"` | `ImGuiCol_FrameBg` |
  | `"frameBgHovered"` | `ImGuiCol_FrameBgHovered` |
  | `"frameBgActive"` | `ImGuiCol_FrameBgActive` |
  | `"button"` | `ImGuiCol_Button` |
  | `"buttonHovered"` | `ImGuiCol_ButtonHovered` |
  | `"buttonActive"` | `ImGuiCol_ButtonActive` |
  | `"checkMark"` | `ImGuiCol_CheckMark` |
  | `"sliderGrab"` | `ImGuiCol_SliderGrab` |
  | `"sliderGrabActive"` | `ImGuiCol_SliderGrabActive` |
  | `"header"` | `ImGuiCol_Header` |
  | `"headerHovered"` | `ImGuiCol_HeaderHovered` |
  | `"separator"` | `ImGuiCol_Separator` |

  That's the full set — imlove has no `ImGuiCol_*` for things it doesn't
  draw (tabs, docking, plot lines/histograms use `text`, nav highlights,
  ...).
- **`PushStyleVar` shape rules** — a plain number for a scalar field, a
  `{x, y}` table for a pair field; passing the wrong shape is an `error()`,
  not silent truncation:

  | imlove name | shape | closest ImGuiStyleVar | notes |
  |---|---|---|---|
  | `"windowPadding"` | number | `ImGuiStyleVar_WindowPadding` | ImGui's is an `ImVec2` (x and y independently); imlove only ever had one uniform padding value, so this stays a single number rather than gaining a second axis. |
  | `"framePadding"` | `{x, y}` | `ImGuiStyleVar_FramePadding` | Matches ImGui's `ImVec2` shape exactly. |
  | `"itemSpacing"` | `{x, y}` | `ImGuiStyleVar_ItemSpacing` | Matches ImGui's `ImVec2` shape exactly. |
  | `"innerSpacing"` | number | `ImGuiStyleVar_ItemInnerSpacing` | ImGui's is an `ImVec2`; imlove only ever used it as one scalar gap (widget-frame to label), so it stays a single number. |
  | `"indent"` | number | `ImGuiStyleVar_IndentSpacing` | Matches. |
  | `"rounding"` | number | `ImGuiStyleVar_FrameRounding` / `WindowRounding` | ImGui has separate frame/window/child/popup/scrollbar/grab rounding vars; imlove has always drawn every rounded corner (window and frame alike) from this one shared value, so pushing it re-themes both at once. |
  | `"sliderWidth"` | number | *(none)* | No ImGui equivalent — closest in spirit is `ImGuiStyleVar_GrabMinSize`, but that's the grab, not the track; imlove's sliders/drags/combos/color swatches all share one fixed track width instead of ImGui's per-widget `CalcItemWidth()`. |
  | `"grabWidth"` | number | `ImGuiStyleVar_GrabMinSize`-ish | ImGui's is a *minimum* grab size that can grow; imlove's is a fixed width. |

- **Coordinates are LÖVE screen pixels.** No ImVec2 anywhere; functions take
  and return plain `x, y` pairs.
- **No menu bar / `BeginMainMenuBar`/`BeginMenu`/`MenuItem`.** Not yet
  implemented — build a menu-like popup with `BeginPopup()` +
  `Selectable()`s if you need one today.
- **A press that dismisses a popup is consumed**, exactly like a press
  landing on a widget is — your game's own click handlers never see it,
  even though (unlike a press that lands *on* UI) it didn't land on
  anything imlove drew.
- **A `Combo()` dropdown very close to the bottom (or right) screen edge can
  overlap its own preview box.** A popup's position is decided once, the
  frame it opens, from the *previous* frame's content size — which for a
  brand-new popup is still zero, so there's nothing meaningful to clamp or
  flip against yet at the moment the decision is made. In practice this only
  bites when the combo box itself sits within a dropdown's height of the
  screen edge; move the box (or the window it's in) if you hit it. Not
  worth the extra frame of lag a real fix (measure-then-position) would
  add for a debug UI.
