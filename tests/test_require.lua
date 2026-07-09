-- Module hygiene: requiring imlove must work without LÖVE present (the
-- library may only touch `love` at runtime), must leak no globals, and the
-- lifecycle functions must fail loudly when misused.

return function(T, H)

  T("require works without love and leaks no globals", function()
    -- This test runs first, before any stub is installed, so `love` really
    -- is absent here.
    assert(rawget(_G, "love") == nil, "precondition: no love global yet")
    local before = {}
    for k in pairs(_G) do before[k] = true end

    package.loaded["imlove"] = nil
    local im = require "imlove"

    assert(type(im) == "table", "require must return the module table")
    assert(type(im.Begin) == "function" and type(im.End) == "function")
    assert(type(im.NewFrame) == "function" and type(im.Render) == "function")
    assert(im._VERSION == "1.0.0")
    for k in pairs(_G) do
      assert(before[k], "module leaked a global: " .. tostring(k))
    end
  end)

  T("End without Begin errors", function()
    local im = H.fresh()
    im.NewFrame()
    local ok, err = pcall(im.End)
    assert(not ok and err:find("without a matching"), tostring(err))
  end)

  T("Render with an unclosed window errors", function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("W")
    local ok, err = pcall(im.Render)
    assert(not ok and err:find("missing imlove.End"), tostring(err))
  end)

  T("nested Begin errors", function()
    local im = H.fresh()
    im.NewFrame()
    im.Begin("A")
    local ok, err = pcall(im.Begin, "B")
    assert(not ok and err:find("missing imlove.End"), tostring(err))
  end)

  T("Begin before NewFrame errors", function()
    local im = H.fresh()
    local ok, err = pcall(im.Begin, "W")
    assert(not ok and err:find("before imlove.NewFrame"), tostring(err))
  end)

  T("widgets outside a window error", function()
    local im = H.fresh()
    im.NewFrame()
    local ok, err = pcall(im.Button, "X")
    assert(not ok and err:find("outside a Begin"), tostring(err))
  end)

  T("empty frames are fine", function()
    local im = H.fresh()
    H.frame()
    H.frame(function()
      im.Begin("Empty")
      im.End()
    end)
  end)

end
