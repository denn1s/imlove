-- Widget interaction logic: the hover/click/drag state transitions.

return function(T, H)

  T("Button fires exactly once, on release over it", function()
    local im = H.fresh()
    local presses, rect = 0, {}
    local function ui()
      im.Begin("W")
      if im.Button("Click") then presses = presses + 1 end
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui) -- first frame establishes geometry
    local cx, cy = H.center(rect)

    H.stub.setMouse(cx, cy)
    H.frame(ui)
    assert(presses == 0, "hovering must not fire")

    im.mousepressed(cx, cy, 1)
    H.frame(ui)
    assert(presses == 0, "pressing must not fire yet")

    im.mousereleased(cx, cy, 1)
    H.frame(ui)
    assert(presses == 1, "releasing over the button fires once")

    H.frame(ui)
    assert(presses == 1, "no repeat fire on later frames")
  end)

  T("Button press-drag-off-release cancels the click", function()
    local im = H.fresh()
    local presses, rect = 0, {}
    local function ui()
      im.Begin("W")
      if im.Button("Click") then presses = presses + 1 end
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local cx, cy = H.center(rect)

    H.stub.setMouse(cx, cy)
    im.mousepressed(cx, cy, 1)
    H.frame(ui)
    H.stub.setMouse(cx, cy + 300) -- drag far off the button
    H.frame(ui)
    im.mousereleased(cx, cy + 300, 1)
    H.frame(ui)
    assert(presses == 0, "releasing away from the button must not fire")
  end)

  T("Checkbox toggles and reports changed", function()
    local im = H.fresh()
    local value, changed, rect = false, nil, {}
    local changes = 0
    local function ui()
      im.Begin("W")
      value, changed = im.Checkbox("Enabled", value)
      if changed then changes = changes + 1 end
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    assert(value == false and changes == 0)

    -- click the box itself (left end of the item rect)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    assert(value == true, "click must toggle on")
    assert(changes == 1, "changed must be true exactly once per toggle")

    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    assert(value == false, "second click toggles back off")
    assert(changes == 2)

    H.frame(ui)
    assert(changes == 2, "no change without a click")
  end)

  T("Checkbox label is clickable too", function()
    local im = H.fresh()
    local value, rect = false, {}
    local function ui()
      im.Begin("W")
      value = im.Checkbox("Enabled", value)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x2 - 3, rect.y1 + 5, ui) -- far right: over the label text
    assert(value == true, "clicking the label must toggle the box")
  end)

  T("SliderFloat maps a click on the track to the value", function()
    local im = H.fresh()
    local value, rect = 0, {}
    local function ui()
      im.Begin("W")
      value = im.SliderFloat("S", value, 0, 100)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    -- The track is the first 160px of the item (style.sliderWidth).
    H.click(rect.x1 + 40, rect.y1 + 5, ui) -- 25% along the track
    assert(math.abs(value - 25) < 0.5, "expected ~25, got " .. value)
  end)

  T("SliderFloat keeps dragging while held, even off the track", function()
    local im = H.fresh()
    local value, changed, rect = 0, nil, {}
    local function ui()
      im.Begin("W")
      value, changed = im.SliderFloat("S", value, 0, 100)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local y = rect.y1 + 5

    H.stub.setMouse(rect.x1 + 40, y)
    im.mousepressed(rect.x1 + 40, y, 1)
    H.frame(ui)
    assert(math.abs(value - 25) < 0.5 and changed == true)

    H.stub.setMouse(rect.x1 + 80, y) -- drag to 50%
    H.frame(ui)
    assert(math.abs(value - 50) < 0.5 and changed == true)

    H.stub.setMouse(rect.x1 + 80, y + 200) -- stray below the window
    H.frame(ui)
    assert(math.abs(value - 50) < 0.5, "vertical stray must not lose the drag")

    H.stub.setMouse(rect.x1 + 500, y + 200) -- way past the right end
    H.frame(ui)
    assert(math.abs(value - 100) < 0.5, "value clamps to max while dragging")

    im.mousereleased(rect.x1 + 500, y + 200, 1)
    H.frame(ui)
    H.frame(ui)
    assert(math.abs(value - 100) < 0.5 and changed == false,
      "value stays after release, with no phantom changed")
  end)

  T("TreeNode opens on click, persists, indents children", function()
    local im = H.fresh()
    local state = {}
    local node, child = {}, {}
    local function ui()
      im.Begin("W")
      state.open = im.TreeNode("Branch")
      H.grabRect(node, im)
      if state.open then
        im.Text("leaf")
        H.grabRect(child, im)
        im.TreePop()
      end
      im.End()
    end
    H.frame(ui)
    assert(state.open == false, "nodes start closed")

    local nx, ny = H.center(node)
    H.click(nx, ny, ui)
    assert(state.open == true, "click opens the node")

    H.frame(ui)
    H.frame(ui)
    assert(state.open == true, "open state persists across frames")
    assert(child.x1 > node.x1, "children must be indented")

    H.click(nx, ny, ui)
    assert(state.open == false, "second click closes it again")
  end)

  T("Selectable reports clicks", function()
    local im = H.fresh()
    local clicked, rect = 0, {}
    local function ui()
      im.Begin("W")
      if im.Selectable("Row 1", false) then clicked = clicked + 1 end
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local cx, cy = H.center(rect)
    H.click(cx, cy, ui)
    assert(clicked == 1)
  end)

  T("SameLine places the next item on the same row", function()
    local im = H.fresh()
    local a, b, c = {}, {}, {}
    local function ui()
      im.Begin("W")
      im.Text("first")
      H.grabRect(a, im)
      im.SameLine()
      im.Text("second")
      H.grabRect(b, im)
      im.Text("third") -- no SameLine: back to a fresh row
      H.grabRect(c, im)
      im.End()
    end
    H.frame(ui)
    assert(b.y1 == a.y1, "SameLine keeps the same y")
    assert(b.x1 > a.x2, "SameLine places it to the right, with spacing")
    assert(c.y1 > a.y1, "next widget returns to a new row")
    assert(c.x1 == a.x1, "new row starts back at the left margin")
  end)

  T("Text formats its arguments; ## suffixes are hidden", function()
    local im = H.fresh()
    local function ui()
      im.Begin("W")
      im.Text("hp: %d/%d", 7, 10)
      im.Button("Save##slot1")
      im.End()
    end
    H.stub.clearCalls()
    H.frame(ui)
    local printed = table.concat(H.stub.printed(), "|")
    assert(printed:find("hp: 7/10", 1, true), "formatted text must be drawn")
    assert(printed:find("|Save|") or printed:find("|Save$"),
      "the ## id suffix must not be drawn")
    assert(not printed:find("slot1", 1, true), "id suffix leaked: " .. printed)
  end)

  T("widgets inside a collapsed window are inert no-ops", function()
    local im = H.fresh()
    local value, results, pos = 5, {}, {}
    local function ui()
      -- Deliberately not guarding on Begin's return: even then, widgets
      -- must be safe and return their inputs unchanged.
      results.open = im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      results.pressed = im.Button("B")
      results.value, results.changed = im.SliderFloat("S", value, 0, 10)
      im.End()
    end
    H.frame(ui)
    -- The collapse arrow is a title-bar-height square (20px with the stub
    -- font) in the window's top-left corner.
    H.click(pos.x + 10, pos.y + 10, ui)
    H.frame(ui)
    assert(results.open == false, "Begin must return false while collapsed")
    assert(results.pressed == false)
    assert(results.value == 5 and results.changed == false,
      "collapsed slider must return the input value unchanged")
  end)

end
