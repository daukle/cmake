local values = daukle.require("lib/values")

local PACKAGE_KEYS = { name = true, version = true, components = true, targets = true }

local function checked_word(value, at, what)
  if type(value) ~= "string" or string.match(value, "^[%w_%-]+$") == nil then
    error(string.format('%s needs %s of letters, digits, "_" and "-", not "%s"', at, what,
                        tostring(value)), 0)
  end
  return value
end

local function checked_version(value, at)
  if value == nil then return nil end
  if type(value) ~= "string" or string.match(value, "^%d+[%.%d]*$") == nil
     or string.match(value, "%.%.") ~= nil or string.match(value, "%.$") ~= nil then
    error(string.format('%s.version must be a version such as "1.2", not "%s"', at,
                        tostring(value)), 0)
  end
  return value
end

--- @implNote the imported targets are declared rather than discovered, because which ones a
--- package provides is known only once CMake has found it: naming them is what lets a link to
--- one keep the same typo check as a link to a declared target.
local function checked_targets(value, at)
  local list = values.cmake_text_list(value, at .. ".targets", "imported target names",
                                      "imported target name")
  if list == nil or #list == 0 then
    error(string.format('%s.targets must name the imported targets the package provides, such as'
                        .. ' "ZLIB::ZLIB": a link to one is checked against this list', at), 0)
  end
  for _, name in ipairs(list) do
    if string.match(name, "^[%w_%.%-]+::[%w_%.%-]+$") == nil then
      error(string.format('%s.targets names "%s", which is not an imported target name of the'
                          .. ' form "Package::Target"', at, name), 0)
    end
  end
  return list
end

local function checked_components(value, at)
  local list = values.cmake_text_list(value, at .. ".components", "components", "component") or {}
  for _, component in ipairs(list) do checked_word(component, at .. ".components", "a component") end
  return list
end

--- Every package `find_package` is to find on the host, as `{ name, version, components, targets }`.
local function find_packages_of(config)
  local declared = config.findPackages
  if declared == nil then return {} end
  if type(declared) ~= "table" or #declared == 0 then
    error('"findPackages" must be a list of package tables, and an empty one finds nothing: omit'
          .. ' the key when the project needs no host package', 0)
  end
  local out = {}
  local seen = {}
  for index = 1, #declared do
    local entry = declared[index]
    local at = "findPackages[" .. index .. "]"
    if type(entry) ~= "table" then
      error(string.format("%s must be a package table, not a %s", at, type(entry)), 0)
    end
    for key in pairs(entry) do
      if PACKAGE_KEYS[key] == nil then
        error(string.format('"%s" is not a key a found package knows, in %s', key, at), 0)
      end
    end
    local name = checked_word(entry.name, at, 'a "name"')
    if seen[name] ~= nil then
      error(string.format('%s and %s both find "%s"', seen[name], at, name), 0)
    end
    seen[name] = at
    out[index] = {
      name = name,
      version = checked_version(entry.version, at),
      components = checked_components(entry.components, at),
      targets = checked_targets(entry.targets, at),
    }
  end
  return out
end

--- The imported target names every found package provides, which a link may name.
local function imported_targets_of(packages)
  local names = {}
  for _, package in ipairs(packages) do
    for _, name in ipairs(package.targets) do names[#names + 1] = name end
  end
  return names
end

return { find_packages_of = find_packages_of, imported_targets_of = imported_targets_of }
