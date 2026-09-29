local LANGUAGES = { c = "C", ["c++"] = "CXX" }
local STANDARD_PROPERTY = { c = "C_STANDARD", ["c++"] = "CXX_STANDARD" }
local KINDS = { executable = true, library = true }
local DEFAULT_SOURCES = { "src/*.c" }

local function config_of(context)
  return context.toolchain ~= nil and context.toolchain.config or context.config
end

local function version_of(context)
  local version = (context.toolchain ~= nil and context.toolchain.version)
                  or config_of(context).version
  if version == nil then
    error('a cmake toolchain needs a "version": which CMake to provision is not inferred', 0)
  end
  if string.match(version, "^%d+%.%d+$") == nil then
    error('a cmake toolchain version must be an exact major.minor version such as "4.4",'
          .. ' not a range: this plugin pins its releases and does not match ranges', 0)
  end
  return version
end

local function climbs_out(path)
  if string.match(path, "^/") ~= nil or string.match(path, "^%a:") ~= nil then return true end
  if string.find(path, "\\", 1, true) ~= nil then return true end
  if path == ".." or string.match(path, "^%.%./") ~= nil then return true end
  return string.find(path, "/../", 1, true) ~= nil or string.match(path, "/%.%.$") ~= nil
end

local function string_list(value, key, singular)
  if value == nil then return nil end
  if type(value) ~= "table" then
    error('"' .. key .. '" must be a list of ' .. singular .. ', not a ' .. type(value), 0)
  end
  for index = 1, #value do
    if type(value[index]) ~= "string" then
      error(string.format('"%s" must name a %s as a string, not a %s',
                          key, singular:gsub("s$", ""), type(value[index])), 0)
    end
  end
  return value
end

local function path_list(value, key, singular)
  local list = string_list(value, key, singular)
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
  return value
end

local function target_of(project)
  local last = string.match(project, "([^/]+)$")
  if last == nil or string.match(last, "^[%w_%-]+$") == nil then
    error(string.format('the project id "%s" is not usable as a CMake target name:'
                        .. ' its last segment must hold only letters, digits, "_" and "-"',
                        project), 0)
  end
  return last
end

local function read(context)
  local config = config_of(context)

  local language = config.language or "c"
  if LANGUAGES[language] == nil then
    error('"language" must be "c" or "c++", not "' .. tostring(language) .. '"', 0)
  end

  local kind = config.kind or "executable"
  if KINDS[kind] == nil then
    error('"kind" must be "executable" or "library", not "' .. tostring(kind) .. '"', 0)
  end

  local sources = path_list(config.sources, "sources", "globs") or DEFAULT_SOURCES
  if #sources == 0 then
    error('"sources" is empty, so there is nothing to compile', 0)
  end

  local build_type = config.buildType
  if build_type ~= nil and type(build_type) ~= "string" then
    error('"buildType" must be a string such as "Debug", not a ' .. type(build_type), 0)
  end

  local generator = config.generator
  if generator ~= nil and type(generator) ~= "string" then
    error('"generator" must be a string, not a ' .. type(generator), 0)
  end

  return {
    version = version_of(context),
    language = language,
    cmake_language = LANGUAGES[language],
    standard_property = STANDARD_PROPERTY[language],
    kind = kind,
    target = target_of(context.project),
    sources = sources,
    includes = path_list(config.includes, "includes", "directories"),
    defines = string_list(config.defines, "defines", "definitions"),
    standard = scalar_version(config.standard, "standard"),
    buildType = build_type or "Debug",
    generator = generator,
    configureArgs = string_list(config.configureArgs, "configureArgs", "arguments"),
    buildArgs = string_list(config.buildArgs, "buildArgs", "arguments"),
    runArgs = string_list(config.runArgs, "runArgs", "arguments"),
    root = context.root,
  }
end

return { read = read }
