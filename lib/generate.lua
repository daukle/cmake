local function render(spec)
  local out = {}
  local function put(line) out[#out + 1] = line end
  local function source_path(relative)
    return string.format('"${CMAKE_CURRENT_SOURCE_DIR}/%s/%s"', spec.root, relative)
  end

  put("cmake_minimum_required(VERSION 3.20)")
  put(string.format("project(%s LANGUAGES %s)", spec.target, spec.cmake_language))
  put("")

  if #spec.dependencies > 0 then
    put("include(FetchContent)")
    for index = 1, #spec.dependencies do
      local entry = spec.dependencies[index]
      put(string.format('FetchContent_Declare(%s URL "%s" URL_HASH SHA256=%s)',
                        entry.package, entry.url, entry.sha256))
      put(string.format("FetchContent_MakeAvailable(%s)", entry.package))
    end
    put("")
  end

  -- CONFIGURE_DEPENDS re-globs at build time. Without it a new source file is
  -- invisible until someone reconfigures, which this project has on record as
  -- a trap rather than a preference.
  put("file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS")
  for index = 1, #spec.sources do
    put("     " .. source_path(spec.sources[index]))
  end
  put(")")
  put("")

  if spec.kind == "library" then
    put(string.format("add_library(%s ${DAUKLE_SOURCES})", spec.target))
  else
    put(string.format("add_executable(%s ${DAUKLE_SOURCES})", spec.target))
  end

  if #spec.dependencies > 0 then
    local names = {}
    for index = 1, #spec.dependencies do names[index] = spec.dependencies[index].package end
    put(string.format("target_link_libraries(%s PRIVATE %s)",
                      spec.target, table.concat(names, " ")))
  end

  if spec.includes ~= nil and #spec.includes > 0 then
    put(string.format("target_include_directories(%s PRIVATE", spec.target))
    for index = 1, #spec.includes do
      put("     " .. source_path(spec.includes[index]))
    end
    put(")")
  end

  if spec.defines ~= nil and #spec.defines > 0 then
    local quoted = {}
    for index = 1, #spec.defines do
      quoted[index] = string.format('"%s"', spec.defines[index])
    end
    put(string.format("target_compile_definitions(%s PRIVATE %s)",
                      spec.target, table.concat(quoted, " ")))
  end

  if spec.standard ~= nil then
    put(string.format("set_target_properties(%s PROPERTIES %s %s %s_REQUIRED ON)",
                      spec.target, spec.standard_property, spec.standard,
                      spec.standard_property))
  end

  if spec.kind == "executable" then
    put("")
    -- No verb can execute a binary the build produced, so CMake launches it.
    -- add_dependencies orders it: a DEPENDS clause on add_custom_target names
    -- files, not targets, and would let run execute a stale binary.
    put(string.format('add_custom_target(run COMMAND "$<TARGET_FILE:%s>" USES_TERMINAL)',
                      spec.target))
    put(string.format("add_dependencies(run %s)", spec.target))
  end

  return table.concat(out, "\n") .. "\n"
end

return { render = render }
