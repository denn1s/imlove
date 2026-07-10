--[[
Settings persistence: imlove.io.IniFilename, SaveIniSettings()/
LoadIniSettings(), and the write-on-change lifecycle wired into NewFrame()/
Begin()/Render() (see the "Settings persistence" section in imlove.lua).

Most tests here use H.fresh() like everywhere else, which gives each test its
own empty in-memory "disk" (stub_love.lua's stub.files, reset in
stub.install()). The round-trip test is the one exception: it needs the fake
disk to survive a module reload, so it re-requires "imlove" directly instead
of going through H.fresh() a second time — see the comment on that test.

Known stub geometry (see stub_love.lua and the style table):
  font: 7px/char wide, 14px tall     windowPadding = 8
  framePadding = {6, 3}              titleH = 14 + 3*2 = 20
  minWindowWidth = 60                gripSize = 14
]]

return function(T, H)

  T("round trip: position, size, and collapsed state survive a save, a "
    .. "module reload, and a load — and only the explicitly-sized window's "
    .. "size is persisted", function()
    local im = H.fresh()

    -- Window "Fixed": drag it, then give it an explicit size, then collapse
    -- it — all three persisted fields get exercised.
    local fixedPos, fixedSize, fixedState = {}, {}, {}
    -- Window "Auto": never explicitly sized, moved once. Only its position
    -- (and un-collapsed state) should survive; no Size= line for it at all.
    local autoPos = {}
    local function ui()
      im.Begin("Fixed")
      fixedPos.x, fixedPos.y = im.GetWindowPos()
      fixedSize.w, fixedSize.h = im.GetWindowSize()
      im.Text("fixed window content")
      im.End()

      im.Begin("Auto")
      autoPos.x, autoPos.y = im.GetWindowPos()
      im.Text("auto-fit window content")
      im.End()
    end

    H.frame(ui)
    H.frame(ui)

    -- Move "Auto" FIRST, far away, while it's still the frontmost cascaded
    -- window (both windows heavily overlap at their cascade defaults) — this
    -- sidesteps any ambiguity about which window a later click lands on:
    -- once "Fixed" starts getting dragged/resized below, it will get raised
    -- in front and could otherwise shadow Auto's original position.
    local ax0, ay0 = autoPos.x, autoPos.y
    local agx, agy = ax0 + 30, ay0 + 10
    H.stub.setMouse(agx, agy)
    im.mousepressed(agx, agy, 1)
    H.frame(ui)
    H.stub.setMouse(agx + 300, agy + 260)
    H.frame(ui)
    im.mousereleased(agx + 300, agy + 260, 1)
    H.frame(ui)

    -- Move "Fixed" by dragging its title bar. Auto is now far out of the
    -- way, so this (and everything below) can't accidentally land on it.
    local x0, y0 = fixedPos.x, fixedPos.y
    local gx, gy = x0 + fixedSize.w / 2, y0 + 10
    H.stub.setMouse(gx, gy)
    im.mousepressed(gx, gy, 1)
    H.frame(ui)
    H.stub.setMouse(gx + 55, gy + 30)
    H.frame(ui)
    im.mousereleased(gx + 55, gy + 30, 1)
    H.frame(ui)

    -- Give "Fixed" an explicit size via the resize grip.
    local fx, fy = fixedPos.x, fixedPos.y
    local fw, fh = fixedSize.w, fixedSize.h
    local gs = 14
    local rgx, rgy = fx + fw - gs / 2, fy + fh - gs / 2
    H.stub.setMouse(rgx, rgy)
    im.mousepressed(rgx, rgy, 1)
    H.frame(ui)
    H.stub.setMouse(rgx + 40, rgy + 25)
    H.frame(ui)
    im.mousereleased(rgx + 40, rgy + 25, 1)
    H.frame(ui)

    -- Collapse "Fixed".
    H.click(fixedPos.x + 10, fixedPos.y + 10, ui)
    H.frame(ui)
    fixedState.collapsedX, fixedState.collapsedY = fixedPos.x, fixedPos.y

    -- The collapse click's Render() already wrote the file (write-on-change,
    -- see imlove.SaveIniSettings()); one more frame to be safe.
    H.frame(ui)

    local savedIni = H.stub.files["imlove.ini"]
    assert(type(savedIni) == "string" and #savedIni > 0,
      "expected imlove.ini to have been written")
    assert(savedIni:find("%[Window%]%[Fixed%]"), "missing Fixed block")
    assert(savedIni:find("%[Window%]%[Auto%]"), "missing Auto block")
    -- Only the explicitly-sized window gets a Size= line.
    local fixedBlock = savedIni:match("%[Window%]%[Fixed%](.-)%[Window%]")
      or savedIni:match("%[Window%]%[Fixed%](.*)$")
    local autoBlock = savedIni:match("%[Window%]%[Auto%](.-)%[Window%]")
      or savedIni:match("%[Window%]%[Auto%](.*)$")
    assert(fixedBlock:find("Size="), "Fixed must persist its explicit size")
    assert(not autoBlock:find("Size="),
      "Auto must NOT persist a size — it was never explicitly sized")
    assert(fixedBlock:find("Collapsed=1"), "Fixed must persist collapsed=1")

    -- Now reload the module WITHOUT wiping the fake disk: bypass H.fresh()
    -- (it resets stub.files) and re-require "imlove" directly, exactly the
    -- way a real process restart would find the same imlove.ini on disk.
    package.loaded["imlove"] = nil
    local im2 = require "imlove"

    local pos2, size2, autoPos2 = {}, {}, {}
    local openReturn
    local function ui2()
      openReturn = im2.Begin("Fixed")
      pos2.x, pos2.y = im2.GetWindowPos()
      size2.w, size2.h = im2.GetWindowSize()
      im2.End()

      im2.Begin("Auto")
      autoPos2.x, autoPos2.y = im2.GetWindowPos()
      im2.Text("auto-fit window content")
      im2.End()
    end
    im2.NewFrame() -- lazy ini load happens here
    ui2()
    im2.Render()
    im2.NewFrame()
    ui2()
    im2.Render()

    assert(pos2.x == fixedState.collapsedX and pos2.y == fixedState.collapsedY,
      ("Fixed's position should have been restored, got (%d,%d)")
        :format(pos2.x, pos2.y))
    assert(math.abs(size2.w - (fw + 40)) < 0.001,
      "Fixed's explicit width should have been restored")
    assert(openReturn == false,
      "Fixed's collapsed state should have been restored")
    assert(autoPos2.x == ax0 + 300 and autoPos2.y == ay0 + 260,
      "Auto's position should have been restored too")
  end)

  T("SetNextWindowPos(..., \"always\") wins over a loaded ini entry",
    function()
    local im = H.fresh()
    H.stub.files["imlove.ini"] =
      "[Window][W]\nPos=123,456\n"
    local pos = {}
    local function ui()
      im.SetNextWindowPos(7, 8, "always")
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      im.End()
    end
    H.frame(ui)
    assert(pos.x == 7 and pos.y == 8,
      "'always' must override the ini entry, got " .. pos.x .. "," .. pos.y)
  end)

  T("SetNextWindowPos(..., \"once\") yields to a loaded ini entry",
    function()
    local im = H.fresh()
    H.stub.files["imlove.ini"] =
      "[Window][W]\nPos=123,456\n"
    local pos = {}
    local function ui()
      im.SetNextWindowPos(7, 8, "once")
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      im.End()
    end
    H.frame(ui)
    assert(pos.x == 123 and pos.y == 456,
      "'once' must yield to the ini entry, got " .. pos.x .. "," .. pos.y)
  end)

  T("IniFilename = nil disables persistence entirely: nothing is read or "
    .. "written", function()
    local im = H.fresh()
    H.stub.files["imlove.ini"] = "[Window][W]\nPos=123,456\n"
    im.io.IniFilename = nil
    local pos = {}
    local function ui()
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      im.Text("hi")
      im.End()
    end
    H.frame(ui)
    -- The pre-existing ini entry must NOT have been applied (loading is
    -- disabled), so the window falls back to its cascade default.
    assert(pos.x == 40 and pos.y == 40,
      "with persistence disabled, the ini file must not be read")

    -- Move it and collapse it — still must not write.
    H.click(pos.x + 10, pos.y + 10, ui)
    H.frame(ui)
    H.frame(ui)
    assert(H.stub.files["imlove.ini"] == "[Window][W]\nPos=123,456\n",
      "with persistence disabled, the ini file must not be written either")
  end)

  T("a garbage ini file is tolerated silently: no error, no entries applied",
    function()
    local im = H.fresh()
    H.stub.files["imlove.ini"] = "not an ini file at all\n???\n[garbage"
    local pos = {}
    local function ui()
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      im.Text("hi")
      im.End()
    end
    local ok = pcall(H.frame, ui)
    assert(ok, "a garbage ini file must not raise an error")
    assert(pos.x == 40 and pos.y == 40,
      "a garbage ini file must yield no usable entries")
  end)

  T("an ini block missing Pos= is discarded entirely", function()
    local im = H.fresh()
    -- Size/Collapsed with no Pos= — the whole block should be dropped.
    H.stub.files["imlove.ini"] = "[Window][W]\nSize=200,150\nCollapsed=1\n"
    local pos, state = {}, {}
    local function ui()
      state.open = im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      im.Text("hi")
      im.End()
    end
    H.frame(ui)
    assert(pos.x == 40 and pos.y == 40,
      "an incomplete block (no Pos=) must be discarded, not partially applied")
    assert(state.open == true, "must not come up collapsed from a discarded block")
  end)

  T("manual SaveIniSettings()/LoadIniSettings() work outside the automatic "
    .. "lifecycle, and accept an explicit filename", function()
    local im = H.fresh()
    local pos, size = {}, {}
    local function ui()
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      im.Text("hi")
      im.End()
    end
    H.frame(ui)
    H.frame(ui)
    -- Grab the middle of the title bar (clear of the collapse arrow, which
    -- occupies the first title-bar-height square — see test_windows.lua).
    local x0, y0 = pos.x, pos.y
    local gx, gy = x0 + size.w / 2, y0 + 10
    H.stub.setMouse(gx, gy)
    im.mousepressed(gx, gy, 1)
    H.frame(ui)
    H.stub.setMouse(gx + 33, gy + 44)
    H.frame(ui)
    im.mousereleased(gx + 33, gy + 44, 1)
    H.frame(ui)
    assert(pos.x == x0 + 33 and pos.y == y0 + 44, "test setup: window moved")

    im.SaveIniSettings("custom.ini")
    assert(H.stub.files["custom.ini"],
      "SaveIniSettings(filename) must write that file")

    -- Move the window further, then load the OLD custom.ini snapshot back.
    local gx2, gy2 = gx + 33, gy + 44
    H.stub.setMouse(gx2, gy2)
    im.mousepressed(gx2, gy2, 1)
    H.frame(ui)
    H.stub.setMouse(gx2 + 57, gy2 + 46)
    H.frame(ui)
    im.mousereleased(gx2 + 57, gy2 + 46, 1)
    H.frame(ui)
    assert(pos.x == x0 + 90 and pos.y == y0 + 90, "test setup: window moved again")

    im.LoadIniSettings("custom.ini")
    H.frame(ui)
    assert(pos.x == x0 + 33 and pos.y == y0 + 44,
      "LoadIniSettings(filename) must re-apply the older snapshot")
  end)

  T("the dirty flag debounces: Render() only writes when something actually "
    .. "changed", function()
    local im = H.fresh()
    local pos, size = {}, {}
    local function ui()
      im.Begin("W")
      pos.x, pos.y = im.GetWindowPos()
      size.w, size.h = im.GetWindowSize()
      im.Text("hi")
      im.End()
    end
    H.frame(ui) -- creating "W" marks it dirty; this Render() writes once
    H.frame(ui)

    local writeCount = 0
    local realWrite = love.filesystem.write
    love.filesystem.write = function(...)
      writeCount = writeCount + 1
      return realWrite(...)
    end

    for _ = 1, 5 do H.frame(ui) end
    assert(writeCount == 0,
      "Render() must not write when nothing changed, wrote " .. writeCount
        .. " times")

    -- Grab the middle of the title bar (clear of the collapse arrow).
    local gx, gy = pos.x + size.w / 2, pos.y + 10
    H.stub.setMouse(gx, gy)
    im.mousepressed(gx, gy, 1)
    H.frame(ui)
    H.stub.setMouse(gx + 20, gy + 20)
    H.frame(ui)
    im.mousereleased(gx + 20, gy + 20, 1)
    H.frame(ui) -- the release frame ends the drag and marks it dirty
    assert(writeCount == 1,
      "moving the window should trigger exactly one write, got " .. writeCount)

    for _ = 1, 5 do H.frame(ui) end
    assert(writeCount == 1,
      "no further writes once settled again, got " .. writeCount)

    love.filesystem.write = realWrite
  end)

end
