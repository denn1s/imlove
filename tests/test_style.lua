--[[
v1.5: style & polish — PushStyleColor/PopStyleColor, PushStyleVar/
PopStyleVar, GetStyle, PushFont/PopFont, ColorEdit3/ColorEdit4.

Known stub geometry (see stub_love.lua and the style table):
  font: 7px/char wide, 14px tall     windowPadding = 8
  framePadding = {6, 3}              titleH = 14 + 3*2 = 20
  itemSpacing = {8, 5}               frameHeight = 14 + 3*2 = 20
  minWindowWidth = 60                sliderWidth = 160
  default screen size: 800x600

A "second font" for the PushFont tests is not the stub's shared font object
(stub_love.lua's love.graphics.newFont() always returns that one, regardless
of arguments) — it's a plain Lua table built right here, satisfying the same
duck-typed Font interface (:getWidth()/:getHeight()) every widget already
uses. PushFont() never checks a type, only ever calls those two methods (and
:getWrap() for TextWrapped, unused by these tests), so this is exactly as
legitimate as passing a real love.graphics.newFont() result.
]]

local bigFont = {}
function bigFont:getWidth(text) return #tostring(text) * 14 end
function bigFont:getHeight() return 28 end

return function(T, H)

  --------------------------------------------------------------------------
  -- PushStyleColor / PopStyleColor
  --------------------------------------------------------------------------

  T("PushStyleColor/PopStyleColor: draw commands capture a COLOR TABLE " ..
    "REFERENCE, so a push/pop pair around one widget affects only that " ..
    "widget's drawn color", function()
    local im = H.fresh()
    local red = { 1, 0, 0, 1 }
    local defaultRef -- the original style.colors.button table, captured live
    local function ui()
      im.Begin("W")
      defaultRef = im.GetStyle().colors.button
      im.Button("A") -- before the push: default color
      im.PushStyleColor("button", red)
      im.Button("B") -- wrapped: red
      im.PopStyleColor()
      im.Button("C") -- after the pop: default color again
      im.End()
    end
    H.frame(ui)

    -- Every "fill" rectangle, paired with whatever setColor() call drew it
    -- (Render() always calls g.setColor(c.color) immediately before the
    -- matching draw call — see playDrawList()). The window itself draws two
    -- fills first (background, title bar), then one per button in order.
    local fills = {}
    for i, c in ipairs(H.stub.calls) do
      if c[1] == "rectangle" and c[2] == "fill" then
        local prev = H.stub.calls[i - 1]
        fills[#fills + 1] = prev and prev[1] == "setColor" and prev[2] or nil
      end
    end
    local colorA, colorB, colorC = fills[3], fills[4], fills[5]
    assert(colorA == defaultRef, "Button A must draw with the default table")
    assert(colorB == red, "Button B must draw with the exact pushed table")
    assert(colorC == defaultRef,
      "Button C must draw with the default table again, same reference " ..
      "PopStyleColor() restored")
    assert(colorA ~= red and colorC ~= red)
  end)

  T("PushStyleColor: nested pushes restore in LIFO order", function()
    local im = H.fresh()
    local a, b = { 1, 0, 0, 1 }, { 0, 1, 0, 1 }
    local original = im.GetStyle().colors.text
    im.PushStyleColor("text", a)
    assert(im.GetStyle().colors.text == a)
    im.PushStyleColor("text", b)
    assert(im.GetStyle().colors.text == b)
    im.PopStyleColor()
    assert(im.GetStyle().colors.text == a, "must unwind to the first push")
    im.PopStyleColor()
    assert(im.GetStyle().colors.text == original, "must unwind to the original")
  end)

  T("PopStyleColor(count) pops several at once", function()
    local im = H.fresh()
    local originalButton = im.GetStyle().colors.button
    local originalText = im.GetStyle().colors.text
    local originalBorder = im.GetStyle().colors.border
    im.PushStyleColor("button", { 1, 0, 0, 1 })
    im.PushStyleColor("text", { 0, 1, 0, 1 })
    im.PushStyleColor("border", { 0, 0, 1, 1 })
    im.PopStyleColor(3)
    assert(im.GetStyle().colors.button == originalButton)
    assert(im.GetStyle().colors.text == originalText)
    assert(im.GetStyle().colors.border == originalBorder)
  end)

  T("PushStyleColor: unknown color name errors immediately", function()
    local im = H.fresh()
    local ok, err = pcall(im.PushStyleColor, "bogus", { 1, 1, 1, 1 })
    assert(not ok and err:find("unknown") and err:find("bogus"), tostring(err))
  end)

  T("PopStyleColor with nothing pushed errors", function()
    local im = H.fresh()
    local ok, err = pcall(im.PopStyleColor)
    assert(not ok and err:find("no matching"), tostring(err))
  end)

  T("an unbalanced PushStyleColor is caught by Render(), not immediately",
    function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("W")
    im.PushStyleColor("button", { 1, 0, 0, 1 })
    im.End()
    local ok, err = pcall(im.Render)
    assert(not ok and err:find("PushStyleColor") and err:find("unpopped"),
      tostring(err))
  end)

  T("regression: an unbalanced PushStyleColor does not brick the UI -- " ..
    "Render() unwinds the stack, restores the default color, and the next " ..
    "frame works normally", function()
    local im = H.fresh()
    local defaultButton = im.GetStyle().colors.button
    im.NewFrame()
    im.Begin("W")
    im.PushStyleColor("button", { 1, 0, 0, 1 }) -- never popped (e.g. an
                                                 -- early return in game code)
    im.End()
    local ok = pcall(im.Render)
    assert(not ok, "Render() must still error the offending frame")
    assert(im.GetStyle().colors.button == defaultButton,
      "the shadowed color must be restored, not left corrupted forever")

    -- A pcall'd Render() must not leave ctx.inFrame stuck true: NewFrame()
    -- would otherwise error "called twice" on every frame for the rest of
    -- the process, even after the game fixes its missing PopStyleColor().
    local ok2 = pcall(function()
      im.NewFrame()
      im.Begin("W2")
      im.Button("normal button")
      im.End()
      im.Render()
    end)
    assert(ok2, "a clean frame right after the error must succeed")
  end)

  --------------------------------------------------------------------------
  -- PushStyleVar / PopStyleVar
  --------------------------------------------------------------------------

  T("PushStyleVar: unknown var name errors immediately", function()
    local im = H.fresh()
    local ok, err = pcall(im.PushStyleVar, "bogus", 1)
    assert(not ok and err:find("unknown") and err:find("bogus"), tostring(err))
  end)

  T("PushStyleVar: wrong shape for a scalar var errors", function()
    local im = H.fresh()
    local ok, err = pcall(im.PushStyleVar, "rounding", { 1, 2 })
    assert(not ok and err:find("rounding") and err:find("number"),
      tostring(err))
  end)

  T("PushStyleVar: wrong shape for a pair var errors", function()
    local im = H.fresh()
    local ok, err = pcall(im.PushStyleVar, "framePadding", 5)
    assert(not ok and err:find("framePadding"), tostring(err))
  end)

  T("an unbalanced PushStyleVar is caught by Render()", function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("W")
    im.PushStyleVar("rounding", 10)
    im.End()
    local ok, err = pcall(im.Render)
    assert(not ok and err:find("PushStyleVar") and err:find("unpopped"),
      tostring(err))
  end)

  T("regression: an unbalanced PushStyleVar does not brick the UI -- " ..
    "Render() unwinds the stack, restores the default value, and the next " ..
    "frame works normally", function()
    local im = H.fresh()
    local defaultRounding = im.GetStyle().rounding
    im.NewFrame()
    im.Begin("W")
    im.PushStyleVar("rounding", 10) -- never popped
    im.End()
    local ok = pcall(im.Render)
    assert(not ok, "Render() must still error the offending frame")
    assert(im.GetStyle().rounding == defaultRounding,
      "the shadowed var must be restored, not left corrupted forever")

    local ok2 = pcall(function()
      im.NewFrame()
      im.Begin("W2")
      im.Button("normal button")
      im.End()
      im.Render()
    end)
    assert(ok2, "a clean frame right after the error must succeed")
  end)

  T("PushStyleVar('framePadding', ...) changes Button geometry", function()
    local im = H.fresh()
    local rectDefault, rectPadded = {}, {}
    local function ui()
      im.Begin("W")
      im.Button("X")
      H.grabRect(rectDefault, im)
      im.PushStyleVar("framePadding", { 20, 20 })
      im.Button("Y")
      H.grabRect(rectPadded, im)
      im.PopStyleVar()
      im.End()
    end
    H.frame(ui)
    local wDefault = rectDefault.x2 - rectDefault.x1
    local hDefault = rectDefault.y2 - rectDefault.y1
    local wPadded = rectPadded.x2 - rectPadded.x1
    local hPadded = rectPadded.y2 - rectPadded.y1
    assert(hDefault == 20, "default: 14 + 3*2")
    assert(hPadded == 54, "padded: 14 + 20*2, got " .. hPadded)
    assert(wPadded > wDefault, "wider frame padding must widen the button too")
  end)

  T("PushStyleVar('itemSpacing', ...) changes the cursor advance between " ..
    "widgets", function()
    local im = H.fresh()
    local rectA, rectB = {}, {}
    local function ui()
      im.Begin("W")
      im.PushStyleVar("itemSpacing", { 8, 50 })
      im.Button("A")
      H.grabRect(rectA, im)
      im.Button("B")
      H.grabRect(rectB, im)
      im.PopStyleVar()
      im.End()
    end
    H.frame(ui)
    local gap = rectB.y1 - rectA.y2
    assert(gap == 50, "expected a 50px gap, got " .. tostring(gap))
  end)

  T("regression: windowPadding is locked at Begin() -- pushing it AFTER " ..
    "Begin (balanced by popping before End) has NO effect on that window " ..
    "at all, not a lopsided mix of old margin + new auto-fit size",
    function()
    local imBase = H.fresh()
    local sizeBase = {}
    local function uiBase()
      imBase.Begin("W")
      sizeBase.w, sizeBase.h = imBase.GetWindowSize()
      imBase.Text("x")
      imBase.End()
    end
    H.frame(uiBase)
    H.frame(uiBase) -- GetWindowSize reports last frame's settled size

    local imPushed = H.fresh()
    local sizePushed = {}
    local function uiPushed()
      imPushed.Begin("W")
      sizePushed.w, sizePushed.h = imPushed.GetWindowSize()
      imPushed.PushStyleVar("windowPadding", 40) -- after Begin: too late to
                                                  -- affect THIS window
      imPushed.Text("x")
      imPushed.PopStyleVar()
      imPushed.End()
    end
    H.frame(uiPushed)
    H.frame(uiPushed)

    assert(sizePushed.w == sizeBase.w and sizePushed.h == sizeBase.h,
      ("a windowPadding pushed after Begin() must not change this " ..
       "window's size at all -- got %dx%d vs no-push baseline %dx%d")
        :format(sizePushed.w, sizePushed.h, sizeBase.w, sizeBase.h))
  end)

  T("regression: windowPadding pushed BEFORE Begin pads the window " ..
    "symmetrically -- the left/top margin and the auto-fit size agree",
    function()
    local im = H.fresh()
    local size = {}
    local function ui()
      im.PushStyleVar("windowPadding", 40)
      im.Begin("W")
      size.w, size.h = im.GetWindowSize()
      im.Text("x")
      im.End()
      im.PopStyleVar()
    end
    H.frame(ui)
    H.frame(ui)

    -- One line of "x" (stub font: 7px/char, 14px tall); titleH = 14 + 3*2.
    local expectedW = 40 * 2 + 7
    local expectedH = 20 + 40 * 2 + 14
    assert(size.w == expectedW,
      ("expected symmetric left+right padding (%d), got %d")
        :format(expectedW, size.w))
    assert(size.h == expectedH,
      ("expected symmetric top+bottom padding (%d), got %d")
        :format(expectedH, size.h))
  end)

  --------------------------------------------------------------------------
  -- GetStyle
  --------------------------------------------------------------------------

  T("GetStyle returns the live style table: a direct mutation takes " ..
    "effect immediately", function()
    local im = H.fresh()
    local mutated = { 0.1, 0.2, 0.3, 1 }
    im.GetStyle().colors.text = mutated
    local function ui()
      im.Begin("W")
      im.Text("hi")
      im.End()
    end
    H.frame(ui)
    local found = false
    for i, c in ipairs(H.stub.calls) do
      if c[1] == "print" and c[2] == "hi" then
        local prev = H.stub.calls[i - 1]
        found = prev and prev[1] == "setColor" and prev[2] == mutated
      end
    end
    assert(found, "Text() must have drawn with the mutated color table")
  end)

  --------------------------------------------------------------------------
  -- ColorEdit3 / ColorEdit4
  --------------------------------------------------------------------------

  T("ColorEdit4: click opens a popup; dragging a channel slider returns " ..
    "a NEW table with changed = true, leaving the original untouched",
    function()
    local im = H.fresh()
    local color = { 0.20, 0.30, 0.40, 1.00 }
    local original = color
    local changed, rect = false, {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("W")
      color, changed = im.ColorEdit4("Tint", color)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    assert(color == original, "must not change before anything is clicked")

    -- Swatch occupies the left (frameHeight*2 = 40px) of the item rect.
    local swatchCx, swatchCy = rect.x1 + 20, rect.y1 + 10
    H.click(swatchCx, swatchCy, ui)
    assert(color == original, "opening the popup must not itself change it")

    -- Popup content starts at (rect.x1 + 8, rect.y1 + 22 + 8): anchored at
    -- (swatchX, swatchY + swatchH + 2) with an 8px window padding, no title
    -- bar (see beginPopupContent()/colorEdit()). The R slider is the first
    -- widget in it, track width 160 (style.sliderWidth).
    --
    -- Press only (not a full click): a slider's own "changed" is true on the
    -- PRESS frame that maps the click to a new value, but false again once
    -- the mouse is released and it's handed the already-updated value back
    -- (nothing left to change) — the same reason
    -- "SliderFloat keeps dragging while held" in test_widgets.lua checks
    -- `changed` mid-drag, not after a full H.click().
    local rTrackX, rTrackY = rect.x1 + 8, rect.y1 + 30
    H.press(rTrackX + 0.75 * 160, rTrackY + 10, 1, ui) -- ~75% along R's track
    assert(changed, "dragging a channel slider must report changed = true")
    assert(color ~= original, "must be a NEW table, not a mutation")
    assert(math.abs(color[1] - 0.75) < 0.03,
      "R must follow the click, got " .. tostring(color[1]))
    assert(math.abs(color[2] - 0.30) < 1e-9, "G must be untouched")
    assert(math.abs(color[3] - 0.40) < 1e-9, "B must be untouched")
    assert(math.abs(color[4] - 1.00) < 1e-9, "A must be untouched")
    assert(original[1] == 0.20, "the ORIGINAL table must never be mutated")
    H.release(rTrackX + 0.75 * 160, rTrackY + 10, 1, ui) -- let go, for hygiene
  end)

  T("ColorEdit3 leaves alpha alone: a 4th channel on the input table " ..
    "passes through unchanged, and a 3-element input stays 3-element",
    function()
    local im = H.fresh()
    local withAlpha = { 0.20, 0.30, 0.40, 0.5 }
    local rect = {}
    local function ui()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("W")
      withAlpha = im.ColorEdit3("Tint3", withAlpha)
      H.grabRect(rect, im)
      im.End()
    end
    H.frame(ui)
    local swatchCx, swatchCy = rect.x1 + 20, rect.y1 + 10
    H.click(swatchCx, swatchCy, ui)
    local rTrackX, rTrackY = rect.x1 + 8, rect.y1 + 30
    H.click(rTrackX + 0.5 * 160, rTrackY + 10, ui)
    assert(math.abs(withAlpha[4] - 0.5) < 1e-9,
      "ColorEdit3 must never touch a pre-existing 4th channel")

    -- A genuinely 3-element input stays 3-element (no phantom alpha).
    local noAlpha = { 0.1, 0.2, 0.3 }
    local rect2 = {}
    local function ui2()
      im.SetNextWindowPos(10, 10, "always")
      im.Begin("W2")
      noAlpha = im.ColorEdit3("Tint3b", noAlpha)
      H.grabRect(rect2, im)
      im.End()
    end
    H.frame(ui2)
    local cx2, cy2 = rect2.x1 + 20, rect2.y1 + 10
    H.click(cx2, cy2, ui2)
    local trackX2, trackY2 = rect2.x1 + 8, rect2.y1 + 30
    H.click(trackX2 + 0.5 * 160, trackY2 + 10, ui2)
    assert(noAlpha[4] == nil, "must not invent a 4th channel")
  end)

  --------------------------------------------------------------------------
  -- PushFont / PopFont
  --------------------------------------------------------------------------

  T("PushFont changes measured layout and which font each text draw " ..
    "carries; PopFont restores both", function()
    local im = H.fresh()
    local defaultFont = H.stub.font
    local rectPlain1, rectBig, rectPlain2 = {}, {}, {}
    local function ui()
      im.Begin("W")
      im.Text("Hi")
      H.grabRect(rectPlain1, im)
      im.PushFont(bigFont)
      im.Text("Hi")
      H.grabRect(rectBig, im)
      im.PopFont()
      im.Text("Hi")
      H.grabRect(rectPlain2, im)
      im.End()
    end
    H.frame(ui)

    -- Layout: default font is 7px/char, 14px tall; bigFont is 14px/char,
    -- 28px tall — "Hi" is 2 characters.
    assert(rectPlain1.x2 - rectPlain1.x1 == 14)
    assert(rectPlain1.y2 - rectPlain1.y1 == 14)
    assert(rectBig.x2 - rectBig.x1 == 28, "PushFont must affect measuring")
    assert(rectBig.y2 - rectBig.y1 == 28)
    assert(rectPlain2.x2 - rectPlain2.x1 == 14, "PopFont must restore it")
    assert(rectPlain2.y2 - rectPlain2.y1 == 14)

    -- Drawing: each text command carries its own font, and Render() only
    -- calls setFont() where the font actually changes (see playDrawList()'s
    -- currentDrawFont tracking) — not once per text command.
    local fontCalls = {}
    for _, c in ipairs(H.stub.calls) do
      if c[1] == "setFont" then fontCalls[#fontCalls + 1] = c[2] end
    end
    assert(#fontCalls == 4,
      "expected 4 setFont calls (initial, to bigFont, back to default, " ..
      "final restore), got " .. #fontCalls)
    assert(fontCalls[1] == defaultFont)
    assert(fontCalls[2] == bigFont)
    assert(fontCalls[3] == defaultFont)
    assert(fontCalls[4] == defaultFont)
  end)

  T("PopFont with nothing pushed errors", function()
    local im = H.fresh()
    local ok, err = pcall(im.PopFont)
    assert(not ok and err:find("no matching"), tostring(err))
  end)

  T("an unbalanced PushFont is caught by Render()", function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("W")
    im.PushFont(bigFont)
    im.End()
    local ok, err = pcall(im.Render)
    assert(not ok and err:find("PushFont") and err:find("unpopped"),
      tostring(err))
  end)

  T("regression: an unbalanced PushFont does not brick the UI -- Render() " ..
    "unwinds the stack, restores the default font, and the next frame " ..
    "works normally", function()
    local im = H.fresh()
    local defaultFont = H.stub.font
    im.NewFrame()
    im.Begin("W")
    im.PushFont(bigFont) -- never popped
    im.End()
    local ok = pcall(im.Render)
    assert(not ok, "Render() must still error the offending frame")

    -- NewFrame() resets ctx.font to the base font every frame regardless,
    -- so the real risk here is the stale fontStack entry and ctx.inFrame
    -- being left true -- both must be cleaned up by the failed Render().
    local rect = {}
    local ok2 = pcall(function()
      im.NewFrame()
      im.Begin("W2")
      im.Text("Hi")
      H.grabRect(rect, im)
      im.End()
      im.Render()
    end)
    assert(ok2, "a clean frame right after the error must succeed")
    assert(rect.x2 - rect.x1 == 14,
      "the next frame's text must measure with the default font again, " ..
      "not a leftover bigFont")
  end)

  T("regression: PushFont(nil) and PushFont(42) error immediately instead " ..
    "of crashing frames later inside textSize()/Render()", function()
    local im = H.fresh()
    local ok1, err1 = pcall(im.PushFont, nil)
    assert(not ok1 and err1:find("PushFont") and err1:find("Font"),
      tostring(err1))
    local ok2, err2 = pcall(im.PushFont, 42)
    assert(not ok2 and err2:find("PushFont") and err2:find("Font"),
      tostring(err2))

    -- Must not have partially pushed before failing (nothing left to unwind).
    im.NewFrame()
    im.Begin("W")
    im.Button("ok")
    im.End()
    local ok3 = pcall(im.Render)
    assert(ok3, "a rejected PushFont() must leave no stray fontStack entry")
  end)

end
