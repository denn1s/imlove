--[[
A minimal stand-in for the LÖVE API, so imlove can run headless under plain
luajit. It provides exactly what imlove touches at runtime: a font that can
measure text (fixed-width: 7px per character, 14px tall, which makes test
geometry easy to reason about), a mouse position, and graphics functions that
record their calls into `stub.calls` instead of drawing, so tests can assert
on what would have been drawn.
]]

-- files: love.filesystem's in-memory backing store, name -> contents.
-- ctrlDown: love.keyboard.isDown("lctrl"/"rctrl") stub state.
-- clipboard: love.system.get/setClipboardText's in-memory backing.
local stub = { mouseX = 0, mouseY = 0, calls = {}, screenW = 800, screenH = 600,
  files = {}, ctrlDown = false, clipboard = "" }

local font = {}
function font:getWidth(text) return #tostring(text) * 7 end
function font:getHeight() return 14 end
-- A minimal stand-in for LÖVE's Font:getWrap(text, wraplimit): greedy word
-- wrap using the same fixed 7px-per-character metric as getWidth, one
-- output line per paragraph (existing "\n"s always break). Returns width,
-- wrappedLines — same shape as the real thing (width, table).
function font:getWrap(text, wraplimit)
  local lines = {}
  for paragraph in (text .. "\n"):gmatch("(.-)\n") do
    local cur = ""
    for word in paragraph:gmatch("%S+") do
      local candidate = cur == "" and word or (cur .. " " .. word)
      if cur == "" or #candidate * 7 <= wraplimit then
        cur = candidate
      else
        lines[#lines + 1] = cur
        cur = word
      end
    end
    lines[#lines + 1] = cur
  end
  local maxW = 0
  for _, line in ipairs(lines) do
    local w = #line * 7
    if w > maxW then maxW = w end
  end
  return maxW, lines
end
stub.font = font

-- (Re)define the global `love`. Called by the harness before every test so
-- each test starts from a clean slate.
function stub.install()
  local calls = stub.calls
  stub.scissor = nil
  -- A fresh in-memory "disk" every install() (i.e. every H.fresh()) — tests
  -- get file isolation the same way they get isolation from every other
  -- piece of module state. Tests that specifically want a file to survive
  -- a fresh imlove module reload (settings persistence round-trips) must
  -- re-require "imlove" directly instead of going through H.fresh(), so
  -- this store is left untouched — see tests/test_settings.lua.
  stub.files = {}
  stub.clipboard = ""
  local function record(name)
    return function(...) calls[#calls + 1] = { name, ... } end
  end
  love = {
    filesystem = {
      -- Mirrors love.filesystem.read(name): returns contents, size on
      -- success, or nil, errormsg if the "file" doesn't exist — same
      -- contract as the real thing, so imlove.lua's defensive handling
      -- gets genuinely exercised.
      read = function(name)
        local data = stub.files[name]
        if data == nil then return nil, "could not open file " .. tostring(name) end
        return data, #data
      end,
      write = function(name, data)
        stub.files[name] = data
        return true
      end,
      getInfo = function(name)
        local data = stub.files[name]
        if data == nil then return nil end
        return { type = "file", size = #data }
      end,
      getSaveDirectory = function() return "/tmp/imlove-test-save" end,
    },
    graphics = {
      getFont   = function() return font end,
      newFont   = function() return font end,
      setFont   = record("setFont"),
      getDimensions = function() return stub.screenW, stub.screenH end,
      getColor  = function() return 1, 1, 1, 1 end,
      setColor  = record("setColor"),
      rectangle = record("rectangle"),
      polygon   = record("polygon"),
      line      = record("line"),
      circle    = record("circle"),
      print     = record("print"),
      getScissor = function()
        if not stub.scissor then return end -- LÖVE returns nothing, not nil
        local s = stub.scissor
        return s.x, s.y, s.w, s.h
      end,
      setScissor = function(x, y, w, h)
        calls[#calls + 1] = { "setScissor", x, y, w, h }
        if x == nil then
          stub.scissor = nil
        else
          stub.scissor = { x = x, y = y, w = w, h = h }
        end
      end,
    },
    mouse = {
      getPosition = function() return stub.mouseX, stub.mouseY end,
    },
    keyboard = {
      -- imlove only ever asks about lctrl/rctrl (to detect ctrl-click and
      -- ctrl+v/ctrl+c); stub.ctrlDown drives both uniformly.
      isDown = function(...)
        if not stub.ctrlDown then return false end
        for _, key in ipairs({ ... }) do
          if key == "lctrl" or key == "rctrl" then return true end
        end
        return false
      end,
    },
    system = {
      getClipboardText = function() return stub.clipboard end,
      setClipboardText = function(text) stub.clipboard = text end,
    },
    timer = {
      -- Fixed fake delta: deterministic, and non-zero so anything that
      -- divides by dt (or accumulates a phase) behaves sanely under test.
      getDelta = function() return 1 / 60 end,
    },
  }
end

function stub.setMouse(x, y)
  stub.mouseX, stub.mouseY = x, y
end

-- Sets whether love.keyboard.isDown("lctrl"/"rctrl") reports held, for
-- exercising ctrl-click-to-edit and ctrl+v/ctrl+c.
function stub.setCtrl(down)
  stub.ctrlDown = down
end

-- Sets the stubbed screen size that love.graphics.getDimensions() reports —
-- what popups/tooltips clamp themselves against. Defaults to 800x600;
-- stub.install() does not reset this, so call it again in setup() if a test
-- needs the default restored after a previous test changed it.
function stub.setScreenSize(w, h)
  stub.screenW, stub.screenH = w, h
end

function stub.clearCalls()
  for i = #stub.calls, 1, -1 do stub.calls[i] = nil end
end

-- Every string that Render() printed, in draw order.
function stub.printed()
  local out = {}
  for _, c in ipairs(stub.calls) do
    if c[1] == "print" then out[#out + 1] = tostring(c[2]) end
  end
  return out
end

-- Every setScissor(...) call Render() made, in order, as { x, y, w, h }
-- (x == nil means "scissor disabled").
function stub.scissorCalls()
  local out = {}
  for _, c in ipairs(stub.calls) do
    if c[1] == "setScissor" then
      out[#out + 1] = { c[2], c[3], c[4], c[5] }
    end
  end
  return out
end

return stub
