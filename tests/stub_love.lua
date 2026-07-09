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
stub.font = font

-- (Re)define the global `love`. Called by the harness before every test so
-- each test starts from a clean slate.
function stub.install()
  local calls = stub.calls
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
      print     = record("print"),
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

return stub
