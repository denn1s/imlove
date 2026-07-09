-- Window behavior: state persistence across frames, title-bar dragging,
-- collapsing, and z-order (clicks go to the front-most window; clicking a
-- window raises it).

return function(T, H)

  T("window position persists across frames", function()
    local im = H.fresh()
    local pos = {}
    local function ui()
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      im.Text("hello")
      im.End()
    end
    H.frame(ui)
    local x0, y0 = pos.x, pos.y
    for _ = 1, 3 do H.frame(ui) end
    assert(pos.x == x0 and pos.y == y0)
  end)

  T("dragging the title bar moves the window and it stays moved", function()
    local im = H.fresh()
    local pos, size = {}, {}
    local function ui()
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      im.Text("some content here")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local x0, y0 = pos.x, pos.y
    -- Grab the middle of the title bar (clear of the collapse arrow, which
    -- occupies the first title-bar-height square).
    local gx, gy = x0 + size.w / 2, y0 + 10

    H.stub.setMouse(gx, gy)
    im.mousepressed(gx, gy, 1)
    H.frame(ui)
    H.stub.setMouse(gx + 55, gy + 30)
    H.frame(ui)
    assert(pos.x == x0 + 55 and pos.y == y0 + 30,
      ("window should follow the mouse, got (%d,%d)"):format(pos.x, pos.y))

    im.mousereleased(gx + 55, gy + 30, 1)
    H.frame(ui)
    H.stub.setMouse(0, 0)
    H.frame(ui)
    assert(pos.x == x0 + 55 and pos.y == y0 + 30,
      "the new position must persist after the drag ends")
  end)

  T("dragging the body does NOT move the window", function()
    local im = H.fresh()
    local pos, rect = {}, {}
    local function ui()
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      im.Text("just some text, not a widget")
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local x0 = pos.x
    local cx, cy = H.center(rect)
    H.stub.setMouse(cx, cy)
    im.mousepressed(cx, cy, 1)
    H.frame(ui)
    H.stub.setMouse(cx + 60, cy + 60)
    H.frame(ui)
    im.mousereleased(cx + 60, cy + 60, 1)
    H.frame(ui)
    assert(pos.x == x0, "grabbing window content must not drag the window")
  end)

  T("collapse hides content, shrinks to the title bar, and restores", function()
    local im = H.fresh()
    local state, pos, size = {}, {}, {}
    local function ui()
      state.open = im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      if state.open then
        im.Text("secret content")
      end
      im.End()
    end
    H.frame(ui)
    H.frame(ui) -- GetWindowSize reports last frame's size, so warm up twice
    assert(state.open == true)
    local fullH = size.h
    assert(fullH > 20, "test setup: expected a real content height")

    H.click(pos.x + 10, pos.y + 10, ui) -- the collapse arrow
    H.frame(ui)
    assert(state.open == false, "Begin returns false while collapsed")
    assert(size.h < fullH, "collapsed window must shrink to its title bar")
    H.stub.clearCalls()
    H.frame(ui)
    for _, text in ipairs(H.stub.printed()) do
      assert(text ~= "secret content", "collapsed content must not be drawn")
    end

    H.click(pos.x + 10, pos.y + 10, ui) -- expand again
    H.frame(ui)
    assert(state.open == true, "clicking the arrow again restores the window")
    assert(size.h == fullH)
  end)

  T("collapsed state persists across frames and is per-window", function()
    local im = H.fresh()
    local state, posA = {}, {}
    local function ui()
      state.a = im.Begin("A")
      posA.x, posA.y = im.GetWindowPos()
      im.End()
      im.SetNextWindowPos(400, 300, "always")
      state.b = im.Begin("B")
      im.End()
    end
    H.frame(ui)
    H.click(posA.x + 10, posA.y + 10, ui) -- collapse A
    for _ = 1, 3 do H.frame(ui) end
    assert(state.a == false, "A stays collapsed")
    assert(state.b == true, "B is unaffected: state is keyed by title")
  end)

  T("clicks land on the front-most window; clicking raises a window", function()
    local im = H.fresh()
    local hits, btn, brect = 0, {}, {}
    local bx, by = 100, 100 -- B starts right on top of A
    local function ui()
      im.SetNextWindowPos(100, 100, "always")
      im.Begin("A")
      if im.Button("Hit") then hits = hits + 1 end
      H.grabRect(btn, im)
      im.End()
      im.SetNextWindowPos(bx, by, "always")
      im.Begin("B")
      im.Text("a wide window body")
      brect.x, brect.y = im.GetWindowPos()
      brect.w, brect.h = im.GetWindowSize()
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    local cx, cy = H.center(btn)
    -- Sanity check the setup: A's button really is underneath B.
    assert(cx >= brect.x and cx < brect.x + brect.w
       and cy >= brect.y and cy < brect.y + brect.h,
      "test setup: B must cover A's button")

    H.click(cx, cy, ui)
    assert(hits == 0, "B is in front, so it must swallow the click")

    bx, by = 500, 400 -- move B out of the way
    H.frame(ui)
    H.click(cx, cy, ui) -- this click also raises A
    assert(hits == 1, "with B gone, A's button receives the click")

    bx, by = 100, 100 -- B returns, but A is now in front
    H.frame(ui)
    H.click(cx, cy, ui)
    assert(hits == 2, "A was raised by the previous click and stays on top")
  end)

  T("a window that stops being submitted stops swallowing clicks", function()
    local im = H.fresh()
    local hits, btn = 0, {}
    local showB = true
    local function ui()
      im.SetNextWindowPos(100, 100, "always")
      im.Begin("A")
      if im.Button("Hit") then hits = hits + 1 end
      H.grabRect(btn, im)
      im.End()
      if showB then
        im.SetNextWindowPos(100, 100, "always")
        im.Begin("B")
        im.Text("a wide window body")
        im.End()
      end
    end
    H.frame(ui)
    H.frame(ui)
    local cx, cy = H.center(btn)
    H.click(cx, cy, ui)
    assert(hits == 0, "B swallows the click while it exists")
    showB = false
    H.frame(ui)
    H.frame(ui)
    H.click(cx, cy, ui)
    assert(hits == 1, "once B is gone, its ghost must not block A")
  end)

  T("SetNextWindowPos 'once' places only on first appearance", function()
    local im = H.fresh()
    local pos = {}
    local function ui()
      im.SetNextWindowPos(222, 111, "once")
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      im.End()
    end
    H.frame(ui)
    assert(pos.x == 222 and pos.y == 111, "'once' applies to a new window")
    -- Drag it somewhere else; 'once' must not snap it back.
    H.stub.setMouse(250, 116) -- on the title bar, clear of the arrow
    im.mousepressed(250, 116, 1)
    H.frame(ui)
    H.stub.setMouse(290, 150) -- +40, +34
    H.frame(ui)
    im.mousereleased(290, 150, 1)
    H.frame(ui)
    assert(pos.x == 262 and pos.y == 145,
      "'once' must not fight the user's dragging: got " .. pos.x .. "," .. pos.y)
  end)

end
