# Changelog

All notable changes to imlove are documented here. The format is loosely
[Keep a Changelog](https://keepachangelog.com/); the v1 API itself is a
contract — see [ROADMAP.md](ROADMAP.md) — so entries below are additions and
fixes, never breaking changes.

## Unreleased

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
