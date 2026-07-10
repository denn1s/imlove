--[[
v1.4 keyboard & text input: keyboard focus lifecycle and
io.WantCaptureKeyboard, InputText, InputFloat/InputInt, and ctrl-click-to-type
on the four slider/drag widgets.

Known stub geometry used throughout (see stub_love.lua and the style table):
  font: 7px/char wide, 14px tall     windowPadding = 8
  framePadding = {6, 3}              frameHeight = 14 + 3*2 = 20
  itemSpacing = {8, 5}               sliderWidth = 160 (also InputText's
  minWindowWidth = 60                  and InputFloat/InputInt's field width)
  default screen size: 800x600

Timing note that recurs throughout this file: io.WantCaptureKeyboard (and
what the keypressed()/textinput() forwarders return) is computed once at the
TOP of NewFrame(), from whatever ctx.focusId was at the END of the previous
frame — exactly the same one-frame lag io.WantCaptureMouse already has (see
tests/test_capture.lua's "drag that leaves the window" case). So after
focusing/defocusing a field mid-frame, an extra H.frame(ui) is needed before
the flag (or a forwarder's return value) reflects it — otherwise a
textinput()/keypressed() call would silently see the STALE flag and drop the
event.
]]

return function(T, H)

  local function backspaceN(n, ui)
    for i = 1, n do H.key("backspace", ui) end
  end

  --------------------------------------------------------------------------
  -- Focus lifecycle + io.WantCaptureKeyboard / forwarder return matrix
  --------------------------------------------------------------------------

  T("no field focused: keyboard is never captured, even with an unclicked " ..
    "InputText on screen", function()
    local im = H.fresh()
    local text = "hi"
    local function ui()
      im.Begin("W")
      text = im.InputText("Name", text)
      im.End()
    end
    H.frame(ui)
    assert(im.io.WantCaptureKeyboard == false)
    assert(im.keypressed("a") == false)
    assert(im.textinput("a") == false)
  end)

  T("clicking an InputText gives it focus, one frame later " ..
    "io.WantCaptureKeyboard and the forwarders reflect it", function()
    local im = H.fresh()
    local rect = {}
    local text = "hi"
    local function ui()
      im.Begin("W")
      text = im.InputText("Name", text)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local fx, fy = rect.x1 + 5, rect.y1 + 5
    H.click(fx, fy, ui)
    assert(im.io.WantCaptureKeyboard == false,
      "stale flag on the very frame focus was gained (one-frame lag)")

    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == true)
    assert(im.keypressed("a") == true,
      "keypressed is consumed while focused, regardless of the key")
    assert(im.textinput("x") == true)
  end)

  --------------------------------------------------------------------------
  -- InputText: typing, editing keys, commit/revert, EnterReturnsTrue
  --------------------------------------------------------------------------

  T("InputText: typing inserts at the cursor and returns changed = true " ..
    "on every keystroke by default", function()
    local im = H.fresh()
    local rect = {}
    local text, changed = "", nil
    local function ui()
      im.Begin("W")
      text, changed = im.InputText("Name", text)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local fx, fy = rect.x1 + 5, rect.y1 + 5
    H.click(fx, fy, ui)
    H.frame(ui) -- settle

    H.type("abc", ui)
    assert(text == "abc", "got " .. tostring(text))
    assert(changed == true)
  end)

  T("InputText: Backspace/Delete/Left/Right/Home/End all work", function()
    local im = H.fresh()
    local rect = {}
    local text = ""
    local function ui()
      im.Begin("W")
      text = im.InputText("Name", text)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle

    H.type("abcde", ui)
    assert(text == "abcde")
    H.key("home", ui)
    H.type("X", ui)
    assert(text == "Xabcde", "Home then type: got " .. text)
    H.key("end", ui)
    H.key("left", ui)
    H.key("left", ui) -- cursor now between "abc" and "de" (index 4 of "Xabcde")
    H.key("delete", ui)
    assert(text == "Xabce", "Delete removed the char at the cursor: got " .. text)
    H.key("backspace", ui)
    assert(text == "Xabe", "Backspace removed the char before the cursor: got "
      .. text)
  end)

  T("InputText: multi-byte UTF-8 is handled character-by-character, not " ..
    "byte-by-byte (exercises the pure-Lua fallback under plain luajit)",
    function()
    local im = H.fresh()
    local rect = {}
    local text = ""
    local function ui()
      im.Begin("W")
      text = im.InputText("Name", text)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle

    H.type("héllo", ui) -- "é" is a 2-byte UTF-8 sequence; 5 characters, 6 bytes
    assert(text == "héllo" and #text == 6, "got " .. text .. " (#" .. #text .. ")")

    H.key("left", ui)
    H.key("left", ui)
    H.key("left", ui) -- cursor now after "h" + "é" (2 characters, 3 bytes)
    H.key("backspace", ui) -- must delete the WHOLE "é", not one of its bytes
    assert(text == "hllo", "backspace over a multi-byte char: got " .. text)

    H.key("right", ui)
    H.type("Z", ui)
    assert(text == "hlZlo", "insertion position after the edit: got " .. text)
  end)

  T("InputText: Enter commits and defocuses; the committed text is " ..
    "whatever was typed", function()
    local im = H.fresh()
    local rect = {}
    local text = "old"
    local function ui()
      im.Begin("W")
      text = im.InputText("Name", text)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle

    backspaceN(3, ui)
    H.type("new", ui)
    assert(text == "new")
    H.key("return", ui)
    assert(text == "new", "Enter commits the typed text")

    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == false, "Enter defocuses the field")
  end)

  T("InputText: Escape reverts to the text the field had when it gained " ..
    "focus, and defocuses", function()
    local im = H.fresh()
    local rect = {}
    local text = "old"
    local function ui()
      im.Begin("W")
      text = im.InputText("Name", text)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle

    H.type("XXX", ui)
    assert(text == "oldXXX")
    H.key("escape", ui)
    assert(text == "old", "Escape reverts: got " .. text)

    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == false, "Escape defocuses the field")
  end)

  T("InputText: the 'EnterReturnsTrue' flag withholds changed/text until " ..
    "Enter, instead of live-updating on every keystroke", function()
    local im = H.fresh()
    local rect = {}
    local text, changed = "abc", nil
    local function ui()
      im.Begin("W")
      text, changed = im.InputText("Name", text, "EnterReturnsTrue")
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle

    H.type("d", ui)
    assert(text == "abc" and changed == false,
      "no live update while EnterReturnsTrue is set: got " .. tostring(text))

    H.key("return", ui)
    assert(text == "abcd" and changed == true,
      "commits exactly once, on the Enter frame: got " .. tostring(text))
  end)

  T("InputText: a click outside the field defocuses it WITHOUT consuming " ..
    "the click — it still reaches whatever it landed on", function()
    local im = H.fresh()
    local fieldRect, btnRect = {}, {}
    local text, clicks = "hi", 0
    local function ui()
      im.Begin("W")
      text = im.InputText("Name", text)
      H.grabRect(fieldRect, im)
      if im.Button("Elsewhere") then clicks = clicks + 1 end
      H.grabRect(btnRect, im)
      im.End()
    end
    H.frame(ui)
    H.click(fieldRect.x1 + 5, fieldRect.y1 + 5, ui)
    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == true)

    local bx, by = H.center(btnRect)
    H.click(bx, by, ui)
    assert(clicks == 1, "the click-away click still activated the button")

    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == false, "clicking away defocused the field")
  end)

  T("InputText: a focused field that stops being submitted loses focus " ..
    "(same lastFrame-staleness rule as windows/popups)", function()
    local im = H.fresh()
    local rect = {}
    local showField = true
    local text = "hi"
    local function ui()
      im.Begin("W")
      if showField then
        text = im.InputText("Name", text)
        H.grabRect(rect, im)
      end
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == true)

    showField = false
    H.frame(ui) -- one frame of grace, mirrors window/popup staleness
    H.frame(ui) -- second frame without a submission: now stale
    assert(im.io.WantCaptureKeyboard == false,
      "a field that stopped being submitted must give up focus")
  end)

  --------------------------------------------------------------------------
  -- InputFloat / InputInt
  --------------------------------------------------------------------------

  T("InputFloat: live-updates on every parseable keystroke, keeps the " ..
    "last good value on an unparseable intermediate state", function()
    local im = H.fresh()
    local rect = {}
    local value, changed = 0, nil
    local function ui()
      im.Begin("W")
      value, changed = im.InputFloat("F", value)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle

    backspaceN(#("0.000"), ui) -- clear the seeded "0.000" buffer
    H.type("3.5", ui)
    assert(value == 3.5 and changed == true, "got " .. tostring(value))

    H.type("-", ui) -- "3.5-" doesn't parse
    assert(value == 3.5 and changed == false,
      "an unparseable intermediate state must not commit garbage")

    H.key("escape", ui)
    assert(value == 0, "Escape reverts to the value at focus time")
  end)

  T("InputInt: floors a typed float on commit (3.7 commits as 3, not 4)",
    function()
    local im = H.fresh()
    local rect = {}
    local value = 0
    local function ui()
      im.Begin("W")
      value = im.InputInt("I", value)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle

    backspaceN(#("0"), ui)
    H.type("3.7", ui)
    H.key("return", ui)
    assert(value == 3, "InputInt floors, doesn't round: got " .. tostring(value))
  end)

  T("InputInt: an empty buffer on commit reverts instead of committing " ..
    "garbage", function()
    local im = H.fresh()
    local rect = {}
    local value = 5
    local function ui()
      im.Begin("W")
      value = im.InputInt("I", value)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle

    backspaceN(#("5"), ui)
    H.key("return", ui)
    assert(value == 5, "empty buffer commit reverts: got " .. tostring(value))
  end)

  T("InputFloat: the step buttons nudge the value directly, bypassing " ..
    "text parsing, and work even while not focused", function()
    local im = H.fresh()
    local rect = {}
    local value = 5
    local function ui()
      im.Begin("W")
      value = im.InputFloat("F", value, 0.5)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    -- Layout: field (160px) + gap(4) + minus(20x20) + gap(4) + plus(20x20).
    local fieldW, gap, btn = 160, 4, 20
    local minusCx = rect.x1 + fieldW + gap + btn / 2
    local plusCx  = rect.x1 + fieldW + gap * 2 + btn + btn / 2
    local cy = rect.y1 + btn / 2

    H.click(plusCx, cy, ui)
    assert(value == 5.5, "+ button: got " .. tostring(value))
    H.click(minusCx, cy, ui)
    H.click(minusCx, cy, ui)
    assert(value == 4.5, "- button: got " .. tostring(value))
  end)

  --------------------------------------------------------------------------
  -- Ctrl-click-to-type on SliderFloat/SliderInt/DragFloat/DragInt
  --------------------------------------------------------------------------

  T("SliderFloat: ctrl-click enters a numeric editor; Enter commits a " ..
    "clamped value; a plain click still works exactly as before", function()
    local im = H.fresh()
    local rect = {}
    local value, changed = 5, nil
    local function ui()
      im.Begin("W")
      value, changed = im.SliderFloat("S", value, 0, 10)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local cx, cy = rect.x1 + 5, rect.y1 + 5

    H.stub.setCtrl(true)
    H.click(cx, cy, ui)
    H.stub.setCtrl(false)
    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == true, "ctrl-click focuses the slider")

    backspaceN(#("5.000"), ui)
    H.type("999", ui) -- out of range
    H.key("return", ui)
    assert(value == 10 and changed == true,
      "commit clamps to max and reports changed = true: got "
      .. tostring(value) .. "/" .. tostring(changed))

    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == false, "commit released focus")

    -- A plain click still maps the track position to a value, unaffected.
    H.click(rect.x1 + 40, rect.y1 + 5, ui) -- 25% along a 160px 0..10 track
    assert(value == 2.5, "plain click still works: got " .. tostring(value))
  end)

  T("SliderFloat: Escape reverts the ctrl-click editor without committing",
    function()
    local im = H.fresh()
    local rect = {}
    local value = 5
    local function ui()
      im.Begin("W")
      value = im.SliderFloat("S", value, 0, 10)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.stub.setCtrl(true)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.stub.setCtrl(false)
    H.frame(ui) -- settle

    H.type("2", ui)
    H.key("escape", ui)
    assert(value == 5, "Escape reverts: got " .. tostring(value))
    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == false)
  end)

  T("SliderInt: ctrl-click-to-type rounds and clamps like its own " ..
    "click/drag math does", function()
    local im = H.fresh()
    local rect = {}
    local value, changed = 5, nil
    local function ui()
      im.Begin("W")
      value, changed = im.SliderInt("SI", value, 0, 10)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.stub.setCtrl(true)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.stub.setCtrl(false)
    H.frame(ui) -- settle

    backspaceN(#("5"), ui)
    H.type("50", ui) -- out of range
    H.key("return", ui)
    assert(value == 10 and changed == true,
      "commit clamps to max: got " .. tostring(value))
    assert(math.floor(value) == value)
  end)

  T("DragFloat: ctrl-click-to-type is unbounded by default, just like " ..
    "dragging is", function()
    local im = H.fresh()
    local rect = {}
    local value, changed = 5, nil
    local function ui()
      im.Begin("W")
      value, changed = im.DragFloat("D", value)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.stub.setCtrl(true)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.stub.setCtrl(false)
    H.frame(ui) -- settle

    backspaceN(#("5.000"), ui)
    H.type("123.5", ui)
    H.key("return", ui)
    assert(value == 123.5 and changed == true,
      "no clamping when min/max are nil: got " .. tostring(value))
  end)

  T("DragFloat: ctrl-click-to-type clamps when min/max are given", function()
    local im = H.fresh()
    local rect = {}
    local value = 5
    local function ui()
      im.Begin("W")
      value = im.DragFloat("D", value, 1, 0, 10)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.stub.setCtrl(true)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.stub.setCtrl(false)
    H.frame(ui) -- settle

    backspaceN(#("5.000"), ui)
    H.type("999", ui)
    H.key("return", ui)
    assert(value == 10, "clamped to the given max: got " .. tostring(value))
  end)

  T("DragInt: ctrl-click-to-type rounds to the nearest integer and " ..
    "reports changed = true on commit", function()
    local im = H.fresh()
    local rect = {}
    local value, changed = 5, nil
    local function ui()
      im.Begin("W")
      value, changed = im.DragInt("DI", value)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.stub.setCtrl(true)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.stub.setCtrl(false)
    H.frame(ui) -- settle

    backspaceN(#("5"), ui)
    H.type("42", ui)
    H.key("return", ui)
    assert(value == 42 and changed == true, "got " .. tostring(value))
    assert(math.floor(value) == value)
  end)

  --------------------------------------------------------------------------
  -- Clipboard: Ctrl+C copies the whole field, Ctrl+V pastes at the cursor
  --------------------------------------------------------------------------

  T("InputText: Ctrl+C copies the whole field, Ctrl+V pastes at the cursor",
    function()
    local im = H.fresh()
    local rect = {}
    local text = "hello world"
    local function ui()
      im.Begin("W")
      text = im.InputText("Name", text)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle

    H.stub.setCtrl(true)
    H.key("c", ui)
    assert(H.stub.clipboard == "hello world",
      "Ctrl+C copies the whole field: got " .. tostring(H.stub.clipboard))

    H.key("home", ui)
    H.stub.clipboard = "XYZ-"
    H.key("v", ui)
    H.stub.setCtrl(false)
    assert(text == "XYZ-hello world", "Ctrl+V pastes at the cursor: got " .. text)
  end)

  --------------------------------------------------------------------------
  -- Popups & modals
  --------------------------------------------------------------------------

  T("InputText works inside an open popup, and typing does not close it",
    function()
    local im = H.fresh()
    local openRect, fieldRect, isOpen = {}, {}, false
    local text = "hi"
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      if im.Button("Open") then im.OpenPopup("p") end
      H.grabRect(openRect, im)
      isOpen = im.BeginPopup("p")
      if isOpen then
        text = im.InputText("Name", text)
        H.grabRect(fieldRect, im)
        im.EndPopup()
      end
      im.End()
    end
    H.frame(ui)
    local ox, oy = H.center(openRect)
    H.click(ox, oy, ui)
    assert(isOpen, "popup should be open")
    H.frame(ui) -- settle the popup's fitted size, same as test_popups.lua

    H.click(fieldRect.x1 + 5, fieldRect.y1 + 5, ui)
    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == true,
      "a field inside a popup can gain focus")

    H.type("!!", ui)
    assert(text == "hi!!", "typed text applied inside the popup: " .. text)
    assert(isOpen, "typing must not close the popup")
  end)

  T("a field under an open modal cannot gain focus (blocked by the same " ..
    "hover gating a modal already applies to every widget beneath it)",
    function()
    local im = H.fresh()
    local deleteRect, fieldRect, isOpen = {}, {}, false
    local text = "orig"
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("Main")
      if im.Button("Delete") then im.OpenPopup("Confirm") end
      H.grabRect(deleteRect, im)
      text = im.InputText("Name", text)
      H.grabRect(fieldRect, im)
      isOpen = im.BeginPopupModal("Confirm")
      if isOpen then
        im.Text("sure?")
        im.EndPopup()
      end
      im.End()
    end
    H.frame(ui)
    local dx, dy = H.center(deleteRect)
    H.click(dx, dy, ui)
    assert(isOpen, "modal should be open")
    H.frame(ui) -- settle the modal's fitted centering

    H.press(fieldRect.x1 + 5, fieldRect.y1 + 5, 1, ui)
    H.release(fieldRect.x1 + 5, fieldRect.y1 + 5, 1, ui)
    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == false,
      "a field under an open modal must not gain focus")
    assert(text == "orig", "text is unchanged")
  end)

  --------------------------------------------------------------------------
  -- Regressions found by adversarial review of the v1.4 diff
  --------------------------------------------------------------------------

  -- Finding 1 (blocker): NewFrame()'s click-away check used to call
  -- clearFocus() before any widget ran, so a textinput()/keypressed() event
  -- latched in the SAME poll as a defocusing click had nobody left to drain
  -- ctx.frameEvents and was silently dropped. Fixed by deferring the actual
  -- clearFocus() to the owning widget (ctx.focusDefocusPending), which
  -- drains this frame's events first. These three tests hit the three call
  -- sites that pattern touches: InputText, numericInput() (InputFloat/
  -- InputInt), and numericEditOverlay() (ctrl-click sliders/drags).

  T("REGRESSION (finding 1): a textinput() event latched in the same poll " ..
    "as a defocusing click must still reach the field -- InputText",
    function()
    local im = H.fresh()
    local fieldRect, btnRect = {}, {}
    local text = "hi"
    local function ui()
      im.Begin("W")
      text = im.InputText("Name", text)
      H.grabRect(fieldRect, im)
      im.Button("Elsewhere")
      H.grabRect(btnRect, im)
      im.End()
    end
    H.frame(ui)
    H.click(fieldRect.x1 + 5, fieldRect.y1 + 5, ui)
    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == true)

    -- A textinput event AND an outside-click press, both latched before the
    -- next NewFrame() runs -- exactly how LOVE can deliver two events
    -- between one pair of update ticks.
    local bx, by = H.center(btnRect)
    H.stub.setMouse(bx, by)
    im.textinput("Z")
    im.mousepressed(bx, by, 1)
    H.frame(ui) -- both events drain in this single frame

    assert(text == "hiZ", "the keystroke must land in the field, not " ..
      "vanish into the defocusing click: got " .. tostring(text))
    assert(im.io.WantCaptureKeyboard == true,
      "still captured THIS frame -- one-frame lag, same as WantCaptureMouse")
    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == false,
      "the deferred click-away completes the frame after")
  end)

  T("REGRESSION (finding 1): same drop-on-defocus bug, for InputFloat's " ..
    "live-parsed buffer", function()
    local im = H.fresh()
    local fieldRect, btnRect = {}, {}
    local value = 0
    local function ui()
      im.Begin("W")
      value = im.InputFloat("F", value)
      H.grabRect(fieldRect, im)
      im.Button("Elsewhere")
      H.grabRect(btnRect, im)
      im.End()
    end
    H.frame(ui)
    H.click(fieldRect.x1 + 5, fieldRect.y1 + 5, ui)
    H.frame(ui) -- settle

    backspaceN(#("0.000"), ui)
    H.type("4", ui)
    assert(value == 4, "sanity: live-parsed before the click-away")

    local bx, by = H.center(btnRect)
    H.stub.setMouse(bx, by)
    im.textinput("2") -- would make the buffer "42"
    im.mousepressed(bx, by, 1) -- outside click, same poll
    H.frame(ui)

    assert(value == 42, "the digit must still be applied before the " ..
      "field loses focus, not dropped: got " .. tostring(value))
  end)

  T("REGRESSION (finding 1): same drop-on-defocus bug, for a ctrl-click " ..
    "numeric editor's Enter-commit landing in the same poll as the click " ..
    "that would otherwise silently defocus it", function()
    local im = H.fresh()
    local rect, btnRect = {}, {}
    local value = 5
    local function ui()
      im.Begin("W")
      value = im.SliderFloat("S", value, 0, 10)
      H.grabRect(rect, im)
      im.Button("Elsewhere")
      H.grabRect(btnRect, im)
      im.End()
    end
    H.frame(ui)
    H.stub.setCtrl(true)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.stub.setCtrl(false)
    H.frame(ui) -- settle

    backspaceN(#("5.000"), ui)
    H.type("8", ui)

    local bx, by = H.center(btnRect)
    H.stub.setMouse(bx, by)
    im.keypressed("return") -- commit
    im.mousepressed(bx, by, 1) -- outside click, same poll
    H.frame(ui)

    assert(value == 8, "Enter's commit must still land even though an " ..
      "outside click was latched in the very same poll: got " ..
      tostring(value))
  end)

  -- Finding 2 (major): numericInput()'s unfocused display branch was missing
  -- the pushClip/popClip InputText's own unfocused branch has, so a long
  -- committed value could paint over the step buttons and label.

  T("REGRESSION (finding 2): InputFloat's unfocused display is clipped to " ..
    "the field, same as InputText's, so a long value can't paint over the " ..
    "step buttons or label", function()
    local im = H.fresh()
    local rect = {}
    local value = 0
    local function ui()
      im.Begin("W")
      value = im.InputFloat("F", value, 0.1)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle

    backspaceN(#("0.000"), ui)
    H.type("1234567890123456789", ui) -- 19 digits: ~161px at 7px/char > 160px field

    -- drawEditField() (used while FOCUSED) already emits its own clip of the
    -- same width every typing frame above -- clear the log so the scissor
    -- calls inspected below can only have come from the commit/unfocused
    -- frame, isolating the branch this regression actually targets.
    H.stub.clearCalls()
    H.key("return", ui) -- commit + defocus: renders the unfocused branch

    local fieldW, fpx = 160, 6 -- style.sliderWidth, style.framePadding[1]
    local found = false
    for _, c in ipairs(H.stub.scissorCalls()) do
      if c[3] == fieldW - fpx * 2 then found = true end
    end
    assert(found, "the unfocused numeric display must be clipped to the " ..
      "field's own width (" .. (fieldW - fpx * 2) .. "px), not left to " ..
      "overflow")
  end)

  -- Finding 3 (minor): Ctrl+V used to splice clipboard text verbatim into a
  -- single-line field, so a multi-line paste broke the cursor/scroll math
  -- and drew multiple lines. Pasted \r is now stripped and \n flattened to
  -- a space, same as ImGui's own single-line InputText filters a paste.

  T("REGRESSION (finding 3): Ctrl+V flattens a multi-line clipboard paste " ..
    "into single-line text instead of splicing in raw newlines", function()
    local im = H.fresh()
    local rect = {}
    local text = ""
    local function ui()
      im.Begin("W")
      text = im.InputText("Name", text)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle

    H.stub.clipboard = "line one\r\nline two\nline three"
    H.stub.setCtrl(true)
    H.key("v", ui)
    H.stub.setCtrl(false)
    assert(text == "line one line two line three",
      "CRLF and LF must both flatten to a single space, no raw \\r or " ..
      "\\n left in the buffer: got " .. string.format("%q", text))
  end)

  -- Finding 4 (nit): the `if focused then clearFocus() end` guard inside
  -- InputFloat/InputInt's step-button handlers was dead code even before
  -- finding 1's fix (the button's rect always lies outside the field's own
  -- focusRect, so the generic click-away already ends focus before the step
  -- handlers run) -- and stays dead after the fix too, since the deferred
  -- defocus is now finalized earlier in the SAME call, before the step
  -- buttons are even evaluated (see numericInput()'s comment on this). The
  -- dead lines were deleted; this test pins the actual behavior instead: a
  -- step-click while the field is still showing its editor applies the live
  -- typed buffer first, then steps from THAT, and cleanly ends editing.

  T("REGRESSION (finding 4): clicking a step button while its field's " ..
    "editor is still open steps from the live typed buffer, not the " ..
    "stale original value, and cleanly ends editing", function()
    local im = H.fresh()
    local rect = {}
    local value, changed = 1.5, nil
    local function ui()
      im.Begin("W")
      value, changed = im.InputFloat("F", value, 0.1)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    H.click(rect.x1 + 5, rect.y1 + 5, ui)
    H.frame(ui) -- settle
    assert(im.io.WantCaptureKeyboard == true)

    backspaceN(#("1.500"), ui)
    H.type("5", ui) -- live buffer is "5", not yet committed via Enter
    assert(value == 5 and changed == true,
      "live-parsed before the step click: got " .. tostring(value))

    -- Layout: field (160px) + gap(4) + minus(20x20) + gap(4) + plus(20x20).
    local fieldW, gap, btn = 160, 4, 20
    local plusCx = rect.x1 + fieldW + gap * 2 + btn + btn / 2
    local cy = rect.y1 + btn / 2
    H.click(plusCx, cy, ui) -- click "+" while the editor is still open

    assert(value == 5.1, "steps from the live buffer (5), not the stale " ..
      "original (1.5): got " .. tostring(value))
    assert(im.io.WantCaptureKeyboard == false,
      "the field's own editor is no longer open after a step-click")
  end)

end
