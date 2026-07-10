--[[
Headless test runner. No LÖVE, no test framework, no dependencies:

    luajit tests/run.lua

Each tests/test_*.lua file returns a function(T, H) that registers named
tests with T; H is the shared harness (see harness.lua). Exit code is the
number-of-failures-is-zero convention: 0 on success, 1 otherwise.
]]

local here = arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path = here .. "/?.lua;" .. here .. "/../?.lua;" .. package.path

local files = {
  "test_require",  -- must run first: it checks behavior with no `love` global
  "test_widgets",
  "test_widgets_v11",
  "test_ids",
  "test_windows",
  "test_windows_v12",
  "test_capture",
  "test_popups",
}

local pass, fail = 0, 0

local function T(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    pass = pass + 1
    print("PASS  " .. name)
  else
    fail = fail + 1
    print("FAIL  " .. name)
    print("      " .. tostring(err):gsub("\n", "\n      "))
  end
end

local H = require "harness"

for _, file in ipairs(files) do
  require(file)(T, H)
end

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
