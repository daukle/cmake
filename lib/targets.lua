local values = daukle.require("lib/values")

local KINDS = { executable = true, library = true }
local DEFAULT_SOURCES = {
  c = { "src/*.c" },
  ["c++"] = { "src/*.cpp", "src/*.cc", "src/*.cxx" },
}

--- The usage requirements, each a private key with a `public*` and an `interface*` form that
--- reach the target's consumers, and the reader that checks its values.
local REQUIREMENT_FAMILIES = {
  { key = "includes", read = function(value, at)
      return values.path_list(value, at, "directories", "directory") end },
  { key = "systemIncludes", read = function(value, at)
      return values.path_list(value, at, "directories", "directory") end },
  { key = "defines", read = function(value, at)
      return values.cmake_text_list(value, at, "definitions", "definition") end },
  { key = "links", read = function(value, at)
      return values.cmake_text_list(value, at, "target names", "target name") or {} end },
  { key = "compileOptions", read = function(value, at)
      return values.cmake_text_list(value, at, "options", "option") end },
  { key = "linkOptions", read = function(value, at)
      return values.cmake_text_list(value, at, "options", "option") end },
  { key = "features", read = function(value, at)
      return values.cmake_text_list(value, at, "features", "feature") end },
}

local function consumer_forms_of(key)
  local capitalised = string.upper(string.sub(key, 1, 1)) .. string.sub(key, 2)
  return "public" .. capitalised, "interface" .. capitalised
end

local KNOWN_KEYS = {
  version = true, language = true, kind = true, sources = true, standard = true,
  buildType = true, generator = true, configureArgs = true, buildArgs = true, runArgs = true,
  dependencies = true, compiler = true, targets = true, default = true, systemLinks = true,
  libraryType = true, extensions = true, outputName = true,
}

--- A library target's `libraryType`, as the `add_library` keyword it renders. Without one the
--- keyword is left out and `BUILD_SHARED_LIBS` decides, which is what this plugin always did.
local LIBRARY_KEYWORDS = {
  static = "STATIC", shared = "SHARED", module = "MODULE", object = "OBJECT", interface = "INTERFACE",
}

--[[ The keys a TARGET owns. A project-wide key is not one of these: a
     generator or a build type is a property of the build, not of a thing the
     build produces, and letting a target carry one would mean two targets
     could ask for different generators. ]]
local TARGET_KEYS = {
  name = true, kind = true, sources = true, standard = true, systemLinks = true,
  libraryType = true, extensions = true, outputName = true,
}

--- What reaches a target's consumers, each with the private key that does not.
local PRIVATE_KEY_OF = {}

--- What an `interface` library may not declare, each with the key that says it instead, or false
--- when it has none.
--- @implNote CMake refuses `PRIVATE` and `PUBLIC` on an INTERFACE target at configure time, naming
--- no manifest line: it builds nothing, so only what reaches its consumers can describe it.
local REPLACEMENT_ON_AN_INTERFACE_LIBRARY = {
  sources = false, standard = false, systemLinks = false, extensions = false, outputName = false,
}

for _, family in ipairs(REQUIREMENT_FAMILIES) do
  local public, interface = consumer_forms_of(family.key)
  KNOWN_KEYS[family.key] = family.key ~= "links" or nil
  TARGET_KEYS[family.key], TARGET_KEYS[public], TARGET_KEYS[interface] = true, true, true
  PRIVATE_KEY_OF[public], PRIVATE_KEY_OF[interface] = family.key, family.key
  REPLACEMENT_ON_AN_INTERFACE_LIBRARY[family.key] = interface
  REPLACEMENT_ON_AN_INTERFACE_LIBRARY[public] = interface
end

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

--- @implNote checked here rather than left to CMake, which reports an unknown
--- link as a missing library at LINK time with no mention of the manifest. A
--- library the HOST provides is the one other kind, and it has its own key,
--- "systemLinks", precisely so that anything else in "links" stays a typo.
local function refuse_an_unknown_link(target, index, declared, package_names)
  for _, key in ipairs({ "links", "publicLinks", "interfaceLinks" }) do
    for link_index = 1, #target[key] do
      local link = target[key][link_index]
      if not declared[link] and not package_names_hold(package_names, link) then
        error(string.format('targets[%d].%s names "%s", which is neither another target this'
                            .. ' manifest declares nor a package it fetches. A library the host'
                            .. ' provides, such as "m" or "pthread", goes in "systemLinks"',
                            index, key, link), 0)
      end
    end
  end
end

--- The `add_library` keyword of a target's `libraryType`, or nil when it declares none.
local function library_keyword_of(value, kind, at)
  if value == nil then return nil end
  if kind ~= "library" then
    error(string.format('%s declares "libraryType" and is an executable: only a library has one', at), 0)
  end
  local keyword = type(value) == "string" and LIBRARY_KEYWORDS[value] or nil
  if keyword == nil then
    error(string.format('%s has a "libraryType" that must be "static", "shared", "module", "object"'
                        .. ' or "interface", not "%s"', at, tostring(value)), 0)
  end
  return keyword
end

local function refuse_build_keys_on_an_interface_library(entry, at)
  for key, replacement in pairs(REPLACEMENT_ON_AN_INTERFACE_LIBRARY) do
    if entry[key] ~= nil then
      local remedy = replacement and string.format(': write it as "%s"', replacement)
                     or ', since it compiles and links nothing'
      error(string.format('%s is an "interface" library and declares "%s", which only a library that'
                          .. ' is built can use%s', at, key, remedy), 0)
    end
  end
end

--- @implNote checked here because CMake refuses to link a MODULE library, at configure time and
--- naming no manifest line: a module is loaded at run time, never linked.
local function refuse_a_link_to_a_module(target, index, keyword_of)
  for _, key in ipairs({ "links", "publicLinks", "interfaceLinks" }) do
    for _, link in ipairs(target[key]) do
      if keyword_of[link] == "MODULE" then
        error(string.format('targets[%d].%s names "%s", a "module" library, which is loaded at run time'
                            .. ' and cannot be linked: make it "shared" to link it', index, key, link), 0)
      end
    end
  end
end

--- An executable has no consumer for a usage requirement to reach, so one written on it would
--- change nothing and say otherwise.
local function refuse_usage_requirements_on_an_executable(entry, kind, at)
  if kind ~= "executable" then return end
  for key, private_key in pairs(PRIVATE_KEY_OF) do
    if entry[key] ~= nil then
      error(string.format('%s is an executable and declares "%s": nothing links an executable,'
                          .. ' so it has no consumer for that to reach. Write it as "%s"',
                          at, key, private_key), 0)
    end
  end
end

--- @implNote the converse of refuse_an_unknown_link: a target or a package
--- named in "systemLinks" would link, but it would skip the one check that
--- makes "links" worth having.
local function refuse_a_known_name_as_a_system_library(target, key, declared, package_names)
  for link_index = 1, #target.systemLinks do
    local library = target.systemLinks[link_index]
    if declared[library] or package_names_hold(package_names, library) then
      error(string.format('"%s" names "%s", which this manifest declares or fetches: it'
                          .. ' belongs in "links", where a misspelling is caught',
                          key, library), 0)
    end
  end
end

local function checked_extensions(value, at)
  if value ~= nil and type(value) ~= "boolean" then
    error(string.format('"%s" must be true or false, not a %s', at, type(value)), 0)
  end
  return value
end

--- @implNote the name of the file CMake writes, and `cmake:run` starts it by that name, so only a
--- plain file name is taken: a path would move the binary away from where the run looks.
local function checked_output_name(value, at)
  if value == nil then return nil end
  if type(value) ~= "string" or string.match(value, "^[%w_%.%-]+$") == nil then
    error(string.format('"%s" must be a file name of letters, digits, ".", "_" and "-", not "%s"',
                        at, tostring(value)), 0)
  end
  return value
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
    local sources = values.path_list(config.sources, "sources", "globs", "glob")
                    or default_sources(language)
    if #sources == 0 then
      error('"sources" is empty, so there is nothing to compile', 0)
    end
    local library_keyword = library_keyword_of(config.libraryType, kind, "the project")
    if library_keyword == "INTERFACE" then
      error('an "interface" library is described by its "interfaceIncludes", "interfaceDefines" and'
            .. ' "interfaceLinks", which are target keys: declare it in "targets"', 0)
    end
    local only = {
      name = project_target,
      task = task_name_of(project_target),
      kind = kind,
      libraryKeyword = library_keyword,
      sources = sources,
      standard = values.scalar_version(config.standard, "standard"),
      extensions = checked_extensions(config.extensions, "extensions"),
      outputName = checked_output_name(config.outputName, "outputName"),
      systemLinks = values.system_library_list(config.systemLinks, "systemLinks") or {},
    }
    for _, family in ipairs(REQUIREMENT_FAMILIES) do
      local public, interface = consumer_forms_of(family.key)
      only[family.key] = family.read(config[family.key], family.key)
      only[public], only[interface] = family.read(nil, public), family.read(nil, interface)
    end
    only.links = package_names
    refuse_a_known_name_as_a_system_library(only, "systemLinks", { [project_target] = true },
                                            package_names)
    return { only }
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
    refuse_usage_requirements_on_an_executable(entry, kind, at)
    local library_keyword = library_keyword_of(entry.libraryType, kind, at)
    local sources = {}
    if library_keyword == "INTERFACE" then
      refuse_build_keys_on_an_interface_library(entry, at)
    else
      sources = values.path_list(entry.sources, at .. ".sources", "globs", "glob")
                or default_sources(language)
      if #sources == 0 then
        error(string.format('%s has an empty "sources", so there is nothing to compile', at), 0)
      end
    end
    out[index] = {
      name = name,
      task = task,
      kind = kind,
      libraryKeyword = library_keyword,
      sources = sources,
      standard = values.scalar_version(entry.standard, at .. ".standard"),
      extensions = checked_extensions(entry.extensions, at .. ".extensions"),
      outputName = checked_output_name(entry.outputName, at .. ".outputName"),
      systemLinks = values.system_library_list(entry.systemLinks, at .. ".systemLinks") or {},
    }
    for _, family in ipairs(REQUIREMENT_FAMILIES) do
      local public, interface = consumer_forms_of(family.key)
      for _, key in ipairs({ family.key, public, interface }) do
        out[index][key] = family.read(entry[key], at .. "." .. key)
      end
    end
  end

  local keyword_of = {}
  for _, target in ipairs(out) do keyword_of[target.name] = target.libraryKeyword end
  for index = 1, #out do
    refuse_an_unknown_link(out[index], index, declared, package_names)
    refuse_a_link_to_a_module(out[index], index, keyword_of)
    refuse_a_known_name_as_a_system_library(out[index], 'targets[' .. index .. '].systemLinks',
                                            declared, package_names)
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

--- @implNote an INTERFACE library compiles nothing, so CMake gives it no build target and a
--- `cmake --build --target` naming it fails: such a target gets no task of its own.
local function has_no_build_target(entry)
  return entry.libraryType == "interface"
end

--- The task name and kind of every target, read from the manifest as PARSED
--- rather than from a run-time context, so a chunk can register one task per
--- target before any command runs.
---
--- @implNote it validates NAMES and refuses a collision, and deliberately
--- validates nothing else. This runs at chunk time, where raising takes every
--- command in the project down with it, so an empty "sources" or an unknown
--- link stays the run's business and keeps its own message. The two it does
--- refuse are fatal at registration anyway: a name a task cannot hold, and two
--- targets that lowercase to one task.
local function task_targets(document)
  local toolchains = document.toolchains
  local config = toolchains ~= nil and toolchains.cmake or nil
  if type(config) ~= "table" then return {} end

  if config.targets == nil then
    if type(document.project) ~= "string" then return {} end
    local name = target_of(document.project)
    return { { name = name, task = task_name_of(name), kind = config.kind or "executable" } }
  end
  if type(config.targets) ~= "table" then return {} end

  local out = {}
  local seen = {}
  for index = 1, #config.targets do
    local entry = config.targets[index]
    if type(entry) ~= "table" then return {} end
    local at = "targets[" .. index .. "]"
    local task = task_name_of(checked_target_name(entry.name, at))
    if seen[task] ~= nil then
      error(string.format('%s is called "%s" and %s is called "%s": they are different CMake'
                          .. ' targets and the same daukle task "cmake:%s"',
                          at, entry.name, seen[task].at, seen[task].name, task), 0)
    end
    seen[task] = { at = at, name = entry.name }
    if not has_no_build_target(entry) then
      out[#out + 1] = { name = entry.name, task = task, kind = entry.kind or "executable" }
    end
  end
  return out
end

return {
  KNOWN_KEYS = KNOWN_KEYS,
  target_of = target_of,
  task_name_of = task_name_of,
  targets_of = targets_of,
  default_target = default_target,
  task_targets = task_targets,
}
