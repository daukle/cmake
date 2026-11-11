local values = daukle.require("lib/values")

local TEST_KEYS = { name = true, target = true, args = true }

--- The lifecycle task `tests` run through, which a target of the same name would also claim.
local TEST_TASK = "test"

local function checked_test_name(value, at, seen)
  if type(value) ~= "string" or string.match(value, "^[%w_%.%-]+$") == nil then
    error(string.format('%s needs a "name" of letters, digits, ".", "_" and "-", not "%s"',
                        at, tostring(value)), 0)
  end
  if seen[value] ~= nil then
    error(string.format('%s and %s are both called "%s": ctest names a test once', seen[value], at,
                        value), 0)
  end
  seen[value] = at
  return value
end

local function checked_test_target(value, at, executables)
  if type(value) ~= "string" then
    error(string.format('%s needs a "target" naming the executable it runs, as a string', at), 0)
  end
  if not executables[value] then
    error(string.format('%s runs "%s", which is not an executable target this manifest declares:'
                        .. ' a test runs a program the build produces', at, value), 0)
  end
  return value
end

--- @implNote a target called "test" already owns the task `cmake:test`, which would otherwise
--- run the tests; refusing the pair keeps both meanings of the name from silently colliding.
local function refuse_a_target_called_test(targets)
  for _, target in ipairs(targets) do
    if target.task == TEST_TASK and target.libraryKeyword ~= "INTERFACE" then
      error(string.format('the target "%s" takes the task "cmake:test", which is the one that runs'
                          .. ' "tests": rename the target to declare tests', target.name), 0)
    end
  end
end

--- Every declared test, as `{ name, target, args }`, each running an executable target.
local function tests_of(config, targets)
  if config.tests == nil then return {} end
  if type(config.tests) ~= "table" or #config.tests == 0 then
    error('"tests" must be a list of test tables, and an empty one tests nothing: omit the key'
          .. ' when the project declares no tests', 0)
  end
  refuse_a_target_called_test(targets)

  local executables = {}
  for _, target in ipairs(targets) do
    if target.kind == "executable" then executables[target.name] = true end
  end

  local out = {}
  local seen = {}
  for index = 1, #config.tests do
    local entry = config.tests[index]
    local at = "tests[" .. index .. "]"
    if type(entry) ~= "table" then
      error(string.format("%s must be a test table, not a %s", at, type(entry)), 0)
    end
    for key in pairs(entry) do
      if TEST_KEYS[key] == nil then
        error(string.format('"%s" is not a key a test knows, in %s', key, at), 0)
      end
    end
    out[index] = {
      name = checked_test_name(entry.name, at, seen),
      target = checked_test_target(entry.target, at, executables),
      args = values.cmake_text_list(entry.args, at .. ".args", "arguments", "argument") or {},
    }
  end
  return out
end

return { tests_of = tests_of, TEST_TASK = TEST_TASK }
