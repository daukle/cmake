local values = daukle.require("lib/values")

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
    local sources = values.path_list(config.sources, "sources", "globs", "glob")
                    or default_sources(language)
    if #sources == 0 then
      error('"sources" is empty, so there is nothing to compile', 0)
    end
    return { {
      name = project_target,
      task = task_name_of(project_target),
      kind = kind,
      sources = sources,
      includes = values.path_list(config.includes, "includes", "directories", "directory"),
      defines = values.cmake_text_list(config.defines, "defines", "definitions", "definition"),
      standard = values.scalar_version(config.standard, "standard"),
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
    local sources = values.path_list(entry.sources, at .. ".sources", "globs", "glob")
                    or default_sources(language)
    if #sources == 0 then
      error(string.format('%s has an empty "sources", so there is nothing to compile', at), 0)
    end
    out[index] = {
      name = name,
      task = task,
      kind = kind,
      sources = sources,
      includes = values.path_list(entry.includes, at .. ".includes", "directories", "directory"),
      defines = values.cmake_text_list(entry.defines, at .. ".defines", "definitions",
                                       "definition"),
      standard = values.scalar_version(entry.standard, at .. ".standard"),
      links = values.cmake_text_list(entry.links, at .. ".links", "target names",
                                     "target name") or {},
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
    out[#out + 1] = { name = entry.name, task = task, kind = entry.kind or "executable" }
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
