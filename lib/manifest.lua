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
  compiler = true, targets = true, default = true,
}

--[[ The five keys a TARGET owns. A project-wide key is not one of these: a
     generator or a build type is a property of the build, not of a thing the
     build produces, and letting a target carry one would mean two targets
     could ask for different generators. ]]
local TARGET_KEYS = {
  name = true, kind = true, sources = true, includes = true, defines = true,
  standard = true, links = true,
}

-- A target becomes a task, and core refuses a task name that is not lowercase
-- or that a lifecycle verb already took.
local RESERVED_TARGET_NAMES = { build = true, run = true, configure = true }

local function default_sources(language)
  local defaults = DEFAULT_SOURCES[language]
  local copy = {}
  for index = 1, #defaults do copy[index] = defaults[index] end
  return copy
end

local function package_names_hold(names, wanted)
  for index = 1, #names do
    if names[index] == wanted then return true end
  end
  return false
end

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

--- The task spelling of a target name. Lowercased rather than refused, because
--- a target name is the user's own word and CMake allows a case this plugin
--- cannot put after a colon. Two targets that lowercase to one task name are
--- refused by name, which is the only case the mapping cannot carry.
local function task_name_of(target_name)
  return string.lower(target_name)
end

local function checked_target_name(value, at)
  if type(value) ~= "string" then
    error(string.format('%s needs a "name" as a string, not a %s', at, type(value)), 0)
  end
  if string.match(value, "^[%w_%.%-]+$") == nil then
    error(string.format('%s has a "name" this plugin cannot use: "%s". A target becomes a daukle'
                        .. ' task, and a task name holds only letters, digits, ".", "_" and "-"',
                        at, value), 0)
  end
  if RESERVED_TARGET_NAMES[task_name_of(value)] then
    error(string.format('%s is called "%s", which is already a task this toolchain declares:'
                        .. ' "cmake:build", "cmake:run" and "cmake:configure" are the lifecycle'
                        .. ' verbs and a target may not take one', at, value), 0)
  end
  return value
end

local function reject_unknown_target_keys(target, at)
  for key in pairs(target) do
    if TARGET_KEYS[key] == nil then
      error(string.format('"%s" is not a key a target knows, in %s: a misspelled key would'
                          .. ' otherwise be ignored and build the wrong thing silently', key, at), 0)
    end
  end
end

--- Every target, as a LIST, whether the manifest declared one implicitly
--- through the project-wide keys or several through "targets". The caller
--- never branches on which, which is the whole point: a generator that loops
--- over one element is the same code that loops over five, and the special
--- case for "the simple project" is how the number one got hardcoded here.
local function targets_of(config, language, project_target, package_names)
  if config.targets == nil then
    --[[ The legacy shape, and it must stay BYTE identical: the one target is
         named after the project, takes the project-wide keys, and links every
         fetched package, which is what this plugin did before it could count
         past one. ]]
    local kind = config.kind or "executable"
    if KINDS[kind] == nil then
      error('"kind" must be "executable" or "library", not "' .. tostring(kind) .. '"', 0)
    end
    local sources = path_list(config.sources, "sources", "globs", "glob")
                    or default_sources(language)
    if #sources == 0 then
      error('"sources" is empty, so there is nothing to compile', 0)
    end
    return { {
      name = project_target,
      task = task_name_of(project_target),
      kind = kind,
      sources = sources,
      includes = path_list(config.includes, "includes", "directories", "directory"),
      defines = cmake_text_list(config.defines, "defines", "definitions", "definition"),
      standard = scalar_version(config.standard, "standard"),
      links = package_names,
    } }
  end

  if type(config.targets) ~= "table" or #config.targets == 0 then
    error('"targets" must be a list of target tables, and an empty one builds nothing:'
          .. ' omit the key to declare the single target this project is named after', 0)
  end
  for key in pairs(KNOWN_KEYS) do
    if TARGET_KEYS[key] ~= nil and key ~= "name" and config[key] ~= nil then
      error(string.format('"%s" is a target key and "targets" is declared, so it has to live on a'
                          .. ' target: a project-wide "%s" beside "targets" would silently apply'
                          .. ' to none of them', key, key), 0)
    end
  end

  local out = {}
  local seen_task = {}
  local declared = {}
  for index = 1, #config.targets do
    local entry = config.targets[index]
    local at = 'targets[' .. index .. ']'
    if type(entry) ~= "table" then
      error(string.format("%s must be a target table, not a %s", at, type(entry)), 0)
    end
    reject_unknown_target_keys(entry, at)
    local name = checked_target_name(entry.name, at)
    local task = task_name_of(name)
    if seen_task[task] ~= nil then
      error(string.format('%s is called "%s" and %s is called "%s": they are different CMake'
                          .. ' targets and the same daukle task "cmake:%s"',
                          at, name, seen_task[task].at, seen_task[task].name, task), 0)
    end
    seen_task[task] = { at = at, name = name }
    declared[name] = true

    local kind = entry.kind or "executable"
    if KINDS[kind] == nil then
      error(string.format('%s has a "kind" that must be "executable" or "library", not "%s"',
                          at, tostring(kind)), 0)
    end
    local sources = path_list(entry.sources, at .. ".sources", "globs", "glob")
                    or default_sources(language)
    if #sources == 0 then
      error(string.format('%s has an empty "sources", so there is nothing to compile', at), 0)
    end
    out[index] = {
      name = name,
      task = task,
      kind = kind,
      sources = sources,
      includes = path_list(entry.includes, at .. ".includes", "directories", "directory"),
      defines = cmake_text_list(entry.defines, at .. ".defines", "definitions", "definition"),
      standard = scalar_version(entry.standard, at .. ".standard"),
      links = cmake_text_list(entry.links, at .. ".links", "target names", "target name") or {},
    }
  end

  --[[ Checked here rather than left to CMake, which reports an unknown link as
       a missing library at LINK time with no mention of the manifest. A link
       names a sibling target or a package the resolver fetched; there is no
       third kind, so anything else is a typo. ]]
  for index = 1, #out do
    local links = out[index].links
    for link_index = 1, #links do
      local link = links[link_index]
      if not declared[link] and not package_names_hold(package_names, link) then
        error(string.format('targets[%d] links "%s", which is neither another target this'
                            .. ' manifest declares nor a package it fetches', index, link), 0)
      end
    end
  end
  return out
end

--- Which executable `cmake:run` means. nil is a legitimate answer and is not
--- an error here: a project of two executables with no favourite is a
--- buildable project, so the ambiguity is raised by the run TASK and not by
--- generation, which would take `cmake:build` down with it.
local function default_target(config, targets)
  local executables = {}
  for index = 1, #targets do
    if targets[index].kind == "executable" then executables[#executables + 1] = targets[index] end
  end

  if config.default ~= nil then
    if type(config.default) ~= "string" then
      error('"default" must name a target as a string, not a ' .. type(config.default), 0)
    end
    for index = 1, #executables do
      if executables[index].name == config.default then return executables[index] end
    end
    error(string.format('"default" names "%s", which is not an executable target this manifest'
                        .. ' declares: cmake:run has to have a binary to run', config.default), 0)
  end

  if #executables == 1 then return executables[1] end
  return nil
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

  local project_target = target_of(context.project)
  local targets = targets_of(config, language, project_target, package_names)

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
    project_name = project_target,
    targets = targets,
    default = default_target(config, targets),
    buildType = build_type or "Debug",
    generator = generator,
    compiler = compiler,
    configureArgs = string_list(config.configureArgs, "configureArgs", "arguments", "argument"),
    buildArgs = string_list(config.buildArgs, "buildArgs", "arguments", "argument"),
    runArgs = string_list(config.runArgs, "runArgs", "arguments", "argument"),
    dependencies = dependencies,
    root = context.root,
  }
end

return { read = read, task_name_of = task_name_of }
