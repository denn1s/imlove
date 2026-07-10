--[[
imlove_demo.lua — a single-window, self-documenting tour of every widget in
imlove, mirroring Dear ImGui's own imgui_demo.cpp: it ships as a companion
file, separate from the library itself, precisely so it can be an honest
consumer of imlove's PUBLIC API only (this file does `require "imlove"` at
the top, just like your own game would) — nothing in here reaches into
imlove's internals. It doubles as the library's most thorough integration
test: run it and every widget in the library gets exercised at least once.

Usage — this file is a companion, not part of the library proper. Copy BOTH
`imlove.lua` and `imlove_demo.lua` into your project if you want the demo
available (copying just `imlove.lua` is enough to use the library; the demo
is optional):

    local ShowDemoWindow = require "imlove_demo"

    function love.update(dt)
      imlove.NewFrame()
      demoOpen = ShowDemoWindow(demoOpen)  -- demoOpen: nil, or a boolean
      ...
    end

    function love.draw()
      ...
      imlove.Render()
    end

`ShowDemoWindow(open)` follows the exact same `open` convention as
`imlove.Begin()`: pass `nil` for no close button (the window just always
shows), or a boolean to get a close button in the title bar — the return
value is that boolean, possibly flipped to `false` the frame it's clicked;
reassign it to your variable, same as any other imlove value.

See examples/demo.lua for a complete, runnable example (`love . demo`).
]]

local imlove = require "imlove"

-- All demo state lives in this one table so it persists frame to frame —
-- exactly the pattern any real imlove caller should follow (module-local
-- state, not globals).
local demo = {
  -- "Widgets"
  clickCount = 0,
  checked = true,
  radioChoice = 1,
  sliderFloat = 0.5,
  sliderInt = 5,
  dragFloat = 1.0,
  dragInt = 0,
  treeFruits = { "apple", "banana", "cherry", "date" },
  treeSelected = 1,
  flatFruits = { "red", "green", "blue", "purple" },
  flatSelected = 2,
  comboItems = { "one", "two", "three", "four" },
  comboValue = 1,
  listItems = { "alpha", "bravo", "charlie", "delta", "echo", "foxtrot",
    "golf", "hotel" },
  listValue = 3,
  wavePhase = 0,
  sineBuf = {},
  cosineBuf = {},

  -- "Layout"
  showChildBorder = true,
  childLines = { "line 1", "line 2", "line 3", "line 4", "line 5", "line 6",
    "line 7", "line 8", "line 9", "line 10", "line 11", "line 12" },

  -- "Popups & tooltips"
  menuLastPick = "(nothing yet)",
  contextLastPick = "(nothing yet)",
  modalDeleteCount = 0,

  -- "Windows"
  showSecondary = false,
  secondaryOpen = true,
  secNoTitleBar = false,
  secNoResize = false,
  secAlwaysAutoResize = false,
}

local WAVE_HISTORY = 100

local function pushWaveSample()
  local dt = love.timer.getDelta()
  demo.wavePhase = demo.wavePhase + dt * 2
  local s, c = demo.sineBuf, demo.cosineBuf
  s[#s + 1] = math.sin(demo.wavePhase)
  c[#c + 1] = math.abs(math.cos(demo.wavePhase))
  if #s > WAVE_HISTORY then table.remove(s, 1) end
  if #c > WAVE_HISTORY then table.remove(c, 1) end
end

-- ------------------------------------------------------------------- Help

local function showHelp()
  -- Open by default (the second, "defaultOpen" argument only matters the
  -- very first time this id is ever seen — see imlove.CollapsingHeader()),
  -- so a first-time reader sees the pitch immediately.
  if imlove.CollapsingHeader("Help", true) then
    imlove.TextWrapped("imlove is an immediate-mode debug UI for LOVE 11.5: " ..
      "no widget objects, no layout files — you rebuild the whole UI every " ..
      "frame from plain Lua, and a widget's identity is just its label.")
    imlove.Spacing()
    imlove.BulletText("README.md has the pitch and a quickstart.")
    imlove.BulletText("docs/api.md is the exhaustive function reference.")
    imlove.BulletText("docs/imgui.md maps this API onto Dear ImGui, if you " ..
      "already know it.")
    imlove.Spacing()
    imlove.TextDisabled("This whole window is built from nothing but the " ..
      "public imlove.* API — read imlove_demo.lua alongside it.")
  end
end

-- ---------------------------------------------------------------- Widgets

local function showWidgets()
  if imlove.CollapsingHeader("Widgets", true) then -- open by default, see above
    imlove.TextDisabled("Buttons, checkboxes, radios, and text variants.")
    if imlove.Button("Click me") then demo.clickCount = demo.clickCount + 1 end
    imlove.SameLine()
    if imlove.SmallButton("reset") then demo.clickCount = 0 end
    imlove.SameLine(nil, 20)
    imlove.Text("clicked %d times", demo.clickCount)

    demo.checked = imlove.Checkbox("A checkbox", demo.checked)
    imlove.SameLine(160)
    if imlove.RadioButton("A", demo.radioChoice == 1) then
      demo.radioChoice = 1
    end
    imlove.SameLine()
    if imlove.RadioButton("B", demo.radioChoice == 2) then
      demo.radioChoice = 2
    end
    imlove.SameLine()
    if imlove.RadioButton("C", demo.radioChoice == 3) then
      demo.radioChoice = 3
    end

    imlove.TextColored({ 0.4, 0.9, 1, 1 }, "TextColored: any {r,g,b,a}.")
    imlove.TextDisabled("TextDisabled: for de-emphasized captions.")
    imlove.TextWrapped("TextWrapped reflows to the window's available " ..
      "width instead of running off the edge — good for prose like this.")
    imlove.BulletText("BulletText: prefixed with a small bullet.")

    imlove.Separator()
    imlove.TextDisabled("Sliders, drags, and a progress bar.")
    demo.sliderFloat = imlove.SliderFloat("SliderFloat", demo.sliderFloat, 0, 1)
    demo.sliderInt = imlove.SliderInt("SliderInt", demo.sliderInt, 0, 10)
    demo.dragFloat = imlove.DragFloat("DragFloat", demo.dragFloat, 0.02, 0, 5)
    demo.dragInt = imlove.DragInt("DragInt", demo.dragInt, 1, -10, 10)
    imlove.ProgressBar(demo.sliderFloat)

    imlove.Separator()
    imlove.TextDisabled("TreeNode: PushID() each child so identical labels " ..
      "don't collide.")
    if imlove.TreeNode("Fruits (TreeNode)") then
      for i, name in ipairs(demo.treeFruits) do
        imlove.PushID(i)
        if imlove.Selectable(name, demo.treeSelected == i) then
          demo.treeSelected = i
        end
        imlove.PopID()
      end
      imlove.TreePop()
    end

    imlove.Spacing()
    imlove.TextDisabled("Selectable: a flat pick-one-of-many list, no tree.")
    for i, name in ipairs(demo.flatFruits) do
      imlove.PushID(1000 + i) -- a distinct range from the TreeNode's ids above
      if imlove.Selectable(name, demo.flatSelected == i) then
        demo.flatSelected = i
      end
      imlove.PopID()
    end

    imlove.Spacing()
    imlove.TextDisabled("Combo: a closed dropdown preview.")
    demo.comboValue = imlove.Combo("Combo", demo.comboValue, demo.comboItems)

    imlove.TextDisabled("ListBox: always-visible, scrolls past its height.")
    demo.listValue = imlove.ListBox("ListBox", demo.listValue, demo.listItems, 4)

    imlove.Separator()
    imlove.TextDisabled("PlotLines/PlotHistogram fed by a rolling sine wave.")
    pushWaveSample()
    imlove.PlotLines("sine", demo.sineBuf, -1, 1, nil, nil,
      string.format("%.2f", demo.sineBuf[#demo.sineBuf] or 0))
    imlove.PlotHistogram("|cosine|", demo.cosineBuf, 0, 1)
  end
end

-- ----------------------------------------------------------------- Layout

local function showLayout()
  if imlove.CollapsingHeader("Layout") then
    imlove.TextDisabled("SameLine: three ways to place the next widget.")
    imlove.Text("no-arg:")
    imlove.SameLine()
    imlove.Text("right after, plus one item spacing")

    imlove.Text("fixed column:")
    imlove.SameLine(120)
    imlove.Text("<- always starts at x=120")

    imlove.Text("extra gap:")
    imlove.SameLine(nil, 40)
    imlove.Text("<- 40px gap instead of the default")

    imlove.Separator()
    imlove.TextDisabled("Indent/Unindent shift the cursor, no ID push.")
    imlove.Text("not indented")
    imlove.Indent()
    imlove.Text("indented once")
    imlove.Indent()
    imlove.Text("indented twice")
    imlove.Unindent()
    imlove.Unindent()

    imlove.Separator()
    imlove.TextDisabled("Dummy/Spacing/NewLine reserve blank layout space.")
    imlove.Text("before")
    imlove.Spacing()
    imlove.Text("after Spacing()")
    imlove.Dummy(0, 16)
    imlove.Text("after a 16px Dummy()")
    imlove.Text("forced")
    imlove.NewLine()
    imlove.Text("onto its own line even though nothing called SameLine()")

    imlove.Separator()
    demo.showChildBorder = imlove.Checkbox("bordered child",
      demo.showChildBorder)
    imlove.TextDisabled("BeginChild: a fixed-size scrolling region embedded " ..
      "in this window — try the wheel or its scrollbar.")
    if imlove.BeginChild("demo-child", 0, 110, demo.showChildBorder) then
      for _, line in ipairs(demo.childLines) do imlove.Text("%s", line) end
    end
    imlove.EndChild()

    imlove.Separator()
    imlove.TextDisabled("Item queries: IsItemHovered/Active/Clicked, read " ..
      "right after the widget they describe.")
    imlove.Button("query me")
    imlove.Text("hovered=%s  active=%s  clicked=%s",
      tostring(imlove.IsItemHovered()), tostring(imlove.IsItemActive()),
      tostring(imlove.IsItemClicked()))
  end
end

-- --------------------------------------------------------- Popups & tooltips

local function showPopups()
  if imlove.CollapsingHeader("Popups & tooltips") then
    imlove.TextDisabled("SetTooltip: one line, shown on hover.")
    imlove.Button("hover me (SetTooltip)")
    if imlove.IsItemHovered() then
      imlove.SetTooltip("clicked %d times so far", demo.clickCount)
    end

    imlove.TextDisabled("BeginTooltip/EndTooltip: more than one widget.")
    imlove.Button("hover me (BeginTooltip)")
    if imlove.IsItemHovered() then
      imlove.BeginTooltip()
      imlove.Text("a tooltip can hold")
      imlove.TextColored({ 1, 0.8, 0.3, 1 }, "any widgets at all")
      imlove.EndTooltip()
    end

    imlove.Separator()
    imlove.TextDisabled("OpenPopup/BeginPopup: a floating menu, dismissed " ..
      "by clicking outside it.")
    if imlove.Button("Open menu") then imlove.OpenPopup("demo-menu") end
    if imlove.BeginPopup("demo-menu") then
      if imlove.Selectable("Pick A", false) then
        demo.menuLastPick = "A"
        imlove.CloseCurrentPopup()
      end
      if imlove.Selectable("Pick B", false) then
        demo.menuLastPick = "B"
        imlove.CloseCurrentPopup()
      end
      if imlove.Selectable("Pick C", false) then
        demo.menuLastPick = "C"
        imlove.CloseCurrentPopup()
      end
      imlove.EndPopup()
    end
    imlove.SameLine()
    imlove.Text("last pick: %s", demo.menuLastPick)

    imlove.Separator()
    imlove.TextDisabled("BeginPopupContextItem: right-click the row below.")
    imlove.Selectable("right-click me", false)
    if imlove.BeginPopupContextItem() then
      if imlove.Selectable("Option 1", false) then
        demo.contextLastPick = "Option 1"
        imlove.CloseCurrentPopup()
      end
      if imlove.Selectable("Option 2", false) then
        demo.contextLastPick = "Option 2"
        imlove.CloseCurrentPopup()
      end
      imlove.EndPopup()
    end
    imlove.Text("last context pick: %s", demo.contextLastPick)

    imlove.Separator()
    imlove.TextDisabled("BeginPopupModal: dims and blocks everything else " ..
      "until you answer it.")
    if imlove.Button("Delete something") then
      imlove.OpenPopup("Confirm delete?")
    end
    if imlove.BeginPopupModal("Confirm delete?") then
      imlove.Text("This can't be undone. Really delete it?")
      if imlove.Button("Delete##confirm") then
        demo.modalDeleteCount = demo.modalDeleteCount + 1
        imlove.CloseCurrentPopup()
      end
      imlove.SameLine()
      if imlove.Button("Cancel") then imlove.CloseCurrentPopup() end
      imlove.EndPopup()
    end
    imlove.Text("confirmed deletes: %d", demo.modalDeleteCount)
  end
end

-- ----------------------------------------------------------------- Windows

local function showWindows()
  if imlove.CollapsingHeader("Windows") then
    imlove.TextDisabled("A second window, with flags you can toggle live.")
    demo.showSecondary = imlove.Checkbox("Show secondary window",
      demo.showSecondary)
    if demo.showSecondary and not demo.secondaryOpen then
      -- Reopened via the checkbox after being closed by its own X — same
      -- round trip a real caller performs on its own `open` variable.
      demo.secondaryOpen = true
    end
    demo.secNoTitleBar = imlove.Checkbox("NoTitleBar", demo.secNoTitleBar)
    imlove.SameLine()
    demo.secNoResize = imlove.Checkbox("NoResize", demo.secNoResize)
    imlove.SameLine()
    demo.secAlwaysAutoResize = imlove.Checkbox("AlwaysAutoResize",
      demo.secAlwaysAutoResize)
  end
end

--- A second, independent top-level window. This MUST be Begin()/End()'d
--- outside of "imlove Demo"'s own Begin()/End() block — imlove only ever
--- has one window open at a time (nesting Begin() calls errors) — so
--- ShowDemoWindow() calls this after closing the main window, not from
--- inside showWindows() above.
local function showSecondaryWindow()
  if not demo.showSecondary then return end
  local flags = {}
  if demo.secNoTitleBar then flags[#flags + 1] = "NoTitleBar" end
  if demo.secNoResize then flags[#flags + 1] = "NoResize" end
  if demo.secAlwaysAutoResize then
    flags[#flags + 1] = "AlwaysAutoResize"
  end
  imlove.SetNextWindowPos(470, 40, "once")
  if not demo.secAlwaysAutoResize then
    imlove.SetNextWindowSize(220, 120, "once")
  end
  local notCollapsed, open = imlove.Begin(
    "imlove Demo: Secondary##imlove_demo", demo.secondaryOpen, flags)
  if notCollapsed then
    imlove.TextWrapped("Close me with the X, or uncheck the box in " ..
      "the main demo window.")
  end
  imlove.End()
  demo.secondaryOpen = open
  if open == false then demo.showSecondary = false end
end

--- Builds (or skips) the "imlove Demo" window for the current frame. Call it
--- once per frame, between imlove.NewFrame() and imlove.Render() — exactly
--- where you'd call any of your own Begin()/End() blocks.
---
--- open follows imlove.Begin()'s own convention: nil means no close button
--- (the window always shows); a boolean adds one, and the return value is
--- that boolean, possibly flipped to false the frame it's clicked — assign
--- it back to your variable, the same as any other imlove value.
local function ShowDemoWindow(open)
  imlove.SetNextWindowPos(20, 20, "once")
  imlove.SetNextWindowSize(430, 520, "once")
  local notCollapsed, stillOpen = imlove.Begin("imlove Demo", open)
  if notCollapsed then
    imlove.TextDisabled("imlove %s -- a self-documenting tour of every " ..
      "widget, built from nothing but the public API (see imlove_demo.lua).",
      imlove._VERSION)
    imlove.Separator()

    showHelp()
    showWidgets()
    showLayout()
    showPopups()
    showWindows()
  end
  imlove.End()

  -- Outside the main window's Begin()/End() block -- see
  -- showSecondaryWindow()'s comment for why.
  showSecondaryWindow()

  return stillOpen
end

return ShowDemoWindow
