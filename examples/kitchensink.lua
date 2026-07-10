--[[
Kitchen-sink example for imlove. Run from the repo root with:

    love .
    love . kitchensink

There is a tiny "game" (drifting circles standing in for entities) plus
seven imlove windows:

  * "Widget gallery"    — every widget in the library, once.
  * "Entity Inspector"  — the realistic use case: a tree of entities where
                          selecting one exposes its fields as live sliders.
  * "World"             — pause/step-style controls for the game itself.
  * "Tip##v12"          — v1.2: the close-button/`open` param round trip —
                          close it with the X, then re-open it with the
                          checkbox in the Widget gallery.
  * "Long list (50 items)##v12" — v1.2: an explicitly-sized, scrolling
                          window (`SetNextWindowSize` + the resize grip).
  * "Event log##v12"    — v1.2: a bordered, scrollable `BeginChild()`
                          region logging game/UI events as they happen.
  * an untitled top-right overlay — v1.2: a `"NoTitleBar", "NoMove"` FPS
                          HUD, the classic overlay-widget pattern.

v1.3 additions live in the Widget gallery and Entity Inspector: a `Combo`
and a `ListBox` sharing selection state with the tree of Selectables, a
tooltip on hover, an "Options" button opening a `BeginPopup`, and a
"Delete" button on the selected entity opening a `BeginPopupModal`
confirmation.

Click a circle in the world to select it, and notice that clicks on the UI
never reach the game: mousepressed below checks imlove's return value.
]]

local imlove = require "imlove"

-- ----------------------------------------------------------------- the game

local WORLD_W, WORLD_H = 900, 600
local KINDS = { "goblin", "slime", "wisp" }

local entities = {}
local selected = nil
local world = { paused = false, timescale = 1.0 }

local function load()
  math.randomseed(42)
  entities = {}
  for i = 1, 10 do
    entities[i] = {
      name = KINDS[(i - 1) % #KINDS + 1] .. " " .. i,
      x = math.random(60, WORLD_W - 60),
      y = math.random(60, WORLD_H - 60),
      angle = math.random() * 2 * math.pi,
      speed = math.random(20, 90),
      radius = math.random(8, 22),
      hue = math.random(),
      alive = true,
    }
  end
  love.graphics.setBackgroundColor(0.13, 0.13, 0.16)
end

local function updateWorld(dt)
  if world.paused then return end
  dt = dt * world.timescale
  for _, e in ipairs(entities) do
    if e.alive then
      e.x = (e.x + math.cos(e.angle) * e.speed * dt) % WORLD_W
      e.y = (e.y + math.sin(e.angle) * e.speed * dt) % WORLD_H
    end
  end
end

local function hsvToRgb(h, s, v)
  local i = math.floor(h * 6) % 6
  local f = h * 6 - math.floor(h * 6)
  local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
  if i == 0 then return v, t, p elseif i == 1 then return q, v, p
  elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
  elseif i == 4 then return t, p, v else return v, p, q end
end

local function drawWorld()
  for _, e in ipairs(entities) do
    if e.alive then
      love.graphics.setColor(hsvToRgb(e.hue, 0.55, 0.9))
      love.graphics.circle("fill", e.x, e.y, e.radius)
      if e == selected then
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.circle("line", e.x, e.y, e.radius + 4)
      end
    end
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.print("click a circle to select it  |  space = pause", 10,
    WORLD_H - 22)
end

-- ------------------------------------------------------------- demo windows

local gallery = {
  clicks = 0,
  checked = true,
  value = 0.5,
  fruit = 2,
  fruits = { "apple", "banana", "cherry" },
  sliderInt = 5,
  dragFloat = 1.0,
  dragInt = 0,
  mode = "walk",
  frameTimes = {},
  showTip = true, -- v1.2: reopens the "Tip##v12" window (see tipWindow())
  listKind = 1,   -- v1.3: ListBox() demo selection, from KINDS
}

-- A running log feeding the "Event log##v12" window's bordered BeginChild,
-- v1.2's scrollable-sub-region feature. Capped like the frame-time buffer.
local EVENT_LOG_HISTORY = 200
local eventLog = {}

local function logEvent(fmt, ...)
  eventLog[#eventLog + 1] = fmt:format(...)
  if #eventLog > EVENT_LOG_HISTORY then table.remove(eventLog, 1) end
end

-- A rolling buffer of frame times, the canonical PlotLines() feed. Capped so
-- the plot always shows the same time window regardless of framerate.
local FRAME_HISTORY = 90

local function pushFrameTime()
  local dt = love.timer.getDelta()
  local t = gallery.frameTimes
  t[#t + 1] = dt
  if #t > FRAME_HISTORY then table.remove(t, 1) end
end

local function widgetGallery()
  pushFrameTime()
  imlove.SetNextWindowPos(20, 20, "once")
  if imlove.Begin("Widget gallery") then
    imlove.Text("Every imlove widget, at least once.")
    imlove.TextColored({ 0.4, 0.9, 1, 1 }, "FPS: %d", love.timer.getFPS())
    imlove.TextDisabled("(drag/click anything below)")
    imlove.TextWrapped("TextWrapped reflows to the window's width, which is " ..
      "handy for changelogs, tooltips, or any prose too long for a single " ..
      "Text() line.")
    imlove.Separator()

    if imlove.Button("Click me") then
      gallery.clicks = gallery.clicks + 1
    end
    if imlove.IsItemHovered() then
      imlove.SetTooltip("clicked %d times so far", gallery.clicks)
    end
    imlove.SameLine()
    if imlove.SmallButton("reset") then
      gallery.clicks = 0
    end
    imlove.SameLine(nil, 20) -- a wider-than-default gap before the count
    imlove.Text("clicked %d times", gallery.clicks)
    if imlove.IsItemHovered() then
      imlove.SameLine()
      imlove.TextDisabled("(hovered)")
    end

    -- v1.3: OpenPopup()/BeginPopup() — a small floating menu, positioned at
    -- the mouse, dismissed by clicking anywhere outside it.
    imlove.SameLine()
    if imlove.Button("Options") then imlove.OpenPopup("gallery-options") end
    if imlove.BeginPopup("gallery-options") then
      -- Each pick closes the menu itself (CloseCurrentPopup()) instead of
      -- leaving it open until an outside click dismisses it — the usual
      -- idiom for a one-shot action menu like this one.
      if imlove.Selectable("Reset click counter", false) then
        gallery.clicks = 0
        imlove.CloseCurrentPopup()
      end
      if imlove.Selectable("Reset sliders", false) then
        gallery.value = 0.5
        gallery.sliderInt = 5
        gallery.dragFloat = 1.0
        gallery.dragInt = 0
        imlove.CloseCurrentPopup()
      end
      imlove.EndPopup()
    end

    gallery.checked = imlove.Checkbox("A checkbox", gallery.checked)
    gallery.showTip = imlove.Checkbox("Show tip window", gallery.showTip)
    gallery.value = imlove.SliderFloat("a slider", gallery.value, 0, 1)
    gallery.sliderInt = imlove.SliderInt("an int slider", gallery.sliderInt,
      0, 10)
    gallery.dragFloat = imlove.DragFloat("drag float", gallery.dragFloat,
      0.02, 0, 5)
    gallery.dragInt = imlove.DragInt("drag int", gallery.dragInt, 1, -10, 10)
    imlove.ProgressBar(gallery.value)

    imlove.Spacing()
    imlove.Text("Movement mode:")
    -- SameLine(offset) lines the group up at fixed columns, regardless of
    -- how wide each radio button's label is.
    imlove.SameLine(120)
    if imlove.RadioButton("walk", gallery.mode == "walk") then
      gallery.mode = "walk"
    end
    imlove.SameLine(200)
    if imlove.RadioButton("run", gallery.mode == "run") then
      gallery.mode = "run"
    end
    imlove.SameLine(280)
    if imlove.RadioButton("fly", gallery.mode == "fly") then
      gallery.mode = "fly"
    end

    imlove.Spacing()
    imlove.PlotLines("frame time", gallery.frameTimes, 0, 1 / 30, nil, nil,
      string.format("%.1f ms", love.timer.getDelta() * 1000))

    if imlove.CollapsingHeader("Layout & tree widgets") then
      imlove.Indent()
      imlove.BulletText("Indent()/Unindent() shift the cursor, no ID push.")
      imlove.Dummy(0, 8) -- a hand-sized gap, instead of Spacing()'s fixed one

      if imlove.TreeNode("A tree node") then
        imlove.Text("Nodes indent children and\nremember being open.")
        if imlove.TreeNode("Selectables") then
          for i, name in ipairs(gallery.fruits) do
            if imlove.Selectable(name, gallery.fruit == i) then
              gallery.fruit = i
            end
          end
          imlove.TreePop()
        end
        imlove.TreePop()
      end
      imlove.Unindent()

      -- v1.3: Combo and ListBox both share `gallery.fruit`/`.listKind` with
      -- the Selectables above — three different widgets, same 1-based
      -- index convention, always in sync.
      imlove.Spacing()
      gallery.fruit = imlove.Combo("Combo (same selection)", gallery.fruit,
        gallery.fruits)
      gallery.listKind = imlove.ListBox("ListBox", gallery.listKind, KINDS, 3)
    end

    imlove.Separator()
    imlove.Text("WantCaptureMouse: %s",
      tostring(imlove.io.WantCaptureMouse))
  end
  imlove.End()
end

-- The primary use case: an inspector over a list of plain tables.
local function entityInspector()
  imlove.SetNextWindowPos(560, 20, "once")
  if imlove.Begin("Entity Inspector") then
    if imlove.TreeNode("Entities") then
      for i, e in ipairs(entities) do
        imlove.PushID(i)
        if imlove.Selectable(e.name, selected == e) then
          selected = e
          logEvent("selected %s", e.name)
        end
        imlove.PopID()
      end
      imlove.TreePop()
    end
    imlove.Separator()
    if selected then
      imlove.Text("%s", selected.name)
      selected.x = imlove.SliderFloat("x", selected.x, 0, WORLD_W)
      selected.y = imlove.SliderFloat("y", selected.y, 0, WORLD_H)
      selected.speed = imlove.SliderFloat("speed", selected.speed, 0, 200)
      selected.radius = imlove.SliderFloat("radius", selected.radius, 2, 40)
      selected.alive = imlove.Checkbox("alive", selected.alive)
      if imlove.Button("Deselect") then
        logEvent("deselected %s", selected.name)
        selected = nil
      end
      imlove.SameLine()
      -- v1.3: BeginPopupModal() — dims and blocks the rest of the UI (and
      -- the game world behind it) until the player picks Delete or Cancel;
      -- unlike BeginPopup(), clicking outside it does nothing.
      if imlove.Button("Delete") then imlove.OpenPopup("Delete entity?") end
      if imlove.BeginPopupModal("Delete entity?") then
        imlove.Text("Delete %s? This can't be undone.", selected.name)
        if imlove.Button("Delete##confirm") then
          logEvent("deleted %s", selected.name)
          selected.alive = false
          selected = nil
          imlove.CloseCurrentPopup()
        end
        imlove.SameLine()
        if imlove.Button("Cancel") then imlove.CloseCurrentPopup() end
        imlove.EndPopup()
      end
    else
      imlove.Text("Select an entity above, or\nclick a circle in the world.")
    end
  end
  imlove.End()
end

local function worldControls()
  imlove.SetNextWindowPos(560, 260, "once")
  if imlove.Begin("World") then
    local wasPaused = world.paused
    world.paused = imlove.Checkbox("Paused", world.paused)
    if world.paused ~= wasPaused then
      logEvent(world.paused and "paused" or "unpaused")
    end
    world.timescale = imlove.SliderFloat("time scale", world.timescale, 0, 3)
    if imlove.Button("Reset world") then
      load()
      selected = nil
      logEvent("world reset")
    end
  end
  imlove.End()
end

-- v1.2: the `Begin(title, open, flags)` close-button round trip. `open` is
-- passed in every frame regardless of its value — when it's `false` (the
-- user clicked the X last frame), `Begin` still must be paired with `End()`,
-- but internally skips the window and every widget call between them. The
-- "Show tip window" checkbox in the Widget gallery flips it back to `true`.
local function tipWindow()
  imlove.SetNextWindowPos(360, 20, "once")
  imlove.SetNextWindowSize(190, 110, "once")
  local notCollapsed, open = imlove.Begin("Tip##v12", gallery.showTip)
  if notCollapsed then
    imlove.TextWrapped("Close me with the X. Bring me back with the " ..
      "checkbox in the Widget gallery.")
  end
  imlove.End()
  gallery.showTip = open
end

-- v1.2: an explicitly-sized window (SetNextWindowSize) whose content — 50
-- Selectable rows — is much taller than its fixed height, so it scrolls by
-- mouse wheel or by dragging the scrollbar/resize grip. Auto-fit windows
-- (every other window in this demo) never need to do this.
local function longListWindow()
  imlove.SetNextWindowPos(770, 55, "once")
  imlove.SetNextWindowSize(210, 190, "once")
  if imlove.Begin("Long list (50 items)##v12") then
    imlove.TextDisabled("Explicit size + scrolling.")
    for i = 1, 50 do
      imlove.PushID(i)
      imlove.Selectable(("item %02d"):format(i), false)
      imlove.PopID()
    end
  end
  imlove.End()
end

-- v1.2: a bordered, fixed-size BeginChild()/EndChild() region embedded in an
-- otherwise auto-fit window — its own scroll position and cursor, but no
-- separate z-order (it draws into "Event log##v12"'s own draw list).
local function eventLogWindow()
  imlove.SetNextWindowPos(560, 460, "once")
  if imlove.Begin("Event log##v12") then
    imlove.Text("Recent events:")
    if imlove.BeginChild("log", 260, 140, true) then
      if #eventLog == 0 then
        imlove.TextDisabled("(nothing yet)")
      end
      for _, line in ipairs(eventLog) do
        imlove.Text("%s", line)
      end
    end
    imlove.EndChild()
  end
  imlove.End()
end

-- v1.2: an overlay-style HUD — "NoTitleBar"+"NoMove" strip the window down
-- to a bare content box pinned in a screen corner, the classic ImGui FPS-
-- counter pattern. Repinned every frame ("always") since NoMove only blocks
-- dragging, not SetNextWindowPos.
local function fpsOverlay()
  imlove.SetNextWindowPos(870, 10, "always")
  if imlove.Begin("##fps-overlay", nil, { "NoTitleBar", "NoMove" }) then
    imlove.TextColored({ 0.4, 0.9, 1, 1 }, "FPS: %d", love.timer.getFPS())
  end
  imlove.End()
end

-- ---------------------------------------------------------- module callbacks

local M = {}

function M.load()
  load()
end

function M.update(dt)
  imlove.NewFrame()      -- start the UI frame first...
  widgetGallery()        -- ...then declare the UI anywhere you like...
  entityInspector()
  worldControls()
  tipWindow()
  longListWindow()
  eventLogWindow()
  fpsOverlay()
  updateWorld(dt)
end

function M.draw()
  drawWorld()
  imlove.Render()        -- ...and draw it on top of everything.
end

function M.mousepressed(x, y, button)
  if imlove.mousepressed(x, y, button) then return end
  -- The UI didn't want this click, so it belongs to the game.
  for _, e in ipairs(entities) do
    local dx, dy = x - e.x, y - e.y
    if e.alive and dx * dx + dy * dy <= (e.radius + 3) ^ 2 then
      selected = e
      logEvent("selected %s", e.name)
      return
    end
  end
  selected = nil
end

function M.mousereleased(x, y, button)
  imlove.mousereleased(x, y, button)
end

function M.wheelmoved(dx, dy)
  imlove.wheelmoved(dx, dy)
end

function M.keypressed(key)
  if imlove.keypressed(key) then return end
  if key == "space" then world.paused = not world.paused end
  if key == "escape" then love.event.quit() end
end

return M
