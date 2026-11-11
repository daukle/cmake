local plan = daukle.require("lib/plan")
local values = daukle.require("lib/values")

local SURFACE = "CMAKE-SURFACE.md: "
local LANGUAGE_ROW = SURFACE .. "1. The project, the language and the standard"
local TARGETS_ROW = SURFACE .. "2. Targets"
local REQUIREMENTS_ROW = SURFACE .. "3. Usage requirements and target properties"
local DEPENDENCIES_ROW = SURFACE .. "6. Dependencies"
local LOGIC_ROW = SURFACE .. "7. Build logic"

local COMPILED = {
  EXECUTABLE = true, STATIC_LIBRARY = true, SHARED_LIBRARY = true, MODULE_LIBRARY = true, OBJECT_LIBRARY = true,
}

local function blocker(construct, where, why, surface)
  return { construct = construct, where = where, why = why, surface = surface }
end

--- @implNote the read's build directory lies below the project, under `build/`, so a file a
--- configure wrote there is project-relative and would otherwise be carried as a source.
local function is_build_output(relative)
  return relative == "build" or string.sub(relative, 1, 6) == "build/"
end

--- The project-relative file that declared a target: the first node of its backtrace.
local function where_of(target, reply, root)
  local graph = target.backtraceGraph
  if graph == nil or target.backtrace == nil then return "CMakeLists.txt" end
  local node = graph.nodes[target.backtrace + 1]
  local file = node ~= nil and graph.files[node.file + 1] or nil
  if file == nil then return "CMakeLists.txt" end
  return plan.project_relative(file, reply.source_root, root) or file
end

local function is_fetched(target, reply)
  local source = target.paths ~= nil and target.paths.source or ""
  local full = plan.normalised(reply.source_root .. "/" .. source)
  return string.find(full, "/_deps/", 1, true) ~= nil
end

local function source_blockers(target, where, reply, root, out)
  for _, source in ipairs(target.sources or {}) do
    local relative = plan.project_relative(source.path, reply.source_root, root)
    if source.isGenerated then
      out[#out + 1] = blocker(target.name, where, string.format('compiles the generated source "%s"',
                              relative or source.path), LOGIC_ROW)
    elseif relative == nil then
      out[#out + 1] = blocker(target.name, where, string.format('compiles "%s", outside the project',
                              source.path), TARGETS_ROW)
    elseif is_build_output(relative) then
      out[#out + 1] = blocker(target.name, where, string.format('compiles "%s", which a configure wrote'
                              .. ' and nothing regenerates', relative), LOGIC_ROW)
    end
  end
end

local function include_blockers(target, where, reply, root, out)
  for _, group in ipairs(target.compileGroups or {}) do
    for _, include in ipairs(group.includes or {}) do
      local relative = plan.project_relative(include.path, reply.source_root, root)
      if relative == nil or is_build_output(relative) then
        out[#out + 1] = blocker(target.name, where, string.format('includes "%s", outside the project',
                                relative or include.path), REQUIREMENTS_ROW)
      end
    end
  end
end

local function escaped_values_blockers(entry, where, out)
  for _, key in ipairs({ "defines", "compileOptions", "includes" }) do
    for _, value in ipairs(entry[key] or {}) do
      if values.escapes_cmake(value) then
        out[#out + 1] = blocker(entry.name, where, string.format('carries "%s", which holds a character'
                                .. ' daukle/cmake refuses in a generated file', value), REQUIREMENTS_ROW)
      end
    end
  end
end

local function file_name_of(path)
  return string.match(string.gsub(path, "\\", "/"), "([^/]+)$") or path
end

--- Whether the read's configure loaded the file `find_package(<package>)` reads, module or config.
local function package_was_found(reply, package)
  local wanted = { ["Find" .. package .. ".cmake"] = true, [package .. "Config.cmake"] = true,
                   [string.lower(package) .. "-config.cmake"] = true }
  for _, input in ipairs(reply.cmake_inputs or {}) do
    if wanted[file_name_of(input.path)] then return true end
  end
  return false
end

--- @implNote a link to an imported target becomes a `findPackages` entry named by its namespace,
--- so one with no namespace, or whose namespace no package file provided, has no translation.
local function imported_link_blockers(target, where, reply, out)
  for _, link in ipairs(target.linkLibraries or {}) do
    local name = link.id ~= nil and plan.name_of_id(link.id) or nil
    local abstract = name ~= nil and reply.abstract[name] or nil
    if abstract ~= nil and abstract.imported then
      local package = string.match(name, "^(.-)::")
      if package == nil then
        out[#out + 1] = blocker(target.name, where, string.format('links the imported target "%s", which no'
                                .. ' package provides by name', name), DEPENDENCIES_ROW)
      elseif not package_was_found(reply, package) then
        out[#out + 1] = blocker(target.name, where, string.format('links "%s", and CMake read no Find%s.cmake'
                                .. ' or %sConfig.cmake for it', name, package, package), DEPENDENCIES_ROW)
      end
    end
  end
end

local function languages_of(reply)
  local languages = {}
  for _, target in pairs(reply.targets) do
    for _, group in ipairs(target.compileGroups or {}) do
      if group.language ~= nil then languages[group.language] = true end
    end
  end
  return languages
end

local function target_blockers(target, reply, root, translated_entry, out)
  local where = where_of(target, reply, root)
  if target.type == "UTILITY" then
    out[#out + 1] = blocker(target.name, where, "is a UTILITY target, which daukle/cmake does not declare",
                            LOGIC_ROW)
    return
  end
  if not COMPILED[target.type] then return end
  if is_fetched(target, reply) then
    out[#out + 1] = blocker(target.name, where, "was produced by FetchContent, whose url and digest the"
                            .. " model does not carry", DEPENDENCIES_ROW)
    return
  end
  source_blockers(target, where, reply, root, out)
  include_blockers(target, where, reply, root, out)
  imported_link_blockers(target, where, reply, out)
  if #(target.compileGroups or {}) > 1 then
    out[#out + 1] = blocker(target.name, where, "compiles its sources with different settings, and a"
                            .. " daukle/cmake target has one set", REQUIREMENTS_ROW)
  end
  if translated_entry ~= nil then escaped_values_blockers(translated_entry, where, out) end
end

--- Every construct of the read model a migration cannot carry, in core's blocker shape.
--- @param translated what `migrate_translate.translate` returned
local function of(reply, root, translated)
  local entries = {}
  for _, entry in ipairs(translated.config.targets or {}) do entries[entry.name] = entry end
  local names = {}
  for name, target in pairs(reply.targets) do
    if plan.is_listed(target) then names[#names + 1] = name end
  end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do target_blockers(reply.targets[name], reply, root, entries[name], out) end
  local languages = languages_of(reply)
  if languages.C and languages.CXX then
    out[#out + 1] = blocker("project", "CMakeLists.txt", "compiles C and C++, and daukle/cmake builds one"
                            .. " language per project", LANGUAGE_ROW)
  end
  return out
end

return { of = of }
