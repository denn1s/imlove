--[[
v1.2 window features: the clip/scissor stack, window scrolling, explicit
sizing (SetNextWindowSize + the resize grip), the close button/open param,
window flags, and BeginChild/EndChild.

Known stub geometry used throughout (see stub_love.lua and the style table):
  font: 7px/char wide, 14px tall     windowPadding = 8
  framePadding = {6, 3}              titleH = 14 + 3*2 = 20
  minWindowWidth = 60                scrollbarWidth = 10, gripSize = 14
]]

return function(T, H)

  --------------------------------------------------------------------------
  -- Flags: validation, and each flag's effect
  --------------------------------------------------------------------------

  T("an unknown flag string errors with a helpful message", function()
    local im = H.fresh()
    im.NewFrame()
    local ok, err = pcall(im.Begin, "W", nil, "Bogus")
    assert(not ok and err:find("unknown flag") and err:find("Bogus"),
      tostring(err))
  end)

  T("flags accept a bare string or an array of strings", function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("A", nil, "NoMove")
    im.End()
    im.Begin("B", nil, { "NoMove", "NoResize" })
    im.End()
    im.Render() -- no error means both forms were accepted
  end)

  T("NoTitleBar removes the title bar: content starts at the window's top",
    function()
    local im = H.fresh()
    local r = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("NT", nil, "NoTitleBar")
      im.Text("first")
      H.grabRect(r, im)
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    assert(r.y1 == 10 + 8, "expected content at win.y+pad, got " .. r.y1)
  end)

  T("NoMove: the title bar no longer drags the window", function()
    local im = H.fresh()
    local pos, size = {}, {}
    local function ui()
      im.SetNextWindowPos(50, 50, "once")
      im.Begin("NM", nil, "NoMove")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      im.Text("hi")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local gx, gy = pos.x + size.w / 2, pos.y + 10
    H.stub.setMouse(gx, gy)
    im.mousepressed(gx, gy, 1)
    H.frame(ui)
    H.stub.setMouse(gx + 40, gy + 30)
    H.frame(ui)
    assert(pos.x == 50 and pos.y == 50, "NoMove must not budge the window")
    im.mousereleased(gx + 40, gy + 30, 1)
    H.frame(ui)
  end)

  T("NoResize: dragging the corner grip does nothing", function()
    local im = H.fresh()
    local size = {}
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.SetNextWindowSize(150, 100, "always")
      im.Begin("NR", nil, "NoResize")
      size.w, size.h = im.GetWindowSize()
      im.Text("hi")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local gs = 14
    local gx, gy = 50 + size.w - gs / 2, 50 + size.h - gs / 2
    H.stub.setMouse(gx, gy)
    im.mousepressed(gx, gy, 1)
    H.frame(ui)
    H.stub.setMouse(gx + 60, gy + 60)
    H.frame(ui)
    assert(size.w == 150 and size.h == 100, "NoResize must not resize")
    im.mousereleased(gx + 60, gy + 60, 1)
    H.frame(ui)
  end)

  T("NoCollapse: clicking where the arrow would be does not collapse",
    function()
    local im = H.fresh()
    local open, pos = nil, {}
    local function ui()
      open = im.Begin("NC", nil, "NoCollapse")
      pos.x, pos.y = im.GetWindowPos()
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    H.click(pos.x + 10, pos.y + 10, ui)
    assert(open == true, "NoCollapse window must stay open")
  end)

  T("AlwaysAutoResize always fits content and ignores SetNextWindowSize",
    function()
    local im = H.fresh()
    local size = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.SetNextWindowSize(300, 300, "always")
      im.Begin("AA", nil, "AlwaysAutoResize")
      im.Text("just one line")
      size.w, size.h = im.GetWindowSize()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    assert(size.w < 200 and size.h < 200,
      "AlwaysAutoResize must ignore the explicit 300x300 size")
  end)

  T("NoScrollbar: the wheel still scrolls even though the bar is hidden",
    function()
    local im = H.fresh()
    local r = {}
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.SetNextWindowSize(150, 100, "always")
      im.Begin("NS", nil, "NoScrollbar")
      for i = 1, 20 do
        im.Text("line " .. i)
        if i == 1 then H.grabRect(r, im) end
      end
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local y0 = r.y1
    H.stub.setMouse(100, 90)
    H.frame(ui)
    H.wheel(0, -1, ui)
    assert(r.y1 ~= y0, "content must still scroll under NoScrollbar")
  end)

  --------------------------------------------------------------------------
  -- Sizing model: auto-fit until explicitly sized, then sticky
  --------------------------------------------------------------------------

  T("a fresh window auto-fits to its content", function()
    local im = H.fresh()
    local size = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Auto")
      im.Text("hello")
      size.w, size.h = im.GetWindowSize()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    -- height = titleBarH(20) + windowPadding*2(16) + one text line(14)
    assert(size.w > 0 and size.h == 20 + 16 + 14, "expected one-line auto height")
  end)

  T("SetNextWindowSize takes a window out of auto-fit permanently", function()
    local im = H.fresh()
    local size = {}
    local callSetSize = true
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      if callSetSize then im.SetNextWindowSize(200, 150, "always") end
      im.Begin("Sticky")
      im.Text("x") -- tiny content
      size.w, size.h = im.GetWindowSize()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    assert(size.w == 200 and size.h == 150, "explicit size should apply")
    -- Now stop calling SetNextWindowSize; a v1.1-style window would shrink
    -- back to fit "x", but a sized window must stay put.
    callSetSize = false
    for _ = 1, 3 do H.frame(ui) end
    assert(size.w == 200 and size.h == 150,
      "size must stay sticky once explicitly set, even tiny content")
  end)

  T("dragging the resize grip also switches a window into sticky sizing",
    function()
    local im = H.fresh()
    local size = {}
    local manyLines = true
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.Begin("Grip")
      if manyLines then
        for i = 1, 10 do im.Text("line " .. i) end
      else
        im.Text("x")
      end
      size.w, size.h = im.GetWindowSize()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local autoW, autoH = size.w, size.h
    local gs = 14
    local gx, gy = 50 + autoW - gs / 2, 50 + autoH - gs / 2
    H.stub.setMouse(gx, gy)
    im.mousepressed(gx, gy, 1)
    H.frame(ui)
    H.stub.setMouse(gx + 80, gy + 60)
    H.frame(ui)
    im.mousereleased(gx + 80, gy + 60, 1)
    H.frame(ui)
    local draggedW, draggedH = size.w, size.h
    assert(draggedW > autoW and draggedH > autoH, "grip drag should grow it")
    manyLines = false -- drastically shrink the content
    for _ = 1, 3 do H.frame(ui) end
    assert(size.w == draggedW and size.h == draggedH,
      "once resized by the grip, the window must not shrink back to fit")
  end)

  --------------------------------------------------------------------------
  -- Scroll clamping and wheel-latch application
  --------------------------------------------------------------------------

  T("wheel scrolling moves content and clamps to [0, contentH-visibleH]",
    function()
    local im = H.fresh()
    local pos, size, r1 = {}, {}, {}
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.SetNextWindowSize(150, 100, "always")
      im.Begin("Scroll")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      for i = 1, 20 do
        im.Text("line " .. i)
        if i == 1 then H.grabRect(r1, im) end
      end
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local y0 = r1.y1
    H.stub.setMouse(pos.x + size.w / 2, pos.y + size.h / 2)
    H.frame(ui)

    H.wheel(0, -1, ui) -- one notch down
    local afterOneNotch = r1.y1
    assert(afterOneNotch < y0, "scrolling down should move content up")

    for _ = 1, 30 do H.wheel(0, -1, ui) end -- way past the bottom
    local clampedBottom = r1.y1

    for _ = 1, 30 do H.wheel(0, 1, ui) end -- way past the top
    assert(r1.y1 == y0, "scrolling back up must clamp to the original top")

    -- Clamping must be stable: scrolling down again lands on the exact same
    -- bottom, proving contentH isn't shrinking as a side effect of scrollY
    -- (a self-defeating feedback loop this test guards against).
    for _ = 1, 30 do H.wheel(0, -1, ui) end
    assert(r1.y1 == clampedBottom, "bottom clamp must be stable across scrolls")
  end)

  T("AlwaysAutoResize windows never scroll: the wheel is a no-op", function()
    local im = H.fresh()
    local r = {}
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.Begin("NoScroll", nil, "AlwaysAutoResize")
      for i = 1, 20 do
        im.Text("line " .. i)
        if i == 1 then H.grabRect(r, im) end
      end
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local y0 = r.y1
    H.stub.setMouse(100, 90)
    H.frame(ui)
    H.wheel(0, -5, ui)
    assert(r.y1 == y0, "AlwaysAutoResize must never overflow/scroll")
  end)

  --------------------------------------------------------------------------
  -- Scrollbar grab: proportional size, direct click-to-position mapping
  --------------------------------------------------------------------------

  T("the scrollbar grab maps a click on its track directly to a scroll position",
    function()
    local im = H.fresh()
    local r1 = {}
    -- NoResize keeps the grip out of the way so the whole track is free to
    -- click, including its very bottom pixel.
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.SetNextWindowSize(150, 100, "always")
      im.Begin("SB", nil, "NoResize")
      for i = 1, 20 do
        im.Text("line " .. i)
        if i == 1 then H.grabRect(r1, im) end
      end
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local y0 = r1.y1
    local sbW, trackX, trackY, trackH = 10, 50 + 150 - 10, 50 + 20, 80

    H.stub.setMouse(trackX + sbW / 2, trackY + 2) -- near the top
    im.mousepressed(trackX + sbW / 2, trackY + 2, 1)
    H.frame(ui)
    H.frame(ui) -- one-frame lag: layout picks up the new scroll next frame
    local nearTop = r1.y1
    im.mousereleased(trackX + sbW / 2, trackY + 2, 1)
    H.frame(ui)
    assert(nearTop < y0 and nearTop > y0 - 20,
      "a click near the track's top should scroll only a little")

    H.stub.setMouse(trackX + sbW / 2, trackY + trackH - 2) -- near the bottom
    im.mousepressed(trackX + sbW / 2, trackY + trackH - 2, 1)
    H.frame(ui)
    H.frame(ui)
    local nearBottom = r1.y1
    im.mousereleased(trackX + sbW / 2, trackY + trackH - 2, 1)
    H.frame(ui)
    assert(nearBottom < nearTop - 100,
      "a click near the track's bottom should scroll close to the max")
  end)

  --------------------------------------------------------------------------
  -- Clip/scissor stack (Render)
  --------------------------------------------------------------------------

  T("Render scissors a fixed-size window's content region", function()
    local im = H.fresh()
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.SetNextWindowSize(150, 100, "always")
      im.Begin("Clip")
      im.Text("hi")
      im.End()
    end
    H.frame(ui)
    H.stub.clearCalls()
    H.frame(ui)
    local calls = H.stub.scissorCalls()
    local found = false
    for _, c in ipairs(calls) do
      if c[1] == 50 and c[2] == 70 and c[3] == 150 and c[4] == 80 then
        found = true
      end
    end
    assert(found, "expected a setScissor(50, 70, 150, 80) for the content region")
  end)

  T("Render saves and restores any pre-existing scissor around the frame",
    function()
    local im = H.fresh()
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.SetNextWindowSize(150, 100, "always")
      im.Begin("Clip2")
      im.Text("hi")
      im.End()
    end
    im.NewFrame()
    ui()
    H.stub.scissor = { x = 1, y = 2, w = 3, h = 4 }
    H.stub.clearCalls()
    im.Render()
    assert(H.stub.scissor.x == 1 and H.stub.scissor.y == 2,
      "the pre-existing scissor must be restored after Render()")
  end)

  T("nested BeginChild clip intersects with its window's own clip rect",
    function()
    local im = H.fresh()
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.SetNextWindowSize(150, 100, "always")
      im.Begin("Outer")
      im.BeginChild("wide", 300, 40) -- wider than the window itself
      im.Text("hi")
      im.EndChild()
      im.End()
    end
    H.frame(ui)
    H.stub.clearCalls()
    H.frame(ui)
    local calls = H.stub.scissorCalls()
    for _, c in ipairs(calls) do
      if c[1] then
        assert(c[1] >= 50 and c[1] + c[3] <= 200,
          "no scissor rect may extend past the window's own content region")
      end
    end
  end)

  --------------------------------------------------------------------------
  -- Close button / open param return-value matrix
  --------------------------------------------------------------------------

  T("open == nil: no close button, second return is nil", function()
    local im = H.fresh()
    local visible, openOut
    local function ui()
      visible, openOut = im.Begin("W")
      im.End()
    end
    H.frame(ui)
    assert(visible == true and openOut == nil)
  end)

  T("open == true: second return is true, and clicking the close button "
    .. "flips it to false", function()
    local im = H.fresh()
    local pos, size = {}, {}
    local openState, openOut
    local function ui()
      local visible
      visible, openOut = im.Begin("W", openState == nil and true or openState)
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    assert(openOut == true, "open==true must report back true until closed")
    local titleH = 20
    local cx, cy = pos.x + size.w - titleH / 2, pos.y + titleH / 2
    H.click(cx, cy, ui)
    assert(openOut == false, "clicking the close button must flip open to false")
  end)

  T("open == false at call time: not submitted at all", function()
    local im = H.fresh()
    local visible, openOut, clicked
    local function ui()
      visible, openOut = im.Begin("W", false)
      if im.Button("hit") then clicked = true end
      im.End()
    end
    H.frame(ui)
    assert(visible == false and openOut == false)
    H.click(45, 45, ui) -- wherever it would have cascaded to
    assert(not clicked, "widget calls inside a not-submitted window are no-ops")
  end)

  --------------------------------------------------------------------------
  -- BeginChild / EndChild
  --------------------------------------------------------------------------

  T("BeginChild lays out content in its own region and returns true",
    function()
    local im = H.fresh()
    local visible, r = nil, {}
    local function ui()
      im.Begin("P")
      visible = im.BeginChild("c", 120, 60, true)
      im.Text("inside")
      H.grabRect(r, im)
      im.EndChild()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    assert(visible == true)
  end)

  T("BeginChild defaults: w<=0 uses available width, h<=0 is 200px",
    function()
    local im = H.fresh()
    local w, h
    local function ui()
      im.Begin("P")
      im.BeginChild("c")
      w, h = im.GetWindowSize()
      im.Text("x")
      im.EndChild()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    assert(h == 200, "default child height must be 200")
    assert(w > 0, "default child width must be a positive available width")
  end)

  T("BeginChild scrolls independently and its scroll state persists",
    function()
    local im = H.fresh()
    local r = {}
    local function ui()
      im.Begin("P")
      im.BeginChild("log", 150, 80, true)
      for i = 1, 20 do
        im.Text("line " .. i)
        if i == 1 then H.grabRect(r, im) end
      end
      im.EndChild()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local y0 = r.y1
    local x1, y1, x2, y2 = r.x1, y0, r.x1 + 100, y0 + 60
    H.stub.setMouse((x1 + x2) / 2, (y1 + y2) / 2)
    H.frame(ui)
    H.wheel(0, -1, ui)
    assert(r.y1 ~= y0, "wheel over the child must scroll it")
    for _ = 1, 5 do H.frame(ui) end
    assert(r.y1 ~= y0, "child scroll position must persist across frames")
  end)

  T("nested BeginChild: the innermost hovered child consumes the wheel",
    function()
    local im = H.fresh()
    local outerItem, innerItem = {}, {}
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.SetNextWindowSize(300, 300, "always")
      im.Begin("Outer")
      im.BeginChild("outerchild", 280, 200, true)
      im.Text("outer top")
      H.grabRect(outerItem, im)
      im.BeginChild("innerchild", 200, 80, true)
      im.Text("inner top")
      H.grabRect(innerItem, im)
      for i = 1, 20 do im.Text("inner " .. i) end
      im.EndChild()
      for i = 1, 20 do im.Text("outer " .. i) end
      im.EndChild()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local outerY0, innerY0 = outerItem.y1, innerItem.y1
    H.stub.setMouse((innerItem.x1 + innerItem.x2) / 2,
      (innerItem.y1 + innerItem.y2) / 2)
    H.frame(ui)
    H.wheel(0, -1, ui)
    H.wheel(0, -1, ui)
    assert(outerItem.y1 == outerY0,
      "the outer child must not scroll when the inner one is hovered")
    assert(innerItem.y1 ~= innerY0, "the inner (innermost) child must scroll")
  end)

  T("BeginChild pushes idStr onto the ID stack: same label in two children "
    .. "doesn't collide", function()
    local im = H.fresh()
    local hitsA, hitsB = 0, 0
    local rectA, rectB = {}, {}
    local function ui()
      im.Begin("P")
      im.BeginChild("childA", 120, 60)
      if im.Button("Go") then hitsA = hitsA + 1 end
      H.grabRect(rectA, im)
      im.EndChild()
      im.BeginChild("childB", 120, 60)
      if im.Button("Go") then hitsB = hitsB + 1 end
      H.grabRect(rectB, im)
      im.EndChild()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local cxA, cyA = H.center(rectA)
    H.click(cxA, cyA, ui)
    assert(hitsA == 1 and hitsB == 0,
      "clicking childA's button must not also register on childB's")
  end)

  T("End() errors if a BeginChild is left open", function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("W")
    im.BeginChild("c", 100, 50)
    local ok, err = pcall(im.End)
    assert(not ok and err:find("missing imlove.EndChild"), tostring(err))
    im.EndChild()
    im.End()
  end)

  T("EndChild() errors without a matching BeginChild", function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("W")
    local ok, err = pcall(im.EndChild)
    assert(not ok and err:find("without a matching"), tostring(err))
    im.End()
  end)

  --------------------------------------------------------------------------
  -- Regressions: adversarial-review findings on the v1.2 diff
  --------------------------------------------------------------------------

  T("resize grip: flipping to NoResize while it's held releases the grip "
    .. "instead of freezing every widget", function()
    local im = H.fresh()
    local flags = nil
    local btnRect = {}
    local clicked = false
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.SetNextWindowSize(150, 100, "always")
      im.Begin("StuckGrip", nil, flags)
      if im.Button("Go") then clicked = true end
      H.grabRect(btnRect, im)
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    -- Grab the resize grip (the gripSize x gripSize corner).
    local gs = 14
    local gx, gy = 50 + 150 - gs / 2, 50 + 100 - gs / 2
    H.stub.setMouse(gx, gy)
    im.mousepressed(gx, gy, 1)
    H.frame(ui) -- the grip becomes ctx.activeId

    -- Flip to NoResize *while still held*, before any release event: the
    -- grip's behavior() stops being called this frame.
    flags = "NoResize"
    H.frame(ui)

    im.mousereleased(gx, gy, 1)
    H.frame(ui)

    -- No idle (no press/release/mouse-up) frame occurs in between, so the
    -- global safety net in NewFrame() can't have cleared activeId: only the
    -- explicit release-on-disable can. Click a plain button immediately.
    local bx, by = H.center(btnRect)
    H.click(bx, by, ui)
    assert(clicked, "the button must respond on the very next click; if "
      .. "activeId were left stuck on the grip, behavior()'s hover gate "
      .. "(activeId == nil or activeId == id) would keep every widget dead")
  end)

  T("BeginChild scroll state is keyed by the full ID-stack path, not just "
    .. "the child's own name", function()
    local im = H.fresh()
    local topRect, nestedRect = {}, {}
    local function ui()
      im.Begin("NestedSameName")
      im.BeginChild("Row", 200, 50, true)
      for i = 1, 20 do
        im.Text("top " .. i)
        if i == 1 then H.grabRect(topRect, im) end
      end
      im.EndChild()
      im.BeginChild("Wrapper", 200, 90, true)
      im.BeginChild("Row", 180, 50, true) -- same idStr, nested one level deeper
      for i = 1, 20 do
        im.Text("nested " .. i)
        if i == 1 then H.grabRect(nestedRect, im) end
      end
      im.EndChild()
      im.EndChild()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local topY0, nestedY0 = topRect.y1, nestedRect.y1

    -- Hover and scroll only the top-level "Row".
    H.stub.setMouse(H.center(topRect))
    H.frame(ui)
    H.wheel(0, -1, ui)

    assert(topRect.y1 ~= topY0, "the hovered top-level Row must scroll")
    assert(nestedRect.y1 == nestedY0, "the nested Row sharing the same "
      .. "idStr ('Row') at a different nesting depth must not share scroll "
      .. "state with the top-level Row")
  end)

  T("resizable window: the scrollbar track stops above the resize grip, so "
    .. "its bottom still scrolls instead of being swallowed by the grip",
    function()
    local im = H.fresh()
    local size, r1 = {}, {}
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.SetNextWindowSize(150, 100, "always") -- resizable: no NoResize flag
      im.Begin("SBGrip")
      size.w, size.h = im.GetWindowSize()
      for i = 1, 40 do
        im.Text("line " .. i)
        if i == 1 then H.grabRect(r1, im) end
      end
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    -- Find the true scroll bottom by exhausting the wheel, then rewind.
    H.stub.setMouse(100, 90)
    H.frame(ui)
    for _ = 1, 60 do H.wheel(0, -1, ui) end
    local wheelBottom = r1.y1
    for _ = 1, 60 do H.wheel(0, 1, ui) end

    -- With 40 lines the content is tall enough that the scrollbar grab is
    -- min-clamped to 20px whether the track is the full visibleH (80, the
    -- pre-fix bug) or shortened by gripSize (66, the fix) — so avail is a
    -- known, exact constant either way: 60 (unfixed) vs 46 (fixed). Click at
    -- trackY + 52: that only reaches full scroll (t clamps to 1) once the
    -- track is actually shortened — an unshortened track would map it to
    -- only ~87%, short of the true bottom.
    local sbW = 10
    local trackX, trackY = 50 + 150 - sbW, 50 + 20
    local clickX, clickY = trackX + sbW / 2, trackY + 52
    H.stub.setMouse(clickX, clickY)
    im.mousepressed(clickX, clickY, 1)
    H.frame(ui)
    H.frame(ui)
    im.mousereleased(clickX, clickY, 1)
    H.frame(ui)

    assert(r1.y1 == wheelBottom, "a click on the shortened track must map "
      .. "to the true scroll bottom, proving the track's length (and thus "
      .. "its click-to-scroll math) was actually shortened by gripSize")
    assert(size.w == 150 and size.h == 100,
      "the click must scroll the content, not resize the window")
  end)

  T("availWidth() reserves the scrollbar gutter for full-width widgets once "
    .. "a scrollbar is showing", function()
    local im = H.fresh()
    local selRect = {}
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.SetNextWindowSize(150, 100, "always")
      im.Begin("Gutter")
      for i = 1, 20 do im.Text("line " .. i) end
      im.Selectable("Pick")
      H.grabRect(selRect, im)
      im.End()
    end
    H.frame(ui) -- hasScrollbar not known yet (one-frame lag)
    H.frame(ui) -- now the scrollbar is showing; availWidth must reserve it

    local trackX = 50 + 150 - 10 -- style.scrollbarWidth
    local pad = 8 -- style.windowPadding
    assert(selRect.x2 <= trackX - pad + 0.001,
      "a full-width Selectable must stop short of the scrollbar track " ..
      "(plus the usual padding gap) once a scrollbar is showing, not " ..
      "overlap and steal clicks meant for it")
  end)

  T("EndChild: content scrolled to the bottom rests exactly one "
    .. "windowPadding from the edge, matching End()'s convention", function()
    local im = H.fresh()
    local lastRect, childRect = {}, {}
    local function ui()
      im.Begin("ChildPad")
      im.BeginChild("C", 200, 80, true)
      for i = 1, 10 do
        im.Text("row " .. i)
        if i == 10 then H.grabRect(lastRect, im) end
      end
      im.EndChild()
      H.grabRect(childRect, im) -- the child's own outer rect
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    H.stub.setMouse(H.center(childRect))
    H.frame(ui)
    for _ = 1, 40 do H.wheel(0, -1, ui) end -- scroll to the clamped bottom

    local pad = 8 -- style.windowPadding
    assert(lastRect.y2 == childRect.y2 - pad,
      "the last line's bottom must rest exactly windowPadding above the " ..
      "child's bottom edge, not 2*windowPadding (the pre-fix bug: EndChild " ..
      "subtracted an extra padded origin, so the top-padding contribution " ..
      "cancelled out and content under-scrolled by one windowPadding)")
  end)

  T("REGRESSION: a collapsed FIXED-SIZE window draws only its title bar — "
    .. "not its full-size background, border, and resize grip", function()
    local im = H.fresh()
    local pos = {}
    local function ui()
      im.SetNextWindowSize(300, 200, "once")
      im.Begin("F")
      pos.x, pos.y = im.GetWindowPos()
      im.Text("content")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    -- Collapse via the arrow, then inspect one frame's draw calls. (The
    -- pre-fix bug: auto-fit windows shrank win.h itself on collapse, but a
    -- fixed window's win.h must keep holding the size to restore — and the
    -- background/border/grip were drawn straight from it.)
    H.click(pos.x + 10, pos.y + 10, ui)
    H.stub.clearCalls()
    H.frame(ui)
    local polygons, deepRects = 0, 0
    for _, c in ipairs(H.stub.calls) do
      if c[1] == "polygon" then polygons = polygons + 1 end
      if (c[1] == "rectangle") and c[6] and c[6] > 20 then
        deepRects = deepRects + 1
      end
    end
    assert(deepRects == 0,
      "nothing taller than the 20px title bar may draw while collapsed, "
      .. "got " .. deepRects .. " rect(s)")
    assert(polygons == 1,
      "only the collapse arrow may draw while collapsed (no grip), got "
      .. polygons .. " polygon(s)")

    -- Un-collapse: the full 300x200 background comes back.
    H.click(pos.x + 10, pos.y + 10, ui)
    H.stub.clearCalls()
    H.frame(ui)
    local fullBg = false
    for _, c in ipairs(H.stub.calls) do
      if c[1] == "rectangle" and c[2] == "fill"
          and c[5] == 300 and c[6] == 200 then
        fullBg = true
      end
    end
    assert(fullBg, "un-collapsing must restore the full-size background")
  end)

end
