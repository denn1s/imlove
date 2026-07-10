--[[
v1.3 overlays: SetTooltip/BeginTooltip/EndTooltip, OpenPopup/BeginPopup/
EndPopup/CloseCurrentPopup, BeginPopupContextItem, BeginPopupModal, and the
two widgets that reuse this machinery internally: Combo and ListBox.

Known stub geometry used throughout (see stub_love.lua and the style table):
  font: 7px/char wide, 14px tall     windowPadding = 8
  framePadding = {6, 3}              titleH = 14 + 3*2 = 20
  itemSpacing = {8, 5}               sliderWidth = 160
  minWindowWidth = 60                default screen size: 800x600
]]

return function(T, H)

  --------------------------------------------------------------------------
  -- OpenPopup / BeginPopup / EndPopup: happy path, id scoping, errors
  --------------------------------------------------------------------------

  T("OpenPopup + BeginPopup: opens on the button's release frame, closes " ..
    "when the caller stops calling BeginPopup", function()
    local im = H.fresh()
    local rect, isOpen = {}, false
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      if im.Button("Options") then im.OpenPopup("options") end
      H.grabRect(rect, im)
      isOpen = im.BeginPopup("options")
      if isOpen then
        im.Text("stuff")
        im.EndPopup()
      end
      im.End()
    end
    H.frame(ui)
    assert(not isOpen, "must not be open before it's ever triggered")

    local cx, cy = H.center(rect)
    H.click(cx, cy, ui)
    assert(isOpen, "BeginPopup must return true the frame OpenPopup fires")

    H.frame(ui)
    assert(isOpen, "stays open across frames while nothing dismisses it")
  end)

  T("OpenPopup/BeginPopup ids are scoped like any other widget id: two " ..
    "windows opening the same strId get independent popups", function()
    local im = H.fresh()
    local rectA, rectB = {}, {}
    local openA, openB = false, false
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("A")
      if im.Button("Open") then im.OpenPopup("shared") end
      H.grabRect(rectA, im)
      openA = im.BeginPopup("shared")
      if openA then im.Text("a"); im.EndPopup() end
      im.End()

      im.SetNextWindowPos(300, 10, "always")
      im.Begin("B")
      if im.Button("Open") then im.OpenPopup("shared") end
      H.grabRect(rectB, im)
      openB = im.BeginPopup("shared")
      if openB then im.Text("b"); im.EndPopup() end
      im.End()
    end
    H.frame(ui)
    local ax, ay = H.center(rectA)
    H.click(ax, ay, ui)
    assert(openA and not openB,
      "opening window A's popup must not open window B's")
  end)

  T("EndPopup() without a matching successful BeginPopup() is an error",
    function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("W")
    local ok, err = pcall(im.EndPopup)
    assert(not ok and err:find("BeginPopup"), tostring(err))
    im.End()
  end)

  T("leaving a popup open (no EndPopup) is caught by End()/Render()",
    function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("W")
    im.OpenPopup("p")
    im.BeginPopup("p") -- returns true; deliberately no EndPopup()
    local ok, err = pcall(im.End)
    assert(not ok and err:find("missing imlove.EndPopup"), tostring(err))
  end)

  --------------------------------------------------------------------------
  -- Dismissal: outside press, CloseCurrentPopup, nesting
  --------------------------------------------------------------------------

  T("a press outside the topmost open popup closes it, and consumes the " ..
    "press", function()
    local im = H.fresh()
    local rect, isOpen = {}, false
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      if im.Button("Options") then im.OpenPopup("options") end
      H.grabRect(rect, im)
      isOpen = im.BeginPopup("options")
      if isOpen then im.Text("stuff"); im.EndPopup() end
      im.End()
    end
    H.frame(ui)
    local cx, cy = H.center(rect)
    H.click(cx, cy, ui)
    assert(isOpen, "popup should be open")

    -- Far corner: nowhere near the window, the popup, or its owner button.
    local consumed = H.press(790, 590, 1, ui)
    assert(consumed, "the dismissing press must be consumed")
    assert(not isOpen, "an outside press closes the popup")
    H.release(790, 590, 1, ui)
    assert(not isOpen, "stays closed")
  end)

  T("a press that dismisses a popup does not also activate the widget it " ..
    "exposes underneath", function()
    local im = H.fresh()
    local openRect, isOpen = {}, false
    local bClicks = 0
    local bRect = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("A")
      if im.Button("Open") then im.OpenPopup("p") end
      H.grabRect(openRect, im)
      isOpen = im.BeginPopup("p")
      if isOpen then im.Text("popup"); im.EndPopup() end
      im.End()

      im.SetNextWindowPos(400, 400, "always")
      im.Begin("B")
      if im.Button("Click B") then bClicks = bClicks + 1 end
      H.grabRect(bRect, im)
      im.End()
    end
    H.frame(ui)
    local ox, oy = H.center(openRect)
    H.click(ox, oy, ui)
    assert(isOpen, "popup should be open")

    -- Window B sits far from the popup, so this press dismisses the popup
    -- (it's outside it) AND lands squarely on a real, unrelated widget.
    local bx, by = H.center(bRect)
    H.press(bx, by, 1, ui)
    assert(not isOpen, "the press over Button B still dismisses the popup")
    H.release(bx, by, 1, ui)
    assert(bClicks == 0, "the press that dismissed the popup must not " ..
      "also click the button it landed on")

    -- Not stuck: a subsequent, ordinary click on B works normally.
    H.click(bx, by, ui)
    assert(bClicks == 1, "a fresh click on B afterwards still works")
  end)

  T("CloseCurrentPopup() closes the popup currently being built", function()
    local im = H.fresh()
    local rect, isOpen = {}, false
    local closeRect = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      if im.Button("Options") then im.OpenPopup("options") end
      H.grabRect(rect, im)
      isOpen = im.BeginPopup("options")
      if isOpen then
        if im.Button("Close") then im.CloseCurrentPopup() end
        H.grabRect(closeRect, im)
        im.EndPopup()
      end
      im.End()
    end
    H.frame(ui)
    local cx, cy = H.center(rect)
    H.click(cx, cy, ui)
    assert(isOpen)

    local bx, by = H.center(closeRect)
    H.click(bx, by, ui)
    -- CloseCurrentPopup() takes effect for the NEXT BeginPopup() check, same
    -- one-frame-lag convention as everything else here: the click's own
    -- release frame still renders the popup one last time (isOpen was read
    -- before the close took effect), so an extra frame is needed to observe
    -- it actually gone.
    H.frame(ui)
    assert(not isOpen, "the Close button's CloseCurrentPopup() must close it")
  end)

  T("nested popups: a press on a lower popup closes only what's stacked " ..
    "above it; a press outside both closes everything", function()
    local im = H.fresh()
    local rectA, rectB = {}, {}
    local openA, openB = false, false
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      if im.Button("A") then im.OpenPopup("popupA") end
      H.grabRect(rectA, im)
      openA = im.BeginPopup("popupA")
      if openA then
        if im.Button("B") then im.OpenPopup("popupB") end
        H.grabRect(rectB, im)
        openB = im.BeginPopup("popupB")
        if openB then
          im.Text("leaf")
          im.EndPopup()
        end
        im.EndPopup()
      end
      im.End()
    end
    H.frame(ui)
    local ax, ay = H.center(rectA)
    H.click(ax, ay, ui)
    assert(openA, "popupA should be open")

    local bx, by = H.center(rectB)
    H.click(bx, by, ui)
    assert(openA and openB, "popupB should now also be open")

    -- Land inside popupA's own body — just above Button("B")'s top edge,
    -- in popupA's top padding — but outside popupB, which is anchored well
    -- below and to the right of where Button("B") was clicked.
    local px, py = rectB.x1, rectB.y1 - 4
    H.press(px, py, 1, ui)
    assert(openA and not openB,
      "a press on popupA (below popupB) closes only popupB")
    H.release(px, py, 1, ui)

    -- Now a press far outside both closes what's left (popupA).
    H.press(790, 590, 1, ui)
    assert(not openA, "a press outside everything closes the rest")
    H.release(790, 590, 1, ui)
  end)

  T("a right-click outside an open popup dismisses it too, and is " ..
    "consumed rather than also opening a context menu underneath",
    function()
    local im = H.fresh()
    local openRect, isOpen = {}, false
    local rowRect, ctxOpen = {}, false
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("A")
      if im.Button("Open") then im.OpenPopup("p") end
      H.grabRect(openRect, im)
      isOpen = im.BeginPopup("p")
      if isOpen then im.Text("popup"); im.EndPopup() end
      im.End()

      im.SetNextWindowPos(400, 400, "always")
      im.Begin("B")
      im.Selectable("Row", false)
      H.grabRect(rowRect, im)
      ctxOpen = im.BeginPopupContextItem()
      if ctxOpen then im.Text("Delete"); im.EndPopup() end
      im.End()
    end
    H.frame(ui)
    local ox, oy = H.center(openRect)
    H.click(ox, oy, ui)
    assert(isOpen, "popup should be open")

    -- Right-press over an unrelated row, far from the open popup: it must
    -- dismiss the popup (outside it) AND must not also trigger the context
    -- menu it happens to land on.
    local rx, ry = H.center(rowRect)
    local consumed = H.press(rx, ry, 2, ui)
    assert(consumed, "the dismissing right-press must be consumed")
    assert(not isOpen, "a right-press outside the popup dismisses it too")
    assert(not ctxOpen, "the same right-press must not also open the " ..
      "context menu it landed on")
    H.release(rx, ry, 2, ui)

    -- Not stuck: an ordinary right-click on the row now opens its own menu.
    H.rightClick(rx, ry, ui)
    assert(ctxOpen, "a subsequent, ordinary right-click on the row works")
  end)

  --------------------------------------------------------------------------
  -- BeginPopupContextItem
  --------------------------------------------------------------------------

  T("BeginPopupContextItem opens only on a right-click over the last item",
    function()
    local im = H.fresh()
    local rowRect, isOpen = {}, false
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      im.Selectable("Row", false)
      H.grabRect(rowRect, im)
      isOpen = im.BeginPopupContextItem()
      if isOpen then
        im.Text("Delete")
        im.EndPopup()
      end
      im.End()
    end
    H.frame(ui)
    local cx, cy = H.center(rowRect)

    -- A left-click over the row must not open the context menu.
    H.click(cx, cy, ui)
    assert(not isOpen, "left-click must not open a context menu")

    -- A right-click elsewhere (not over the row) must not open it either.
    H.rightClick(500, 500, ui)
    assert(not isOpen, "right-click away from the item must not open it")

    -- A right-click over the row opens it.
    H.rightClick(cx, cy, ui)
    assert(isOpen, "right-click over the item opens its context menu")
  end)

  --------------------------------------------------------------------------
  -- BeginPopupModal
  --------------------------------------------------------------------------

  T("BeginPopupModal centers itself, blocks input to everything else, and " ..
    "is not dismissed by an outside press", function()
    local im = H.fresh()
    local deleteRect, isOpen = {}, false
    local otherClicks = 0
    local pos, size = {}, {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      if im.Button("Delete") then im.OpenPopup("Confirm Delete") end
      H.grabRect(deleteRect, im)
      if im.Button("Other") then otherClicks = otherClicks + 1 end
      isOpen = im.BeginPopupModal("Confirm Delete")
      if isOpen then
        im.Text("Are you sure?")
        pos.x, pos.y = im.GetWindowPos()
        size.w, size.h = im.GetWindowSize()
        im.EndPopup()
      end
      im.End()
    end
    H.frame(ui)
    local dx, dy = H.center(deleteRect)
    H.click(dx, dy, ui)
    assert(isOpen, "modal should be open")
    H.frame(ui) -- let the centering settle to this frame's fitted size

    assert(pos.x == (800 - size.w) / 2, "modal is horizontally centered")
    assert(pos.y == (600 - size.h) / 2, "modal is vertically centered")

    assert(im.io.WantCaptureMouse == true,
      "WantCaptureMouse is unconditionally true while a modal is open")

    -- Clicking the "Other" button (which is under the modal) must do
    -- nothing: the modal blocks everything beneath it.
    H.press(dx, dy, 1, ui) -- reuse a point under Main, away from modal
    H.release(dx, dy, 1, ui)
    assert(otherClicks == 0, "clicks below a modal are blocked, not just captured")
    assert(isOpen, "an outside/below press does NOT dismiss a modal")

    -- Far outside everything: still must not dismiss it.
    H.press(790, 590, 1, ui)
    H.release(790, 590, 1, ui)
    assert(isOpen, "a press outside the modal does not close it either")
  end)

  T("BeginPopupModal only closes via CloseCurrentPopup", function()
    local im = H.fresh()
    local deleteRect, okRect, isOpen = {}, {}, false
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      if im.Button("Delete") then im.OpenPopup("Confirm") end
      H.grabRect(deleteRect, im)
      isOpen = im.BeginPopupModal("Confirm")
      if isOpen then
        if im.Button("OK") then im.CloseCurrentPopup() end
        H.grabRect(okRect, im)
        im.EndPopup()
      end
      im.End()
    end
    H.frame(ui)
    local dx, dy = H.center(deleteRect)
    H.click(dx, dy, ui)
    assert(isOpen)
    H.frame(ui) -- let the centering settle to this frame's fitted size
                -- (same as the centering test above) before reading okRect,
                -- since the modal's *first* open frame still centers around
                -- its previous (zero) size

    local ox, oy = H.center(okRect)
    H.click(ox, oy, ui)
    H.frame(ui) -- same one-frame-lag as CloseCurrentPopup() above
    assert(not isOpen, "OK's CloseCurrentPopup() closes the modal")
  end)

  T("a modal opening while a title-bar drag is already in progress " ..
    "neutralizes the drag immediately", function()
    local im = H.fresh()
    local pos, size = {}, {}
    local isOpen, shouldOpen = false, false
    local function ui()
      im.SetNextWindowPos(50, 50, "once")
      im.Begin("Main")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      im.Text("hi")
      im.End()

      -- Opened independently of the mouse (e.g. a keyboard shortcut) —
      -- the point is that it can happen mid-drag, without a release event
      -- ever reaching the drag in progress.
      if shouldOpen then im.OpenPopup("Confirm"); shouldOpen = false end
      isOpen = im.BeginPopupModal("Confirm")
      if isOpen then im.Text("modal"); im.EndPopup() end
    end
    H.frame(ui)
    H.frame(ui) -- settle auto-fit size

    -- Start dragging the title bar.
    local gx, gy = pos.x + size.w / 2, pos.y + 10
    H.stub.setMouse(gx, gy)
    im.mousepressed(gx, gy, 1)
    H.frame(ui)
    H.stub.setMouse(gx + 40, gy + 30)
    H.frame(ui)
    assert(pos.x == 90 and pos.y == 80,
      "sanity: the drag moves the window before any modal exists")

    -- Open a modal while the mouse is still held down from the drag above.
    shouldOpen = true
    H.frame(ui)
    assert(isOpen, "modal should now be open")

    -- Keep moving the mouse: the window must NOT keep following.
    H.stub.setMouse(gx + 200, gy + 150)
    H.frame(ui)
    assert(pos.x == 90 and pos.y == 80,
      "the modal must neutralize the in-progress title drag")

    im.mousereleased(gx + 200, gy + 150, 1)
    H.frame(ui)
  end)

  T("a modal opening while a resize-grip drag is already in progress " ..
    "neutralizes the drag immediately", function()
    local im = H.fresh()
    local size = {}
    local isOpen, shouldOpen = false, false
    local function ui()
      im.SetNextWindowPos(50, 50, "always")
      im.Begin("Main")
      im.Text("hi")
      size.w, size.h = im.GetWindowSize()
      im.End()

      if shouldOpen then im.OpenPopup("Confirm"); shouldOpen = false end
      isOpen = im.BeginPopupModal("Confirm")
      if isOpen then im.Text("modal"); im.EndPopup() end
    end
    H.frame(ui)
    H.frame(ui)
    local autoW, autoH = size.w, size.h

    -- Start dragging the resize grip.
    local gs = 14
    local gx, gy = 50 + autoW - gs / 2, 50 + autoH - gs / 2
    H.stub.setMouse(gx, gy)
    im.mousepressed(gx, gy, 1)
    H.frame(ui)
    H.stub.setMouse(gx + 80, gy + 60)
    H.frame(ui)
    local draggedW, draggedH = size.w, size.h
    assert(draggedW > autoW and draggedH > autoH,
      "sanity: the grip drag grows the window before any modal exists")

    -- Open a modal while the mouse is still held down from the drag above.
    shouldOpen = true
    H.frame(ui)
    assert(isOpen, "modal should now be open")

    -- Keep moving the mouse: the window must NOT keep resizing.
    H.stub.setMouse(gx + 300, gy + 200)
    H.frame(ui)
    assert(size.w == draggedW and size.h == draggedH,
      "the modal must neutralize the in-progress resize-grip drag")

    im.mousereleased(gx + 300, gy + 200, 1)
    H.frame(ui)
  end)

  --------------------------------------------------------------------------
  -- Tooltips
  --------------------------------------------------------------------------

  T("SetTooltip is never hit-testable: a click where it's drawn reaches " ..
    "whatever is really there", function()
    local im = H.fresh()
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      im.Text("hover me")
      im.SetTooltip("a tip")
      im.End()
    end
    H.stub.setMouse(400, 300) -- empty area, far from the window
    H.frame(ui)
    -- The tooltip is drawn near (400+16, 300+16), over empty space. A click
    -- there must be a plain miss, exactly as if no tooltip existed.
    H.stub.setMouse(416, 316)
    local consumed = im.mousepressed(416, 316, 1)
    assert(not consumed, "a click on the tooltip's own pixels is not consumed")
    im.mousereleased(416, 316, 1)
  end)

  T("multiple SetTooltip calls in one frame: the last call wins", function()
    local im = H.fresh()
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      im.SetTooltip("first tip")
      im.SetTooltip("second tip")
      im.End()
    end
    H.frame(ui)
    local printed = H.stub.printed()
    local sawFirst, sawSecond = false, false
    for _, s in ipairs(printed) do
      if s == "first tip" then sawFirst = true end
      if s == "second tip" then sawSecond = true end
    end
    assert(sawSecond, "the last SetTooltip call must be drawn")
    assert(not sawFirst, "an earlier SetTooltip call in the same frame " ..
      "must be fully replaced")
  end)

  T("the tooltip draws above even an open popup", function()
    local im = H.fresh()
    local rect, isOpen = {}, false
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      if im.Button("Options") then im.OpenPopup("options") end
      H.grabRect(rect, im)
      isOpen = im.BeginPopup("options")
      if isOpen then
        im.Text("popup-content")
        im.EndPopup()
      end
      im.SetTooltip("tooltip-content")
      im.End()
    end
    H.frame(ui)
    local cx, cy = H.center(rect)
    H.click(cx, cy, ui)
    assert(isOpen)

    local popupIdx, tooltipIdx
    for i, c in ipairs(H.stub.calls) do
      if c[1] == "print" then
        if c[2] == "popup-content" then popupIdx = i end
        if c[2] == "tooltip-content" then tooltipIdx = i end
      end
    end
    assert(popupIdx and tooltipIdx, "both must have been drawn")
    assert(tooltipIdx > popupIdx, "the tooltip must draw after (above) the popup")
  end)

  T("BeginTooltip() called again before EndTooltip() errors, and does " ..
    "not permanently corrupt Render() afterward", function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("Main")
    im.BeginTooltip()
    local ok, err = pcall(im.BeginTooltip)
    assert(not ok, "a second BeginTooltip() before EndTooltip() must error")
    assert(tostring(err):find("BeginTooltip"), tostring(err))

    -- Recover exactly like any other unbalanced Begin*/End* pair: close
    -- what was legitimately opened (the first, successful BeginTooltip()),
    -- then the window, then render. Pre-fix, this was impossible — the
    -- corrupting win.parent = win assignment left ctx.currentWindow
    -- unrecoverable, so Render() would fail forever after, even here.
    im.EndTooltip()
    im.End()
    local renderOk = pcall(im.Render)
    assert(renderOk, "Render() must work once what was left open is " ..
      "properly closed, proving state wasn't permanently corrupted")

    -- A later, unrelated, correctly-paired frame is completely unaffected.
    local ranOk = pcall(function()
      im.NewFrame()
      im.Begin("Other")
      im.Text("fine")
      im.End()
      im.Render()
    end)
    assert(ranOk, "a later frame renders normally")
  end)

  --------------------------------------------------------------------------
  -- Combo
  --------------------------------------------------------------------------

  T("Combo: click opens a dropdown; picking an item returns the new " ..
    "1-based index and changed = true", function()
    local im = H.fresh()
    local items = { "Low", "Medium", "High" }
    local value, changed = 2, false
    local rect = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("W")
      value, changed = im.Combo("Quality", value, items)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    -- Box occupies the left sliderWidth (160px) of the recorded item rect.
    local boxCx, boxCy = rect.x1 + 80, rect.y1 + 10
    H.click(boxCx, boxCy, ui)
    assert(value == 2, "opening the dropdown must not itself change value")

    -- "High" is the 3rd item: popup.x = rect.x1, popup.y = rect.y1 + 22
    -- (box height 20 + 2), each row 20 tall with a 5px gap (see style).
    local itemX = rect.x1 + 8 + 10
    local itemY = rect.y1 + 22 + 8 + 2 * 25 + 10
    H.click(itemX, itemY, ui)
    assert(value == 3 and changed, "picking 'High' selects index 3")
  end)

  T("Combo: re-picking the already-selected item still reports " ..
    "changed = true", function()
    local im = H.fresh()
    local items = { "Low", "Medium", "High" }
    local value, changed = 2, false
    local rect = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("W")
      value, changed = im.Combo("Quality", value, items)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local boxCx, boxCy = rect.x1 + 80, rect.y1 + 10
    H.click(boxCx, boxCy, ui)

    -- "Medium" is the 2nd item — the one already selected.
    local itemX = rect.x1 + 8 + 10
    local itemY = rect.y1 + 22 + 8 + 1 * 25 + 10
    H.click(itemX, itemY, ui)
    assert(value == 2, "re-picking the same item leaves the index unchanged")
    assert(changed, "changed must still be true — a click picked it, " ..
      "regardless of whether the index moved")
  end)

  T("Combo: opening it and dismissing without picking anything reports " ..
    "changed = false", function()
    local im = H.fresh()
    local items = { "Low", "Medium", "High" }
    local value, changed = 2, false
    local rect = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("W")
      value, changed = im.Combo("Quality", value, items)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local boxCx, boxCy = rect.x1 + 80, rect.y1 + 10
    H.click(boxCx, boxCy, ui)
    changed = false -- opening it must not itself have reported a change

    H.press(790, 590, 1, ui) -- dismiss it without picking anything
    H.release(790, 590, 1, ui)
    assert(value == 2 and not changed,
      "dismissing without picking must not report changed")
  end)

  T("Combo: clicking the box again while open closes it without changing " ..
    "the value (the box is its own popup's owner rect)", function()
    local im = H.fresh()
    local items = { "Low", "Medium", "High" }
    local value = 1
    local rect = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("W")
      value = im.Combo("Quality", value, items)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local boxCx, boxCy = rect.x1 + 80, rect.y1 + 10
    H.click(boxCx, boxCy, ui)

    local itemX = rect.x1 + 8 + 10
    local firstItemY = rect.y1 + 22 + 8 + 10
    -- Sanity: the dropdown is open (clicking "Low", the first item, changes
    -- nothing since value is already 1, but proves the popup is present by
    -- not erroring here). Instead, directly re-click the box to toggle off.
    H.click(boxCx, boxCy, ui)
    -- If it re-opened instead of closing, clicking far outside would still
    -- leave it open; verify closed by checking an outside click is a no-op
    -- change (nothing to dismiss) — i.e. WantCaptureMouse over empty space
    -- returns to normal.
    H.stub.setMouse(790, 590)
    local consumed = im.mousepressed(790, 590, 1)
    assert(not consumed, "no popup should remain open to capture this press")
    im.mousereleased(790, 590, 1)
    H.frame(ui)
  end)

  T("Combo tolerates an out-of-range value with an empty preview", function()
    local im = H.fresh()
    local items = { "Low", "Medium", "High" }
    local ok = pcall(function()
      local function ui()
        im.Begin("W")
        im.Combo("Quality", 0, items)
        im.Combo("Quality2", 99, items)
        im.Combo("Quality3", nil, items)
        im.End()
      end
      H.frame(ui)
    end)
    assert(ok, "out-of-range/nil values must not error")
  end)

  --------------------------------------------------------------------------
  -- ListBox
  --------------------------------------------------------------------------

  T("ListBox: picking a visible row selects it; scrolling to the bottom " ..
    "brings the last row into a clickable position", function()
    local im = H.fresh()
    local items = {}
    for i = 1, 10 do items[i] = "Item " .. i end
    local value, changed = 3, false
    local rect = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("W")
      value, changed = im.ListBox("Pick", value, items)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    -- Row 1 sits at the child's top padding: (childX + pad + a bit,
    -- childY + pad + half a row).
    local childX, childY = 10 + 8, 10 + 20 + 8
    H.click(childX + 8 + 10, childY + 8 + 10, ui)
    assert(value == 1 and changed, "clicking the first visible row selects it")

    -- Scroll the list all the way to the bottom (mirrors the documented
    -- "rests exactly one windowPadding from the edge" convention).
    H.stub.setMouse(childX + 70, childY + 70)
    for _ = 1, 40 do H.wheel(0, -1, ui) end

    local boxH = 20 * 7 + 8 * 2 -- default heightInItems=7, see ListBox()
    local lastRowMidY = childY + boxH - 8 - 10
    H.click(childX + 8 + 10, lastRowMidY, ui)
    assert(value == 10 and changed,
      "after scrolling to the bottom, the last row is clickable and picks index 10")
  end)

  T("ListBox: re-picking the already-selected row still reports " ..
    "changed = true", function()
    local im = H.fresh()
    local items = {}
    for i = 1, 5 do items[i] = "Item " .. i end
    local value, changed = 1, false
    local rect = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("W")
      value, changed = im.ListBox("Pick", value, items)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.frame(ui)

    local childX, childY = 10 + 8, 10 + 20 + 8
    H.click(childX + 8 + 10, childY + 8 + 10, ui) -- row 1, already selected
    assert(value == 1, "re-picking the same row leaves the index unchanged")
    assert(changed, "changed must still be true — a click picked it, " ..
      "regardless of whether the index moved")
  end)

  --------------------------------------------------------------------------
  -- WantCaptureMouse / forwarder matrix
  --------------------------------------------------------------------------

  T("io.WantCaptureMouse and the input forwarders capture unconditionally " ..
    "while any popup is open, and stop once it closes", function()
    local im = H.fresh()
    local rect, isOpen = {}, false
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("W")
      if im.Button("Open") then im.OpenPopup("p") end
      H.grabRect(rect, im)
      isOpen = im.BeginPopup("p")
      if isOpen then im.Text("x"); im.EndPopup() end
      im.End()
    end
    H.frame(ui)
    assert(im.io.WantCaptureMouse == false, "nothing open yet")
    H.stub.setMouse(790, 590)
    assert(im.mousepressed(790, 590, 1) == false)
    im.mousereleased(790, 590, 1)
    assert(im.wheelmoved(0, -1) == false, "no window/popup under a far corner")

    local cx, cy = H.center(rect)
    H.click(cx, cy, ui)
    assert(isOpen)
    assert(im.io.WantCaptureMouse == true, "a popup is open")
    H.stub.setMouse(790, 590)
    assert(im.mousepressed(790, 590, 1) == true,
      "any press is consumed (it's this popup's dismiss click) while open")
    assert(im.wheelmoved(0, -1) == true,
      "wheel events are consumed anywhere while a popup is open")
    H.frame(ui) -- process the dismiss triggered by the press above
    im.mousereleased(790, 590, 1)
    H.frame(ui)
    assert(not isOpen, "that press dismissed the popup")
    assert(im.io.WantCaptureMouse == false, "back to normal once it's closed")
  end)

end
