--[[
Window snapping (v1.6): SetNextWindowSnap()/GetWindowSnap(), the drag-to-
edge gesture, the drag-away unsnap, chrome suppression while snapped, and
the ini Snap= line.

Known stub geometry (see stub_love.lua and the style table):
  screen 800x600                     font: 7px/char wide, 14px tall
  framePadding = {6, 3}              titleH = 14 + 3*2 = 20
  windowPadding = 8                  snapZone = 12
  minWindowWidth = 60                gripSize = 14
]]

return function(T, H)

  T("SetNextWindowSnap('left') pins the window: (0,0), full height, "
    .. "width kept", function()
    local im = H.fresh()
    local pos, size = {}, {}
    local function ui()
      im.SetNextWindowSize(300, 200, "once")
      im.SetNextWindowSnap("left")
      im.Begin("S")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    assert(pos.x == 0 and pos.y == 0,
      ("expected (0,0), got (%d,%d)"):format(pos.x, pos.y))
    assert(size.w == 300, "width must stay the window's own")
    assert(size.h == 600, "height must be the full screen height")
  end)

  T("snap 'right' pins to x = screenW - w", function()
    local im = H.fresh()
    local pos, size = {}, {}
    local function ui()
      im.SetNextWindowSize(300, 200, "once")
      im.SetNextWindowSnap("right")
      im.Begin("S")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    assert(pos.x == 500 and pos.y == 0,
      ("expected (500,0), got (%d,%d)"):format(pos.x, pos.y))
    assert(size.w == 300 and size.h == 600)
  end)

  T("a never-sized window snaps too: auto-fit width settles in one frame, "
    .. "then pins", function()
    local im = H.fresh()
    local pos, size = {}, {}
    local function ui()
      im.SetNextWindowSnap("left", "once")
      im.Begin("S")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      im.Text("some content wide enough to matter")
      im.End()
    end
    H.frame(ui) -- the one-frame auto-fit settle
    H.frame(ui)
    assert(size.w > 0, "width must have been auto-fitted")
    assert(size.h == 600 and pos.x == 0 and pos.y == 0)
  end)

  T("a snapped window has no collapse arrow and no resize grip", function()
    local im = H.fresh()
    local vis, size = {}, {}
    local function ui()
      im.SetNextWindowSize(300, 200, "once")
      im.SetNextWindowSnap("left")
      vis.notCollapsed = im.Begin("S")
      size.w, size.h = im.GetWindowSize()
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    -- Click where the collapse arrow would be (the first titleH square of
    -- the title bar): must NOT collapse. (The press starts a title drag
    -- instead; releasing in place, inside the left zone, is a no-op.)
    H.click(10, 10, ui)
    assert(vis.notCollapsed == true, "snapped window must not collapse")
    assert(size.h == 600)

    -- Drag where the resize grip would be (bottom-right corner): must NOT
    -- resize.
    H.stub.setMouse(293, 593)
    im.mousepressed(293, 593, 1)
    H.frame(ui)
    H.stub.setMouse(333, 618)
    H.frame(ui)
    im.mousereleased(333, 618, 1)
    H.frame(ui)
    assert(size.w == 300 and size.h == 600,
      ("snapped window must not resize, got %dx%d"):format(size.w, size.h))

    -- And neither glyph is even drawn: the arrow (inert would read as a
    -- broken button) and the grip are the only triangles this window could
    -- produce, and the title slides left into the arrow's place (x =
    -- framePadding, not x + titleH + 2).
    H.stub.setMouse(400, 400) -- park the mouse off the window
    H.stub.clearCalls()
    H.frame(ui)
    local polygons, titleAtLeft = 0, false
    for _, c in ipairs(H.stub.calls) do
      if c[1] == "polygon" then polygons = polygons + 1 end
      if c[1] == "print" and c[2] == "S" and c[3] == 6 then
        titleAtLeft = true
      end
    end
    assert(polygons == 0, "no arrow and no grip may draw while snapped, "
      .. "got " .. polygons .. " polygon(s)")
    assert(titleAtLeft, "the title must start at framePadding while snapped")
  end)

  T("clicking or slightly wiggling a snapped window's title bar does not "
    .. "unsnap it — only a real pull past snapZone does", function()
    local im = H.fresh()
    local pos, size, snap = {}, {}, {}
    local function ui()
      im.SetNextWindowSize(250, 180, "once")
      im.SetNextWindowSnap("left", "once")
      im.Begin("S")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      snap.side = im.GetWindowSnap()
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    -- Grab the middle of the title bar (x=100: well outside the 12px edge
    -- zone) and just HOLD — the pre-fix bug unsnapped right here, purely
    -- because the grab point wasn't inside the zone.
    H.stub.setMouse(100, 10)
    im.mousepressed(100, 10, 1)
    H.frame(ui)
    H.frame(ui)
    assert(snap.side == "left" and size.h == 600 and pos.x == 0,
      "holding without moving must not unsnap")

    -- A sloppy-click wiggle (~7px, under the 12px threshold): still snapped.
    H.stub.setMouse(106, 14)
    H.frame(ui)
    assert(snap.side == "left" and size.h == 600,
      "a wiggle below snapZone must not unsnap")
    im.mousereleased(106, 14, 1)
    H.frame(ui)
    assert(snap.side == "left" and size.h == 600 and pos.x == 0,
      "releasing after a sloppy click must leave the window snapped")

    -- A real pull (30px straight down, outside the zone): unsnaps.
    H.stub.setMouse(100, 10)
    im.mousepressed(100, 10, 1)
    H.frame(ui)
    H.stub.setMouse(100, 40)
    H.frame(ui)
    assert(snap.side == nil and size.h == 180,
      "pulling past snapZone must unsnap and restore the height")
    im.mousereleased(100, 40, 1)
    H.frame(ui)
  end)

  T("a collapsed window dragged onto an edge snaps OPEN: full height, "
    .. "width re-measured from its un-collapsed content", function()
    local im = H.fresh()
    local vis, pos, size, snap = {}, {}, {}, {}
    local function ui()
      vis.notCollapsed = im.Begin("C")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      snap.side = im.GetWindowSnap()
      im.Text("wide content line here")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    -- Collapse it (arrow at the title bar's left square; cascade puts the
    -- window at (40,40)), and let the auto-fit width shrink to title-only.
    H.click(pos.x + 10, pos.y + 10, ui)
    H.frame(ui)
    assert(vis.notCollapsed == false, "precondition: collapsed")
    local collapsedW = size.w

    -- Drag the collapsed title bar to the left edge and release.
    H.stub.setMouse(pos.x + 45, pos.y + 10)
    im.mousepressed(pos.x + 45, pos.y + 10, 1)
    H.frame(ui)
    H.stub.setMouse(5, 50)
    H.frame(ui)
    im.mousereleased(5, 50, 1)
    H.frame(ui)
    H.frame(ui) -- the one-frame auto-fit settle re-measures the width

    assert(snap.side == "left" and vis.notCollapsed == true,
      "snapping must un-collapse the window")
    assert(pos.x == 0 and pos.y == 0 and size.h == 600,
      ("expected a full-height panel, got (%d,%d) h=%d"):format(
        pos.x, pos.y, size.h))
    assert(size.w > collapsedW,
      ("width must re-fit the un-collapsed content, got %d (collapsed %d)")
        :format(size.w, collapsedW))
  end)

  T("dragging a title bar into an edge zone snaps on release — not while "
    .. "merely passing through", function()
    local im = H.fresh()
    local pos, size, snap = {}, {}, {}
    local function ui()
      im.SetNextWindowPos(300, 200, "once")
      im.SetNextWindowSize(200, 150, "once")
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      snap.side = im.GetWindowSnap()
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    -- Grab the title bar at (400,210) — clear of the collapse arrow.
    H.stub.setMouse(400, 210)
    im.mousepressed(400, 210, 1)
    H.frame(ui)

    -- Mid-drag with the mouse inside the left zone: still just a drag.
    H.stub.setMouse(5, 100)
    H.frame(ui)
    assert(snap.side == nil, "must not snap before release")
    assert(size.h == 150 and pos.x == -95,
      "mid-drag the window follows the mouse unpinned")

    im.mousereleased(5, 100, 1)
    H.frame(ui)
    assert(snap.side == "left", "release inside the zone must snap")
    assert(pos.x == 0 and pos.y == 0)
    assert(size.w == 200 and size.h == 600)
  end)

  T("dragging a snapped window: pinned while the mouse stays in the zone, "
    .. "free (height restored) once it leaves, and 'once' never re-snaps",
    function()
    local im = H.fresh()
    local pos, size, snap = {}, {}, {}
    local function ui()
      im.SetNextWindowSize(250, 180, "once")
      im.SetNextWindowSnap("left", "once")
      im.Begin("S2")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      snap.side = im.GetWindowSnap()
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    assert(snap.side == "left" and size.h == 600)

    -- Grab the title bar and wiggle WITHIN the zone: the pin holds.
    H.stub.setMouse(100, 10)
    im.mousepressed(100, 10, 1)
    H.frame(ui)
    H.stub.setMouse(8, 300)
    H.frame(ui)
    assert(snap.side == "left" and pos.x == 0 and pos.y == 0,
      "inside the zone the pin must hold")

    -- Pull the mouse out of the zone: unsnaps immediately, height comes
    -- back, and the window follows the drag (offset was 100 into the bar).
    H.stub.setMouse(400, 300)
    H.frame(ui)
    assert(snap.side == nil, "leaving the zone must unsnap")
    assert(size.w == 250 and size.h == 180, "pre-snap height must restore")
    assert(pos.x == 300 and pos.y == 290, "window follows the drag")

    im.mousereleased(400, 300, 1)
    H.frame(ui)
    H.frame(ui)
    assert(snap.side == nil and size.h == 180,
      "a 'once' snap must not re-assert after a drag-away")
  end)

  T("a snapped-left window dragged to the right edge switches sides in one "
    .. "gesture", function()
    local im = H.fresh()
    local pos, size, snap = {}, {}, {}
    local function ui()
      im.SetNextWindowSize(300, 180, "once")
      im.SetNextWindowSnap("left", "once")
      im.Begin("S")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      snap.side = im.GetWindowSnap()
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    H.stub.setMouse(150, 10)
    im.mousepressed(150, 10, 1)
    H.frame(ui)
    H.stub.setMouse(795, 100)
    H.frame(ui)
    im.mousereleased(795, 100, 1)
    H.frame(ui)
    assert(snap.side == "right")
    assert(pos.x == 500 and pos.y == 0, "800 - 300 = 500")
    assert(size.w == 300 and size.h == 600)
  end)

  T("SetNextWindowSnap(nil) releases a snap programmatically", function()
    local im = H.fresh()
    local size, snap = {}, {}
    local side = "left"
    local function ui()
      im.SetNextWindowSize(240, 170, "once")
      im.SetNextWindowSnap(side)
      im.Begin("S")
      size.w, size.h = im.GetWindowSize()
      snap.side = im.GetWindowSnap()
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    assert(snap.side == "left" and size.h == 600)

    side = nil
    H.frame(ui)
    assert(snap.side == nil, "nil side must unsnap")
    assert(size.w == 240 and size.h == 170, "pre-snap height must restore")
  end)

  T("'AlwaysAutoResize' ignores snapping, exactly like SetNextWindowSize",
    function()
    local im = H.fresh()
    local size, snap = {}, {}
    local function ui()
      im.SetNextWindowSnap("left")
      im.Begin("A", nil, "AlwaysAutoResize")
      size.w, size.h = im.GetWindowSize()
      snap.side = im.GetWindowSnap()
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    assert(snap.side == nil, "AlwaysAutoResize must never snap")
    assert(size.h > 0 and size.h ~= 600, "must still auto-fit its content")
  end)

  T("an invalid side is an error, not a silent no-op", function()
    local im = H.fresh()
    assert(not pcall(im.SetNextWindowSnap, "top"))
    assert(not pcall(im.SetNextWindowSnap, true))
  end)

  T("a translucent full-height preview band draws while (and only while) a "
    .. "title drag holds the mouse inside an edge zone", function()
    local im = H.fresh()
    local function ui()
      im.SetNextWindowPos(300, 200, "once")
      im.SetNextWindowSize(200, 150, "once")
      im.Begin("W")
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    -- The preview is the only full-screen-height fill this test's window
    -- (unsnapped, 150 tall) can ever produce.
    local function previewRects()
      local found = {}
      for _, c in ipairs(H.stub.calls) do
        if c[1] == "rectangle" and c[2] == "fill" and c[6] == 600 then
          found[#found + 1] = c
        end
      end
      return found
    end

    -- No drag: no preview.
    H.stub.clearCalls()
    H.frame(ui)
    assert(#previewRects() == 0, "no preview without a drag")

    -- Dragging, but the mouse is nowhere near an edge: still none.
    H.stub.setMouse(400, 210)
    im.mousepressed(400, 210, 1)
    H.stub.clearCalls()
    H.frame(ui)
    assert(#previewRects() == 0, "no preview outside the zones")

    -- Mouse into the left zone: exactly one band, the window's own width,
    -- at the edge it would pin to.
    H.stub.setMouse(5, 100)
    H.stub.clearCalls()
    H.frame(ui)
    local rects = previewRects()
    assert(#rects == 1, "expected exactly one preview band, got " .. #rects)
    assert(rects[1][3] == 0 and rects[1][4] == 0
      and rects[1][5] == 200 and rects[1][6] == 600,
      ("band at (%d,%d) %dx%d"):format(rects[1][3], rects[1][4],
        rects[1][5], rects[1][6]))

    -- Same drag, across to the right zone: the band moves to x = 800-200.
    H.stub.setMouse(795, 100)
    H.stub.clearCalls()
    H.frame(ui)
    rects = previewRects()
    assert(#rects == 1 and rects[1][3] == 600,
      "the band must preview the right edge at x = screenW - w")

    -- Back out of any zone and release there: no band, nothing snapped.
    H.stub.setMouse(400, 300)
    H.stub.clearCalls()
    H.frame(ui)
    assert(#previewRects() == 0, "leaving the zone removes the band")
    im.mousereleased(400, 300, 1)
    H.frame(ui)
  end)

  T("round trip: snap state and the PRE-snap size survive a save, a module "
    .. "reload, and a load", function()
    local im = H.fresh()
    local function ui()
      im.SetNextWindowSize(280, 190, "once")
      im.SetNextWindowSnap("left", "once")
      im.Begin("S")
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    local savedIni = H.stub.files["imlove.ini"]
    assert(type(savedIni) == "string" and savedIni:find("Snap=left", 1, true),
      "expected a Snap=left line")
    -- The Size= line must carry the pre-snap height (190), never the
    -- pinned screen height (600).
    assert(savedIni:find("Size=280,190", 1, true),
      "expected the pre-snap size, got:\n" .. tostring(savedIni))

    -- Reload the module WITHOUT wiping the fake disk (same pattern as
    -- test_settings.lua's round trip): a fresh imlove finds the same
    -- imlove.ini, with no SetNextWindow*() calls at all this time.
    package.loaded["imlove"] = nil
    local im2 = require "imlove"
    local pos2, size2, snap2 = {}, {}, {}
    local function ui2()
      im2.Begin("S")
      pos2.x, pos2.y = im2.GetWindowPos()
      size2.w, size2.h = im2.GetWindowSize()
      snap2.side = im2.GetWindowSnap()
      im2.Text("content")
      im2.End()
    end
    for _ = 1, 2 do
      im2.NewFrame() -- the lazy ini load happens on the first of these
      ui2()
      im2.Render()
    end
    assert(snap2.side == "left", "snap must survive the reload")
    assert(pos2.x == 0 and pos2.y == 0)
    assert(size2.w == 280 and size2.h == 600)

    -- Drag it free: the restored height must be the ini's pre-snap 190.
    H.stub.setMouse(140, 10)
    im2.mousepressed(140, 10, 1)
    im2.NewFrame(); ui2(); im2.Render()
    H.stub.setMouse(400, 200)
    im2.NewFrame(); ui2(); im2.Render()
    im2.mousereleased(400, 200, 1)
    im2.NewFrame(); ui2(); im2.Render()
    assert(snap2.side == nil)
    assert(size2.w == 280 and size2.h == 190,
      ("expected 280x190 after unsnap, got %dx%d"):format(size2.w, size2.h))
  end)

end
