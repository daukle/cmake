local LANGUAGES = { c = "C", ["c++"] = "CXX" }
local STANDARD_PROPERTY = { c = "C_STANDARD", ["c++"] = "CXX_STANDARD" }
local KINDS = { executable = true, library = true }
local DEFAULT_SOURCES = {
  c = { "src/*.c" },
  ["c++"] = { "src/*.cpp", "src/*.cc", "src/*.cxx" },
}

local KNOWN_KEYS = {
  version = true, language = true, kind = true, sources = true, includes = true,
  defines = true, standard = true, buildType = true, generator = true,
  configureArgs = true, buildArgs = true, runArgs = true, dependencies = true,
  compiler = true,
}

local function config_of(context)
  if context.toolchain ~= nil then return context.toolchain.config end
  return context.config
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

local function target_of(project)
  local last = string.match(project, "([^/]+)$")
  if last == nil or string.match(last, "^[%w_%-]+$") == nil then
    error(string.format('the project id "%s" is not usable as a CMake target name:'
                        .. ' its last segment must hold only letters, digits, "_" and "-"',
                        project), 0)
  end
  return last
end

local function resolved_of(context)
  if context.toolchain ~= nil then return context.toolchain.dependencies end
  return context.dependencies
end

local function dependencies_of(context)
  local resolved = resolved_of(context)
  local out = {}
  if resolved == nil then return out end
  for index = 1, #resolved do
    local entry = resolved[index]
    local block = entry.block or {}
    if type(block.package) ~= "string" or type(block.url) ~= "string" then
      error(string.format('modules.%s.cmake needs "package" and "url"', entry.module), 0)
    end
    -- Required here where daukle/c leaves it optional: that plugin edits a file
    -- the user reads, and this one writes a file they are told not to.
    if type(block.sha256) ~= "string" then
      error(string.format('modules.%s.cmake needs a "sha256": a generated file is one'
                          .. ' nobody reads, so an unverified download would be invisible',
                          entry.module), 0)
    end
    if string.match(block.package, "^[%w_%-]+$") == nil then
      error(string.format('the package "%s" is not usable as a CMake target name',
                          block.package), 0)
    end
    -- The digest and the url land in the same generated statement the package
    -- name does, so validating only the name closes one field of three.
    if string.match(block.sha256, "^%x+$") == nil or #block.sha256 ~= 64 then
      error(string.format('modules.%s.cmake has a "sha256" that is not 64 hex digits: "%s"',
                          entry.module, block.sha256), 0)
    end
    if escapes_cmake(block.url) then
      error(string.format('modules.%s.cmake has a "url" carrying a CMake metacharacter: "%s"',
                          entry.module, block.url), 0)
    end
    out[#out + 1] = { package = block.package, url = block.url, sha256 = block.sha256 }
  end
  return out
end

local function reject_unknown_keys(config)
  for key in pairs(config) do
    if KNOWN_KEYS[key] == nil then
      error(string.format('"%s" is not a key this toolchain knows: a misspelled key would'
                          .. ' otherwise be ignored and build the wrong thing silently', key), 0)
    end
  end
end

local function default_sources(language)
  local defaults = DEFAULT_SOURCES[language]
  local copy = {}
  for index = 1, #defaults do copy[index] = defaults[index] end
  return copy
end

local function read(context)
  local config = config_of(context)
  reject_unknown_keys(config)

  local language = config.language or "c"
  if LANGUAGES[language] == nil then
    error('"language" must be "c" or "c++", not "' .. tostring(language) .. '"', 0)
  end

  local kind = config.kind or "executable"
  if KINDS[kind] == nil then
    error('"kind" must be "executable" or "library", not "' .. tostring(kind) .. '"', 0)
  end

  local sources = path_list(config.sources, "sources", "globs", "glob")
                  or default_sources(language)
  if #sources == 0 then
    error('"sources" is empty, so there is nothing to compile', 0)
  end

  local build_type = config.buildType
  if build_type ~= nil then
    if type(build_type) ~= "string" then
      error('"buildType" must be a string such as "Debug", not a ' .. type(build_type), 0)
    end
  end

  local generator = config.generator
  if generator ~= nil and type(generator) ~= "string" then
    error('"generator" must be a string, not a ' .. type(generator), 0)
  end

  local compiler = scalar_version(config.compiler, "compiler")
  -- Refused rather than resolved in the plugin's favour: Ninja is the only
  -- generator that both honours CMAKE_C_COMPILER and needs no build program
  -- the host must supply, so there is no generator left to honour. Visual
  -- Studio accepts the variable and silently compiles with MSVC instead, which
  -- is the defect this whole key exists around.
  if compiler ~= nil and generator ~= nil then
    error('"compiler" provisions a compiler and drives it with Ninja, so it cannot also honour'
          .. ' "generator": CMake\'s Visual Studio generator ignores the compiler it is given,'
          .. ' and the others need a build program this plugin does not provision.'
          .. ' Remove one of the two keys', 0)
  end
  -- The provisioned clang++ links libc++ and libunwind out of the toolchain's
  -- own directory, so the binary runs only where that directory is. Refused
  -- until someone decides whether this plugin may link them statically, which
  -- changes what the user's artifact is.
  if compiler ~= nil and language == "c++" then
    error('"compiler" cannot be used with language "c++": the provisioned clang++ links its C++'
          .. ' runtime from inside daukle\'s cache, so the binary it produces does not start'
          .. ' anywhere else. Use language "c", or drop "compiler" and build with the'
          .. ' host\'s compiler', 0)
  end

  return {
    version = version_of(context),
    language = language,
    cmake_language = LANGUAGES[language],
    standard_property = STANDARD_PROPERTY[language],
    kind = kind,
    target = target_of(context.project),
    sources = sources,
    includes = path_list(config.includes, "includes", "directories", "directory"),
    defines = cmake_text_list(config.defines, "defines", "definitions", "definition"),
    standard = scalar_version(config.standard, "standard"),
    buildType = build_type or "Debug",
    generator = generator,
    compiler = compiler,
    configureArgs = string_list(config.configureArgs, "configureArgs", "arguments", "argument"),
    buildArgs = string_list(config.buildArgs, "buildArgs", "arguments", "argument"),
    runArgs = string_list(config.runArgs, "runArgs", "arguments", "argument"),
    dependencies = dependencies_of(context),
    root = context.root,
  }
end

return { read = read }
