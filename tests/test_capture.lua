-- Input capture: the io.WantCaptureMouse / io.WantCaptureKeyboard flags and
-- the per-event return values of the forwarding functions. This is the
-- contract that lets a game share the mouse with the UI.

return function(T, H)

  local function standardUI(im)
    return function()
      im.SetNextWindowPos(100, 100, "always")
      im.Begin("W")
      im.SliderFloat("S", 5, 0, 10)
      im.End()
    end
  end

  T("WantCaptureMouse tracks whether the mouse is over a window", function()
    local im = H.fresh()
    local ui = standardUI(im)
    H.frame(ui)

    H.stub.setMouse(500, 400) -- open space
    H.frame(ui)
    assert(im.io.WantCaptureMouse == false,
      "mouse in open space: the game may use it")

    H.stub.setMouse(120, 130) -- inside the window
    H.frame(ui)
    assert(im.io.WantCaptureMouse == true,
      "mouse over a window: the game must ignore it")

    H.stub.setMouse(500, 400)
    H.frame(ui)
    assert(im.io.WantCaptureMouse == false, "and it releases again")
  end)

  T("mousepressed returns true only when the UI takes the press", function()
    local im = H.fresh()
    local ui = standardUI(im)
    H.frame(ui)

    assert(im.mousepressed(500, 400, 1) == false, "press in open space")
    H.frame(ui)
    im.mousereleased(500, 400, 1)
    H.frame(ui)

    assert(im.mousepressed(120, 130, 1) == true, "press over the window")
    H.frame(ui)
    im.mousereleased(120, 130, 1)
    H.frame(ui)
  end)

  T("a drag that leaves the window still captures the mouse", function()
    local im = H.fresh()
    local value, rect = 5, {}
    local function ui()
      im.SetNextWindowPos(100, 100, "always")
      im.Begin("W")
      value = im.SliderFloat("S", value, 0, 10)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local cx, cy = rect.x1 + 80, rect.y1 + 5

    H.stub.setMouse(cx, cy)
    im.mousepressed(cx, cy, 1)
    H.frame(ui)
    H.stub.setMouse(600, 500) -- drag far outside the window
    H.frame(ui)
    assert(im.io.WantCaptureMouse == true,
      "while a widget is held, the mouse belongs to the UI wherever it is")
    assert(im.mousereleased(600, 500, 1) == true,
      "the matching release belongs to the UI too")
    H.frame(ui)

    H.frame(ui)
    assert(im.io.WantCaptureMouse == false,
      "after the drag ends away from the window, capture is released")
  end)

  T("keyboard is never captured in v1", function()
    local im = H.fresh()
    local ui = standardUI(im)
    H.frame(ui)
    H.stub.setMouse(120, 130) -- even with the mouse over a window
    H.frame(ui)
    assert(im.io.WantCaptureKeyboard == false)
    assert(im.keypressed("a") == false)
    assert(im.textinput("a") == false)
  end)

  T("wheel events over a window are consumed, elsewhere are not", function()
    local im = H.fresh()
    local ui = standardUI(im)
    H.frame(ui)

    H.stub.setMouse(120, 130)
    H.frame(ui)
    assert(im.wheelmoved(0, 1) == true, "wheel over the window is the UI's")

    H.stub.setMouse(500, 400)
    H.frame(ui)
    assert(im.wheelmoved(0, 1) == false, "wheel in open space is the game's")
  end)

end
