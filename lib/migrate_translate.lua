local plan = daukle.require("lib/plan")

local KINDS = {
  EXECUTABLE = { kind = "executable" },
  STATIC_LIBRARY = { kind = "library", libraryType = "static" },
  SHARED_LIBRARY = { kind = "library", libraryType = "shared" },
  MODULE_LIBRARY = { kind = "library", libraryType = "module" },
  OBJECT_LIBRARY = { kind = "library", libraryType = "object" },
}

local UNVERSIONED = "0.1.0"
local OUTPUT_EXTENSIONS = { "%.exe$", "%.lib$", "%.a$", "%.so$", "%.dll$", "%.dylib$" }

local function trimmed(text)
  return (string.gsub(string.gsub(text or "", "^%s+", ""), "%s+$", ""))
end

local function project_name_of(cache)
  local name = cache.CMAKE_PROJECT_NAME or "project"
  return (string.gsub(name, "[^%w_%-]", "-"))
end

--- The manifest's version: core takes only major.minor.patch, so a shorter one is padded with
--- zeros, and a longer one is dropped and named in `dropped`.
local function version_of(cache, dropped)
  local version = cache.CMAKE_PROJECT_VERSION
  if version == nil or version == "" then return UNVERSIONED end
  local components = {}
  for component in string.gmatch(version, "[^%.]+") do components[#components + 1] = component end
  if #components > 3 then
    dropped[#dropped + 1] = 'project(VERSION ' .. version .. '), which has more than three components'
    return UNVERSIONED
  end
  while #components < 3 do components[#components + 1] = "0" end
  return table.concat(components, ".")
end

--- The root `CMakeLists.txt`'s own floor, as `cmake_minimum_required` names it.
local function minimum_required_of(text)
  local lowered = string.lower(text)
  local floor = string.match(lowered, "cmake_minimum_required%s*%(%s*version%s+([%d%.]+)")
  return floor
end

local function language_of(reply)
  local language = "c"
  for _, target in pairs(reply.targets) do
    for _, group in ipairs(target.compileGroups or {}) do
      if group.language == "CXX" then language = "c++" end
    end
  end
  return language
end

local function output_name_of(target)
  local base = target.nameOnDisk
  if base == nil then return nil end
  for _, extension in ipairs(OUTPUT_EXTENSIONS) do base = string.gsub(base, extension, "") end
  if base == target.name or base == "lib" .. target.name then return nil end
  return base
end

--- @implNote the first fragment is CMake's own default flags when it begins with the cache's
--- `CMAKE_<LANG>_FLAGS` and `CMAKE_<LANG>_FLAGS_<CONFIG>`: the new build gets those again from the
--- same cache, so carrying them would compile with them twice.
local function default_flags_of(cache, language, configuration)
  local prefix = trimmed(trimmed(cache["CMAKE_" .. language .. "_FLAGS"]) .. " "
                         .. trimmed(cache["CMAKE_" .. language .. "_FLAGS_" .. string.upper(configuration)]))
  if prefix == "" then return nil end
  return prefix
end

--- @implNote a fragment is command-line text, and one from `COMPILE_FLAGS` holds several flags;
--- written as one option it would reach the compiler as one argument, so it is carried as
--- `SHELL:`, which CMake splits the way the fragment was written.
local function as_one_option(fragment)
  if string.find(fragment, "%s") == nil then return fragment end
  return "SHELL:" .. fragment
end

local function compile_options_of(group, cache, configuration)
  local options = {}
  local defaults = default_flags_of(cache, group.language or "C", configuration)
  for index, fragment in ipairs(group.compileCommandFragments or {}) do
    local is_default = index == 1 and defaults ~= nil
                       and string.sub(fragment.fragment, 1, #defaults) == defaults
    if not is_default then options[#options + 1] = as_one_option(fragment.fragment) end
  end
  return options
end

--- The group's include directories, plain or `SYSTEM` as `system` asks.
local function include_paths(group, reply, root, system)
  local paths = {}
  for _, include in ipairs(group.includes or {}) do
    local relative = plan.project_relative(include.path, reply.source_root, root)
    if relative ~= nil and (include.isSystem == true) == system then paths[#paths + 1] = relative end
  end
  return paths
end

local function sources_of(target, reply, root)
  local sources = {}
  for _, source in ipairs(target.sources or {}) do
    if not source.isGenerated then
      sources[#sources + 1] = plan.project_relative(source.path, reply.source_root, root)
    end
  end
  table.sort(sources)
  return sources
end

local function defines_of(group)
  local defines, seen = {}, {}
  for _, define in ipairs(group.defines or {}) do
    if not seen[define.define] then
      seen[define.define] = true
      defines[#defines + 1] = define.define
    end
  end
  return defines
end

local function nonempty(list)
  if list == nil or #list == 0 then return nil end
  return list
end

--- A target's links split by where each name comes from, imported names recorded per namespace.
local function links_of(target, reply, imported)
  local links, system = {}, {}
  for _, link in ipairs(target.linkLibraries or {}) do
    if link.id ~= nil then
      local name = plan.name_of_id(link.id)
      local abstract = reply.abstract[name]
      if abstract ~= nil and abstract.imported then
        links[#links + 1] = name
        imported[name] = true
      elseif not plan.is_project_interface(reply, name) then
        links[#links + 1] = name
      end
    elseif link.fragment ~= nil then
      system[#system + 1] = link.fragment
    end
  end
  return links, system
end

local function target_entry(target, reply, root, configuration, imported)
  local shape = KINDS[target.type]
  local group = (target.compileGroups or {})[1] or {}
  local links, system = links_of(target, reply, imported)
  local standard = group.languageStandard ~= nil and group.languageStandard.standard or nil
  return {
    name = target.name,
    kind = shape.kind,
    libraryType = shape.libraryType,
    sources = sources_of(target, reply, root),
    includes = nonempty(include_paths(group, reply, root, false)),
    systemIncludes = nonempty(include_paths(group, reply, root, true)),
    defines = nonempty(defines_of(group)),
    compileOptions = nonempty(compile_options_of(group, reply.cache, configuration)),
    standard = standard,
    outputName = output_name_of(target),
    links = nonempty(links),
    systemLinks = nonempty(system),
  }
end

local function find_packages_of(imported)
  local by_package, names = {}, {}
  for name in pairs(imported) do
    local package = string.match(name, "^(.-)::")
    if package ~= nil and by_package[package] == nil then
      by_package[package] = {}
      names[#names + 1] = package
    end
    if package ~= nil then table.insert(by_package[package], name) end
  end
  table.sort(names)
  local packages = {}
  for _, package in ipairs(names) do
    table.sort(by_package[package])
    packages[#packages + 1] = { name = package, targets = by_package[package] }
  end
  return packages
end

--- The `[toolchains.cmake]` block, project and version a configured build translates into.
--- @param root_text the root `CMakeLists.txt`'s text, for its own floor
--- @return { config, project, version, dropped }
local function translate(reply, root, configuration, root_text, cmake_version)
  local names = {}
  for name, target in pairs(reply.targets) do
    if plan.is_listed(target) and KINDS[target.type] ~= nil then names[#names + 1] = name end
  end
  table.sort(names)
  local imported, targets = {}, {}
  for _, name in ipairs(names) do
    targets[#targets + 1] = target_entry(reply.targets[name], reply, root, configuration, imported)
  end
  local config = { version = cmake_version, language = language_of(reply),
                   minimumRequired = minimum_required_of(root_text), targets = targets }
  local packages = find_packages_of(imported)
  if #packages > 0 then config.findPackages = packages end
  local dropped = {}
  return { config = config, project = project_name_of(reply.cache), version = version_of(reply.cache, dropped),
           dropped = dropped }
end

return { translate = translate }
