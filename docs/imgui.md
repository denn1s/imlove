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

## Other deviations worth knowing

- **IDs are compared as strings**, not hashed — `PushID(7)` and `PushID("7")`
  are the same ID. In practice this never matters for debug UIs.
- **One built-in color scheme.** There is no styling API.
- **Coordinates are LÖVE screen pixels.** No ImVec2 anywhere; functions take
  and return plain `x, y` pairs.
