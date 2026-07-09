--[[
Root dispatcher for imlove's examples/. LÖVE's filesystem sandbox means
`love examples/foo` can't `require "../imlove"`, so every example instead
runs from the repo root and this file just picks which one to load:

    love .                          -- default example (kitchensink)
    love . <name>                   -- examples/<name>.lua
    love . <name> --screenshot[=N]  -- also: quit after N frames (default
                                        60), saving screenshot-<name>.png

This dispatcher is deliberately imlove-agnostic and small: each
examples/*.lua module does its own imlove integration end to end (require,
NewFrame/Render, input forwarding) and returns a table of the LÖVE callbacks
it wants — { load, update, draw, mousepressed, mousereleased, wheelmoved,
keypressed, textinput }. This file only installs whatever the module
provides and, optionally, drives the screenshot mode used by CI/tooling.
]]

local DEFAULT_EXAMPLE = "kitchensink"
local DEFAULT_SCREENSHOT_FRAMES = 60

local FORWARDED_CALLBACKS = {
  "mousepressed", "mousereleased", "wheelmoved", "keypressed", "textinput",
}

function love.load(args)
  args = args or {}

  local exampleName = DEFAULT_EXAMPLE
  local nameSet = false
  local screenshotFrames = nil

  for _, a in ipairs(args) do
    if a == "--screenshot" then
      screenshotFrames = screenshotFrames or DEFAULT_SCREENSHOT_FRAMES
    elseif a:match("^%-%-screenshot=%d+$") then
      screenshotFrames = tonumber(a:match("=(%d+)$"))
    elseif not nameSet and a:sub(1, 2) ~= "--" then
      exampleName = a
      nameSet = true
    end
  end

  local example = require("examples." .. exampleName)

  if example.load then example.load() end

  function love.update(dt)
    if example.update then example.update(dt) end
  end

  local frameCount = 0
  local screenshotRequested = false

  function love.draw()
    if example.draw then example.draw() end

    if screenshotFrames and not screenshotRequested then
      frameCount = frameCount + 1
      if frameCount >= screenshotFrames then
        screenshotRequested = true
        love.graphics.captureScreenshot(function(imageData)
          local filename = ("screenshot-%s.png"):format(exampleName)
          imageData:encode("png", filename)
          print(love.filesystem.getSaveDirectory() .. "/" .. filename)
          love.event.quit()
        end)
      end
    end
  end

  for _, name in ipairs(FORWARDED_CALLBACKS) do
    if example[name] then
      love[name] = example[name]
    end
  end
end
