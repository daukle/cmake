local RUNTIME_DIRECTORY = "bin"

--- The line that names the compiler a configure used: id, version and path.
--- @implNote CMake prints "The C compiler identification is ..." only on the
--- configure that detects the compiler and caches it, so every later run's log,
--- cmake:build's included, would otherwise not say which compiler built it (D-186).
local function compiler_report(language)
  return string.format('message(STATUS "daukle: %s compiler ${CMAKE_%s_COMPILER_ID}'
                       .. ' ${CMAKE_%s_COMPILER_VERSION} at ${CMAKE_%s_COMPILER}")',
                       language, language, language, language)
end

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

  --- Puts every executable at one path whatever the generator, so cmake:run can
  --- name the binary to daukle.built without knowing which generator CMake chose.
  --- @implNote the generator expression is what stops a multi-config generator
  --- appending its per-configuration subdirectory, for every configuration
  --- including one the user defines, which listing the four standard
  --- RUNTIME_OUTPUT_DIRECTORY_<CONFIG> variants would miss.
  local function put_runtime_directory(target)
    put(string.format('set_target_properties(%s PROPERTIES RUNTIME_OUTPUT_DIRECTORY'
                      .. ' "$<1:${CMAKE_BINARY_DIR}/%s>")', target.name, RUNTIME_DIRECTORY))
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
      put_runtime_directory(target)
    end

    local linked = {}
    for index_of_link = 1, #target.links do linked[#linked + 1] = target.links[index_of_link] end
    for index_of_library = 1, #target.systemLinks do
      linked[#linked + 1] = target.systemLinks[index_of_library]
    end
    if #linked > 0 then
      put(string.format("target_link_libraries(%s PRIVATE %s)",
                        target.name, table.concat(linked, " ")))
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
  put(compiler_report(spec.cmake_language))
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

  return table.concat(out, "\n") .. "\n"
end

return { render = render, RUNTIME_DIRECTORY = RUNTIME_DIRECTORY }
