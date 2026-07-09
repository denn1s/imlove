function love.conf(t)
  t.version = "11.5"
  t.identity = "imlove" -- stable save directory for examples/*.lua screenshots
  t.window.title = "imlove demo"
  t.window.width = 1000
  t.window.height = 700
  t.window.vsync = 1
  t.modules.joystick = false
  t.modules.physics = false
end
