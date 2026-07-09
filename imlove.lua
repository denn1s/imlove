--[[----------------------------------------------------------------------------
imlove — an immediate-mode debug UI for LÖVE 11.5, in one pure-Lua file.

  local imlove = require "imlove"     -- returns this module table; no globals

The API deliberately mirrors Dear ImGui (https://github.com/ocornut/imgui):
same names, same call patterns, so what you learn here transfers to the real
thing. See README.md for the full reference and the ImGui mapping table.

How an immediate-mode GUI works (for the curious reader):

  There are no widget objects. Every frame, your code *re-declares* the whole
  UI by calling functions like Button() and SliderFloat(). Each call does
  three jobs at once:
    1. lays the widget out (advances a cursor inside the current window),
    2. checks the mouse against the widget's rectangle and reports
       interaction back to you as return values ("was it clicked?"),
    3. records draw commands into a list that Render() plays back later.
  The library keeps only a small amount of state between frames: window
  positions/collapsed flags, which tree nodes are open, and which widget is
  currently "active" (being held). Everything else is rebuilt from scratch,
  which is why the code below has no create/destroy — just per-frame calls.

Two classic IMGUI idioms show up throughout, worth knowing:

  * hot/active: a widget is "hot" when the mouse hovers it, and "active" when
    the mouse button was pressed on it and is still held. A Button only
    "fires" when the mouse is *released* while that button is still both
    active and hot — which is why you can press, drag off, and release to
    cancel a click, just like native buttons everywhere.

  * one-frame lag: a window's size depends on its contents, but its contents
    haven't run yet when the frame starts. So hit-testing ("which window is
    under the mouse?") uses the sizes recorded at the *end of last frame*.
    At 60 fps nobody can tell, and it keeps the whole library single-pass.

MIT License — see LICENSE.
------------------------------------------------------------------------------]]

local imlove = { _VERSION = "1.0.0" }

-- io mirrors Dear ImGui's ImGuiIO flags. After NewFrame() these tell the host
-- game whether the UI wants the mouse/keyboard this frame, so the game can
-- ignore input the UI consumed. The input-forwarding functions at the bottom
-- of this file also return the same answer per event, which is usually the
-- more convenient form in LÖVE callbacks.
imlove.io = {
  WantCaptureMouse    = false,
  WantCaptureKeyboard = false, -- always false in v1: no keyboard widgets yet
}

--------------------------------------------------------------------------------
-- Style: the one built-in color scheme (a dark theme in the spirit of ImGui's
-- default). Colors are {r, g, b, a} with 0..1 components, LÖVE 11 style.
--------------------------------------------------------------------------------

local style = {
  windowPadding = 8,        -- gap between window edge and content
  framePadding  = { 6, 3 }, -- x/y padding inside buttons, sliders, etc.
  itemSpacing   = { 8, 5 }, -- x/y gap between consecutive widgets
  innerSpacing  = 6,        -- gap between a widget's frame and its label
  indent        = 16,       -- horizontal shift per open TreeNode level
  sliderWidth   = 160,      -- width of a slider's track
  grabWidth     = 10,       -- width of a slider's grab handle
  rounding      = 3,        -- corner radius on frames and windows
  minWindowWidth = 60,

  colors = {
    text             = { 0.92, 0.92, 0.92, 1.00 },
    windowBg         = { 0.09, 0.09, 0.11, 0.96 },
    border           = { 0.43, 0.43, 0.50, 0.50 },
    titleBg          = { 0.13, 0.14, 0.17, 1.00 },
    titleBgActive    = { 0.16, 0.29, 0.48, 1.00 }, -- front-most window
    frameBg          = { 0.20, 0.22, 0.27, 1.00 },
    frameBgHovered   = { 0.26, 0.32, 0.43, 1.00 },
    frameBgActive    = { 0.31, 0.40, 0.55, 1.00 },
    button           = { 0.20, 0.32, 0.53, 1.00 },
    buttonHovered    = { 0.26, 0.42, 0.69, 1.00 },
    buttonActive     = { 0.16, 0.53, 0.90, 1.00 },
    checkMark        = { 0.30, 0.62, 1.00, 1.00 },
    sliderGrab       = { 0.34, 0.55, 0.85, 1.00 },
    sliderGrabActive = { 0.30, 0.62, 1.00, 1.00 },
    header           = { 0.26, 0.59, 0.98, 0.31 }, -- selected Selectable
    headerHovered    = { 0.26, 0.59, 0.98, 0.55 },
    separator        = { 0.43, 0.43, 0.50, 0.50 },
  },
}

--------------------------------------------------------------------------------
-- Context: all library state lives in this one table (nothing global).
--------------------------------------------------------------------------------

local ctx = {
  frame       = 0,     -- frame counter; windows stamp it when submitted
  inFrame     = false, -- true between NewFrame() and Render()
  font        = nil,   -- font captured at NewFrame(), used for all measuring

  windows     = {},    -- title -> persistent window state
  windowOrder = {},    -- draw order, back-to-front (last = front-most)
  windowCount = 0,     -- used to cascade default positions of new windows

  currentWindow = nil, -- window between Begin()/End(), nil outside
  hoveredWindow = nil, -- front-most window under the mouse (last-frame rects)
  nextWindowPos = nil, -- pending SetNextWindowPos(), consumed by next Begin()

  idStack   = {},      -- see PushID(); slot 1 is always the window's title
  activeId  = nil,     -- id of the widget being held with the mouse, if any
  hoveredId = nil,     -- id of the widget under the mouse this frame, if any
  dragWindow = nil,    -- window being dragged by its title bar, if any

  openNodes = {},      -- TreeNode id -> true while open (persists over frames)

  -- Mouse state. LÖVE delivers presses/releases as events between frames, so
  -- the forwarding functions only *latch* them here; NewFrame() converts each
  -- latch into a one-frame `pressed`/`released` flag that widgets read.
  mouse = { x = 0, y = 0, down = false, pressed = false, released = false },
  pressLatch   = false,
  releaseLatch = false,
}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function pointIn(px, py, x, y, w, h)
  return px >= x and px < x + w and py >= y and py < y + h
end

-- Dear ImGui's "##" convention: everything after "##" is part of the widget's
-- identity but is not displayed. "Delete##entity7" shows "Delete" but has a
-- unique id, so ten Delete buttons in a list don't collide.
-- Returns: displayText, idText.
local function splitLabel(label)
  label = tostring(label)
  local cut = label:find("##", 1, true)
  if cut then
    return label:sub(1, cut - 1), label
  end
  return label, label
end

-- A widget's full id is its label joined with the whole id stack (which starts
-- with the window title), so "Button 'X' inside PushID(3) inside window 'W'"
-- and the same button under PushID(4) are different widgets. "\31" (ASCII
-- unit separator) just keeps user strings from accidentally colliding.
local function makeId(idText)
  return table.concat(ctx.idStack, "\31") .. "\31" .. idText
end

-- Measure text with the frame's font. Handles embedded newlines the same way
-- love.graphics.print will draw them.
local function textSize(text)
  local font = ctx.font
  local maxW, lines = 0, 0
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local w = font:getWidth(line)
    if w > maxW then maxW = w end
    lines = lines + 1
  end
  return maxW, lines * font:getHeight()
end

local function frameHeight()
  return ctx.font:getHeight() + style.framePadding[2] * 2
end

--------------------------------------------------------------------------------
-- Draw list: widgets never draw directly. They append primitive commands to
-- their window's list, and Render() plays every window's list back in
-- z-order. This is what lets you build the UI from love.update while the
-- actual drawing happens at the end of love.draw.
--------------------------------------------------------------------------------

local function pushRect(win, mode, x, y, w, h, color, rounding)
  local cmd = { kind = "rect", mode = mode, x = x, y = y, w = w, h = h,
                color = color, rounding = rounding or 0 }
  win.drawList[#win.drawList + 1] = cmd
  return cmd -- returned so Begin()/End() can patch sizes known only later
end

local function pushText(win, text, x, y, color)
  win.drawList[#win.drawList + 1] = { kind = "text", text = text,
    x = math.floor(x + 0.5), y = math.floor(y + 0.5), color = color }
end

local function pushTriangle(win, x1, y1, x2, y2, x3, y3, color)
  win.drawList[#win.drawList + 1] = { kind = "triangle", color = color,
    x1 = x1, y1 = y1, x2 = x2, y2 = y2, x3 = x3, y3 = y3 }
end

local function pushLine(win, x1, y1, x2, y2, color)
  win.drawList[#win.drawList + 1] = { kind = "line", color = color,
    x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end

--------------------------------------------------------------------------------
-- Windows: hit-testing and z-order
--------------------------------------------------------------------------------

-- The rectangle a window occupied at the end of the frame it was last
-- submitted (collapsed windows occupy only their title bar).
local function windowRect(win)
  local h = win.collapsed and win.titleH or win.h
  return win.x, win.y, win.w, h
end

-- Front-most window under the point, considering only windows that were
-- actually submitted last frame (a window whose Begin() stopped being called
-- disappears, and must stop swallowing clicks too).
local function windowAt(x, y)
  for i = #ctx.windowOrder, 1, -1 do
    local win = ctx.windowOrder[i]
    if win.lastFrame and win.lastFrame >= ctx.frame - 1 then
      local wx, wy, ww, wh = windowRect(win)
      if pointIn(x, y, wx, wy, ww, wh) then return win end
    end
  end
  return nil
end

local function bringToFront(win)
  for i = 1, #ctx.windowOrder do
    if ctx.windowOrder[i] == win then
      table.remove(ctx.windowOrder, i)
      ctx.windowOrder[#ctx.windowOrder + 1] = win
      return
    end
  end
end

--------------------------------------------------------------------------------
-- Widget behavior: the hot/active logic shared by every clickable widget.
--
-- Given the widget's rectangle, returns three booleans:
--   hovered — mouse is over it (and no *other* widget is being held)
--   held    — the mouse was pressed on it and is still down, wherever the
--             mouse is now (this is what makes sliders keep dragging even
--             when the cursor slips off the track)
--   pressed — the mouse was released over it this frame while held: a click.
--------------------------------------------------------------------------------

local function behavior(win, id, x, y, w, h)
  local m = ctx.mouse
  local hovered = ctx.hoveredWindow == win
    and ctx.dragWindow == nil
    and (ctx.activeId == nil or ctx.activeId == id)
    and pointIn(m.x, m.y, x, y, w, h)

  if hovered then ctx.hoveredId = id end

  if hovered and m.pressed and ctx.activeId == nil then
    ctx.activeId = id
  end

  local pressed = false
  if ctx.activeId == id and m.released then
    pressed = hovered
    ctx.activeId = nil
  end

  return hovered, ctx.activeId == id, pressed
end

--------------------------------------------------------------------------------
-- Layout: each window carries a cursor. itemAdd() places a rectangle of the
-- requested size at the cursor, advances to the next line, and remembers the
-- rectangle so SameLine() and GetItemRect*() can refer back to it.
--------------------------------------------------------------------------------

local function itemAdd(win, w, h)
  local x, y
  if win.sameLineX then
    -- SameLine() was called: continue on the current line.
    x, y = win.sameLineX, win.lineY
    win.sameLineX = nil
    if h > win.lineH then win.lineH = h end
  else
    x, y = win.innerX + win.indent, win.nextY
    win.lineY, win.lineH = y, h
  end
  win.nextY = win.lineY + win.lineH + style.itemSpacing[2]
  win.prevItem.x, win.prevItem.y = x, y
  win.prevItem.w, win.prevItem.h = w, h
  -- Track the content extents; End() turns these into the window's size.
  if x + w > win.contentMaxX then win.contentMaxX = x + w end
  if y + h > win.contentMaxY then win.contentMaxY = y + h end
  return x, y
end

-- Width available for widgets that stretch across the window (Selectable,
-- Separator). Uses last frame's window width — the one-frame lag again.
local function availWidth(win)
  local x = win.innerX + win.indent
  local right = win.x + win.w - style.windowPadding
  return math.max(right - x, 0)
end

local function requireWindow(name)
  local win = ctx.currentWindow
  if not win then
    error("imlove." .. name .. "() called outside a Begin()/End() pair", 3)
  end
  return win
end

--------------------------------------------------------------------------------
-- Frame lifecycle
--------------------------------------------------------------------------------

--- Start a UI frame. Call once per frame (top of love.update is the natural
--- place) before any other imlove call. Equivalent of ImGui::NewFrame().
function imlove.NewFrame()
  if ctx.inFrame then
    error("imlove.NewFrame() called twice without imlove.Render() in between", 2)
  end
  ctx.frame = ctx.frame + 1
  ctx.inFrame = true
  -- The UI owns its font. Adopting the game's current font here (as v1.0.0
  -- did) is a trap: the game may release() that font at any time — e.g. a
  -- scene unloading — and the UI would then draw with a dead object.
  ctx.font = ctx.font or love.graphics.newFont(13)

  local m = ctx.mouse
  m.x, m.y = love.mouse.getPosition()
  m.pressed, ctx.pressLatch = ctx.pressLatch, false
  m.released, ctx.releaseLatch = ctx.releaseLatch, false

  -- Safety net: if the mouse is up and there is no release event left to
  -- deliver, nothing can legitimately still be active. This unsticks widgets
  -- whose window stopped being submitted mid-drag.
  if not m.down and not m.released and not m.pressed then
    ctx.activeId = nil
    ctx.dragWindow = nil
  end

  ctx.hoveredId = nil
  ctx.hoveredWindow = windowAt(m.x, m.y)
  if m.pressed and ctx.hoveredWindow then
    bringToFront(ctx.hoveredWindow)
  end

  imlove.io.WantCaptureMouse = ctx.hoveredWindow ~= nil
    or ctx.activeId ~= nil or ctx.dragWindow ~= nil
  imlove.io.WantCaptureKeyboard = false
end

--- Draw the UI. Call at the end of love.draw so the UI lands on top of the
--- game. Plays back every window's draw list in z-order. Equivalent of
--- ImGui::Render() + backend draw.
function imlove.Render()
  if not ctx.inFrame then return end -- nothing declared this frame; no-op
  if ctx.currentWindow then
    error("imlove.Render() called with window '" .. ctx.currentWindow.title
      .. "' still open — missing imlove.End()", 2)
  end
  ctx.inFrame = false

  local g = love.graphics
  local pr, pg, pb, pa = g.getColor()
  local prevFont = g.getFont()
  g.setFont(ctx.font)

  for i = 1, #ctx.windowOrder do
    local win = ctx.windowOrder[i]
    if win.lastFrame == ctx.frame then
      for j = 1, #win.drawList do
        local c = win.drawList[j]
        g.setColor(c.color)
        if c.kind == "rect" then
          g.rectangle(c.mode, c.x, c.y, c.w, c.h, c.rounding, c.rounding)
        elseif c.kind == "text" then
          g.print(c.text, c.x, c.y)
        elseif c.kind == "triangle" then
          g.polygon("fill", c.x1, c.y1, c.x2, c.y2, c.x3, c.y3)
        elseif c.kind == "line" then
          g.line(c.x1, c.y1, c.x2, c.y2)
        end
      end
    end
  end

  g.setFont(prevFont)
  g.setColor(pr, pg, pb, pa)
end

--------------------------------------------------------------------------------
-- Windows
--------------------------------------------------------------------------------

--- Begin a window. Windows are draggable by their title bar, collapsible via
--- the arrow in the corner, and remember position/collapsed state across
--- frames keyed by their title (use "Title##suffix" for two windows with the
--- same visible title). Returns false when the window is collapsed; you may
--- skip building its contents then, but you must ALWAYS call End() —
--- exactly like Dear ImGui:
---
---   if imlove.Begin("Stats") then
---     imlove.Text("hello")
---   end
---   imlove.End()
function imlove.Begin(title)
  if not ctx.inFrame then
    error("imlove.Begin() called before imlove.NewFrame()", 2)
  end
  if ctx.currentWindow then
    error("imlove.Begin('" .. tostring(title) .. "') called while window '"
      .. ctx.currentWindow.title .. "' is open — missing imlove.End()", 2)
  end
  title = tostring(title)
  local displayTitle, idText = splitLabel(title)

  local win = ctx.windows[title]
  if not win then
    win = { title = title, collapsed = false, w = 0, h = 0 }
    -- Cascade new windows so they don't all spawn on top of each other.
    win.x = 40 + ctx.windowCount * 30
    win.y = 40 + ctx.windowCount * 30
    ctx.windowCount = ctx.windowCount + 1
    ctx.windows[title] = win
    ctx.windowOrder[#ctx.windowOrder + 1] = win
  end
  if win.lastFrame == ctx.frame then
    error("imlove.Begin('" .. title .. "') called twice in one frame", 2)
  end

  local pending = ctx.nextWindowPos
  if pending then
    if pending.cond ~= "once" or not win.placed then
      win.x, win.y = pending.x, pending.y
    end
    ctx.nextWindowPos = nil
  end
  win.placed = true
  win.lastFrame = ctx.frame

  ctx.currentWindow = win
  ctx.idStack = { idText }

  local fpx, fpy = style.framePadding[1], style.framePadding[2]
  local pad = style.windowPadding
  win.titleH = ctx.font:getHeight() + fpy * 2

  -- If this window is being dragged, follow the mouse (before drawing
  -- anything, so there is no visible lag).
  if ctx.dragWindow == win then
    win.x = ctx.mouse.x - win.dragOffsetX
    win.y = ctx.mouse.y - win.dragOffsetY
  end

  -- Start this frame's draw list. Window width/height depend on the content
  -- that hasn't run yet, so the background and title-bar rects are pushed
  -- now and their sizes patched in End().
  win.drawList = {}
  win.bgCmd = pushRect(win, "fill", win.x, win.y, 0, 0,
    style.colors.windowBg, style.rounding)
  local isFront = ctx.windowOrder[#ctx.windowOrder] == win
  win.titleCmd = pushRect(win, "fill", win.x, win.y, 0, win.titleH,
    isFront and style.colors.titleBgActive or style.colors.titleBg,
    style.rounding)

  -- Collapse arrow: a regular button-behavior region in the title bar.
  local ah = win.titleH
  local _, _, arrowClicked = behavior(win, makeId("#COLLAPSE"),
    win.x, win.y, ah, ah)
  if arrowClicked then win.collapsed = not win.collapsed end
  local cx, cy, r = win.x + ah * 0.5, win.y + ah * 0.5, ah * 0.24
  if win.collapsed then -- arrow points right
    pushTriangle(win, cx - r * 0.6, cy - r, cx - r * 0.6, cy + r,
      cx + r, cy, style.colors.text)
  else                  -- arrow points down
    pushTriangle(win, cx - r, cy - r * 0.6, cx + r, cy - r * 0.6,
      cx, cy + r, style.colors.text)
  end
  pushText(win, displayTitle, win.x + ah + 2, win.y + fpy, style.colors.text)

  -- Start a title-bar drag: mouse pressed on the title bar and nothing else
  -- claimed the press (the collapse arrow claims it via activeId).
  if ctx.mouse.pressed and ctx.hoveredWindow == win
      and ctx.activeId == nil and ctx.dragWindow == nil
      and pointIn(ctx.mouse.x, ctx.mouse.y,
        win.x, win.y, math.max(win.w, ah), win.titleH) then
    ctx.dragWindow = win
    win.dragOffsetX = ctx.mouse.x - win.x
    win.dragOffsetY = ctx.mouse.y - win.y
  end

  -- Reset the layout cursor. skipItems makes every widget a cheap no-op
  -- while the window is collapsed (same trick as ImGui's SkipItems).
  win.skipItems = win.collapsed
  win.indent = 0
  win.innerX = win.x + pad
  win.nextY = win.y + win.titleH + pad
  win.lineY, win.lineH = win.nextY, 0
  win.sameLineX = nil
  win.prevItem = { x = win.innerX, y = win.nextY, w = 0, h = 0 }
  win.contentMaxX = win.x + ah + 2 + ctx.font:getWidth(displayTitle) + fpx
  win.contentMaxY = win.y + win.titleH

  return not win.collapsed
end

--- Close the current window. Must be called exactly once for every Begin(),
--- collapsed or not. Fits the window to its content and finishes its draw
--- list. Equivalent of ImGui::End().
function imlove.End()
  local win = ctx.currentWindow
  if not win then
    error("imlove.End() called without a matching imlove.Begin()", 2)
  end
  if #ctx.idStack > 1 then
    error("imlove.End(): " .. (#ctx.idStack - 1)
      .. " PushID()/TreeNode() left unpopped in window '" .. win.title .. "'", 2)
  end

  local pad = style.windowPadding
  win.w = math.max(win.contentMaxX + pad - win.x, style.minWindowWidth)
  win.h = win.collapsed and win.titleH
    or math.max(win.contentMaxY + pad - win.y, win.titleH)

  -- Patch the rects whose width/height weren't known in Begin().
  win.bgCmd.w, win.bgCmd.h = win.w, win.h
  win.titleCmd.w = win.w
  pushRect(win, "line", win.x, win.y, win.w, win.h,
    style.colors.border, style.rounding)

  ctx.currentWindow = nil
  ctx.idStack = {}
end

--- Set the position the next Begin() will use. cond is "always" (default:
--- reposition every frame, which also disables dragging in practice) or
--- "once" (only position the window the first time it is ever created —
--- what you want for a default layout the user can still rearrange).
--- Equivalent of ImGui::SetNextWindowPos().
function imlove.SetNextWindowPos(x, y, cond)
  ctx.nextWindowPos = { x = x, y = y, cond = cond or "always" }
end

--- Position of the current window. Equivalent of ImGui::GetWindowPos().
function imlove.GetWindowPos()
  local win = requireWindow("GetWindowPos")
  return win.x, win.y
end

--- Size of the current window as of last frame (this frame's size isn't
--- known until End()). Equivalent of ImGui::GetWindowSize().
function imlove.GetWindowSize()
  local win = requireWindow("GetWindowSize")
  return win.w, win.h
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

--- Static text. Extra arguments are fed through string.format, like ImGui:
--- imlove.Text("hp: %d/%d", hp, maxHp). Newlines make multi-line text.
function imlove.Text(fmt, ...)
  local win = requireWindow("Text")
  if win.skipItems then return end
  local text = tostring(fmt)
  if select("#", ...) > 0 then text = string.format(text, ...) end
  local w, h = textSize(text)
  local x, y = itemAdd(win, w, h)
  pushText(win, text, x, y, style.colors.text)
end

--- A push button. Returns true on the frame it is clicked (mouse released
--- over it). Equivalent of ImGui::Button().
function imlove.Button(label)
  local win = requireWindow("Button")
  if win.skipItems then return false end
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local fpx, fpy = style.framePadding[1], style.framePadding[2]
  local tw, th = textSize(display)
  local w, h = tw + fpx * 2, th + fpy * 2
  local x, y = itemAdd(win, w, h)
  local hovered, held, pressed = behavior(win, id, x, y, w, h)
  local color = held and style.colors.buttonActive
    or hovered and style.colors.buttonHovered
    or style.colors.button
  pushRect(win, "fill", x, y, w, h, color, style.rounding)
  pushText(win, display, x + fpx, y + fpy, style.colors.text)
  return pressed
end

--- A checkbox. Returns the (possibly toggled) value plus a changed flag:
---   showGrid, changed = imlove.Checkbox("Show grid", showGrid)
--- Note the Lua-ism: ImGui mutates a bool* in place; Lua has no out-params,
--- so you assign the first return value back yourself.
function imlove.Checkbox(label, value)
  local win = requireWindow("Checkbox")
  if win.skipItems then return value, false end
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local fpy = style.framePadding[2]
  local box = ctx.font:getHeight() + fpy * 2
  local tw = ctx.font:getWidth(display)
  local w = box + style.innerSpacing + tw
  local x, y = itemAdd(win, w, box)
  local hovered, held, pressed = behavior(win, id, x, y, w, box)
  if pressed then value = not value end
  local bg = held and style.colors.frameBgActive
    or hovered and style.colors.frameBgHovered
    or style.colors.frameBg
  pushRect(win, "fill", x, y, box, box, bg, style.rounding)
  if value then
    local inset = math.floor(box * 0.25)
    pushRect(win, "fill", x + inset, y + inset,
      box - inset * 2, box - inset * 2, style.colors.checkMark, 1)
  end
  pushText(win, display, x + box + style.innerSpacing, y + fpy,
    style.colors.text)
  return value, pressed
end

--- A horizontal slider for a float. Click or drag anywhere on the track to
--- set the value. Returns the (possibly changed) value plus a changed flag:
---   volume, changed = imlove.SliderFloat("Volume", volume, 0, 1)
--- Same Lua-ism as Checkbox: assign the returned value back.
function imlove.SliderFloat(label, value, min, max)
  local win = requireWindow("SliderFloat")
  value = tonumber(value) or min
  if win.skipItems then return value, false end
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local fpx, fpy = style.framePadding[1], style.framePadding[2]
  local trackW, h = style.sliderWidth, frameHeight()
  local tw = ctx.font:getWidth(display)
  local totalW = trackW + (tw > 0 and style.innerSpacing + tw or 0)
  local x, y = itemAdd(win, totalW, h)
  local hovered, held = behavior(win, id, x, y, trackW, h)

  local old = value
  if held then
    local t = clamp((ctx.mouse.x - x) / trackW, 0, 1)
    value = min + t * (max - min)
  end
  value = clamp(value, math.min(min, max), math.max(min, max))

  local bg = held and style.colors.frameBgActive
    or hovered and style.colors.frameBgHovered
    or style.colors.frameBg
  pushRect(win, "fill", x, y, trackW, h, bg, style.rounding)
  local range = max - min
  local t = range ~= 0 and clamp((value - min) / range, 0, 1) or 0
  local grabW = style.grabWidth
  pushRect(win, "fill", x + 2 + t * (trackW - grabW - 4), y + 2,
    grabW, h - 4, held and style.colors.sliderGrabActive
    or style.colors.sliderGrab, style.rounding)
  local valueText = string.format("%.3f", value)
  pushText(win, valueText,
    x + (trackW - ctx.font:getWidth(valueText)) / 2, y + fpy,
    style.colors.text)
  if tw > 0 then
    pushText(win, display, x + trackW + style.innerSpacing, y + fpy,
      style.colors.text)
  end
  return value, value ~= old
end

--- A collapsible tree node. Returns whether it is open; when it is, its
--- children follow indented, and you MUST call TreePop() after them:
---
---   if imlove.TreeNode("Enemies") then
---     imlove.Text("...children...")
---     imlove.TreePop()
---   end
---
--- Like ImGui, an open TreeNode pushes its label onto the ID stack, so
--- identical widget labels under different nodes don't collide. Open state
--- persists across frames. Equivalent of ImGui::TreeNode().
function imlove.TreeNode(label)
  local win = requireWindow("TreeNode")
  if win.skipItems then return false end
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local open = ctx.openNodes[id] == true
  local fpy = style.framePadding[2]
  local h = frameHeight()
  local arrow = ctx.font:getHeight()
  local w = arrow + style.innerSpacing + ctx.font:getWidth(display)
  local x, y = itemAdd(win, w, h)
  local hovered, held, pressed = behavior(win, id, x, y, w, h)
  if pressed then
    open = not open
    ctx.openNodes[id] = open
  end
  if hovered or held then
    pushRect(win, "fill", x, y, w, h, style.colors.headerHovered,
      style.rounding)
  end
  local cx, cy, r = x + arrow * 0.5, y + h * 0.5, arrow * 0.3
  if open then
    pushTriangle(win, cx - r, cy - r * 0.6, cx + r, cy - r * 0.6,
      cx, cy + r, style.colors.text)
  else
    pushTriangle(win, cx - r * 0.6, cy - r, cx - r * 0.6, cy + r,
      cx + r, cy, style.colors.text)
  end
  pushText(win, display, x + arrow + style.innerSpacing, y + fpy,
    style.colors.text)
  if open then
    ctx.idStack[#ctx.idStack + 1] = idText
    win.indent = win.indent + style.indent
  end
  return open
end

--- Closes the innermost open TreeNode: un-indents and pops its ID. Call
--- exactly once per TreeNode() that returned true. Equivalent of
--- ImGui::TreePop().
function imlove.TreePop()
  local win = requireWindow("TreePop")
  if win.skipItems then return end
  if #ctx.idStack <= 1 then
    error("imlove.TreePop() called without a matching open TreeNode()", 2)
  end
  ctx.idStack[#ctx.idStack] = nil
  win.indent = win.indent - style.indent
end

--- A selectable row spanning the window width, for pick-one-from-a-list UIs.
--- Pass whether this row is currently selected (it draws highlighted);
--- returns true on the frame it is clicked — updating your selection is up
--- to you:
---
---   if imlove.Selectable(e.name, selected == e) then selected = e end
---
--- Equivalent of ImGui::Selectable().
function imlove.Selectable(label, selected)
  local win = requireWindow("Selectable")
  if win.skipItems then return false end
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local fpx, fpy = style.framePadding[1], style.framePadding[2]
  local tw = ctx.font:getWidth(display)
  local w = math.max(availWidth(win), tw + fpx * 2)
  local h = frameHeight()
  local x, y = itemAdd(win, w, h)
  local hovered, held, pressed = behavior(win, id, x, y, w, h)
  if hovered or held then
    pushRect(win, "fill", x, y, w, h, style.colors.headerHovered,
      style.rounding)
  elseif selected then
    pushRect(win, "fill", x, y, w, h, style.colors.header, style.rounding)
  end
  pushText(win, display, x + fpx, y + fpy, style.colors.text)
  return pressed
end

--- A horizontal separator line. Equivalent of ImGui::Separator().
function imlove.Separator()
  local win = requireWindow("Separator")
  if win.skipItems then return end
  local w = math.max(availWidth(win), 1)
  local x, y = itemAdd(win, w, 1)
  pushLine(win, x, y + 0.5, x + w, y + 0.5, style.colors.separator)
end

--- Place the next widget on the same line as the previous one instead of
--- below it. Equivalent of ImGui::SameLine().
function imlove.SameLine()
  local win = requireWindow("SameLine")
  if win.skipItems then return end
  win.sameLineX = win.prevItem.x + win.prevItem.w + style.itemSpacing[1]
end

--------------------------------------------------------------------------------
-- ID stack
--------------------------------------------------------------------------------

--- Push an id (number or string) onto the ID stack. Widget identity is
--- label + ID stack + window, so wrap list items in PushID/PopID and ten
--- rows can each have their own "Delete" button:
---
---   for i, e in ipairs(entities) do
---     imlove.PushID(i)
---     if imlove.Button("Delete") then ... end
---     imlove.PopID()
---   end
---
--- (For a single stray duplicate, the "Label##unique" suffix convention is
--- lighter — see splitLabel above.) Equivalent of ImGui::PushID().
function imlove.PushID(id)
  requireWindow("PushID")
  ctx.idStack[#ctx.idStack + 1] = tostring(id)
end

--- Pop what PushID pushed. Equivalent of ImGui::PopID().
function imlove.PopID()
  requireWindow("PopID")
  if #ctx.idStack <= 1 then
    error("imlove.PopID() called without a matching imlove.PushID()", 2)
  end
  ctx.idStack[#ctx.idStack] = nil
end

--------------------------------------------------------------------------------
-- Item queries (handy for tests and custom layout)
--------------------------------------------------------------------------------

--- Top-left corner of the most recent widget's rectangle.
--- Equivalent of ImGui::GetItemRectMin().
function imlove.GetItemRectMin()
  local win = requireWindow("GetItemRectMin")
  return win.prevItem.x, win.prevItem.y
end

--- Bottom-right corner of the most recent widget's rectangle.
--- Equivalent of ImGui::GetItemRectMax().
function imlove.GetItemRectMax()
  local win = requireWindow("GetItemRectMax")
  return win.prevItem.x + win.prevItem.w, win.prevItem.y + win.prevItem.h
end

--------------------------------------------------------------------------------
-- LÖVE input forwarding. Call these from the matching love.* callbacks.
-- Each returns true when the UI consumed the event, i.e. when your game
-- should ignore it — the per-event equivalent of io.WantCaptureMouse:
--
--   function love.mousepressed(x, y, button)
--     if imlove.mousepressed(x, y, button) then return end
--     -- game click handling here
--   end
--------------------------------------------------------------------------------

local function mouseOverUI(x, y)
  return windowAt(x, y) ~= nil
    or ctx.activeId ~= nil or ctx.dragWindow ~= nil
end

--- Forward from love.mousepressed. Returns true if the UI consumed the press.
function imlove.mousepressed(x, y, button)
  local captured = mouseOverUI(x, y)
  if button == 1 then
    ctx.pressLatch = true
    ctx.mouse.down = true
  end
  imlove.io.WantCaptureMouse = captured
  return captured
end

--- Forward from love.mousereleased. Returns true if the UI consumed the
--- release (a release always belongs to the UI while a widget is held).
function imlove.mousereleased(x, y, button)
  local captured = mouseOverUI(x, y)
  if button == 1 then
    ctx.releaseLatch = true
    ctx.mouse.down = false
  end
  return captured
end

--- Forward from love.wheelmoved. v1 windows auto-size instead of scrolling,
--- so the wheel does nothing yet — but the event still reports as consumed
--- over a window, so the game doesn't zoom/scroll underneath the UI.
function imlove.wheelmoved(dx, dy)
  return windowAt(ctx.mouse.x, ctx.mouse.y) ~= nil
end

--- Forward from love.keypressed. v1 has no keyboard widgets, so this never
--- consumes; it exists so integrations are already correct when text input
--- arrives in a future version.
function imlove.keypressed(key)
  return imlove.io.WantCaptureKeyboard
end

--- Forward from love.textinput. Same story as keypressed.
function imlove.textinput(text)
  return imlove.io.WantCaptureKeyboard
end

return imlove
