-- The ID stack: PushID/PopID, the "##" convention, and TreeNode's implicit
-- push. The point of all of it: identical labels in a list must map to
-- distinct widgets, so clicking one never triggers another.

return function(T, H)

  T("PushID separates identically-labelled buttons", function()
    local im = H.fresh()
    local hits, first, second = { 0, 0 }, {}, {}
    local function ui()
      im.Begin("W")
      for i = 1, 2 do
        im.PushID(i)
        if im.Button("Delete") then hits[i] = hits[i] + 1 end
        H.grabRect(i == 1 and first or second, im)
        im.PopID()
      end
      im.End()
    end
    H.frame(ui)
    local cx, cy = H.center(second)
    H.click(cx, cy, ui)
    assert(hits[2] == 1, "the clicked button must fire")
    assert(hits[1] == 0, "its identically-labelled sibling must not")
  end)

  T("'##' suffixes distinguish widgets without changing the display", function()
    local im = H.fresh()
    local hits, first, second = { 0, 0 }, {}, {}
    local function ui()
      im.Begin("W")
      if im.Button("Save##a") then hits[1] = hits[1] + 1 end
      H.grabRect(first, im)
      if im.Button("Save##b") then hits[2] = hits[2] + 1 end
      H.grabRect(second, im)
      im.End()
    end
    H.frame(ui)
    local cx, cy = H.center(first)
    H.click(cx, cy, ui)
    assert(hits[1] == 1 and hits[2] == 0)
    assert(first.x2 - first.x1 == second.x2 - second.x1,
      "both buttons display the same text, so they must be the same size")
  end)

  T("an open TreeNode scopes the IDs of its children", function()
    local im = H.fresh()
    local hits = { 0, 0 }
    local nodes = { {}, {} }
    local buttons = { {}, {} }
    local function ui()
      im.Begin("W")
      for i = 1, 2 do
        if im.TreeNode("Group " .. i) then
          if im.Button("Act") then hits[i] = hits[i] + 1 end
          H.grabRect(buttons[i], im)
          im.TreePop()
        else
          H.grabRect(nodes[i], im)
        end
      end
      im.End()
    end
    H.frame(ui)
    -- Open both groups by clicking their headers.
    local cx, cy = H.center(nodes[1])
    H.click(cx, cy, ui)
    cx, cy = H.center(nodes[2])
    H.click(cx, cy, ui)
    -- Both "Act" buttons exist now; click only the second.
    cx, cy = H.center(buttons[2])
    H.click(cx, cy, ui)
    assert(hits[2] == 1, "the clicked Act must fire")
    assert(hits[1] == 0, "the Act in the other group must not")
  end)

  T("windows are separate ID namespaces", function()
    local im = H.fresh()
    local hits, rect = { 0, 0 }, {}
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.Begin("A")
      if im.Button("Go") then hits[1] = hits[1] + 1 end
      H.grabRect(rect, im)
      im.End()
      im.SetNextWindowPos(400, 50, "always")
      im.Begin("B")
      if im.Button("Go") then hits[2] = hits[2] + 1 end
      im.End()
    end
    H.frame(ui)
    local cx, cy = H.center(rect)
    H.click(cx, cy, ui)
    assert(hits[1] == 1 and hits[2] == 0,
      "same label in another window must be a different widget")
  end)

  T("PopID underflow errors", function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("W")
    local ok, err = pcall(im.PopID)
    assert(not ok and err:find("without a matching"), tostring(err))
  end)

  T("End catches an unpopped PushID", function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("W")
    im.PushID("oops")
    local ok, err = pcall(im.End)
    assert(not ok and err:find("left unpopped"), tostring(err))
  end)

end
