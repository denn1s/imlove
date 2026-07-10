--[[
Runs imlove's own demo window. Run from the repo root with:

    love . demo

This example is intentionally thin — imlove_demo.lua (at the repo root) is
the star here, not this file. All this does is call ShowDemoWindow() once a
frame and handle its close button: click the demo window's X and it
disappears, replaced by a small "reopen" window, exactly the `open`
round-trip any imlove.Begin() caller has to handle.
]]

local imlove = require "imlove"
local ShowDemoWindow = require "imlove_demo"

local demoOpen = true

local function reopenPrompt()
  imlove.SetNextWindowPos(20, 20, "once")
  if imlove.Begin("Reopen the demo##demo-example", nil,
    "AlwaysAutoResize") then
    imlove.Text("You closed the imlove Demo window.")
    if imlove.Button("Reopen it") then demoOpen = true end
  end
  imlove.End()
end

-- ---------------------------------------------------------- module callbacks

local M = {}

function M.load()
  love.graphics.setBackgroundColor(0.11, 0.12, 0.15)
end

function M.update(dt)
  imlove.NewFrame()
  demoOpen = ShowDemoWindow(demoOpen)
  if not demoOpen then reopenPrompt() end
end

function M.draw()
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.print(
    "love . demo -- imlove's own demo window (see imlove_demo.lua)", 10, 10)
  imlove.Render()
end

function M.mousepressed(x, y, button)
  imlove.mousepressed(x, y, button)
end

function M.mousereleased(x, y, button)
  imlove.mousereleased(x, y, button)
end

function M.wheelmoved(dx, dy)
  imlove.wheelmoved(dx, dy)
end

function M.keypressed(key)
  if imlove.keypressed(key) then return end
  if key == "escape" then love.event.quit() end
end

function M.textinput(text)
  imlove.textinput(text)
end

return M
