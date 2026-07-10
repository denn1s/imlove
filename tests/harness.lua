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
  H.stub.setScreenSize(800, 600)
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

-- A full right-click at (x, y): press + one frame, release + one frame —
-- same interleaving as H.click, button 2 instead of button 1. Right-clicks
-- are a one-frame latch (see ctx.rightPressLatch), consumed on the press
-- frame, so most tests only need the first frame; the release is still
-- forwarded for completeness/symmetry with a real event stream.
function H.rightClick(x, y, ui)
  H.stub.setMouse(x, y)
  H.im.mousepressed(x, y, 2)
  H.frame(ui)
  H.im.mousereleased(x, y, 2)
  H.frame(ui)
end

-- Generic single event + frame, for tests that need to interleave presses/
-- releases/frames in an order H.click()/H.rightClick() don't cover (e.g. a
-- press over one popup while another is open). Returns whatever
-- mousepressed()/mousereleased() returned (was the event consumed), same as
-- calling them directly would — but, critically, also moves the stub's
-- tracked mouse position to (x, y) first: a real LÖVE event's x/y always
-- matches love.mouse.getPosition() by the time NewFrame() polls it, and
-- skipping this step is a common way to accidentally test the wrong point.
function H.press(x, y, button, ui)
  H.stub.setMouse(x, y)
  local consumed = H.im.mousepressed(x, y, button or 1)
  H.frame(ui)
  return consumed
end

function H.release(x, y, button, ui)
  H.stub.setMouse(x, y)
  local consumed = H.im.mousereleased(x, y, button or 1)
  H.frame(ui)
  return consumed
end

-- A textinput event + one frame — types one chunk of UTF-8 text into
-- whatever widget currently holds keyboard focus. Mirrors H.press's
-- event-then-frame shape. Returns whatever imlove.textinput() returned (was
-- the event consumed).
function H.type(text, ui)
  local consumed = H.im.textinput(text)
  H.frame(ui)
  return consumed
end

-- A keypressed event + one frame — named-key edits (backspace, arrows, home,
-- end, return, escape, ctrl+v/ctrl+c) on whatever widget currently holds
-- keyboard focus. Returns whatever imlove.keypressed() returned.
function H.key(key, ui)
  local consumed = H.im.keypressed(key)
  H.frame(ui)
  return consumed
end

-- Queues several textinput/keypressed events (in the exact order given) and
-- then runs a single frame — for asserting that multiple keys/chunks queued
-- within one frame are drained and applied in order. `events` is an array of
-- either plain strings (textinput chunks) or { key = "backspace" }-shaped
-- tables (keypresses).
function H.typeEvents(events, ui)
  for _, ev in ipairs(events) do
    if type(ev) == "table" then
      H.im.keypressed(ev.key)
    else
      H.im.textinput(ev)
    end
  end
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
