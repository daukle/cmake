local function render(spec)
  local out = {}
  local function put(line) out[#out + 1] = line end
  local function source_path(relative)
    return string.format('"${CMAKE_CURRENT_SOURCE_DIR}/%s/%s"', spec.root, relative)
  end

  --- @implNote CONFIGURE_DEPENDS re-globs at build time. Without it a new
  --- source file is invisible until someone reconfigures, which this project
  --- has on record as a trap rather than a preference.
  --- @implNote the variable is per target, because two targets globbing into
  --- one DAUKLE_SOURCES would each compile the other's files.
  local function put_source_glob(target, variable)
    put("file(GLOB " .. variable .. " CONFIGURE_DEPENDS")
    for index = 1, #target.sources do
      put("     " .. source_path(target.sources[index]))
    end
    put(")")
  end

  --- @implNote No verb can execute a binary the build produced, so CMake
  --- launches it. add_dependencies orders it: a DEPENDS clause on
  --- add_custom_target names files, not targets, and would let run execute a
  --- stale binary. VERBATIM is the only portable escaping for the command.
  local function put_run_target(name, target)
    put(string.format('add_custom_target(%s COMMAND "$<TARGET_FILE:%s>" USES_TERMINAL VERBATIM)',
                      name, target.name))
    put(string.format("add_dependencies(%s %s)", name, target.name))
  end

  local function variable_for(index)
    if index == 1 then return "DAUKLE_SOURCES" end
    return "DAUKLE_SOURCES_" .. index
  end

  local function put_target(target, index)
    local variable = variable_for(index)
    put_source_glob(target, variable)
    put("")

    if target.kind == "library" then
      put(string.format("add_library(%s ${%s})", target.name, variable))
    else
      put(string.format("add_executable(%s ${%s})", target.name, variable))
    end

    if #target.links > 0 then
      put(string.format("target_link_libraries(%s PRIVATE %s)",
                        target.name, table.concat(target.links, " ")))
    end

    if target.includes ~= nil and #target.includes > 0 then
      put(string.format("target_include_directories(%s PRIVATE", target.name))
      for index_of_include = 1, #target.includes do
        put("     " .. source_path(target.includes[index_of_include]))
      end
      put(")")
    end

    if target.defines ~= nil and #target.defines > 0 then
      local quoted = {}
      for index_of_define = 1, #target.defines do
        quoted[index_of_define] = string.format('"%s"', target.defines[index_of_define])
      end
      put(string.format("target_compile_definitions(%s PRIVATE %s)",
                        target.name, table.concat(quoted, " ")))
    end

    if target.standard ~= nil then
      put(string.format('set_target_properties(%s PROPERTIES %s "%s" %s_REQUIRED ON)',
                        target.name, spec.standard_property, target.standard,
                        spec.standard_property))
    end
  end

  put("cmake_minimum_required(VERSION 3.20)")
  put(string.format("project(%s LANGUAGES %s)", spec.project_name, spec.cmake_language))
  put("")

  if #spec.dependencies > 0 then
    put("include(FetchContent)")
    for index = 1, #spec.dependencies do
      local entry = spec.dependencies[index]
      put(string.format('FetchContent_Declare(%s URL "%s" URL_HASH "SHA256=%s")',
                        entry.package, entry.url, entry.sha256))
      put(string.format("FetchContent_MakeAvailable(%s)", entry.package))
    end
    put("")
  end

  for index = 1, #spec.targets do
    if index > 1 then put("") end
    put_target(spec.targets[index], index)
  end

  --[[ One run- target per executable, and a bare "run" only where it is
       unambiguous. A project with two executables and no "default" still
       builds; it is cmake:run that has nothing to mean, and that is the run
       TASK's error to raise rather than a reason to refuse the whole file. ]]
  for index = 1, #spec.targets do
    local target = spec.targets[index]
    if target.kind == "executable" then
      put("")
      put_run_target("run-" .. target.task, target)
    end
  end
  if spec.default ~= nil then
    put("")
    put_run_target("run", spec.default)
  end

  return table.concat(out, "\n") .. "\n"
end

return { render = render }
