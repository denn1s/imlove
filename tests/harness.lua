--[[
Shared helpers for the headless tests. The central idea: a test declares its
UI as a function, then "plays" frames and synthetic mouse input against it,
exactly the way LÖVE would (events first, then update, then draw).
]]

local H = {}
H.stub = require "stub_love"

-- A fresh imlove with a fresh love stub. Re-requiring the module resets all
-- of its internal state, because that state lives in module-local tables.
function H.fresh()
  H.stub.install()
  H.stub.clearCalls()
  H.stub.setMouse(0, 0)
  package.loaded["imlove"] = nil
  H.im = require "imlove"
  return H.im
end

-- Run one frame: NewFrame, build the UI, Render. Mirrors love.run's
-- update-then-draw order.
function H.frame(ui)
  H.im.NewFrame()
  if ui then ui() end
  H.im.Render()
end

-- A full click at (x, y): press + one frame, release + one frame — the same
-- event/frame interleaving LÖVE produces. Widget "pressed" results appear on
-- the release frame.
function H.click(x, y, ui)
  H.stub.setMouse(x, y)
  H.im.mousepressed(x, y, 1)
  H.frame(ui)
  H.im.mousereleased(x, y, 1)
  H.frame(ui)
end

-- A wheel event at the current mouse position, applied on the next frame —
-- mirrors H.click's event-then-frame interleaving.
function H.wheel(dx, dy, ui)
  H.im.wheelmoved(dx, dy)
  H.frame(ui)
end

-- Capture the last widget's rectangle into r as x1/y1/x2/y2.
-- Call right after the widget, inside the UI function.
function H.grabRect(r, im)
  r.x1, r.y1 = im.GetItemRectMin()
  r.x2, r.y2 = im.GetItemRectMax()
end

function H.center(r)
  return (r.x1 + r.x2) / 2, (r.y1 + r.y2) / 2
end

return H
