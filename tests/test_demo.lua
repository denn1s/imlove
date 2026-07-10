--[[
imlove_demo.lua is a companion file, not part of the library, but it's also
imlove's most thorough integration test: it's an honest consumer of nothing
but the public API, and it touches nearly every widget, every popup kind, and
a second window in one run. This file drives it headless for a few dozen
frames, throwing a handful of simulated clicks at it along the way (opening
CollapsingHeaders, a regular popup, a right-click context popup, a modal, and
a second Begin/End window) — the goal is to catch crashes, ID-stack
imbalance, and any other API misuse in imlove_demo.lua itself, the same way
a real player mashing the demo would.

Click coordinates below were measured empirically (imlove.GetItemRectMin/Max
around each widget, against this exact stub/font/window geometry: 430x520
window at (20,20), 7px/char font, titleH=20, windowPadding=8) rather than
computed by hand — see the CollapsingHeader/Button/Selectable/Checkbox rects
this produces if imlove_demo.lua's content ever changes and these need
re-deriving.

demo state is private to imlove_demo.lua (by design — see its header
comment), so these tests can't assert on it directly. What they assert is
what test_require.lua asserts for imlove itself: the require returns the
right shape and leaks no globals — plus, implicitly, that none of the
interactions below raise an error (T() fails the test on any exception).
]]

return function(T, H)

  T("require imlove_demo works and leaks no globals", function()
    H.fresh() -- installs the stub and a fresh imlove *before* we snapshot _G
    package.loaded["imlove_demo"] = nil
    local before = {}
    for k in pairs(_G) do before[k] = true end

    local ShowDemoWindow = require "imlove_demo"

    assert(type(ShowDemoWindow) == "function",
      "require \"imlove_demo\" must return a bare function")
    for k in pairs(_G) do
      assert(before[k], "imlove_demo leaked a global: " .. tostring(k))
    end
  end)

  T("ShowDemoWindow runs many frames and survives a tour of every popup " ..
    "kind and a second window, without error", function()
    local im = H.fresh()
    package.loaded["imlove_demo"] = nil
    local ShowDemoWindow = require "imlove_demo"

    local open = true
    -- The UI body handed to H.frame/H.click/H.rightClick: those helpers own
    -- NewFrame()/Render(), this just builds one frame's content.
    local function step()
      open = ShowDemoWindow(open)
      assert(type(open) == "boolean", "open must stay a boolean")
    end

    -- A plain run: Help and Widgets are open by default (defaultOpen=true),
    -- so this alone already exercises buttons, checkboxes, radios, sliders,
    -- drags, a TreeNode, a flat Selectable list, a Combo, a ListBox, and the
    -- rolling PlotLines/PlotHistogram buffers.
    for _ = 1, 10 do H.frame(step) end

    -- Click "Click me" (28,289)-(96,309) and "A checkbox" (28,314)-(124,334).
    H.click(60, 299, step)
    H.click(75, 324, step)

    -- Scroll down and open "Layout" (measured at (28,486)-(432,506) after
    -- one wheelmoved(0, -25) with the mouse over the window).
    H.stub.setMouse(200, 200)
    im.wheelmoved(0, -25)
    H.frame(step)
    H.click(200, 486, step)

    -- Scroll again and open "Popups & tooltips" (measured at
    -- (28,497)-(432,517) after a further wheelmoved(0, -40)) -- this also
    -- exercises Layout's now-visible BeginChild region and item queries.
    H.stub.setMouse(200, 200)
    im.wheelmoved(0, -40)
    H.frame(step)
    H.click(200, 497, step)

    -- Scroll once more to bring Popups' content and the "Windows" header
    -- into view.
    H.stub.setMouse(200, 200)
    im.wheelmoved(0, -40)
    H.frame(step)

    -- Open the regular popup ("Open menu", (28,349)-(103,369)) and pick an
    -- entry ("Pick A", (85,379)-(139,399)) -- exercises OpenPopup/
    -- BeginPopup/Selectable/CloseCurrentPopup/EndPopup. A popup/modal only
    -- becomes hoverable starting the frame *after* it opens (ctx.hoveredWindow
    -- is computed once per NewFrame, so the very frame OpenPopup()/
    -- BeginPopup() first makes it exist is too early for a click to land on
    -- its own content) -- an idle H.frame() settles that one-frame lag before
    -- each popup's content gets clicked below.
    H.click(65, 359, step)
    H.frame(step)
    H.click(112, 389, step)

    -- Right-click "right-click me" ((28,399)-(432,419)) to open the
    -- context popup, then pick "Option 1" ((250,429)-(318,449)) --
    -- exercises BeginPopupContextItem.
    H.rightClick(230, 409, step)
    H.frame(step)
    H.click(280, 439, step)

    -- Open the delete confirmation modal ("Delete something",
    -- (28,468)-(152,488)) and confirm via "Delete##confirm"
    -- ((263,309)-(317,329)) -- exercises BeginPopupModal.
    H.click(90, 478, step)
    H.frame(step)
    H.click(290, 319, step)

    -- Open "Windows" ((28,512)-(432,532)), scroll to its content, and check
    -- "Show secondary window" ((28,487)-(201,507)) -- exercises a second,
    -- independently-flagged Begin()/End() pair driven from inside the demo.
    H.click(230, 522, step)
    H.stub.setMouse(200, 200)
    im.wheelmoved(0, -20)
    H.frame(step)
    H.click(114, 497, step)

    -- A few more idle frames with the secondary window now up.
    for _ = 1, 5 do H.frame(step) end

    -- Close the main demo window via its title-bar X ((430,20)-(450,40))
    -- and confirm the `open` round trip works, then reopen it exactly the
    -- way examples/demo.lua does.
    H.click(440, 30, step)
    assert(open == false, "clicking the close button must flip open to false")
    H.frame(step) -- one frame with open == false: window must not be submitted
    open = true
    H.frame(step) -- reopened
    assert(open == true)
  end)

end
