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
| `io.WantCaptureMouse` | `ImGuiIO::WantCaptureMouse` | Same meaning; valid after `NewFrame()`. |
| `io.WantCaptureKeyboard` | `ImGuiIO::WantCaptureKeyboard` | Always `false` in v1 (no keyboard widgets). |
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
| `SliderFloat(label, v, min, max)` | `ImGui::SliderFloat(label, float* v, min, max, fmt, flags)` | Returns `newValue, changed`; fixed `%.3f` display; no format/flags/ctrl-click-to-type. Chosen over `DragFloat` because a bounded slider is what tuning panels want. |
| `SliderInt(label, v, min, max)` | `ImGui::SliderInt(label, int* v, min, max, fmt, flags)` | Same deviations as `SliderFloat`; fixed `%d` display. |
| `DragFloat(label, v, speed, min, max)` | `ImGui::DragFloat(label, float* v, speed, min, max, fmt, flags)` | Returns `newValue, changed`; fixed `%.3f` display, no format/flags/ctrl-click-to-type. `min`/`max` are independently optional (nil = unbounded on that side) instead of ImGui's `0, 0` "no bound" sentinel. Implemented with a drag-anchor (captures value + mouse x when the drag begins) rather than ImGui's internal per-frame accumulator — same externally-visible behavior: a click alone never changes the value. |
| `DragInt(label, v, speed, min, max)` | `ImGui::DragInt(label, int* v, speed, min, max, fmt, flags)` | Same deviations as `DragFloat`; `speed` defaults to `1`; fixed `%d` display. |
| `ProgressBar(fraction, w, h, overlay)` | `ImGui::ProgressBar(fraction, size, overlay)` | `w, h` instead of an `ImVec2 size`; `overlay` defaults to a centered `"NN%"` string instead of ImGui's `NULL` (which shows nothing). |
| `TreeNode(label)` / `TreePop()` | same | Identical contract, including the implicit ID push while open. |
| `CollapsingHeader(label)` | `ImGui::CollapsingHeader(label, flags)` | Returns just `open` (no `p_open`/close-button form). Simplified relative to real ImGui: always full-width, no indent, and — unlike `TreeNode` — no ID-stack push, so no matching `TreePop()`. |
| `Selectable(label, selected)` | `ImGui::Selectable(label, selected)` | No size/flags. |
| `Separator()` | same | Identical contract. |
| `Spacing()` / `NewLine()` / `Dummy(w, h)` | same | Identical contracts. |
| `Indent(w)` / `Unindent(w)` | `ImGui::Indent(w)` / `ImGui::Unindent(w)` | Identical contract; `w` defaults to the style's indent, same as ImGui's `0`. |
| `SameLine(offsetFromStartX, spacing)` | `ImGui::SameLine(offset_from_start_x, spacing)` | Identical contract and defaults; with no arguments, unchanged from v1. |
| `PlotLines(label, values, scaleMin, scaleMax, w, h, overlay)` | `ImGui::PlotLines(label, values, count, offset, overlay, min, max, size, stride)` | `values` is a plain Lua array (no separate `count`/`stride`/ring-buffer `offset`); `w, h` instead of an `ImVec2 size`; `scaleMin`/`scaleMax` default to nil (auto-range from `values`), matching ImGui's `FLT_MAX` sentinel. |
| `PlotHistogram(...)` | `ImGui::PlotHistogram(...)` | Same deviations as `PlotLines`. |
| `PushID(id)` / `PopID()` | same | Accepts strings and numbers. |
| `"Label##id"` | same | Identical convention, including in window titles. |
| `GetItemRectMin/Max()` | same | Return `x, y` instead of `ImVec2`. |
| `IsItemHovered()` / `IsItemActive()` / `IsItemClicked()` | same | Identical contracts; also well-defined for non-interactive items like `Text()` (`IsItemHovered` is geometric there; `IsItemActive`/`IsItemClicked` are always `false`). |

## Other deviations worth knowing

- **IDs are compared as strings**, not hashed — `PushID(7)` and `PushID("7")`
  are the same ID. In practice this never matters for debug UIs.
- **One built-in color scheme.** There is no styling API.
- **Coordinates are LÖVE screen pixels.** No ImVec2 anywhere; functions take
  and return plain `x, y` pairs.
