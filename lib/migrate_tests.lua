local plan = daukle.require("lib/plan")
local values = daukle.require("lib/values")

local TESTING_ROW = "CMAKE-SURFACE.md: 8. Testing"
local CARRIED_PROPERTIES = { WORKING_DIRECTORY = true, LABELS = true, TIMEOUT = true, WILL_FAIL = true }

--- ctest's own description of every test a configured build declares.
--- @param build_dir the build directory, relative to the directory ctest runs in
local function listed(ctest, build_dir, configuration)
  local result = daukle.exec(ctest, { "--show-only=json-v1", "--test-dir", build_dir, "-C", configuration },
                             { capture = true, check = false })
  if result.code ~= 0 then
    error("ctest could not list the tests of " .. build_dir .. ":\n" .. (result.stderr or ""), 0)
  end
  return daukle.json_parse(result.stdout).tests or {}
end

--- @implNote a multi-config generator names a test's program only once that configuration is
--- built, so a listed test without a command means the build has to run first.
local function needs_build(tests)
  for _, test in ipairs(tests) do
    if test.command == nil then return true end
  end
  return false
end

local function target_of_program(program, reply)
  local wanted = plan.normalised(program)
  for name, target in pairs(reply.targets) do
    for _, artifact in ipairs(target.artifacts or {}) do
      local full = plan.normalised(reply.build_root .. "/" .. artifact.path)
      if plan.normalised(artifact.path) == wanted or full == wanted then return name end
    end
  end
  return nil
end

local function property_of(test, name)
  for _, property in ipairs(test.properties or {}) do
    if property.name == name then return property.value end
  end
  return nil
end

local function blocker(test, why)
  return { construct = test.name, where = "CMakeLists.txt", why = why, surface = TESTING_ROW }
end

--- @implNote ctest's default working directory is the build directory, which differs between
--- the read and the new build, so only a directory the project chose is carried.
local function working_directory_of(test, reply, root)
  local directory = property_of(test, "WORKING_DIRECTORY")
  if directory == nil or plan.normalised(directory) == plan.normalised(reply.build_root) then return nil, nil end
  local relative = plan.project_relative(directory, reply.source_root, root)
  if relative == nil or string.sub(relative, 1, 6) == "build/" then
    return nil, 'runs in "' .. directory .. '", outside the project'
  end
  return relative, nil
end

local function labels_of(test)
  local value = property_of(test, "LABELS")
  if value == nil then return {} end
  if type(value) == "table" then return value end
  local labels = {}
  for label in string.gmatch(value, "[^;]+") do labels[#labels + 1] = label end
  return labels
end

local function test_entry(test, reply, root, blockers)
  local target = target_of_program(test.command[1], reply)
  if target == nil then
    blockers[#blockers + 1] = blocker(test, 'runs "' .. test.command[1] .. '", which is not a target this'
                                      .. ' project builds')
    return nil
  end
  for _, property in ipairs(test.properties or {}) do
    if not CARRIED_PROPERTIES[property.name] then
      blockers[#blockers + 1] = blocker(test, "sets the test property " .. property.name
                                        .. ", which daukle/cmake does not declare")
    end
  end
  local args = {}
  for index = 2, #test.command do
    if values.escapes_cmake(test.command[index]) then
      blockers[#blockers + 1] = blocker(test, 'passes "' .. test.command[index] .. '", which holds a'
                                        .. ' character daukle/cmake refuses in a generated file')
    end
    args[#args + 1] = test.command[index]
  end
  local directory, outside = working_directory_of(test, reply, root)
  if outside ~= nil then blockers[#blockers + 1] = blocker(test, outside) end
  local timeout = tonumber(property_of(test, "TIMEOUT") or "")
  local will_fail = property_of(test, "WILL_FAIL")
  return { name = test.name, target = target, args = args, workingDirectory = directory,
           labels = labels_of(test), timeout = timeout,
           willFail = will_fail == true or will_fail == "ON" or will_fail == "TRUE" or will_fail == "1" }
end

--- Every listed test as `daukle/cmake` declares one, sorted by name, and what blocks the rest.
--- @return tests, blockers
local function of(listed_tests, reply, root)
  local tests, blockers = {}, {}
  for _, test in ipairs(listed_tests) do
    local entry = test_entry(test, reply, root, blockers)
    if entry ~= nil then tests[#tests + 1] = entry end
  end
  table.sort(tests, function(left, right) return left.name < right.name end)
  return tests, blockers
end

--- The plan's line for one test, the same on both sides of the proof.
local function plan_line(test)
  return string.format("test %s %s args=%s directory=%s labels=%s timeout=%s will-fail=%s", test.name,
                       test.target, table.concat(test.args, " "), test.workingDirectory or "-",
                       table.concat(test.labels, ";"), test.timeout ~= nil and string.format("%d", test.timeout) or "-",
                       test.willFail and "yes" or "no")
end

--- The `tests` entries of the manifest, leaving out every property at its default.
local function manifest_entries(tests)
  local entries = {}
  for _, test in ipairs(tests) do
    entries[#entries + 1] = {
      name = test.name, target = test.target,
      args = #test.args > 0 and test.args or nil,
      workingDirectory = test.workingDirectory,
      labels = #test.labels > 0 and test.labels or nil,
      timeout = test.timeout,
      willFail = test.willFail or nil,
    }
  end
  return entries
end

return { listed = listed, needs_build = needs_build, of = of, plan_line = plan_line,
         manifest_entries = manifest_entries }
