local values = daukle.require("lib/values")
local targets = daukle.require("lib/targets")

local LANGUAGES = { c = "C", ["c++"] = "CXX" }
local STANDARD_PROPERTY = { c = "C_STANDARD", ["c++"] = "CXX_STANDARD" }
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
    if values.escapes_cmake(block.url) then
      error(string.format('modules.%s.cmake has a "url" carrying a CMake metacharacter: "%s"',
                          entry.module, block.url), 0)
    end
    out[#out + 1] = { package = block.package, url = block.url, sha256 = block.sha256 }
  end
  return out
end

local function reject_unknown_keys(config)
  for key in pairs(config) do
    if targets.KNOWN_KEYS[key] == nil then
      error(string.format('"%s" is not a key this toolchain knows: a misspelled key would'
                          .. ' otherwise be ignored and build the wrong thing silently', key), 0)
    end
  end
end

local function read(context)
  local config = config_of(context)
  reject_unknown_keys(config)

  local language = config.language or "c"
  if LANGUAGES[language] == nil then
    error('"language" must be "c" or "c++", not "' .. tostring(language) .. '"', 0)
  end

  local dependencies = dependencies_of(context)
  local package_names = {}
  for index = 1, #dependencies do package_names[index] = dependencies[index].package end

  local project_target = targets.target_of(context.project)
  local project_targets = targets.targets_of(config, language, project_target, package_names)

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

  local compiler = values.scalar_version(config.compiler, "compiler")
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
    project_name = project_target,
    targets = project_targets,
    default = targets.default_target(config, project_targets),
    buildType = build_type or "Debug",
    generator = generator,
    compiler = compiler,
    configureArgs = values.string_list(config.configureArgs, "configureArgs", "arguments",
                                       "argument"),
    buildArgs = values.string_list(config.buildArgs, "buildArgs", "arguments", "argument"),
    runArgs = values.string_list(config.runArgs, "runArgs", "arguments", "argument"),
    dependencies = dependencies,
    root = context.root,
  }
end

return { read = read, task_name_of = targets.task_name_of, task_targets = targets.task_targets }
