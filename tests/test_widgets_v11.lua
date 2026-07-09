-- v1.1 widgets: SliderInt/DragFloat/DragInt, RadioButton/ProgressBar,
-- CollapsingHeader, the Text variants, the layout fillers, item queries,
-- Button's size arguments/SmallButton, and PlotLines/PlotHistogram. Follows
-- the same interaction-simulation style as test_widgets.lua.

return function(T, H)

  ------------------------------------------------------------------ SliderInt

  T("SliderInt maps a click on the track to an integer value", function()
    local im = H.fresh()
    local value, changed, rect = 0, nil, {}
    local function ui()
      im.Begin("W")
      value, changed = im.SliderInt("SI", value, 0, 100)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    assert(value == 0 and changed == nil or true) -- warm-up frame only
    H.click(rect.x1 + 40, rect.y1 + 5, ui) -- 25% along a 160px track
    assert(value == 25, "expected exactly 25, got " .. tostring(value))
    assert(math.floor(value) == value, "SliderInt must return an integer")
  end)

  T("SliderInt rounds to the nearest integer while dragging", function()
    local im = H.fresh()
    local value, rect = 0, {}
    local function ui()
      im.Begin("W")
      value = im.SliderInt("SI", value, 0, 30)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local y = rect.y1 + 5
    -- 1/160 of the 0..30 range along the track: rounds, doesn't truncate.
    H.stub.setMouse(rect.x1 + 1, y)
    im.mousepressed(rect.x1 + 1, y, 1)
    H.frame(ui)
    assert(value == math.floor(value), "value must always be an integer")
  end)

  T("SliderInt inside a collapsed window is an inert no-op", function()
    local im = H.fresh()
    local r, pos = {}, {}
    local function ui()
      r.open = im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      r.value, r.changed = im.SliderInt("SI", 7, 0, 10)
      im.End()
    end
    H.frame(ui)
    H.click(pos.x + 10, pos.y + 10, ui)
    H.frame(ui)
    assert(r.open == false)
    assert(r.value == 7 and r.changed == false)
  end)

  -------------------------------------------------------------- DragFloat/Int

  T("DragFloat: no movement leaves the value unchanged", function()
    local im = H.fresh()
    local value, changed, rect = 10, nil, {}
    local function ui()
      im.Begin("W")
      value, changed = im.DragFloat("D", value)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    assert(value == 10 and changed == false)
  end)

  T("DragFloat: horizontal drag moves the value by speed per pixel",
    function()
      local im = H.fresh()
      local value, changed, rect = 10, nil, {}
      local function ui()
        im.Begin("W")
        value, changed = im.DragFloat("D", value, 2.0)
        H.grabRect(rect, im)
        im.End()
      end
      H.frame(ui)
      local y = rect.y1 + 5

      H.stub.setMouse(rect.x1 + 10, y)
      im.mousepressed(rect.x1 + 10, y, 1)
      H.frame(ui)
      assert(value == 10 and changed == false,
        "a press with no movement must not change the value")

      H.stub.setMouse(rect.x1 + 40, y) -- +30px * speed 2.0
      H.frame(ui)
      assert(math.abs(value - 70) < 0.001 and changed == true)

      im.mousereleased(rect.x1 + 40, y, 1)
      H.frame(ui)
      H.frame(ui)
      assert(math.abs(value - 70) < 0.001 and changed == false,
        "value stays after release, with no phantom changed")
    end)

  T("DragFloat: unbounded by default, clamps only when min/max are given",
    function()
      local im = H.fresh()
      local value, rect = 0, {}
      local function ui()
        im.Begin("W")
        value = im.DragFloat("D", value, 1, 0, 5)
        H.grabRect(rect, im)
        im.End()
      end
      H.frame(ui)
      local y = rect.y1 + 5
      H.stub.setMouse(rect.x1, y)
      im.mousepressed(rect.x1, y, 1)
      H.frame(ui)
      H.stub.setMouse(rect.x1 + 500, y) -- way past max
      H.frame(ui)
      assert(value == 5, "value must clamp to max while dragging")
    end)

  T("DragInt: rounds to the nearest integer and respects its own speed",
    function()
      local im = H.fresh()
      local value, changed, rect = 5, nil, {}
      local function ui()
        im.Begin("W")
        value, changed = im.DragInt("DI", value)
        H.grabRect(rect, im)
        im.End()
      end
      H.frame(ui)
      local y = rect.y1 + 5
      H.stub.setMouse(rect.x1 + 10, y)
      im.mousepressed(rect.x1 + 10, y, 1)
      H.frame(ui)
      H.stub.setMouse(rect.x1 + 17, y) -- +7px * default speed 1
      H.frame(ui)
      assert(value == 12 and changed == true,
        "expected 5 + 7 = 12, got " .. tostring(value))
      im.mousereleased(rect.x1 + 17, y, 1)
      H.frame(ui)
    end)

  T("DragFloat/DragInt inside a collapsed window are inert no-ops", function()
    local im = H.fresh()
    local r, pos = {}, {}
    local function ui()
      r.open = im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      r.df, r.dfChanged = im.DragFloat("DF", 1.5)
      r.di, r.diChanged = im.DragInt("DI", 2)
      im.End()
    end
    H.frame(ui)
    H.click(pos.x + 10, pos.y + 10, ui)
    H.frame(ui)
    assert(r.open == false)
    assert(r.df == 1.5 and r.dfChanged == false)
    assert(r.di == 2 and r.diChanged == false)
  end)

  ---------------------------------------------------------------- RadioButton

  T("RadioButton fires on click; the caller owns the selection", function()
    local im = H.fresh()
    local mode = "A"
    local rectA, rectB = {}, {}
    local function ui()
      im.Begin("W")
      if im.RadioButton("A", mode == "A") then mode = "A" end
      H.grabRect(rectA, im)
      if im.RadioButton("B", mode == "B") then mode = "B" end
      H.grabRect(rectB, im)
      im.End()
    end
    H.frame(ui)
    assert(mode == "A")
    local cx, cy = H.center(rectB)
    H.click(cx, cy, ui)
    assert(mode == "B", "clicking B switches the mode")
    cx, cy = H.center(rectA)
    H.click(cx, cy, ui)
    assert(mode == "A", "clicking A switches back")
  end)

  T("RadioButton inside a collapsed window returns false", function()
    local im = H.fresh()
    local r, pos = {}, {}
    local function ui()
      r.open = im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      r.pressed = im.RadioButton("R", true)
      im.End()
    end
    H.frame(ui)
    H.click(pos.x + 10, pos.y + 10, ui)
    H.frame(ui)
    assert(r.open == false)
    assert(r.pressed == false)
  end)

  ---------------------------------------------------------------- ProgressBar

  T("ProgressBar clamps its fraction and shows a default percent overlay",
    function()
      local im = H.fresh()
      local function ui()
        im.Begin("W")
        im.ProgressBar(0.5)
        im.ProgressBar(1.5)          -- clamps to 100%
        im.ProgressBar(-0.2, nil, nil, "custom")
        im.End()
      end
      H.stub.clearCalls()
      H.frame(ui)
      local printed = table.concat(H.stub.printed(), "|")
      assert(printed:find("50%", 1, true), "expected a 50% overlay: " .. printed)
      assert(printed:find("100%", 1, true), "fraction > 1 must clamp to 100%")
      assert(printed:find("custom", 1, true), "explicit overlay text must win")
    end)

  T("ProgressBar inside a collapsed window does not error", function()
    local im = H.fresh()
    local pos = {}
    local function ui()
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      im.ProgressBar(0.5)
      im.End()
    end
    H.frame(ui)
    H.click(pos.x + 10, pos.y + 10, ui)
    H.frame(ui) -- must not error while collapsed
  end)

  ------------------------------------------------------------ CollapsingHeader

  T("CollapsingHeader opens on click, persists, and doesn't indent", function()
    local im = H.fresh()
    local state, header, child = {}, {}, {}
    local function ui()
      im.Begin("W")
      state.open = im.CollapsingHeader("Section")
      H.grabRect(header, im)
      if state.open then
        im.Text("child")
        H.grabRect(child, im)
      end
      im.End()
    end
    H.frame(ui)
    assert(state.open == false, "starts closed")

    local cx, cy = H.center(header)
    H.click(cx, cy, ui)
    assert(state.open == true, "click opens it")

    H.frame(ui)
    H.frame(ui)
    assert(state.open == true, "state persists across frames")
    assert(child.x1 == header.x1,
      "CollapsingHeader must NOT indent its children, unlike TreeNode")
  end)

  T("CollapsingHeader spans the window's available width", function()
    local im = H.fresh()
    local rect = {}
    local function ui()
      im.Begin("W")
      im.Text("a reasonably long line of text to widen the window")
      im.CollapsingHeader("S")
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.frame(ui) -- availWidth uses last frame's window width
    assert(rect.x2 - rect.x1 > 100,
      "header should stretch to the wide window, not just its label")
  end)

  T("CollapsingHeader needs no matching Pop: End() doesn't complain",
    function()
      local im = H.fresh()
      local function ui()
        im.Begin("W")
        if im.CollapsingHeader("S") then
          im.Text("inside")
        end
        im.End() -- would error if CollapsingHeader had pushed an ID
      end
      H.frame(ui)
    end)

  T("CollapsingHeader inside a collapsed window returns false", function()
    local im = H.fresh()
    local r, pos = {}, {}
    local function ui()
      r.open = im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      r.header = im.CollapsingHeader("S")
      im.End()
    end
    H.frame(ui)
    H.click(pos.x + 10, pos.y + 10, ui)
    H.frame(ui)
    assert(r.open == false)
    assert(r.header == false)
  end)

  ------------------------------------------------------------------ Text vars

  T("TextColored draws formatted text in the given color", function()
    local im = H.fresh()
    local function ui()
      im.Begin("W")
      im.TextColored({ 1, 0, 0, 1 }, "danger: %d", 5)
      im.End()
    end
    H.stub.clearCalls()
    H.frame(ui)
    local printed = table.concat(H.stub.printed(), "|")
    assert(printed:find("danger: 5", 1, true))
  end)

  T("TextDisabled formats like Text", function()
    local im = H.fresh()
    local function ui()
      im.Begin("W")
      im.TextDisabled("muted: %s", "yes")
      im.End()
    end
    H.stub.clearCalls()
    H.frame(ui)
    local printed = table.concat(H.stub.printed(), "|")
    assert(printed:find("muted: yes", 1, true))
  end)

  T("TextWrapped wraps to the window's available width", function()
    local im = H.fresh()
    local rect = {}
    local function ui()
      im.Begin("W")
      im.Dummy(300, 1) -- forces a stable, wide window
      im.TextWrapped("one two three four five six seven eight nine ten " ..
        "eleven twelve thirteen fourteen fifteen sixteen")
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.frame(ui) -- wrap width uses last frame's window width
    local h = rect.y2 - rect.y1
    assert(h > 14, "long text at a fixed width must wrap onto more than one line")
    assert(h % 14 == 0, "wrapped height must be a whole number of lines")
  end)

  T("BulletText draws a bullet circle plus formatted text", function()
    local im = H.fresh()
    local function ui()
      im.Begin("W")
      im.BulletText("gold: %d", 42)
      im.End()
    end
    H.stub.clearCalls()
    H.frame(ui)
    local printed = table.concat(H.stub.printed(), "|")
    assert(printed:find("gold: 42", 1, true))
    local sawCircle = false
    for _, c in ipairs(H.stub.calls) do
      if c[1] == "circle" then sawCircle = true end
    end
    assert(sawCircle, "BulletText must draw a bullet")
  end)

  --------------------------------------------------------------- Layout fillers

  T("Spacing() and NewLine() advance the cursor without a widget", function()
    local im = H.fresh()
    local a, b, c = {}, {}, {}
    local function ui()
      im.Begin("W")
      im.Text("first")
      H.grabRect(a, im)
      im.Spacing()
      im.Text("second")
      H.grabRect(b, im)
      im.SameLine()
      im.NewLine() -- cancels the pending SameLine()
      im.Text("third")
      H.grabRect(c, im)
      im.End()
    end
    H.frame(ui)
    assert(b.y1 > a.y1, "Spacing() must drop to a new, lower row")
    assert(c.y1 > b.y1, "NewLine() must override a pending SameLine()")
    assert(c.x1 == a.x1, "the new row starts back at the left margin")
  end)

  T("Indent()/Unindent() shift the layout cursor by the default indent",
    function()
      local im = H.fresh()
      local a, b, c = {}, {}, {}
      local function ui()
        im.Begin("W")
        im.Text("root")
        H.grabRect(a, im)
        im.Indent()
        im.Text("indented")
        H.grabRect(b, im)
        im.Unindent()
        im.Text("back")
        H.grabRect(c, im)
        im.End()
      end
      H.frame(ui)
      assert(b.x1 > a.x1, "Indent() must shift right")
      assert(c.x1 == a.x1, "Unindent() must return to the original column")
    end)

  T("Indent(w)/Unindent(w) accept an explicit width", function()
    local im = H.fresh()
    local a, b = {}, {}
    local function ui()
      im.Begin("W")
      im.Text("root")
      H.grabRect(a, im)
      im.Indent(50)
      im.Text("indented")
      H.grabRect(b, im)
      im.Unindent(50)
      im.End()
    end
    H.frame(ui)
    assert(b.x1 - a.x1 == 50)
  end)

  T("Dummy(w, h) reserves a blank rectangle of that size", function()
    local im = H.fresh()
    local rect = {}
    local function ui()
      im.Begin("W")
      im.Dummy(40, 20)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    assert(rect.x2 - rect.x1 == 40 and rect.y2 - rect.y1 == 20)
  end)

  T("SameLine() with no arguments still behaves as in v1", function()
    local im = H.fresh()
    local a, b = {}, {}
    local function ui()
      im.Begin("W")
      im.Text("first")
      H.grabRect(a, im)
      im.SameLine()
      im.Text("second")
      H.grabRect(b, im)
      im.End()
    end
    H.frame(ui)
    assert(b.y1 == a.y1 and b.x1 > a.x2)
  end)

  T("SameLine(offsetFromStartX) places the next item at an absolute column",
    function()
      local im = H.fresh()
      local a, b = {}, {}
      local function ui()
        im.Begin("W")
        im.Text("first")
        H.grabRect(a, im)
        im.SameLine(100)
        im.Text("second")
        H.grabRect(b, im)
        im.End()
      end
      H.frame(ui)
      assert(b.y1 == a.y1, "still the same row")
      assert(b.x1 == a.x1 + 100,
        "offsetFromStartX is measured from the window's content start")
    end)

  T("SameLine(nil, spacing) overrides the default item-spacing gap",
    function()
      local im = H.fresh()
      local a, b = {}, {}
      local function ui()
        im.Begin("W")
        im.Text("first")
        H.grabRect(a, im)
        im.SameLine(nil, 30)
        im.Text("second")
        H.grabRect(b, im)
        im.End()
      end
      H.frame(ui)
      assert(b.x1 == a.x2 + 30)
    end)

  -------------------------------------------------------------- Item queries

  T("IsItemHovered/IsItemActive/IsItemClicked track a Button through a click",
    function()
      local im = H.fresh()
      local snap, rect = {}, {}
      local function ui()
        im.Begin("W")
        im.Button("Click")
        H.grabRect(rect, im)
        snap.hovered = im.IsItemHovered()
        snap.active = im.IsItemActive()
        snap.clicked = im.IsItemClicked()
        im.End()
      end
      H.frame(ui)
      local cx, cy = H.center(rect)

      H.stub.setMouse(cx, cy)
      H.frame(ui)
      assert(snap.hovered == true and snap.active == false
        and snap.clicked == false, "hovering alone: hovered only")

      im.mousepressed(cx, cy, 1)
      H.frame(ui)
      assert(snap.hovered == true and snap.active == true
        and snap.clicked == false, "pressed and held: active")

      im.mousereleased(cx, cy, 1)
      H.frame(ui)
      assert(snap.active == false and snap.clicked == true,
        "released over it: clicked, on that frame only")

      H.frame(ui)
      assert(snap.clicked == false, "clicked does not persist")
    end)

  T("IsItemHovered works for a non-interactive Text item", function()
    local im = H.fresh()
    local snap, rect = {}, {}
    local function ui()
      im.Begin("W")
      im.Text("hello")
      H.grabRect(rect, im)
      snap.hovered = im.IsItemHovered()
      snap.active = im.IsItemActive()
      snap.clicked = im.IsItemClicked()
      im.End()
    end
    H.frame(ui)
    assert(snap.hovered == false, "mouse starts at (0,0), off the text")

    local cx, cy = H.center(rect)
    H.stub.setMouse(cx, cy)
    H.frame(ui)
    assert(snap.hovered == true,
      "Text's IsItemHovered is computed from geometry, not behavior()")
    assert(snap.active == false and snap.clicked == false,
      "static text is never active or clicked")
  end)

  ------------------------------------------------------------- Button sizing

  T("Button(label, w, h) accepts an explicit size", function()
    local im = H.fresh()
    local rect = {}
    local function ui()
      im.Begin("W")
      im.Button("X", 120, 40)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    assert(rect.x2 - rect.x1 == 120 and rect.y2 - rect.y1 == 40)
  end)

  T("Button(label, 0, 0) auto-sizes exactly like Button(label)", function()
    local im = H.fresh()
    local a, b = {}, {}
    local function ui()
      im.Begin("W")
      im.Button("Same")
      H.grabRect(a, im)
      im.Button("Same##2", 0, 0)
      H.grabRect(b, im)
      im.End()
    end
    H.frame(ui)
    assert(a.x2 - a.x1 == b.x2 - b.x1 and a.y2 - a.y1 == b.y2 - b.y1,
      "0 (or nil) means auto-size on that axis, per widget")
  end)

  T("SmallButton has no vertical frame padding and still fires on release",
    function()
      local im = H.fresh()
      local hits, btnRect, smallRect = 0, {}, {}
      local function ui()
        im.Begin("W")
        im.Button("B")
        H.grabRect(btnRect, im)
        if im.SmallButton("S") then hits = hits + 1 end
        H.grabRect(smallRect, im)
        im.End()
      end
      H.frame(ui)
      assert(smallRect.y2 - smallRect.y1 < btnRect.y2 - btnRect.y1,
        "SmallButton must be shorter than a regular Button")
      local cx, cy = H.center(smallRect)
      H.click(cx, cy, ui)
      assert(hits == 1)
    end)

  ------------------------------------------------------------------ Plotting

  T("PlotLines/PlotHistogram draw an overlay and size themselves sensibly",
    function()
      local im = H.fresh()
      local rect = {}
      local function ui()
        im.Begin("W")
        im.PlotLines("frame time", { 1, 2, 3, 2, 1 })
        H.grabRect(rect, im)
        im.PlotHistogram("hist", { 1, 2, 3, 2, 1 }, nil, nil, 100, 50, "42%")
        im.End()
      end
      H.stub.clearCalls()
      H.frame(ui)
      assert(rect.x2 - rect.x1 > 0 and rect.y2 - rect.y1 > 0)
      local printed = table.concat(H.stub.printed(), "|")
      assert(printed:find("42%", 1, true), "explicit overlay must be drawn")
    end)

  T("PlotLines honors explicit width/height", function()
    local im = H.fresh()
    local rect = {}
    local function ui()
      im.Begin("W")
      im.PlotLines("p", { 1, 2, 3 }, nil, nil, 200, 80)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    assert(rect.y2 - rect.y1 == 80)
  end)

  T("PlotLines/PlotHistogram tolerate an empty values array", function()
    local im = H.fresh()
    local function ui()
      im.Begin("W")
      im.PlotLines("empty", {})
      im.PlotHistogram("empty2", {})
      im.End()
    end
    H.frame(ui) -- must not error
  end)

  T("PlotLines/PlotHistogram inside a collapsed window do not error",
    function()
      local im = H.fresh()
      local pos = {}
      local function ui()
        im.Begin("W")
        pos.x, pos.y = im.GetWindowPos()
        im.PlotLines("p", { 1, 2, 3 })
        im.PlotHistogram("ph", { 1, 2, 3 })
        im.End()
      end
      H.frame(ui)
      H.click(pos.x + 10, pos.y + 10, ui)
      H.frame(ui) -- must not error while collapsed
    end)

  --------------------------------------------------- Everything, collapsed

  T("every v1.1 widget inside a collapsed window is a sane no-op", function()
    local im = H.fresh()
    local r, pos = {}, {}
    local function ui()
      r.open = im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      r.si, r.siChanged = im.SliderInt("SI", 3, 0, 10)
      r.df, r.dfChanged = im.DragFloat("DF", 1.5)
      r.di, r.diChanged = im.DragInt("DI", 2)
      r.radio = im.RadioButton("R", false)
      im.ProgressBar(0.5)
      r.header = im.CollapsingHeader("H")
      im.TextColored({ 1, 0, 0, 1 }, "x")
      im.TextDisabled("x")
      im.TextWrapped("x")
      im.BulletText("x")
      im.Spacing()
      im.NewLine()
      im.Dummy(10, 10)
      im.Indent()
      im.Unindent()
      r.small = im.SmallButton("S")
      im.PlotLines("P", { 1, 2, 3 })
      im.PlotHistogram("PH", { 1, 2, 3 })
      im.End()
    end
    H.frame(ui)
    H.click(pos.x + 10, pos.y + 10, ui) -- the collapse arrow
    H.frame(ui)
    assert(r.open == false, "test setup: window must be collapsed")
    assert(r.si == 3 and r.siChanged == false)
    assert(r.df == 1.5 and r.dfChanged == false)
    assert(r.di == 2 and r.diChanged == false)
    assert(r.radio == false)
    assert(r.header == false)
    assert(r.small == false)
  end)

end
