--[[
A minimal stand-in for the LÖVE API, so imlove can run headless under plain
luajit. It provides exactly what imlove touches at runtime: a font that can
measure text (fixed-width: 7px per character, 14px tall, which makes test
geometry easy to reason about), a mouse position, and graphics functions that
record their calls into `stub.calls` instead of drawing, so tests can assert
on what would have been drawn.
]]

local stub = { mouseX = 0, mouseY = 0, calls = {} }

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
  local function record(name)
    return function(...) calls[#calls + 1] = { name, ... } end
  end
  love = {
    graphics = {
      getFont   = function() return font end,
      newFont   = function() return font end,
      setFont   = record("setFont"),
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
  }
end

function stub.setMouse(x, y)
  stub.mouseX, stub.mouseY = x, y
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
