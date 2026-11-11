local values = daukle.require("lib/values")

local TEST_KEYS = {
  name = true, target = true, args = true,
  workingDirectory = true, labels = true, timeout = true, willFail = true,
}

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

local function checked_working_directory(value, at)
  if value == nil then return nil end
  if type(value) ~= "string" then
    error(string.format('%s.workingDirectory must be a directory as a string, not a %s', at,
                        type(value)), 0)
  end
  return values.path_list({ value }, at .. ".workingDirectory", "directories", "directory")[1]
end

--- @implNote each label is one word, because the labels are joined with ";" into one CMake list.
local function checked_labels(value, at)
  local list = values.cmake_text_list(value, at .. ".labels", "labels", "label") or {}
  for _, label in ipairs(list) do
    if string.match(label, "^[%w_%.%-]+$") == nil then
      error(string.format('%s.labels holds "%s", and a label holds only letters, digits, ".", "_"'
                          .. ' and "-"', at, label), 0)
    end
  end
  return list
end

--- @implNote a TOML integer reaches a plugin as a float such as 30.0, because the manifest passes
--- through JSON, so a whole number is told apart by its value rather than its type.
local function checked_timeout(value, at)
  if value == nil then return nil end
  if type(value) ~= "number" or value ~= math.floor(value) or value <= 0 then
    error(string.format('%s.timeout must be a whole number of seconds above 0, not %s', at,
                        tostring(value)), 0)
  end
  return string.format("%d", value)
end

local function checked_will_fail(value, at)
  if value ~= nil and type(value) ~= "boolean" then
    error(string.format('%s.willFail must be true or false, not a %s', at, type(value)), 0)
  end
  return value == true
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

--- Every declared test, as `{ name, target, args }` and its properties,, each running an executable target.
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
      workingDirectory = checked_working_directory(entry.workingDirectory, at),
      labels = checked_labels(entry.labels, at),
      timeout = checked_timeout(entry.timeout, at),
      willFail = checked_will_fail(entry.willFail, at),
    }
  end
  return out
end

return { tests_of = tests_of, TEST_TASK = TEST_TASK }
