local plan = daukle.require("lib/plan")

local PRESETS = { "CMakePresets.json", "CMakeUserPresets.json" }

local function within(dir, name)
  if dir == nil or dir == "." then return name end
  return dir .. "/" .. name
end

local function has_file(directory, name)
  for _, entry in ipairs(daukle.list(directory) or {}) do
    if entry.name == name and entry.kind == "file" then return true end
  end
  return false
end

--- The old tool's files core moves aside once the proof passes: every CMake file the read's
--- configure loaded from the project itself, and the preset files beside the root one.
--- @implNote an input under build/ is a file the read's own configure wrote or fetched, never the
--- project's, and core refuses an owned path at or below build/daukle.
local function paths(context, reply, root)
  local owned, seen = {}, {}
  for _, input in ipairs(reply.cmake_inputs or {}) do
    if not input.isExternal and not input.isCMake and not input.isGenerated then
      local relative = plan.project_relative(input.path, reply.source_root, root)
      if relative ~= nil and relative ~= "build" and string.sub(relative, 1, 6) ~= "build/" then
        local path = within(context.dir, relative)
        if not seen[path] then
          seen[path] = true
          owned[#owned + 1] = path
        end
      end
    end
  end
  for _, preset in ipairs(PRESETS) do
    if has_file(context.dir or ".", preset) then owned[#owned + 1] = within(context.dir, preset) end
  end
  table.sort(owned)
  return owned
end

return { paths = paths }
