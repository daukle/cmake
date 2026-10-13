local function climbs_out(path)
  if string.match(path, "^/") ~= nil or string.match(path, "^%a:") ~= nil then return true end
  if string.find(path, "\\", 1, true) ~= nil then return true end
  if path == ".." or string.match(path, "^%.%./") ~= nil then return true end
  return string.find(path, "/../", 1, true) ~= nil or string.match(path, "/%.%.$") ~= nil
end

-- Everything here is interpolated into a file the user is told not to read, so
-- a character that ends a CMake argument or starts a variable expansion cannot
-- be allowed through. configureArgs is the escape hatch for anything this
-- refuses.
local function escapes_cmake(value)
  return string.find(value, '"', 1, true) ~= nil
      or string.find(value, "\\", 1, true) ~= nil
      or string.find(value, "$", 1, true) ~= nil
      or string.find(value, ")", 1, true) ~= nil
      or string.find(value, ";", 1, true) ~= nil
      or string.find(value, "\n", 1, true) ~= nil
      or string.find(value, "\r", 1, true) ~= nil
end

local function reject_escapes(value, key)
  if escapes_cmake(value) then
    error(string.format('"%s" may not carry a CMake metacharacter, and "%s" does:'
                        .. ' a generated file is one nobody reads, so use "configureArgs"'
                        .. ' for anything this refuses', key, value), 0)
  end
end

local function string_list(value, key, plural, singular)
  if value == nil then return nil end
  if type(value) ~= "table" then
    error('"' .. key .. '" must be a list of ' .. plural .. ', not a ' .. type(value), 0)
  end
  local count = 0
  for _ in pairs(value) do count = count + 1 end
  if count ~= #value then
    error('"' .. key .. '" must be a list of ' .. plural .. ', not a table of named keys', 0)
  end
  for index = 1, #value do
    if type(value[index]) ~= "string" then
      error(string.format('"%s" must name a %s as a string, not a %s',
                          key, singular, type(value[index])), 0)
    end
  end
  return value
end

-- Only for a list whose entries are interpolated into the generated file. The
-- three *Args lists are the documented escape hatch and reach daukle.exec as
-- argv, so they must NOT be narrowed this way.
local function cmake_text_list(value, key, plural, singular)
  local list = string_list(value, key, plural, singular)
  if list == nil then return nil end
  for index = 1, #list do
    reject_escapes(list[index], key)
  end
  return list
end

local function path_list(value, key, plural, singular)
  local list = cmake_text_list(value, key, plural, singular)
  if list == nil then return nil end
  for index = 1, #list do
    if climbs_out(list[index]) then
      error(string.format('"%s" may not climb out of the project, and "%s" does',
                          key, list[index]), 0)
    end
  end
  return list
end

local function scalar_version(value, key)
  if value == nil then return nil end
  local kind = type(value)
  if kind == "number" then
    -- A TOML integer reaches Lua as a float, and tostring would append ".0",
    -- which is how "release = 17" became "--release 17.0" on the java branch.
    if value ~= math.floor(value) then
      error('"' .. key .. '" must be a whole version such as 17, not ' .. tostring(value), 0)
    end
    return string.format("%d", value)
  end
  if kind ~= "string" then
    error('"' .. key .. '" must be a version such as "17", not a ' .. kind, 0)
  end
  if string.match(value, "^[%w%.%+%-]+$") == nil then
    error(string.format('"%s" must be a version such as "17", and "%s" is not', key, value), 0)
  end
  return value
end

return {
  escapes_cmake = escapes_cmake,
  string_list = string_list,
  cmake_text_list = cmake_text_list,
  path_list = path_list,
  scalar_version = scalar_version,
}
