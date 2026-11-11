local plan = daukle.require("lib/plan")

--- @implNote an `option()` is a BOOL cache entry; CMake's own and FetchContent's are told apart by
--- prefix, and an ADVANCED one is a module's switch rather than the project's.
local function is_project_option(entry)
  if entry.type ~= "BOOL" then return false end
  if string.match(entry.name, "^CMAKE_") or string.match(entry.name, "^FETCHCONTENT_") then return false end
  for _, property in ipairs(entry.properties or {}) do
    if property.name == "ADVANCED" and property.value == "1" then return false end
  end
  return true
end

local function frozen_options(reply)
  local notes = {}
  for _, entry in ipairs(reply.cache_entries or {}) do
    if is_project_option(entry) then notes[#notes + 1] = "frozen " .. entry.name .. "=" .. entry.value end
  end
  table.sort(notes)
  return notes
end

local function install_rules(reply, root)
  local notes = {}
  for _, directory in ipairs(reply.directories or {}) do
    if directory.hasInstallRule then
      local file = plan.project_relative(directory.source .. "/CMakeLists.txt", reply.source_root, root)
      notes[#notes + 1] = "not migrated: install rules in " .. (file or directory.source)
    end
  end
  table.sort(notes)
  return notes
end

--- What a migration reports without blocking: every frozen option, every directory's install
--- rules, and anything the translation dropped (RULES.md, D-280).
local function of(reply, root, translated)
  local notes = frozen_options(reply)
  for _, note in ipairs(install_rules(reply, root)) do notes[#notes + 1] = note end
  for _, dropped in ipairs(translated.dropped) do notes[#notes + 1] = "not migrated: " .. dropped end
  for _, package in ipairs(translated.config.findPackages or {}) do
    notes[#notes + 1] = "found " .. package.name .. " with no version or components: the model does"
                        .. " not carry what the original find_package asked for"
  end
  return notes
end

return { of = of }
