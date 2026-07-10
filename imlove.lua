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

local imlove = { _VERSION = "1.3.0" }

-- io mirrors Dear ImGui's ImGuiIO flags. After NewFrame() these tell the host
-- game whether the UI wants the mouse/keyboard this frame, so the game can
-- ignore input the UI consumed. The input-forwarding functions at the bottom
-- of this file also return the same answer per event, which is usually the
-- more convenient form in LÖVE callbacks.
imlove.io = {
  WantCaptureMouse    = false,
  WantCaptureKeyboard = false, -- always false in v1: no keyboard widgets yet
  -- Settings persistence (see "Settings persistence" below, and
  -- SaveIniSettings()/LoadIniSettings()): the file window position/size/
  -- collapsed state is saved to and loaded from, via love.filesystem.
  -- Mirrors ImGui's io.IniFilename. Set to nil or false before your first
  -- NewFrame() to disable persistence entirely.
  IniFilename = "imlove.ini",
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
  scrollbarWidth = 10,      -- width of a window/child's scrollbar track
  gripSize       = 14,      -- side length of the resize-grip corner triangle

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
    textDisabled     = { 0.50, 0.50, 0.50, 1.00 },
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

  currentWindow = nil, -- window (or child) between Begin()/End(), nil outside
  hoveredWindow = nil, -- front-most window under the mouse (last-frame rects)
  nextWindowPos = nil, -- pending SetNextWindowPos(), consumed by next Begin()
  nextWindowSize = nil, -- pending SetNextWindowSize(), consumed by next Begin()

  idStack   = {},      -- see PushID(); slot 1 is always the window's title
  activeId  = nil,     -- id of the widget being held with the mouse, if any
  hoveredId = nil,     -- id of the widget under the mouse this frame, if any
  dragWindow = nil,    -- window being dragged by its title bar, if any
  resizeWindow = nil,  -- window being resized via its corner grip, if any

  openNodes = {},      -- TreeNode/CollapsingHeader id -> true while open
  dragAnchor = nil,    -- { id, x, value } drag origin for DragFloat/DragInt

  -- Popups & tooltips (see the "Popups & tooltips" section below): drawn in
  -- an overlay band above every window, and hit-tested before them.
  popups     = {},     -- resolved popup id -> persistent { win, kind, ... }
  popupOrder = {},     -- open popup ids, oldest/bottommost first (last =
                       -- topmost) — also the z-order Render() plays back
  tooltipWin = nil,    -- the one persistent tooltip "window", reused by
                       -- every SetTooltip()/BeginTooltip() call

  -- Mouse state. LÖVE delivers presses/releases as events between frames, so
  -- the forwarding functions only *latch* them here; NewFrame() converts each
  -- latch into a one-frame `pressed`/`released` flag that widgets read.
  mouse = { x = 0, y = 0, down = false, pressed = false, released = false,
    rightPressed = false },
  pressLatch      = false,
  releaseLatch    = false,
  rightPressLatch = false, -- right-button press latch, for BeginPopupContextItem
  wheelLatch      = 0, -- accumulated wheelmoved() dy, consumed by NewFrame()

  -- Settings persistence (see the "Settings persistence" section below).
  iniLoaded  = false, -- whether the lazy first-NewFrame() load has run yet
  iniEntries = nil,   -- title -> {x, y, w, h, sized, collapsed}, from the
                      -- most recently loaded ini file; consulted by Begin()
                      -- when a window is first created (or re-applied to
                      -- already-existing windows by LoadIniSettings())
  iniDirty   = false, -- true when something changed that's worth writing
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

local function pushCircle(win, mode, x, y, r, color)
  win.drawList[#win.drawList + 1] = { kind = "circle", mode = mode,
    x = x, y = y, r = r, color = color }
end

-- Push/pop a clip rectangle. Render() maintains a stack of these and
-- intersects nested rects, so a clip pushed by a fixed-size window's content
-- region and a BeginChild() inside it combine correctly. Widgets between a
-- push/pop pair are what actually get scissored; see Render().
local function pushClip(win, x, y, w, h)
  win.drawList[#win.drawList + 1] = { kind = "clipPush", x = x, y = y,
    w = w, h = h }
end

local function popClip(win)
  win.drawList[#win.drawList + 1] = { kind = "clipPop" }
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
-- Popup bookkeeping used by hit-testing and NewFrame() (must come before
-- Frame lifecycle, below, since NewFrame() calls into it). The functions
-- that actually BUILD a popup's contents — beginPopupContent()/
-- endPopupContent() — live further down, right before Begin()/End(), since
-- they need pushRect()/itemAdd()/style, and the public
-- OpenPopup()/BeginPopup()/EndPopup()/SetTooltip() API sits there too.
--------------------------------------------------------------------------------

-- What's currently open, for Begin()/End()/Render()'s "you forgot to close
-- something" errors — one place so all three agree on wording.
local function whatIsOpen(win)
  if win.isChild then
    return "BeginChild('" .. win.idStr .. "') is open — missing imlove.EndChild()"
  elseif win.isTooltip then
    return "a tooltip is open — missing imlove.EndTooltip()"
  elseif win.isPopup then
    return "a popup is open — missing imlove.EndPopup()"
  else
    return "window '" .. win.title .. "' is open — missing imlove.End()"
  end
end

-- OpenPopup(strId)/BeginPopup(strId) share an id the same way any other
-- widget does: the current ID stack (window/PushID/BeginPopup scope) joined
-- with the string, via the same makeId() every widget uses. Two windows
-- each calling OpenPopup("options") get two different popups; a
-- BeginPopup("options") called from the same scope as the OpenPopup() that
-- opened it always finds it.
local function popupId(strId)
  return makeId(tostring(strId))
end

local function popupIsOpen(id)
  for i = 1, #ctx.popupOrder do
    if ctx.popupOrder[i] == id then return true end
  end
  return false
end

-- Marks a (resolved) id open: pushes it onto the top of the popup stack and
-- captures where it should appear (anchorX/Y default to just past the
-- mouse, SetTooltip()-style; Combo() passes its own box's position
-- instead). ownerRect, if given (Combo() uses this), is a widget rectangle
-- that counts as "inside" the popup for dismissal purposes, so clicking the
-- combo box itself to close its dropdown is never also seen as an
-- outside-dismiss click.
local function openPopupById(id, kind, ownerRect, anchorX, anchorY)
  if popupIsOpen(id) then return end
  local p = ctx.popups[id] or { id = id }
  ctx.popups[id] = p
  p.kind = kind or "popup"
  p.anchorX = anchorX or ctx.mouse.x + 12
  p.anchorY = anchorY or ctx.mouse.y + 12
  p.justOpened = true
  p.ownerRect = ownerRect
  ctx.popupOrder[#ctx.popupOrder + 1] = id
end

local function closePopup(id)
  for i = 1, #ctx.popupOrder do
    if ctx.popupOrder[i] == id then
      table.remove(ctx.popupOrder, i)
      return
    end
  end
end

-- Frontmost popup/modal under the point — popups are hit-tested BEFORE
-- regular windows, topmost (most recently opened) first (see NewFrame()).
-- Never returns the tooltip; it is never hit-testable (see SetTooltip()).
-- The second return, `blocked`, is true when the point fell through to an
-- open modal without landing on it (or on anything stacked above it): the
-- modal still swallows the click/hover, but nothing underneath — not even a
-- regular window — counts as "hit".
local function popupAt(x, y)
  for i = #ctx.popupOrder, 1, -1 do
    local p = ctx.popups[ctx.popupOrder[i]]
    local win = p and p.win
    if win and win.lastFrame and win.lastFrame >= ctx.frame - 1 then
      if pointIn(x, y, win.x, win.y, win.w, win.h) then return p end
      if p.kind == "modal" then return nil, true end
    end
  end
  return nil, false
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

-- A widget is only hoverable while the mouse is within its window's current
-- clip rect (nil = unclipped, the common case). This is what keeps a
-- BeginChild() row that has scrolled out of view — or content of a
-- fixed-size window scrolled past its bottom edge — from still receiving
-- clicks meant for whatever it's hidden behind.
local function withinClip(win, x, y)
  local clip = win.clipRect
  return not clip or pointIn(x, y, clip.x, clip.y, clip.w, clip.h)
end

local function behavior(win, id, x, y, w, h)
  local m = ctx.mouse
  -- A child window shares its root's hover/z-order: behavior() always
  -- compares against the ROOT window, since ctx.hoveredWindow is only ever
  -- set to root-level windows (see windowAt()).
  local hovered = ctx.hoveredWindow == (win.root or win)
    and ctx.dragWindow == nil
    and (ctx.activeId == nil or ctx.activeId == id)
    and pointIn(m.x, m.y, x, y, w, h)
    and withinClip(win, m.x, m.y)

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

-- A widget's region can become disabled between one frame and the next while
-- it is held — e.g. a window's flags flip to "NoResize" mid-drag, or its
-- "open" argument stops being passed so the close button disappears. If the
-- disabled region simply stops calling behavior(), nothing ever clears
-- ctx.activeId, and since behavior()'s hover gate is
-- `activeId == nil or activeId == id`, EVERY widget in EVERY window stops
-- responding until a fully idle frame (no press/release, mouse up) happens.
-- Disabled regions must explicitly give up any stale claim instead of
-- silently going quiet.
local function releaseIfActive(id)
  if ctx.activeId == id then ctx.activeId = nil end
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

-- Stashes the just-placed item's interactive state so IsItemHovered() /
-- IsItemActive() / IsItemClicked() can answer without every call site
-- re-deriving it. "clicked" means the widget's own notion of a completed
-- click (what it returns as pressed/changed), not merely a mouse-down.
local function recordItem(win, hovered, active, clicked)
  win.prevItem.hovered = hovered
  win.prevItem.active  = active
  win.prevItem.clicked = clicked
end

-- Same as itemAdd(), for widgets with no behavior() of their own (Text and
-- friends, Separator, Dummy, ...). They still report IsItemHovered() from
-- geometry alone, gated the same way behavior() gates hovered: only the
-- front window, only while no other widget is held.
local function itemAddPassive(win, w, h)
  local x, y = itemAdd(win, w, h)
  local hovered = ctx.hoveredWindow == (win.root or win) and ctx.dragWindow == nil
    and ctx.activeId == nil
    and pointIn(ctx.mouse.x, ctx.mouse.y, x, y, w, h)
    and withinClip(win, ctx.mouse.x, ctx.mouse.y)
  recordItem(win, hovered, false, false)
  return x, y
end

-- Width available for widgets that stretch across the window (Selectable,
-- Separator). Uses last frame's window width — the one-frame lag again —
-- and, the same way, last frame's "did this window/child show a scrollbar"
-- flag: when it did, the content region must stop short of the scrollbar
-- track (reserving its full width plus the usual padding gap), or a
-- full-width widget's own behavior() region overlaps the track and steals
-- clicks meant for the scrollbar.
local function availWidth(win)
  local x = win.innerX + win.indent
  local right = win.x + win.w - style.windowPadding
  if win.hasScrollbar then right = right - style.scrollbarWidth end
  return math.max(right - x, 0)
end

local function requireWindow(name)
  local win = ctx.currentWindow
  if not win then
    error("imlove." .. name .. "() called outside a Begin()/End() pair", 3)
  end
  return win
end

-- Applies a latched wheel delta to whatever is under the mouse: a
-- BeginChild() region if the point falls inside one (the innermost —
-- smallest-area — match wins, so a child nested inside another scrolls
-- itself rather than its parent), the window itself otherwise. Uses last
-- frame's rects/content sizes, same one-frame lag as hit-testing.
local function applyWheel(win, dy)
  if win.flags and win.flags.AlwaysAutoResize then return end -- never overflows
  local target = win
  if win.lastChildRects then
    local bestArea
    for i = 1, #win.lastChildRects do
      local r = win.lastChildRects[i]
      if pointIn(ctx.mouse.x, ctx.mouse.y, r.x, r.y, r.w, r.h) then
        local area = r.w * r.h
        if not bestArea or area < bestArea then
          target, bestArea = win.childScroll[r.id], area
        end
      end
    end
  end
  if not target then return end
  local step = 3 * ctx.font:getHeight() -- ImGui scrolls ~3 lines per notch
  local maxScroll = math.max((target.contentH or 0) - (target.visibleH or 0), 0)
  target.scrollY = clamp((target.scrollY or 0) - dy * step, 0, maxScroll)
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

  -- Settings persistence: load once, lazily, the very first frame (never
  -- again after that — see LoadIniSettings() for reloading on demand).
  -- ctx.windows is always empty at this point (Begin() can't have run
  -- before the first NewFrame()), so there's nothing yet to re-apply to —
  -- just seed ctx.iniEntries for Begin() to consult as windows are created.
  if not ctx.iniLoaded then
    ctx.iniLoaded = true
    if imlove.io.IniFilename then imlove.LoadIniSettings() end
  end

  local m = ctx.mouse
  m.x, m.y = love.mouse.getPosition()
  m.pressed, ctx.pressLatch = ctx.pressLatch, false
  m.released, ctx.releaseLatch = ctx.releaseLatch, false
  m.rightPressed, ctx.rightPressLatch = ctx.rightPressLatch, false
  local wheelDy = ctx.wheelLatch
  ctx.wheelLatch = 0

  -- Safety net: if the mouse is up and there is no release event left to
  -- deliver, nothing can legitimately still be active. This unsticks widgets
  -- whose window stopped being submitted mid-drag.
  if not m.down and not m.released and not m.pressed then
    ctx.activeId = nil
    ctx.dragWindow = nil
    ctx.resizeWindow = nil
  end

  -- Prune popups whose BeginPopup()/BeginPopupModal()/BeginPopupContextItem()
  -- stopped being called — the caller stopped submitting them, same idea as
  -- a window whose Begin() stops being called (see windowAt()) — otherwise
  -- a stale entry would keep io.WantCaptureMouse stuck true and every press
  -- captured forever.
  for i = #ctx.popupOrder, 1, -1 do
    local p = ctx.popups[ctx.popupOrder[i]]
    local win = p and p.win
    if not (win and win.lastFrame and win.lastFrame >= ctx.frame - 1) then
      table.remove(ctx.popupOrder, i)
    end
  end

  ctx.hoveredId = nil
  -- Popups are hit-tested BEFORE regular windows, and a modal blocks
  -- everything beneath it (see popupAt()).
  local hitPopup, blocked = popupAt(m.x, m.y)
  if hitPopup then
    ctx.hoveredWindow = hitPopup.win
  elseif blocked then
    ctx.hoveredWindow = nil
  else
    ctx.hoveredWindow = windowAt(m.x, m.y)
  end
  if m.pressed and ctx.hoveredWindow and not ctx.hoveredWindow.isPopup then
    bringToFront(ctx.hoveredWindow)
  end
  if wheelDy ~= 0 and ctx.hoveredWindow then
    applyWheel(ctx.hoveredWindow, wheelDy)
  end

  -- A modal dims and blocks EVERYTHING beneath it — including a title-bar
  -- drag, a resize-grip drag, or a scrollbar drag that was already in
  -- progress the moment it opened (none of those are hover-gated; they run
  -- off ctx.dragWindow/ctx.resizeWindow/ctx.activeId directly, every frame,
  -- regardless of ctx.hoveredWindow). Forcibly release those every frame a
  -- modal is open, unless the claim belongs to the modal's own content (or
  -- a popup opened from within it) — same idea as releaseIfActive(), just
  -- keyed by an id-stack PREFIX since NewFrame() has no widget ids of its
  -- own to compare against (see beginPopupContent()'s p.idPrefix).
  local modalIdx
  for i = 1, #ctx.popupOrder do
    if ctx.popups[ctx.popupOrder[i]].kind == "modal" then
      modalIdx = i
      break
    end
  end
  if modalIdx then
    ctx.dragWindow = nil
    ctx.resizeWindow = nil
    if ctx.activeId then
      local prefix = ctx.popups[ctx.popupOrder[modalIdx]].idPrefix
      local ownedByModal = prefix
        and ctx.activeId:sub(1, #prefix + 1) == (prefix .. "\31")
      if not ownedByModal then ctx.activeId = nil end
    end
  end

  -- Dismiss popups: a press — either mouse button — outside the topmost
  -- open popup closes it, and everything stacked above whatever it DID
  -- land on — so a press on a lower popup in a nested stack closes only
  -- what's above that one. Modals are never dismissed this way — only
  -- CloseCurrentPopup() closes them. The dismissing press is CONSUMED: it
  -- must not ALSO activate whatever it just exposed underneath (a press)
  -- or open a context menu on top of it (a right press reaching
  -- BeginPopupContextItem()) later this same frame.
  if (m.pressed or m.rightPressed) and #ctx.popupOrder > 0 then
    local hitIndex, modalBlocked = nil, false
    for i = #ctx.popupOrder, 1, -1 do
      local id = ctx.popupOrder[i]
      local p = ctx.popups[id]
      local win = p.win
      local hitWin = win and pointIn(m.x, m.y, win.x, win.y, win.w, win.h)
      local hitOwner = p.ownerRect and pointIn(m.x, m.y, p.ownerRect.x,
        p.ownerRect.y, p.ownerRect.w, p.ownerRect.h)
      if hitWin or hitOwner then
        hitIndex = i
        break
      end
      if p.kind == "modal" then
        modalBlocked = true
        break
      end
    end
    if not modalBlocked then
      local toClose = {}
      for i = #ctx.popupOrder, (hitIndex or 0) + 1, -1 do
        toClose[#toClose + 1] = ctx.popupOrder[i]
      end
      if #toClose > 0 then
        for i = 1, #toClose do closePopup(toClose[i]) end
        m.pressed = false
        m.rightPressed = false
      end
    end
  end

  imlove.io.WantCaptureMouse = ctx.hoveredWindow ~= nil
    or ctx.activeId ~= nil or ctx.dragWindow ~= nil or #ctx.popupOrder > 0
  imlove.io.WantCaptureKeyboard = false
end

--- Draw the UI. Call at the end of love.draw so the UI lands on top of the
--- game. Plays back every window's draw list in z-order, then popups (see
--- OpenPopup()/BeginPopup()) above all of them, then the tooltip (see
--- SetTooltip()) last of all, above even popups. Equivalent of
--- ImGui::Render() + backend draw.
function imlove.Render()
  if not ctx.inFrame then return end -- nothing declared this frame; no-op
  if ctx.currentWindow then
    error("imlove.Render() called while " .. whatIsOpen(ctx.currentWindow), 2)
  end
  ctx.inFrame = false

  local g = love.graphics
  local pr, pg, pb, pa = g.getColor()
  local prevFont = g.getFont()
  local psx, psy, psw, psh = g.getScissor()
  g.setFont(ctx.font)

  -- Clip stack: clipPush/clipPop commands nest, and each level is the
  -- INTERSECTION with whatever was already scissored, so a BeginChild()
  -- inside a scrolling window can never paint outside the window's own
  -- content region either. Restored to the pre-Render() scissor (if any)
  -- when the stack empties, exactly like the color/font save-restore above.
  -- Shared across every draw list played back below (windows, then popups,
  -- then the tooltip) so a clip pushed by one never leaks into the next.
  local clipStack = {}

  local function applyTopScissor()
    local top = clipStack[#clipStack]
    if top then
      g.setScissor(top.x, top.y, top.w, top.h)
    elseif psx then
      g.setScissor(psx, psy, psw, psh)
    else
      g.setScissor()
    end
  end

  local function playDrawList(drawList)
    for j = 1, #drawList do
      local c = drawList[j]
      if c.kind == "clipPush" then
        local nx, ny, nw, nh = c.x, c.y, c.w, c.h
        local top = clipStack[#clipStack]
        if top then
          local x1, y1 = math.max(top.x, nx), math.max(top.y, ny)
          local x2 = math.min(top.x + top.w, nx + nw)
          local y2 = math.min(top.y + top.h, ny + nh)
          nx, ny, nw, nh = x1, y1, math.max(x2 - x1, 0), math.max(y2 - y1, 0)
        end
        clipStack[#clipStack + 1] = { x = nx, y = ny, w = nw, h = nh }
        applyTopScissor()
      elseif c.kind == "clipPop" then
        clipStack[#clipStack] = nil
        applyTopScissor()
      else
        g.setColor(c.color)
        if c.kind == "rect" then
          g.rectangle(c.mode, c.x, c.y, c.w, c.h, c.rounding, c.rounding)
        elseif c.kind == "text" then
          g.print(c.text, c.x, c.y)
        elseif c.kind == "triangle" then
          g.polygon("fill", c.x1, c.y1, c.x2, c.y2, c.x3, c.y3)
        elseif c.kind == "line" then
          g.line(c.x1, c.y1, c.x2, c.y2)
        elseif c.kind == "circle" then
          g.circle(c.mode, c.x, c.y, c.r)
        end
      end
    end
  end

  for i = 1, #ctx.windowOrder do
    local win = ctx.windowOrder[i]
    if win.lastFrame == ctx.frame then playDrawList(win.drawList) end
  end

  -- Overlay band: popups draw above every window, back-to-front in the same
  -- open/nesting order as ctx.popupOrder (see OpenPopup()); the tooltip (at
  -- most one, see SetTooltip()) draws last of all, above even popups.
  for i = 1, #ctx.popupOrder do
    local p = ctx.popups[ctx.popupOrder[i]]
    if p and p.win and p.win.lastFrame == ctx.frame then
      playDrawList(p.win.drawList)
    end
  end
  local tip = ctx.tooltipWin
  if tip and tip.lastFrame == ctx.frame then
    playDrawList(tip.drawList)
  end

  if psx then g.setScissor(psx, psy, psw, psh) else g.setScissor() end
  g.setFont(prevFont)
  g.setColor(pr, pg, pb, pa)

  -- Settings persistence: write-on-change, no debounce timer (see the
  -- "Settings persistence" section above) — only actually touches disk
  -- when something changed AND persistence is still enabled.
  if ctx.iniDirty and imlove.io.IniFilename then
    imlove.SaveIniSettings()
  end
end

--------------------------------------------------------------------------------
-- Settings persistence: ImGui's .ini behavior via love.filesystem. What
-- persists, per window title, is position, collapsed state, and — only for
-- a window that was ever given an EXPLICIT size (see the sizing model in
-- Begin()'s doc comment) — its size. Popups, tooltips, and BeginChild()
-- regions are never persisted; they aren't windows in ctx.windows/
-- ctx.windowOrder to begin with. The caller-owned open/close (close-button)
-- state is deliberately NOT persisted either, exactly like ImGui: `open` is
-- yours to remember, not the library's.
--
-- Precedence when a window is first created (see Begin()): an "always"
-- SetNextWindowPos()/SetNextWindowSize() always wins; a "once" one only
-- wins when there is NO ini entry for that title — otherwise the ini
-- position/size applies instead, exactly as if "once" had already fired
-- once before your code ever ran. This falls out of reusing the same
-- win.placed/win.sizePlaced bookkeeping Begin() already had for "once".
--
-- Lifecycle is deliberately simple, no timers: LOAD once, lazily, at the
-- first NewFrame() (tolerating an absent or garbage file silently). SAVE
-- write-on-change instead of ImGui's ~5s debounce: a title drag ending, a
-- resize-grip drag ending, a collapse toggle, or a brand-new window all
-- mark ctx.iniDirty, and Render() writes the whole file whenever it's
-- dirty. Simpler than debouncing, at the cost of an extra disk write on
-- some frames a real game would consider "still settling" — a fine trade
-- for a debug UI, and documented as a deviation (see docs/imgui.md).
--------------------------------------------------------------------------------

-- Parses an ImGui-ini-flavored file defensively: unrecognized/malformed
-- lines are simply ignored rather than erroring, and any block missing a
-- Pos= line (a truncated or hand-edited file) is discarded entirely, so a
-- garbage file just behaves like an empty/absent one.
local function parseIniText(text)
  local entries = {}
  local current = nil
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    local title = line:match("^%[Window%]%[(.*)%]$")
    if title then
      current = { collapsed = false }
      entries[title] = current
    elseif current then
      local x, y = line:match("^Pos=([%-%d%.]+),([%-%d%.]+)$")
      -- Each match() above/below is its own statement (not chained with
      -- "and") so both capture groups survive: "and" truncates a multi-
      -- value function call to its first result, which would silently
      -- discard the second half of every Pos=/Size= pair.
      local w, h
      if not x then w, h = line:match("^Size=([%-%d%.]+),([%-%d%.]+)$") end
      local c
      if not x and not w then c = line:match("^Collapsed=(%d)$") end
      if x then
        current.x, current.y = tonumber(x), tonumber(y)
      elseif w then
        current.w, current.h = tonumber(w), tonumber(h)
        current.sized = true
      elseif c then
        current.collapsed = c ~= "0"
      end
    end
  end
  for title, e in pairs(entries) do
    if not e.x or not e.y then entries[title] = nil end -- incomplete: discard
  end
  return entries
end

-- The inverse of parseIniText(): one [Window][Title] block per window ever
-- created this session (ctx.windowOrder — root windows only, see above),
-- in the same z-order they're kept in (harmless; ImGui's own order isn't
-- meaningful either, since Begin()/End() never reads back by position).
local function serializeIniText()
  local lines = {}
  for i = 1, #ctx.windowOrder do
    local win = ctx.windowOrder[i]
    lines[#lines + 1] = "[Window][" .. win.title .. "]"
    lines[#lines + 1] = string.format("Pos=%d,%d",
      math.floor(win.x + 0.5), math.floor(win.y + 0.5))
    if win.sizeMode == "fixed" then
      lines[#lines + 1] = string.format("Size=%d,%d",
        math.floor(win.w + 0.5), math.floor(win.h + 0.5))
    end
    if win.collapsed then
      lines[#lines + 1] = "Collapsed=1"
    end
    lines[#lines + 1] = ""
  end
  return table.concat(lines, "\n")
end

-- Applies one parsed entry to an already-existing window table (used both
-- by Begin() the moment a window is first created, and by
-- LoadIniSettings() reapplying a freshly (re)loaded file to windows that
-- already exist). Sets win.placed/win.sizePlaced the same way a consumed
-- SetNextWindowPos()/SetNextWindowSize() "once" would, so a later "once"
-- call correctly finds itself too late (see the precedence note above).
local function applyIniEntryToWindow(win)
  local entry = ctx.iniEntries and ctx.iniEntries[win.title]
  if not entry then return end
  win.x, win.y = entry.x, entry.y
  win.placed = true
  win.collapsed = entry.collapsed or false
  if entry.sized then
    win.w, win.h = entry.w, entry.h
    win.sizeMode = "fixed"
    win.sizePlaced = true
  end
end

--- Manually write the current window settings (position, collapsed state,
--- and size for any explicitly-sized window) to disk now, bypassing the
--- normal write-on-change lifecycle. filename defaults to
--- imlove.io.IniFilename; a no-op if that's also nil/false, or if
--- love.filesystem isn't available. Equivalent of
--- ImGui::SaveIniSettingsToDisk().
function imlove.SaveIniSettings(filename)
  filename = filename or imlove.io.IniFilename
  if not filename then return end
  if not (love and love.filesystem and love.filesystem.write) then return end
  love.filesystem.write(filename, serializeIniText())
  ctx.iniDirty = false
end

--- Manually (re)load window settings from disk now and apply them to any
--- window that already exists, in addition to seeding windows created from
--- here on (exactly like the lazy load NewFrame() performs once at
--- startup). filename defaults to imlove.io.IniFilename; a no-op if that's
--- also nil/false, if love.filesystem isn't available, or if the file is
--- absent/unreadable — corrupt or partial files are tolerated, parsed
--- defensively line-by-line (see parseIniText() above). Equivalent of
--- ImGui::LoadIniSettingsFromDisk().
function imlove.LoadIniSettings(filename)
  filename = filename or imlove.io.IniFilename
  if not filename then return end
  local fs = love and love.filesystem
  if not (fs and fs.read) then return end
  if fs.getInfo and not fs.getInfo(filename) then return end
  local ok, contents = pcall(fs.read, filename)
  if not ok or type(contents) ~= "string" then return end
  ctx.iniEntries = parseIniText(contents)
  for _, win in pairs(ctx.windows) do
    applyIniEntryToWindow(win)
  end
end

--------------------------------------------------------------------------------
-- Windows
--------------------------------------------------------------------------------

-- Window flags, passed to Begin() as a bare string or an array of strings.
-- Unknown flag names error immediately (typo protection) rather than being
-- silently ignored.
local VALID_WINDOW_FLAGS = {
  NoTitleBar       = true, -- no drag region, no collapse arrow, no close
                           -- button; content starts at the window's top
  NoMove           = true, -- title bar no longer drags the window
  NoResize         = true, -- no corner resize grip
  NoCollapse       = true, -- no collapse arrow (title bar still drags)
  AlwaysAutoResize = true, -- always fit content; no scrollbar, grip, or
                           -- scrolling, ever — the v1.1 behavior
  NoScrollbar      = true, -- scrolling by wheel still works, bar hidden
}

local function normalizeFlags(flags, fnName)
  local set = {}
  if flags == nil then return set end
  if type(flags) == "string" then flags = { flags } end
  for _, f in ipairs(flags) do
    if not VALID_WINDOW_FLAGS[f] then
      error("imlove." .. fnName .. "(): unknown flag '" .. tostring(f) .. "'", 3)
    end
    set[f] = true
  end
  return set
end

-- Shared track+grab for a scrolling window or BeginChild region. `state` is
-- any table with scrollY/contentH/visibleH fields (a window IS one; a
-- child's persistent scroll table is one too). Only called when content
-- actually overflows. Direct click-to-position mapping, same idiom as
-- SliderFloat/SliderInt's track (no drag-anchor, unlike DragFloat).
local function pushScrollbar(win, id, trackX, trackY, trackW, trackH, state)
  local sbW = style.scrollbarWidth
  local x = trackX + trackW - sbW
  local maxScroll = math.max(state.contentH - state.visibleH, 0)
  local grabH = clamp(trackH * trackH / state.contentH, 20, trackH)
  local avail = math.max(trackH - grabH, 0)

  local hovered, held = behavior(win, id, x, trackY, sbW, trackH)
  if held and avail > 0 then
    local t = clamp((ctx.mouse.y - trackY) / avail, 0, 1)
    state.scrollY = t * maxScroll
  end
  state.scrollY = clamp(state.scrollY, 0, maxScroll)
  local grabY = trackY + (avail > 0 and (state.scrollY / maxScroll) * avail or 0)

  pushRect(win, "fill", x, trackY, sbW, trackH, style.colors.frameBg, 0)
  pushRect(win, "fill", x + 1, grabY, sbW - 2, grabH,
    held and style.colors.sliderGrabActive
    or hovered and style.colors.sliderGrabActive
    or style.colors.sliderGrab, style.rounding)
end

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
---
--- open, if not nil, adds a close button to the title bar (mirroring
--- ImGui's bool* p_open) and is returned back, possibly toggled to false on
--- the frame the button is clicked — assign it back to your variable like
--- any other imlove value:
---
---   visible, showStats = imlove.Begin("Stats", showStats)
---   if visible then imlove.Text("hello") end
---   imlove.End()
---
--- Passing open == false skips the window entirely: Begin() returns
--- `false, false` without drawing anything, and every widget call inside
--- becomes a cheap no-op — but End() must still be called.
---
--- flags is a string or array of strings: "NoTitleBar", "NoMove",
--- "NoResize", "NoCollapse", "AlwaysAutoResize", "NoScrollbar". An unknown
--- flag name is an error, not a silent no-op.
---
--- A window auto-fits to its content until it is explicitly given a size —
--- via SetNextWindowSize() or by the user dragging the resize grip — at
--- which point its size becomes sticky and overflowing content scrolls
--- instead of growing the window ("AlwaysAutoResize" opts a window out of
--- this permanently, exactly like ImGui's flag of the same name).
--- Equivalent of ImGui::Begin(name, p_open, flags).
function imlove.Begin(title, open, flags)
  if not ctx.inFrame then
    error("imlove.Begin() called before imlove.NewFrame()", 2)
  end
  if ctx.currentWindow then
    error("imlove.Begin('" .. tostring(title) .. "') called while "
      .. whatIsOpen(ctx.currentWindow), 2)
  end
  title = tostring(title)
  local displayTitle, idText = splitLabel(title)

  local win = ctx.windows[title]
  if not win then
    win = { title = title, collapsed = false, w = 0, h = 0,
      scrollY = 0, sizeMode = "auto" }
    -- Cascade new windows so they don't all spawn on top of each other.
    win.x = 40 + ctx.windowCount * 30
    win.y = 40 + ctx.windowCount * 30
    ctx.windowCount = ctx.windowCount + 1
    ctx.windows[title] = win
    ctx.windowOrder[#ctx.windowOrder + 1] = win
    -- A loaded ini entry (see LoadIniSettings()) beats the cascade default
    -- above, and — via win.placed/win.sizePlaced — beats a "once"
    -- SetNextWindowPos()/SetNextWindowSize() below too (see the "Settings
    -- persistence" section's precedence note).
    applyIniEntryToWindow(win)
    ctx.iniDirty = true -- a brand-new window is worth persisting
  end
  if win.lastFrame == ctx.frame then
    error("imlove.Begin('" .. title .. "') called twice in one frame", 2)
  end

  ctx.currentWindow = win
  ctx.idStack = { idText }
  win.flags = normalizeFlags(flags, "Begin")

  if open == false then
    -- Not submitted at all: don't touch position/size/draw list/lastFrame,
    -- so it behaves exactly like a window whose Begin() stopped being
    -- called (see windowAt()) — it simply stops existing for this frame.
    -- None of the grip/collapse-arrow/close-button behavior() calls below
    -- will run this frame (or any frame until it's reopened), so release any
    -- stale claim on them now — see releaseIfActive()'s comment.
    releaseIfActive(makeId("#GRIP"))
    releaseIfActive(makeId("#COLLAPSE"))
    releaseIfActive(makeId("#CLOSE"))
    if ctx.resizeWindow == win then ctx.resizeWindow = nil end
    if ctx.dragWindow == win then ctx.dragWindow = nil end
    win.skipItems = true
    win.notSubmitted = true
    win.indent = 0
    win.openChild = nil
    win.prevItem = win.prevItem
      or { x = 0, y = 0, w = 0, h = 0, hovered = false, active = false,
        clicked = false }
    return false, false
  end
  win.notSubmitted = false

  local pending = ctx.nextWindowPos
  if pending then
    if pending.cond ~= "once" or not win.placed then
      win.x, win.y = pending.x, pending.y
    end
    ctx.nextWindowPos = nil
  end
  win.placed = true

  -- A window can never be sized shorter than its title bar plus a couple of
  -- content lines, or narrower than the style's minimum — otherwise it
  -- could clip away its own chrome (grip, scrollbar, close button).
  local minWinH = ctx.font:getHeight() + style.framePadding[2] * 2 -- titleH
    + frameHeight() * 2 + style.windowPadding * 2

  local pendingSize = ctx.nextWindowSize
  if pendingSize then
    if win.flags.AlwaysAutoResize then
      -- Explicitly ignored: this flag means "always fit content", full stop.
    elseif pendingSize.cond ~= "once" or not win.sizePlaced then
      win.w = math.max(pendingSize.w, style.minWindowWidth)
      win.h = math.max(pendingSize.h, minWinH)
      win.sizeMode = "fixed"
      win.sizePlaced = true
    end
    ctx.nextWindowSize = nil
  end

  win.lastFrame = ctx.frame

  local fpx, fpy = style.framePadding[1], style.framePadding[2]
  local pad = style.windowPadding
  win.titleH = ctx.font:getHeight() + fpy * 2
  local flagSet = win.flags
  local hasTitleBar = not flagSet.NoTitleBar
  if not hasTitleBar then win.collapsed = false end
  win.titleBarH = hasTitleBar and win.titleH or 0

  -- Reset before the close button's behavior() check below can set it back
  -- to true: "or false" (formerly here) would only ever patch a nil away,
  -- never a stale `true` left over from the frame the X was actually
  -- clicked — without this, closing a window once and then reopening it
  -- (the caller flips `open` back to true, the exact round trip
  -- ShowDemoWindow() and its own callers use) would report closedThisFrame
  -- forever after, even though no new click ever happened.
  win.closedThisFrame = false

  -- Clear last frame's content clip rect before any chrome hit-testing runs
  -- below (drag zone, resize grip, collapse arrow, close button). Chrome
  -- lives outside the scissored content region, so it must never be gated by
  -- withinClip() — leaving last frame's clip in place here (it's only
  -- recomputed further down, once this frame's own w/h are settled) would
  -- otherwise make title-bar chrome unclickable on any fixed-size window,
  -- since the content clip rect always excludes the title bar's y range.
  win.clipRect = nil

  -- If this window is being dragged, follow the mouse (before drawing
  -- anything, so there is no visible lag).
  if ctx.dragWindow == win then
    win.x = ctx.mouse.x - win.dragOffsetX
    win.y = ctx.mouse.y - win.dragOffsetY
    if ctx.mouse.released then
      -- The title-bar drag ends this frame: settle here instead of
      -- waiting for NewFrame()'s idle-frame safety net (see
      -- releaseIfActive()'s comment), and persist the new position.
      ctx.dragWindow = nil
      ctx.iniDirty = true
    end
  end

  -- Same idea for an in-progress resize (dragging the corner grip): apply
  -- it before drawing so the frame the drag starts already reflects it.
  local resizable = not flagSet.NoResize and not flagSet.AlwaysAutoResize
  if resizable then
    local gs = style.gripSize
    local gx = win.x + win.w - gs
    local gy = win.y + win.h - gs
    local gripId = makeId("#GRIP")
    local _, gripHeld = behavior(win, gripId, gx, gy, gs, gs)
    if gripHeld then
      if ctx.resizeWindow ~= win then
        ctx.resizeWindow = win
        win.resizeStartX, win.resizeStartY = ctx.mouse.x, ctx.mouse.y
        win.resizeStartW, win.resizeStartH = win.w, win.h
      end
      win.w = math.max(style.minWindowWidth,
        win.resizeStartW + (ctx.mouse.x - win.resizeStartX))
      win.h = math.max(minWinH,
        win.resizeStartH + (ctx.mouse.y - win.resizeStartY))
      win.sizeMode = "fixed"
    elseif ctx.resizeWindow == win then
      ctx.resizeWindow = nil
      ctx.iniDirty = true -- the resize-grip drag just ended: persist the size
    end
  else
    -- "NoResize"/"AlwaysAutoResize" flipped on mid-drag: give up the grip's
    -- claim instead of silently going quiet (see releaseIfActive()).
    releaseIfActive(makeId("#GRIP"))
    if ctx.resizeWindow == win then ctx.resizeWindow = nil end
  end

  -- Start this frame's draw list. Window width/height depend on the content
  -- that hasn't run yet, so the background and title-bar rects are pushed
  -- now and their sizes patched in End().
  win.drawList = {}
  win.childRectList = {}
  win.bgCmd = pushRect(win, "fill", win.x, win.y, 0, 0,
    style.colors.windowBg, style.rounding)

  local ah = win.titleH
  if hasTitleBar then
    local isFront = ctx.windowOrder[#ctx.windowOrder] == win
    win.titleCmd = pushRect(win, "fill", win.x, win.y, 0, win.titleH,
      isFront and style.colors.titleBgActive or style.colors.titleBg,
      style.rounding)

    -- Collapse arrow: a regular button-behavior region in the title bar.
    local collapsible = not flagSet.NoCollapse
    if collapsible then
      local _, _, arrowClicked = behavior(win, makeId("#COLLAPSE"),
        win.x, win.y, ah, ah)
      if arrowClicked then
        win.collapsed = not win.collapsed
        ctx.iniDirty = true
      end
    else
      -- "NoCollapse" flipped on mid-hold: release, don't go quiet.
      releaseIfActive(makeId("#COLLAPSE"))
      win.collapsed = false
    end
    local cx, cy, r = win.x + ah * 0.5, win.y + ah * 0.5, ah * 0.24
    if win.collapsed then -- arrow points right
      pushTriangle(win, cx - r * 0.6, cy - r, cx - r * 0.6, cy + r,
        cx + r, cy, style.colors.text)
    else                  -- arrow points down
      pushTriangle(win, cx - r, cy - r * 0.6, cx + r, cy - r * 0.6,
        cx, cy + r, style.colors.text)
    end
    pushText(win, displayTitle, win.x + ah + 2, win.y + fpy, style.colors.text)

    -- Close button: a small X at the title bar's right edge, only when the
    -- caller passed an `open` value (nil means "no close button", as today).
    if open ~= nil then
      local bx, by = win.x + win.w - ah, win.y
      local closeId = makeId("#CLOSE")
      local closeHovered, closeHeld, closePressed =
        behavior(win, closeId, bx, by, ah, ah)
      if closePressed then win.closedThisFrame = true end
      if closeHeld or closeHovered then
        pushRect(win, "fill", bx, by, ah, ah,
          closeHeld and style.colors.buttonActive
          or style.colors.buttonHovered, style.rounding)
      end
      local ip = ah * 0.28
      pushLine(win, bx + ip, by + ip, bx + ah - ip, by + ah - ip,
        style.colors.text)
      pushLine(win, bx + ah - ip, by + ip, bx + ip, by + ah - ip,
        style.colors.text)
    else
      -- The `open` argument stopped being passed (back to nil, "no close
      -- button"): release, don't go quiet.
      releaseIfActive(makeId("#CLOSE"))
    end

    -- Start a title-bar drag: mouse pressed on the title bar and nothing
    -- else claimed the press (the collapse arrow/close button claim it via
    -- activeId).
    if not flagSet.NoMove and ctx.mouse.pressed and ctx.hoveredWindow == win
        and ctx.activeId == nil and ctx.dragWindow == nil
        and pointIn(ctx.mouse.x, ctx.mouse.y,
          win.x, win.y, math.max(win.w, ah), win.titleH) then
      ctx.dragWindow = win
      win.dragOffsetX = ctx.mouse.x - win.x
      win.dragOffsetY = ctx.mouse.y - win.y
    end
  else
    win.titleCmd = nil
    -- "NoTitleBar" flipped on: takes the collapse arrow and close button
    -- with it, so release any stale claim on them too.
    releaseIfActive(makeId("#COLLAPSE"))
    releaseIfActive(makeId("#CLOSE"))
  end

  -- The resize grip itself: drawn last so it sits in front of the border
  -- End() will add, in the bottom-right corner.
  if resizable then
    local gs = style.gripSize
    pushTriangle(win, win.x + win.w, win.y + win.h - gs,
      win.x + win.w - gs, win.y + win.h,
      win.x + win.w, win.y + win.h, style.colors.border)
  end

  -- Reset the layout cursor. skipItems makes every widget a cheap no-op
  -- while the window is collapsed (same trick as ImGui's SkipItems).
  win.skipItems = win.collapsed
  win.indent = 0
  win.innerX = win.x + pad
  win.nextY = win.y + win.titleBarH + pad - (win.scrollY or 0)
  win.lineY, win.lineH = win.nextY, 0
  win.sameLineX = nil
  win.prevItem = { x = win.innerX, y = win.nextY, w = 0, h = 0,
    hovered = false, active = false, clicked = false }
  win.contentMaxX = hasTitleBar
    and (win.x + ah + 2 + ctx.font:getWidth(displayTitle) + fpx)
    or win.x
  win.contentMaxY = win.y + win.titleBarH

  -- Fixed-size windows clip their content region so it can't paint over the
  -- title bar or below the window's own bounds — this is also what makes
  -- scrolled-out widgets stop being clickable (see withinClip()). Auto-fit
  -- windows never need this: they always grow to fit, so there's nothing to
  -- clip against.
  win.clipRect = nil
  if not win.collapsed and win.sizeMode == "fixed" and not flagSet.AlwaysAutoResize then
    local cy = win.y + win.titleBarH
    local ch = math.max(win.h - win.titleBarH, 0)
    pushClip(win, win.x, cy, win.w, ch)
    win.clipRect = { x = win.x, y = cy, w = win.w, h = ch }
  end

  if win.closedThisFrame then
    return not win.collapsed, false
  end
  if open == nil then
    return not win.collapsed, nil
  end
  return not win.collapsed, true
end

--- Close the current window. Must be called exactly once for every Begin(),
--- collapsed or not. Fits the window to its content and finishes its draw
--- list. Equivalent of ImGui::End().
function imlove.End()
  local win = ctx.currentWindow
  if not win then
    error("imlove.End() called without a matching imlove.Begin()", 2)
  end
  if win.isChild then
    error("imlove.End() called with BeginChild('" .. win.idStr
      .. "') still open — missing imlove.EndChild()", 2)
  end
  if win.isPopup then
    error("imlove.End() called with a popup still open — missing imlove.EndPopup()", 2)
  end
  if win.isTooltip then
    error("imlove.End() called with a tooltip still open — missing imlove.EndTooltip()", 2)
  end
  if #ctx.idStack > 1 then
    error("imlove.End(): " .. (#ctx.idStack - 1)
      .. " PushID()/TreeNode() left unpopped in window '" .. win.title .. "'", 2)
  end

  if win.notSubmitted then
    ctx.currentWindow = nil
    ctx.idStack = {}
    return
  end

  local pad = style.windowPadding
  local flagSet = win.flags or {}
  local autoFit = flagSet.AlwaysAutoResize or win.sizeMode ~= "fixed"

  if autoFit then
    win.w = math.max(win.contentMaxX + pad - win.x, style.minWindowWidth)
    win.h = win.collapsed and win.titleBarH
      or math.max(win.contentMaxY + pad - win.y, win.titleBarH)
    win.scrollY, win.contentH, win.visibleH = 0, 0, 0
  else
    if not win.collapsed then
      popClip(win) -- close the content clip region pushed in Begin()
    end
    win.visibleH = math.max(win.h - win.titleBarH, 0)
    -- contentMaxY was measured against a cursor that already started at
    -- -scrollY (so content draws in the right place while scrolled), so add
    -- it back here to get the scroll-independent total content height —
    -- otherwise contentH would shrink as scrollY grows, clamping scrollY
    -- back down and fighting the very scroll that just happened.
    win.contentH = math.max(
      win.contentMaxY + pad - (win.y + win.titleBarH) + win.scrollY, 0)
    local maxScroll = math.max(win.contentH - win.visibleH, 0)
    win.scrollY = clamp(win.scrollY, 0, maxScroll)
  end

  -- Patch the rects whose width/height weren't known in Begin().
  win.bgCmd.w, win.bgCmd.h = win.w, win.h
  if win.titleCmd then win.titleCmd.w = win.w end
  win.lastChildRects = win.childRectList

  win.hasScrollbar = not win.collapsed and not autoFit
    and not flagSet.NoScrollbar and win.contentH > win.visibleH
  if win.hasScrollbar then
    -- The resize grip sits in the bottom-right corner, gripSize square, and
    -- (being anchored to the same corner) always overlaps the bottom of a
    -- full-height scrollbar track. Its behavior() runs earlier, in Begin(),
    -- so it always wins that overlap — shorten the track instead of leaving
    -- the scrollbar's bottom permanently dead under a resizable window.
    local trackH = win.visibleH
    local resizable = not flagSet.NoResize and not flagSet.AlwaysAutoResize
    if resizable then trackH = math.max(trackH - style.gripSize, 0) end
    pushScrollbar(win, makeId("#SCROLLBAR"),
      win.x, win.y + win.titleBarH, win.w, trackH, win)
  end

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

--- Set the size the next Begin() will use, taking the window out of
--- auto-fit mode (see Begin()'s sizing model) — from then on it keeps this
--- size and overflowing content scrolls instead of growing the window.
--- cond is "always" (default) or "once" (only the first time the window is
--- ever created). Ignored by a window with the "AlwaysAutoResize" flag.
--- Equivalent of ImGui::SetNextWindowSize().
function imlove.SetNextWindowSize(w, h, cond)
  ctx.nextWindowSize = { w = w, h = h, cond = cond or "always" }
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

--- Begin a scrollable child region embedded at the cursor in the current
--- window (or child) — a fixed-size box that participates in its root
--- window's draw list (no separate z-order) and gets its own cursor, ID
--- scope, and scroll position, keyed by idStr and persistent across frames
--- like everything else. w/h <= 0 mean, respectively, "remaining width" and
--- a 200px default (there is no well-defined "remaining height" the way
--- there is width, since content can always continue below the fold).
--- border, if truthy, draws a border line around it. Must be matched by
--- EndChild(). Returns whether it's visible — with imlove's clipping model
--- that's simply "false while an ancestor window/child is collapsed or
--- skipping, true otherwise". Equivalent of ImGui::BeginChild().
function imlove.BeginChild(idStr, w, h, border)
  local parent = requireWindow("BeginChild")
  idStr = tostring(idStr)
  local resolvedW = (w and w > 0) and w or availWidth(parent)
  local resolvedH = (h and h > 0) and h or 200

  local root = parent.root or parent
  local idStackBase = #ctx.idStack
  ctx.idStack[idStackBase + 1] = idStr
  -- Keyed by the FULL id-stack path, not the bare idStr: two BeginChild()
  -- calls with the same idStr nested at different depths (e.g. "Row" at the
  -- window's top level and "Row" again inside a "Wrapper" child) must not
  -- share scroll state just because their last path segment matches.
  local scrollKey = table.concat(ctx.idStack, "\31")

  local cx, cy
  if parent.skipItems then
    cx, cy = parent.innerX or parent.x, parent.nextY or parent.y
  else
    cx, cy = itemAdd(parent, resolvedW, resolvedH)
  end

  root.childScroll = root.childScroll or {}
  local scrollState = root.childScroll[scrollKey]
  if not scrollState then
    scrollState = { scrollY = 0, contentH = 0, visibleH = resolvedH }
    root.childScroll[scrollKey] = scrollState
  end

  local pad = style.windowPadding
  local child = {
    isChild = true, title = idStr, idStr = idStr, scrollKey = scrollKey,
    root = root, parent = parent,
    idStackBase = idStackBase, border = border and true or false,
    x = cx, y = cy, w = resolvedW, h = resolvedH,
    indent = 0, innerX = cx + pad,
    nextY = cy + pad - scrollState.scrollY,
    sameLineX = nil,
    prevItem = { x = cx + pad, y = cy + pad, w = 0, h = 0,
      hovered = false, active = false, clicked = false },
    contentMaxX = cx + pad, contentMaxY = cy + pad,
    skipItems = parent.skipItems,
    clipRect = { x = cx, y = cy, w = resolvedW, h = resolvedH },
    drawList = parent.drawList,
    scrollState = scrollState,
    -- Last frame's "did this child show a scrollbar" (see availWidth()).
    -- A fresh `child` table is built every call, so this must be read back
    -- from the persistent scrollState, not the (nonexistent) previous child.
    hasScrollbar = scrollState.hasScrollbar,
  }
  child.lineY, child.lineH = child.nextY, 0

  if not parent.skipItems then
    pushClip(child, cx, cy, resolvedW, resolvedH)
  end

  parent.openChild = child
  ctx.currentWindow = child
  return not parent.skipItems
end

--- Close the current BeginChild() region. Must be called exactly once per
--- BeginChild(); Begin()/End() (and an outer BeginChild()/EndChild()) will
--- error if you forget. Equivalent of ImGui::EndChild().
function imlove.EndChild()
  local win = ctx.currentWindow
  if not win or not win.isChild then
    error("imlove.EndChild() called without a matching imlove.BeginChild()", 2)
  end
  if win.openChild then
    error("imlove.EndChild(): BeginChild('" .. win.openChild.idStr
      .. "') still open — missing imlove.EndChild()", 2)
  end
  if #ctx.idStack ~= win.idStackBase + 1 then
    error("imlove.EndChild(): " .. (#ctx.idStack - win.idStackBase - 1)
      .. " PushID()/TreeNode() left unpopped in child '" .. win.idStr .. "'", 2)
  end
  ctx.idStack[#ctx.idStack] = nil

  local parent = win.parent
  parent.openChild = nil

  if not win.skipItems then
    popClip(win)

    local pad = style.windowPadding
    local st = win.scrollState
    -- Same scrollY-added-back correction as End() — see the comment there.
    -- The subtracted origin must be the UNPADDED win.y, exactly like End()
    -- subtracts the unpadded (win.y + win.titleBarH) — not (win.y + pad):
    -- BeginChild's initial contentMaxY (cy + pad) already accounts for the
    -- top padding the same way a window's first widget does, so subtracting
    -- an extra pad here double-counted it and made children under-scroll by
    -- one windowPadding (the last line rested 2*pad from the bottom instead
    -- of pad).
    st.contentH = math.max(
      win.contentMaxY + pad - win.y + st.scrollY, 0)
    -- Also match End()'s visibleH convention: a window's visibleH is
    -- win.h - titleBarH — the full remaining span down to the window's
    -- bottom edge, with NO bottom pad subtracted (the resting gap at max
    -- scroll comes entirely from contentH's "+pad" term, not from here). A
    -- child has no title bar (its equivalent is 0), so its visibleH must be
    -- the full win.h. Subtracting pad*2 here (as before) double-reserved the
    -- bottom pad on top of contentH's own "+pad", shrinking maxScroll and
    -- leaving content resting 3*pad from the edge instead of 1*pad.
    st.visibleH = math.max(win.h, 0)
    local maxScroll = math.max(st.contentH - st.visibleH, 0)
    st.scrollY = clamp(st.scrollY, 0, maxScroll)

    st.hasScrollbar = st.contentH > st.visibleH
    if st.hasScrollbar then
      pushScrollbar(win, makeId("#SCROLLBAR"), win.x, win.y, win.w, win.h, st)
    end
    if win.border then
      pushRect(win, "line", win.x, win.y, win.w, win.h, style.colors.border, 0)
    end

    local root = win.root
    root.childRectList = root.childRectList or {}
    root.childRectList[#root.childRectList + 1] =
      { id = win.scrollKey, x = win.x, y = win.y, w = win.w, h = win.h }
  end

  ctx.currentWindow = parent
end

--------------------------------------------------------------------------------
-- Popups & tooltips: a small overlay layer drawn ABOVE every window (see
-- Render()'s overlay pass) and hit-tested BEFORE them (see NewFrame(); the
-- bookkeeping — popupId(), popupIsOpen(), openPopupById(), closePopup(),
-- popupAt() — lives further up, before Frame lifecycle, since NewFrame()
-- needs it). Popups reuse the exact same window-shaped table and
-- cursor/clip machinery as Begin() — every existing widget function works
-- unmodified inside one — but keep their own draw list, aren't part of
-- ctx.windowOrder, and are closed with EndPopup() instead of End(). A
-- tooltip is the simplest overlay of all: it never accepts input, always
-- follows the mouse, and always draws last of all (above even popups).
--------------------------------------------------------------------------------

-- Shared layout for BeginPopup()/BeginPopupModal()/BeginPopupContextItem()
-- (and Combo()'s internal dropdown): sets up a window-shaped table exactly
-- like Begin() does — cursor, padding, its own draw list — so every widget
-- function works inside unmodified, but with no drag/resize/collapse, drawn
-- into the overlay band instead of a regular window's slot, and reparented
-- through ctx.currentWindow so nesting (a popup opened from inside another
-- popup, or from inside a regular window/child) unwinds correctly in
-- EndPopup(). `strId` becomes the content scope's ID-stack entry, the same
-- convention as BeginChild()'s idStr.
local function beginPopupContent(id, strId, kind, title)
  local p = ctx.popups[id]
  local win = p.win
  if not win then
    win = { w = 0, h = 0 }
    p.win = win
  end
  win.isPopup = true
  win.popupId = id
  win.kind = kind
  win.parent = ctx.currentWindow
  win.flags = {}

  ctx.currentWindow = win
  win.idStackBase = #ctx.idStack
  ctx.idStack[win.idStackBase + 1] = tostring(strId)
  win.lastFrame = ctx.frame
  -- Snapshot of the id-stack path leading INTO this popup's own content —
  -- every widget id built while it's open has this as a prefix (including
  -- ids in a nested popup opened from inside it). NewFrame() uses this, for
  -- a modal, to tell "belongs to the modal" apart from "belongs to
  -- something the modal blocks" without knowing any widget ids itself —
  -- see the modal input-lockout there.
  p.idPrefix = table.concat(ctx.idStack, "\31")

  local hasTitleBar = kind == "modal"
  win.titleH = hasTitleBar
    and (ctx.font:getHeight() + style.framePadding[2] * 2) or 0
  win.titleBarH = win.titleH

  local sw, sh = love.graphics.getDimensions()
  if kind == "modal" then
    -- Always centered — recomputed every frame from last frame's size (the
    -- library's usual one-frame lag), so it settles into place within a
    -- frame or two of first appearing and stays centered as content grows.
    win.x = (sw - (win.w or 0)) / 2
    win.y = (sh - (win.h or 0)) / 2
  elseif p.justOpened then
    -- Positioned once, at the anchor openPopupById() captured, clamped to
    -- stay fully on screen (using last known size — same one-frame lag);
    -- unlike a modal or the tooltip, it then stays put while open.
    win.x = clamp(p.anchorX, 0, math.max(sw - (win.w or 0), 0))
    win.y = clamp(p.anchorY, 0, math.max(sh - (win.h or 0), 0))
  end
  p.justOpened = false

  win.drawList = {}
  win.childRectList = {}
  if kind == "modal" then
    -- Dims and blocks the rest of the screen — see NewFrame()'s hit-testing
    -- and popupAt(): a regular window is never hovered while any modal is
    -- open. Pushed first so it sits behind this popup's own background.
    pushRect(win, "fill", 0, 0, sw, sh, { 0, 0, 0, 0.55 }, 0)
  end
  win.bgCmd = pushRect(win, "fill", win.x, win.y, 0, 0,
    style.colors.windowBg, style.rounding)
  if hasTitleBar then
    win.titleCmd = pushRect(win, "fill", win.x, win.y, 0, win.titleH,
      style.colors.titleBgActive, style.rounding)
    pushText(win, title or strId, win.x + style.framePadding[1],
      win.y + style.framePadding[2], style.colors.text)
  else
    win.titleCmd = nil
  end

  win.skipItems = false
  win.indent = 0
  win.innerX = win.x + style.windowPadding
  win.nextY = win.y + win.titleBarH + style.windowPadding
  win.lineY, win.lineH = win.nextY, 0
  win.sameLineX = nil
  win.prevItem = { x = win.innerX, y = win.nextY, w = 0, h = 0,
    hovered = false, active = false, clicked = false }
  win.contentMaxX = win.x
  win.contentMaxY = win.y + win.titleBarH
  win.clipRect = nil
  win.hasScrollbar = false
end

-- Closes what beginPopupContent() opened: fits the popup to its content
-- (position was already decided in beginPopupContent() — same one-frame-lag
-- convention a resizing window uses — so it's never touched here) and
-- restores ctx.currentWindow.
local function endPopupContent(win)
  local pad = style.windowPadding
  win.w = math.max(win.contentMaxX + pad - win.x, style.minWindowWidth)
  win.h = math.max(win.contentMaxY + pad - win.y, win.titleBarH)
  win.bgCmd.w, win.bgCmd.h = win.w, win.h
  if win.titleCmd then win.titleCmd.w = win.w end
  pushRect(win, "line", win.x, win.y, win.w, win.h, style.colors.border,
    style.rounding)

  ctx.idStack[#ctx.idStack] = nil
  ctx.currentWindow = win.parent
end

--- Set a tooltip for this frame: a small auto-fit box with no title bar,
--- positioned just past the mouse cursor (clamped to stay on screen),
--- drawn above absolutely everything (even open popups), and never
--- hit-testable — hovering or clicking where it's drawn always reaches
--- whatever is really there. Typically called right after IsItemHovered():
---
---   imlove.Button("Save")
---   if imlove.IsItemHovered() then imlove.SetTooltip("writes to disk") end
---
--- Calling it more than once in a frame replaces the previous call — only
--- the LAST one shows, exactly like calling BeginTooltip()/EndTooltip()
--- yourself twice would. Equivalent of ImGui::SetTooltip().
function imlove.SetTooltip(fmt, ...)
  imlove.BeginTooltip()
  imlove.Text(fmt, ...)
  imlove.EndTooltip()
end

--- Manual form of SetTooltip(), for a tooltip with more than one widget in
--- it. Must be paired with EndTooltip(); unlike Begin()/End(), calling this
--- more than once in a frame is fine — each call simply replaces whatever
--- the previous one built, "last call wins" exactly like SetTooltip().
--- Equivalent of ImGui::BeginTooltip().
function imlove.BeginTooltip()
  -- Calling this again before EndTooltip() would otherwise set
  -- win.parent = win (ctx.currentWindow IS already the tooltip), a
  -- self-reference that EndTooltip() could never undo — every Render()
  -- from then on, forever, would fail with "a tooltip is open" (see
  -- whatIsOpen()), even after the caller fixes the bug, since nothing
  -- would ever restore ctx.currentWindow to anything else. Erroring here,
  -- before that assignment happens, keeps this the same kind of
  -- one-frame, fix-it-and-it's-fine mistake as every other unbalanced
  -- Begin*/End* pair in the library instead.
  if ctx.currentWindow and ctx.currentWindow.isTooltip then
    error("imlove.BeginTooltip() called while a tooltip is already open — "
      .. "missing imlove.EndTooltip()", 2)
  end
  local win = ctx.tooltipWin
  if not win then
    win = { title = "##tooltip" }
    ctx.tooltipWin = win
  end
  win.isTooltip = true
  win.parent = ctx.currentWindow
  win.flags = {}
  ctx.currentWindow = win
  win.idStackBase = #ctx.idStack
  ctx.idStack[win.idStackBase + 1] = "##tooltip"
  win.lastFrame = ctx.frame

  local sw, sh = love.graphics.getDimensions()
  win.x = clamp(ctx.mouse.x + 16, 0, math.max(sw - (win.w or 0), 0))
  win.y = clamp(ctx.mouse.y + 16, 0, math.max(sh - (win.h or 0), 0))

  win.drawList = {}
  win.bgCmd = pushRect(win, "fill", win.x, win.y, 0, 0,
    style.colors.windowBg, style.rounding)
  win.titleCmd = nil
  win.skipItems = false
  win.indent = 0
  win.innerX = win.x + style.windowPadding
  win.nextY = win.y + style.windowPadding
  win.lineY, win.lineH = win.nextY, 0
  win.sameLineX = nil
  win.prevItem = { x = win.innerX, y = win.nextY, w = 0, h = 0,
    hovered = false, active = false, clicked = false }
  win.contentMaxX, win.contentMaxY = win.x, win.y
  win.clipRect = nil
  win.hasScrollbar = false
end

--- Closes what BeginTooltip() opened. Equivalent of ImGui::EndTooltip().
function imlove.EndTooltip()
  local win = ctx.currentWindow
  if not win or not win.isTooltip then
    error("imlove.EndTooltip() called without a matching imlove.BeginTooltip()", 2)
  end
  local pad = style.windowPadding
  win.w = math.max(win.contentMaxX + pad - win.x, style.minWindowWidth)
  win.h = math.max(win.contentMaxY + pad - win.y, 1)
  win.bgCmd.w, win.bgCmd.h = win.w, win.h
  pushRect(win, "line", win.x, win.y, win.w, win.h, style.colors.border,
    style.rounding)

  ctx.idStack[#ctx.idStack] = nil
  ctx.currentWindow = win.parent
end

--- Marks strId's popup open — resolved against the current ID stack exactly
--- like a widget id (see BeginPopup()'s doc comment), so it's typically
--- called right after the button/item that should open it:
---
---   if imlove.Button("Options") then imlove.OpenPopup("options") end
---
--- Equivalent of ImGui::OpenPopup().
function imlove.OpenPopup(strId)
  openPopupById(popupId(strId), "popup")
end

--- Begin a popup opened with OpenPopup(strId): a small floating, auto-fit,
--- no-title-bar window, positioned where the mouse was when OpenPopup() was
--- called (clamped to stay on screen), drawn above every regular window.
--- Returns whether it's open; UNLIKE Begin()/End() (where you always call
--- End()), EndPopup() must be called ONLY when this returns true — exactly
--- Dear ImGui's convention:
---
---   if imlove.BeginPopup("options") then
---     imlove.Text("...")
---     imlove.EndPopup()
---   end
---
--- strId is resolved against the current ID stack the same way OpenPopup()
--- resolves it, so call both from the same scope (window, PushID, or
--- enclosing popup) unless you want them to refer to different popups. A
--- press outside the topmost open popup closes it — and everything stacked
--- above whatever it landed on, if it landed on a lower popup in a nested
--- stack — and that dismissing press is CONSUMED (your game never sees
--- it), exactly like a press that lands ON a popup or widget is. Equivalent
--- of ImGui::BeginPopup().
function imlove.BeginPopup(strId)
  local id = popupId(strId)
  if not popupIsOpen(id) then return false end
  beginPopupContent(id, strId, "popup", nil)
  return true
end

--- Closes a popup opened with a successful BeginPopup()/BeginPopupModal()/
--- BeginPopupContextItem() — call it ONLY when that call returned true (see
--- BeginPopup()'s doc comment). Calling it without a matching open popup is
--- an error, and so is leaving one open past End()/EndChild()/Render().
--- Equivalent of ImGui::EndPopup().
function imlove.EndPopup()
  local win = ctx.currentWindow
  if not win or not win.isPopup then
    error("imlove.EndPopup() called without a matching successful "
      .. "imlove.BeginPopup()/BeginPopupModal()/BeginPopupContextItem()", 2)
  end
  if #ctx.idStack ~= win.idStackBase + 1 then
    error("imlove.EndPopup(): " .. (#ctx.idStack - win.idStackBase - 1)
      .. " PushID()/TreeNode() left unpopped in popup", 2)
  end
  endPopupContent(win)
end

--- Closes whichever popup's content is currently being built — call it from
--- inside a BeginPopup()/BeginPopupModal()/BeginPopupContextItem() block
--- (e.g. from a "Close"/"OK" Button(), or right after a Selectable() picks
--- an option) instead of tracking the popup's id yourself. A no-op outside
--- a popup. Equivalent of ImGui::CloseCurrentPopup().
function imlove.CloseCurrentPopup()
  local win = ctx.currentWindow
  if win and win.isPopup then
    closePopup(win.popupId)
  end
end

--- Opens a popup on a right-click over the most recently submitted item
--- (its rectangle — the same one IsItemHovered() reads) — the canonical
--- right-click context menu:
---
---   imlove.PushID(e.id)
---   imlove.Selectable(e.name, false)
---   if imlove.BeginPopupContextItem() then
---     if imlove.Selectable("Delete") then removeEntity(e) end
---     imlove.EndPopup()
---   end
---   imlove.PopID()
---
--- strId defaults to a fixed name scoped to the surrounding ID stack —
--- exactly like every other widget, wrap each row in PushID()/PopID() (as
--- you already would to give each row's own widgets distinct ids) to keep
--- separate rows' context menus separate; pass an explicit strId if you'd
--- rather not rely on that. Otherwise behaves exactly like BeginPopup():
--- auto-fit, no title bar, positioned at the click, dismissed by an outside
--- press (consumed) — pair with EndPopup() only when this returns true.
--- Equivalent of ImGui::BeginPopupContextItem().
function imlove.BeginPopupContextItem(strId)
  local win = requireWindow("BeginPopupContextItem")
  strId = strId or "##popupcontext"
  local id = popupId(strId)

  if not win.skipItems and ctx.mouse.rightPressed and win.prevItem.hovered then
    openPopupById(id, "popup")
  end

  if not popupIsOpen(id) then return false end
  beginPopupContent(id, strId, "popup", nil)
  return true
end

--- Begin a modal popup opened with OpenPopup(title) (or the id portion of
--- "Label##id"): has a title bar showing title, is always centered on
--- screen, dims and blocks input to everything else — regular windows stop
--- being hit-testable and io.WantCaptureMouse is unconditionally true while
--- it's open — and, unlike BeginPopup(), an outside press does NOT dismiss
--- it: only CloseCurrentPopup() does (wire it to your own OK/Cancel
--- buttons). Pair with EndPopup() only when this returns true, exactly like
--- BeginPopup(). Equivalent of ImGui::BeginPopupModal().
function imlove.BeginPopupModal(title)
  title = tostring(title)
  local _, idText = splitLabel(title)
  local id = popupId(idText)
  if not popupIsOpen(id) then return false end
  ctx.popups[id].kind = "modal"
  beginPopupContent(id, idText, "modal", title)
  return true
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
  local x, y = itemAddPassive(win, w, h)
  pushText(win, text, x, y, style.colors.text)
end

--- Static text drawn in an explicit color instead of the theme's default,
--- e.g. imlove.TextColored({1, 0.4, 0.4, 1}, "low health!"). Extra arguments
--- go through string.format like Text(). Equivalent of ImGui::TextColored().
function imlove.TextColored(color, fmt, ...)
  local win = requireWindow("TextColored")
  if win.skipItems then return end
  local text = tostring(fmt)
  if select("#", ...) > 0 then text = string.format(text, ...) end
  local w, h = textSize(text)
  local x, y = itemAddPassive(win, w, h)
  pushText(win, text, x, y, color)
end

--- Static text dimmed to a muted gray, for de-emphasized captions or
--- placeholders. Equivalent of ImGui::TextDisabled().
function imlove.TextDisabled(fmt, ...)
  local win = requireWindow("TextDisabled")
  if win.skipItems then return end
  local text = tostring(fmt)
  if select("#", ...) > 0 then text = string.format(text, ...) end
  local w, h = textSize(text)
  local x, y = itemAddPassive(win, w, h)
  pushText(win, text, x, y, style.colors.textDisabled)
end

--- Static text that word-wraps to the window's available content width
--- (as of last frame — the usual one-frame lag; see availWidth()).
--- Equivalent of ImGui::TextWrapped().
function imlove.TextWrapped(fmt, ...)
  local win = requireWindow("TextWrapped")
  if win.skipItems then return end
  local text = tostring(fmt)
  if select("#", ...) > 0 then text = string.format(text, ...) end
  local wrapW = math.max(availWidth(win), 1)
  local _, wrapped = ctx.font:getWrap(text, wrapW)
  text = table.concat(wrapped, "\n")
  local w, h = textSize(text)
  local x, y = itemAddPassive(win, w, h)
  pushText(win, text, x, y, style.colors.text)
end

--- Static text prefixed with a small filled bullet, for flat lists of facts
--- that don't need a full TreeNode. Equivalent of ImGui::BulletText().
function imlove.BulletText(fmt, ...)
  local win = requireWindow("BulletText")
  if win.skipItems then return end
  local text = tostring(fmt)
  if select("#", ...) > 0 then text = string.format(text, ...) end
  local fontH = ctx.font:getHeight()
  local bulletW = fontH * 0.6
  local tw, th = textSize(text)
  local w = bulletW + style.innerSpacing + tw
  local x, y = itemAddPassive(win, w, th)
  pushCircle(win, "fill", x + bulletW * 0.5, y + th * 0.5, fontH * 0.15,
    style.colors.text)
  pushText(win, text, x + bulletW + style.innerSpacing, y, style.colors.text)
end

--- A push button. Returns true on the frame it is clicked (mouse released
--- over it). w/h are optional explicit sizes; 0 or nil on either axis means
--- "auto-size to the label" on that axis, same as ImGui's ImVec2(0, 0).
--- Equivalent of ImGui::Button().
function imlove.Button(label, w, h)
  local win = requireWindow("Button")
  if win.skipItems then return false end
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local fpx, fpy = style.framePadding[1], style.framePadding[2]
  local tw, th = textSize(display)
  w = (w and w > 0) and w or tw + fpx * 2
  h = (h and h > 0) and h or th + fpy * 2
  local x, y = itemAdd(win, w, h)
  local hovered, held, pressed = behavior(win, id, x, y, w, h)
  recordItem(win, hovered, held, pressed)
  local color = held and style.colors.buttonActive
    or hovered and style.colors.buttonHovered
    or style.colors.button
  pushRect(win, "fill", x, y, w, h, color, style.rounding)
  pushText(win, display, x + (w - tw) / 2, y + (h - th) / 2, style.colors.text)
  return pressed
end

--- A push button with no vertical frame padding, for placing a button
--- inline with a line of text. Equivalent of ImGui::SmallButton().
function imlove.SmallButton(label)
  local win = requireWindow("SmallButton")
  if win.skipItems then return false end
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local fpx = style.framePadding[1]
  local tw, th = textSize(display)
  local w, h = tw + fpx * 2, th
  local x, y = itemAdd(win, w, h)
  local hovered, held, pressed = behavior(win, id, x, y, w, h)
  recordItem(win, hovered, held, pressed)
  local color = held and style.colors.buttonActive
    or hovered and style.colors.buttonHovered
    or style.colors.button
  pushRect(win, "fill", x, y, w, h, color, style.rounding)
  pushText(win, display, x + fpx, y, style.colors.text)
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
  recordItem(win, hovered, held, pressed)
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

--- A radio button: a circular Selectable. Pass whether it is the currently
--- chosen option (it draws with a filled dot); returns true on the frame it
--- is clicked — switching the selection is up to you, exactly like
--- Selectable():
---
---   if imlove.RadioButton("Easy", difficulty == "easy") then
---     difficulty = "easy"
---   end
---
--- Equivalent of ImGui::RadioButton(label, active).
function imlove.RadioButton(label, active)
  local win = requireWindow("RadioButton")
  if win.skipItems then return false end
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local fpy = style.framePadding[2]
  local box = ctx.font:getHeight() + fpy * 2
  local tw = ctx.font:getWidth(display)
  local w = box + style.innerSpacing + tw
  local x, y = itemAdd(win, w, box)
  local hovered, held, pressed = behavior(win, id, x, y, w, box)
  recordItem(win, hovered, held, pressed)
  local cx, cy, r = x + box * 0.5, y + box * 0.5, box * 0.5 - 1
  local bg = held and style.colors.frameBgActive
    or hovered and style.colors.frameBgHovered
    or style.colors.frameBg
  pushCircle(win, "fill", cx, cy, r, bg)
  if active then
    pushCircle(win, "fill", cx, cy, r * 0.5, style.colors.checkMark)
  end
  pushText(win, display, x + box + style.innerSpacing, y + fpy,
    style.colors.text)
  return pressed
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
  recordItem(win, hovered, held, false)

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

--- A horizontal slider for an integer, stepped and displayed as "%d". Same
--- click/drag/return contract as SliderFloat(). Equivalent of
--- ImGui::SliderInt().
function imlove.SliderInt(label, value, min, max)
  local win = requireWindow("SliderInt")
  value = math.floor(tonumber(value) or min)
  if win.skipItems then return value, false end
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local fpx, fpy = style.framePadding[1], style.framePadding[2]
  local trackW, h = style.sliderWidth, frameHeight()
  local tw = ctx.font:getWidth(display)
  local totalW = trackW + (tw > 0 and style.innerSpacing + tw or 0)
  local x, y = itemAdd(win, totalW, h)
  local hovered, held = behavior(win, id, x, y, trackW, h)
  recordItem(win, hovered, held, false)

  local old = value
  if held then
    local t = clamp((ctx.mouse.x - x) / trackW, 0, 1)
    value = min + t * (max - min)
  end
  value = clamp(value, math.min(min, max), math.max(min, max))
  value = math.floor(value + 0.5)

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
  local valueText = string.format("%d", value)
  pushText(win, valueText,
    x + (trackW - ctx.font:getWidth(valueText)) / 2, y + fpy,
    style.colors.text)
  if tw > 0 then
    pushText(win, display, x + trackW + style.innerSpacing, y + fpy,
      style.colors.text)
  end
  return value, value ~= old
end

-- Shared drag math for DragFloat/DragInt: while held, the value tracks
-- horizontal mouse movement scaled by speed, anchored to the value and
-- mouse position captured the frame the drag began. Anchoring (rather than
-- accumulating a per-frame delta) means the value can never drift from
-- rounding error, and a click that doesn't move the mouse changes nothing —
-- unlike SliderFloat, a Drag widget never "jumps" to a clicked position.
local function dragValue(id, held, value, speed, min, max)
  if held then
    local anchor = ctx.dragAnchor
    if not anchor or anchor.id ~= id then
      anchor = { id = id, x = ctx.mouse.x, value = value }
      ctx.dragAnchor = anchor
    end
    value = anchor.value + (ctx.mouse.x - anchor.x) * speed
    if min and max then
      value = clamp(value, math.min(min, max), math.max(min, max))
    elseif min then
      value = math.max(value, min)
    elseif max then
      value = math.min(value, max)
    end
  elseif ctx.dragAnchor and ctx.dragAnchor.id == id then
    ctx.dragAnchor = nil
  end
  return value
end

--- An unbounded (by default) float editor: click and drag horizontally to
--- change the value by speed per pixel, instead of mapping the whole track
--- to a fixed range like SliderFloat. min/max are optional — nil means
--- unbounded on that side (ImGui uses a 0, 0 sentinel for this; Lua just
--- omits the argument). speed defaults to 1.0, ImGui's default. Returns
--- value, changed like every other value widget. Equivalent of
--- ImGui::DragFloat().
function imlove.DragFloat(label, value, speed, min, max)
  local win = requireWindow("DragFloat")
  value = tonumber(value) or 0
  if win.skipItems then return value, false end
  speed = speed or 1.0
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local fpx, fpy = style.framePadding[1], style.framePadding[2]
  local trackW, h = style.sliderWidth, frameHeight()
  local tw = ctx.font:getWidth(display)
  local totalW = trackW + (tw > 0 and style.innerSpacing + tw or 0)
  local x, y = itemAdd(win, totalW, h)
  local hovered, held = behavior(win, id, x, y, trackW, h)
  recordItem(win, hovered, held, false)

  local old = value
  value = dragValue(id, held, value, speed, min, max)

  local bg = held and style.colors.frameBgActive
    or hovered and style.colors.frameBgHovered
    or style.colors.frameBg
  pushRect(win, "fill", x, y, trackW, h, bg, style.rounding)
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

--- The integer counterpart of DragFloat(): speed defaults to 1, and the
--- value is rounded to the nearest integer. Equivalent of ImGui::DragInt().
function imlove.DragInt(label, value, speed, min, max)
  local win = requireWindow("DragInt")
  value = math.floor(tonumber(value) or 0)
  if win.skipItems then return value, false end
  speed = speed or 1
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local fpx, fpy = style.framePadding[1], style.framePadding[2]
  local trackW, h = style.sliderWidth, frameHeight()
  local tw = ctx.font:getWidth(display)
  local totalW = trackW + (tw > 0 and style.innerSpacing + tw or 0)
  local x, y = itemAdd(win, totalW, h)
  local hovered, held = behavior(win, id, x, y, trackW, h)
  recordItem(win, hovered, held, false)

  local old = value
  value = math.floor(dragValue(id, held, value, speed, min, max) + 0.5)

  local bg = held and style.colors.frameBgActive
    or hovered and style.colors.frameBgHovered
    or style.colors.frameBg
  pushRect(win, "fill", x, y, trackW, h, bg, style.rounding)
  local valueText = string.format("%d", value)
  pushText(win, valueText,
    x + (trackW - ctx.font:getWidth(valueText)) / 2, y + fpy,
    style.colors.text)
  if tw > 0 then
    pushText(win, display, x + trackW + style.innerSpacing, y + fpy,
      style.colors.text)
  end
  return value, value ~= old
end

--- A progress bar filled to fraction (clamped to 0..1). w/h default to the
--- slider width and frame height; overlay defaults to a centered "NN%"
--- label, or pass your own string. Equivalent of ImGui::ProgressBar().
function imlove.ProgressBar(fraction, w, h, overlay)
  local win = requireWindow("ProgressBar")
  fraction = clamp(tonumber(fraction) or 0, 0, 1)
  if win.skipItems then return end
  w = (w and w > 0) and w or style.sliderWidth
  h = (h and h > 0) and h or frameHeight()
  local x, y = itemAddPassive(win, w, h)
  pushRect(win, "fill", x, y, w, h, style.colors.frameBg, style.rounding)
  if fraction > 0 then
    pushRect(win, "fill", x, y, w * fraction, h, style.colors.sliderGrab,
      style.rounding)
  end
  local text = overlay or string.format("%d%%",
    math.floor(fraction * 100 + 0.5))
  local tw = ctx.font:getWidth(text)
  pushText(win, text, x + (w - tw) / 2, y + style.framePadding[2],
    style.colors.text)
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
  recordItem(win, hovered, held, pressed)
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

--- A full-width framed header, for organizing a debug panel into sections.
--- Unlike TreeNode(), it doesn't indent its content and doesn't push
--- anything onto the ID stack, and there is no matching "Pop" call — put
--- your following widgets directly under it:
---
---   if imlove.CollapsingHeader("Rendering") then
---     imlove.Text("...")
---   end
---
--- Open state persists across frames, keyed like every other widget id.
--- defaultOpen (optional, default false) only matters the very first time
--- this id is ever seen — like ImGui's ImGuiTreeNodeFlags_DefaultOpen, it
--- seeds the initial state, and never overrides whatever the user has since
--- clicked it to.
--- Equivalent of ImGui::CollapsingHeader(label, ImGuiTreeNodeFlags_DefaultOpen).
function imlove.CollapsingHeader(label, defaultOpen)
  local win = requireWindow("CollapsingHeader")
  if win.skipItems then return false end
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  if ctx.openNodes[id] == nil then ctx.openNodes[id] = defaultOpen == true end
  local open = ctx.openNodes[id] == true
  local fpx, fpy = style.framePadding[1], style.framePadding[2]
  local h = frameHeight()
  local arrow = ctx.font:getHeight()
  local w = math.max(availWidth(win),
    arrow + style.innerSpacing + ctx.font:getWidth(display) + fpx * 2)
  local x, y = itemAdd(win, w, h)
  local hovered, held, pressed = behavior(win, id, x, y, w, h)
  recordItem(win, hovered, held, pressed)
  if pressed then
    open = not open
    ctx.openNodes[id] = open
  end
  local bg = held and style.colors.frameBgActive
    or hovered and style.colors.headerHovered
    or style.colors.frameBg
  pushRect(win, "fill", x, y, w, h, bg, style.rounding)
  local cx, cy, r = x + fpx + arrow * 0.5, y + h * 0.5, arrow * 0.3
  if open then
    pushTriangle(win, cx - r, cy - r * 0.6, cx + r, cy - r * 0.6,
      cx, cy + r, style.colors.text)
  else
    pushTriangle(win, cx - r * 0.6, cy - r, cx - r * 0.6, cy + r,
      cx + r, cy, style.colors.text)
  end
  pushText(win, display, x + fpx + arrow + style.innerSpacing, y + fpy,
    style.colors.text)
  return open
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
  recordItem(win, hovered, held, pressed)
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
  local x, y = itemAddPassive(win, w, 1)
  pushLine(win, x, y + 0.5, x + w, y + 0.5, style.colors.separator)
end

--- A blank vertical gap the size of one item spacing. Equivalent of
--- ImGui::Spacing().
function imlove.Spacing()
  local win = requireWindow("Spacing")
  if win.skipItems then return end
  itemAddPassive(win, 0, 0)
end

--- Forces the next widget onto a new row, even right after SameLine().
--- Equivalent of ImGui::NewLine().
function imlove.NewLine()
  local win = requireWindow("NewLine")
  if win.skipItems then return end
  win.sameLineX = nil -- cancel any pending SameLine(): really start a row
  itemAddPassive(win, 0, ctx.font:getHeight())
end

--- Reserves a w x h blank rectangle in the layout — a spacer, or a stand-in
--- for a widget you draw yourself. Equivalent of ImGui::Dummy().
function imlove.Dummy(w, h)
  local win = requireWindow("Dummy")
  if win.skipItems then return end
  itemAddPassive(win, w, h)
end

--- Shifts every following widget in this window right by w (default:
--- style's indent). Call Unindent() with the same w to undo it — unlike
--- TreeNode(), this is a plain cursor shift with no ID stack involved, so it
--- nests however you call it. Equivalent of ImGui::Indent().
function imlove.Indent(w)
  local win = requireWindow("Indent")
  if win.skipItems then return end
  win.indent = win.indent + ((w and w ~= 0) and w or style.indent)
end

--- Undoes Indent(w). Equivalent of ImGui::Unindent().
function imlove.Unindent(w)
  local win = requireWindow("Unindent")
  if win.skipItems then return end
  win.indent = win.indent - ((w and w ~= 0) and w or style.indent)
end

--- Place the next widget on the same line as the previous one instead of
--- below it. With no arguments, continues right after the previous item
--- plus one item spacing — the v1 behavior. offsetFromStartX, if non-zero,
--- instead places it at that x offset from the window's content start
--- (handy for aligning a column of trailing widgets). spacing, if given,
--- overrides the default item-spacing gap. Equivalent of ImGui::SameLine().
function imlove.SameLine(offsetFromStartX, spacing)
  local win = requireWindow("SameLine")
  if win.skipItems then return end
  if offsetFromStartX and offsetFromStartX ~= 0 then
    win.sameLineX = win.innerX + win.indent + offsetFromStartX
  else
    win.sameLineX = win.prevItem.x + win.prevItem.w
      + (spacing or style.itemSpacing[1])
  end
end

-- Auto-range for PlotLines/PlotHistogram when scaleMin/scaleMax are nil:
-- the min/max of the sampled values, like ImGui's FLT_MAX sentinel does.
local function autoRange(values)
  local lo, hi = math.huge, -math.huge
  for i = 1, #values do
    local v = values[i]
    if v < lo then lo = v end
    if v > hi then hi = v end
  end
  if lo > hi then lo, hi = 0, 0 end -- no samples: avoid returning +/-inf
  return lo, hi
end

-- Shared layout/drawing for PlotLines/PlotHistogram: only the plotted shape
-- differs between them.
local function plotWidget(win, kind, label, values, scaleMin, scaleMax,
    w, h, overlay)
  local display, idText = splitLabel(label)
  local fpy = style.framePadding[2]
  w = (w and w > 0) and w or style.sliderWidth
  h = (h and h > 0) and h or frameHeight() * 3
  local tw = ctx.font:getWidth(display)
  local totalW = w + (tw > 0 and style.innerSpacing + tw or 0)
  local x, y = itemAddPassive(win, totalW, h)
  pushRect(win, "fill", x, y, w, h, style.colors.frameBg, style.rounding)

  local n = #values
  if n > 0 then
    local lo = scaleMin
    local hi = scaleMax
    if not lo or not hi then
      local autoLo, autoHi = autoRange(values)
      lo = lo or autoLo
      hi = hi or autoHi
    end
    local range = hi - lo
    local function plotY(v)
      local t = range ~= 0 and clamp((v - lo) / range, 0, 1) or 0.5
      return y + h - t * h
    end

    if kind == "lines" then
      for i = 1, n - 1 do
        local x1 = x + (i - 1) / (n - 1) * w
        local x2 = x + i / (n - 1) * w
        pushLine(win, x1, plotY(values[i]), x2, plotY(values[i + 1]),
          style.colors.sliderGrab)
      end
    else -- "histogram"
      local barW = w / n
      for i = 1, n do
        local bx = x + (i - 1) * barW
        local by = plotY(values[i])
        pushRect(win, "fill", bx, by, math.max(barW - 1, 1), y + h - by,
          style.colors.sliderGrab)
      end
    end
  end

  if overlay then
    local ow = ctx.font:getWidth(overlay)
    pushText(win, overlay, x + (w - ow) / 2, y + fpy, style.colors.text)
  end
  if tw > 0 then
    pushText(win, display, x + w + style.innerSpacing,
      y + (h - ctx.font:getHeight()) / 2, style.colors.text)
  end
end

--- A line-graph plot of values (a plain Lua array of numbers), the
--- canonical "FPS over time" debug widget:
---
---   imlove.PlotLines("frame time", history, 0, 0.05)
---
--- scaleMin/scaleMax default to the min/max found in values when nil. w/h
--- default to the slider width and three line-heights. overlay, if given,
--- is centered on top of the plot (e.g. a current-value readout) instead of
--- the label, which is drawn to the right like SliderFloat's.
--- Equivalent of ImGui::PlotLines().
function imlove.PlotLines(label, values, scaleMin, scaleMax, w, h, overlay)
  local win = requireWindow("PlotLines")
  if win.skipItems then return end
  plotWidget(win, "lines", label, values, scaleMin, scaleMax, w, h, overlay)
end

--- Same signature and semantics as PlotLines(), drawn as vertical bars
--- instead of a connected line. Equivalent of ImGui::PlotHistogram().
function imlove.PlotHistogram(label, values, scaleMin, scaleMax, w, h,
    overlay)
  local win = requireWindow("PlotHistogram")
  if win.skipItems then return end
  plotWidget(win, "histogram", label, values, scaleMin, scaleMax, w, h,
    overlay)
end

--- A dropdown: shows `items[value]` (a plain array of strings) in a slider-
--- width preview box with a small arrow, click to open a popup listing every
--- item as a Selectable(), pick one to close it. Returns the (possibly
--- changed) value plus a changed flag, same convention as SliderFloat:
---
---   quality, changed = imlove.Combo("Quality", quality, {"Low", "Medium", "High"})
---
--- DEVIATION from ImGui: value is a 1-based index into items (Lua
--- convention), not a 0-based int. An out-of-range value (including 0 or
--- nil) shows an empty preview instead of erroring — handy for "nothing
--- selected yet". Reuses the same popup machinery as BeginPopup(); the
--- dropdown is drawn and dismissed exactly like any other popup, it just
--- opens and closes itself instead of requiring your own OpenPopup() call.
--- Equivalent of ImGui::Combo().
function imlove.Combo(label, value, items)
  local win = requireWindow("Combo")
  if win.skipItems then return value, false end
  local display, idText = splitLabel(label)
  local id = makeId(idText)
  local fpx, fpy = style.framePadding[1], style.framePadding[2]
  local boxW, h = style.sliderWidth, frameHeight()
  local tw = ctx.font:getWidth(display)
  local totalW = boxW + (tw > 0 and style.innerSpacing + tw or 0)
  local x, y = itemAdd(win, totalW, h)
  local hovered, held = behavior(win, id, x, y, boxW, h)
  recordItem(win, hovered, held, false)

  local popId = popupId(idText)
  local isOpen = popupIsOpen(popId)
  if hovered and ctx.mouse.pressed then
    -- Press-time toggle (not release-time like most widgets): the generic
    -- outside-press dismiss-scan in NewFrame() also runs at press-time, and
    -- this box is registered as that popup's ownerRect, so a press here
    -- while open is never treated as an outside/dismiss click — it reaches
    -- here and this toggle is the only thing that closes it.
    if isOpen then
      closePopup(popId)
    else
      openPopupById(popId, "popup", { x = x, y = y, w = boxW, h = h },
        x, y + h + 2)
    end
    isOpen = not isOpen
  end

  local bg = held and style.colors.frameBgActive
    or hovered and style.colors.frameBgHovered
    or style.colors.frameBg
  pushRect(win, "fill", x, y, boxW, h, bg, style.rounding)
  local preview = items and items[value]
  if preview then
    pushText(win, tostring(preview), x + fpx, y + fpy, style.colors.text)
  end
  local ax, ay = x + boxW - fpx - 4, y + h / 2
  pushTriangle(win, ax - 4, ay - 2.5, ax + 4, ay - 2.5, ax, ay + 3,
    style.colors.text)
  if tw > 0 then
    pushText(win, display, x + boxW + style.innerSpacing, y + fpy,
      style.colors.text)
  end

  -- A pick reports changed = true unconditionally, even re-picking the
  -- already-selected item — matching ImGui's Combo (it sets value_changed
  -- on the click itself, not on whether the index actually moved). Only
  -- "opened it, picked nothing, dismissed it" is changed = false.
  local picked = false
  if isOpen then
    beginPopupContent(popId, idText, "popup", nil)
    for i, item in ipairs(items or {}) do
      imlove.PushID(i)
      if imlove.Selectable(tostring(item), i == value) then
        value = i
        picked = true
        closePopup(popId)
      end
      imlove.PopID()
    end
    endPopupContent(ctx.currentWindow)
  end
  return value, picked
end

--- An inline, scrollable list of items (a plain array of strings) shown as
--- Selectable() rows in a fixed-height child region — pick one to select
--- it. Returns the (possibly changed) value plus a changed flag, same
--- convention as Combo():
---
---   choice, changed = imlove.ListBox("Level", choice, levelNames, 6)
---
--- DEVIATION from ImGui: value is a 1-based index into items, same as
--- Combo(). heightInItems defaults to 7 (ImGui's default too), i.e. the
--- box is tall enough to show that many rows before it starts scrolling.
--- Equivalent of ImGui::ListBox().
function imlove.ListBox(label, value, items, heightInItems)
  local win = requireWindow("ListBox")
  if win.skipItems then return value, false end
  local display, idText = splitLabel(label)
  local rowH = frameHeight()
  local boxH = rowH * (heightInItems or 7) + style.windowPadding * 2

  -- Same "changed = true on any pick, even the already-selected row" rule
  -- as Combo() — see its comment.
  local picked = false
  imlove.BeginChild("##listbox_" .. idText, style.sliderWidth, boxH, true)
  for i, item in ipairs(items or {}) do
    imlove.PushID(i)
    if imlove.Selectable(tostring(item), i == value) then
      value = i
      picked = true
    end
    imlove.PopID()
  end
  imlove.EndChild()

  if #display > 0 then
    imlove.SameLine()
    imlove.Text("%s", display)
  end
  return value, picked
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

--- Was the most recent item hovered by the mouse this frame? Works for any
--- item, including non-interactive ones like Text() (computed from its
--- rectangle rather than a stored hot-state). Equivalent of
--- ImGui::IsItemHovered().
function imlove.IsItemHovered()
  local win = requireWindow("IsItemHovered")
  return win.prevItem.hovered == true
end

--- Is the most recent item currently held down by the mouse? Always false
--- for non-interactive items. Equivalent of ImGui::IsItemActive().
function imlove.IsItemActive()
  local win = requireWindow("IsItemActive")
  return win.prevItem.active == true
end

--- Was the most recent item clicked this frame — its own notion of a
--- completed click, e.g. Button()'s release-over-it or TreeNode()'s toggle.
--- Always false for non-interactive items. Equivalent of
--- ImGui::IsItemClicked().
function imlove.IsItemClicked()
  local win = requireWindow("IsItemClicked")
  return win.prevItem.clicked == true
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
  -- Any open popup (including a modal) captures every press/hover on the
  -- screen, whether or not it lands inside the popup itself: an outside
  -- press dismisses/is blocked rather than reaching the game (see
  -- NewFrame()'s dismiss-scan and popupAt()'s `blocked` return).
  if #ctx.popupOrder > 0 then return true end
  return windowAt(x, y) ~= nil
    or ctx.activeId ~= nil or ctx.dragWindow ~= nil
end

--- Forward from love.mousepressed. Returns true if the UI consumed the press.
function imlove.mousepressed(x, y, button)
  local captured = mouseOverUI(x, y)
  if button == 1 then
    ctx.pressLatch = true
    ctx.mouse.down = true
  elseif button == 2 then
    ctx.rightPressLatch = true
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

--- Forward from love.wheelmoved. Latches dy to be applied to whatever
--- window (or BeginChild() region) is under the mouse at the next
--- NewFrame() — same latch-then-apply pattern as mouse press/release, so a
--- wheelmoved() that arrives between frames is never dropped. Still reports
--- consumed whenever the mouse is over any window, exactly as in v1, so the
--- game doesn't zoom/scroll underneath the UI even for windows or
--- "NoScrollbar" windows that have nothing to scroll.
function imlove.wheelmoved(dx, dy)
  ctx.wheelLatch = ctx.wheelLatch + dy
  return #ctx.popupOrder > 0 or windowAt(ctx.mouse.x, ctx.mouse.y) ~= nil
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
