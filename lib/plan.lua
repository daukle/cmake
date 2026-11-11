local FILE = "plan.txt"

local function is_absolute(path)
  return string.match(path, "^/") ~= nil or string.match(path, "^%a:") ~= nil
end

--- @implNote both sides of a proof must spell one file one way, and CMake reports a path through
--- the generated file's `../../..` unresolved, with Windows writing either drive-letter case.
local function normalised(path)
  path = string.gsub(path, "\\", "/")
  path = string.gsub(path, "^(%a):", function(drive) return string.lower(drive) .. ":" end)
  local segments = {}
  for segment in string.gmatch(path, "[^/]+") do
    if segment == ".." and #segments > 0 and segments[#segments] ~= ".." then
      segments[#segments] = nil
    elseif segment ~= "." then
      segments[#segments + 1] = segment
    end
  end
  local joined = table.concat(segments, "/")
  if string.match(path, "^/") then return "/" .. joined end
  return joined
end

local function absolute(path, base)
  if is_absolute(path) then return normalised(path) end
  return normalised(base .. "/" .. path)
end

--- A path below the project as relative to it, else nil.
local function below(path, project_root)
  if path == project_root then return "." end
  local prefix = project_root .. "/"
  if string.sub(path, 1, #prefix) == prefix then return string.sub(path, #prefix + 1) end
  return nil
end

local function path_line(kind, path, base, project_root)
  local full = absolute(path, base)
  local relative = below(full, project_root)
  if relative == nil then return "  " .. kind .. "-outside " .. full end
  return "  " .. kind .. " " .. relative
end

--- The name a file API id gives a target, without its directory hash.
local function name_of_id(id)
  return (string.gsub(id, "::@[%x]+$", ""))
end

local function is_project_interface(reply, name)
  local abstract = reply.abstract[name]
  return abstract ~= nil and not abstract.imported
end

local function source_lines(target, base, project_root)
  local lines = {}
  for _, source in ipairs(target.sources or {}) do
    local kind = source.isGenerated and "source-generated" or "source"
    lines[#lines + 1] = path_line(kind, source.path, base, project_root)
  end
  table.sort(lines)
  return lines
end

local function group_lines(group, base, project_root)
  local standard = group.languageStandard ~= nil and group.languageStandard.standard or "-"
  local lines = { string.format("  group %s standard %s", group.language or "-", standard) }
  for _, include in ipairs(group.includes or {}) do
    lines[#lines + 1] = path_line("include", include.path, base, project_root)
  end
  local seen = {}
  for _, define in ipairs(group.defines or {}) do
    if not seen[define.define] then
      seen[define.define] = true
      lines[#lines + 1] = "  define " .. define.define
    end
  end
  for _, fragment in ipairs(group.compileCommandFragments or {}) do
    lines[#lines + 1] = "  fragment " .. fragment.fragment
  end
  return lines
end

local function link_lines(reply, target)
  local lines = {}
  for _, link in ipairs(target.linkLibraries or {}) do
    if link.id ~= nil then
      local name = name_of_id(link.id)
      if not is_project_interface(reply, name) then lines[#lines + 1] = "  link " .. name end
    elseif link.fragment ~= nil then
      lines[#lines + 1] = "  link-fragment " .. link.fragment
    end
  end
  return lines
end

local function is_listed(target)
  return not target.isGeneratorProvided and target.name ~= "ALL_BUILD" and target.name ~= "ZERO_CHECK"
end

local function append(lines, more)
  for _, line in ipairs(more) do lines[#lines + 1] = line end
end

local function target_block(reply, target, project_root)
  local base = reply.source_root
  local lines = { string.format("target %s %s", target.name, target.type),
                  "  output " .. (target.nameOnDisk or "-") }
  append(lines, source_lines(target, base, project_root))
  for _, group in ipairs(target.compileGroups or {}) do append(lines, group_lines(group, base, project_root)) end
  append(lines, link_lines(reply, target))
  return table.concat(lines, "\n")
end

--- The canonical description of a configured build that both sides of a migration's proof write.
--- @param reply what `file_api.read_reply` returned
--- @param project_root the project's absolute path, in any spelling CMake might use
--- @param test_lines one line per test, already sorted, from `migrate_tests.plan_line`
local function text(reply, project_root, test_lines)
  local root = normalised(project_root)
  local names = {}
  for name, target in pairs(reply.targets) do
    if is_listed(target) then names[#names + 1] = name end
  end
  table.sort(names)
  local blocks = {}
  for _, name in ipairs(names) do blocks[#blocks + 1] = target_block(reply, reply.targets[name], root) end
  if test_lines ~= nil and #test_lines > 0 then blocks[#blocks + 1] = table.concat(test_lines, "\n") end
  return table.concat(blocks, "\n\n") .. "\n"
end

--- A path the reply gives, relative to the project, or nil when it lies outside it.
local function project_relative(path, base, project_root)
  return below(absolute(path, base), normalised(project_root))
end

return { FILE = FILE, text = text, normalised = normalised, project_relative = project_relative,
         name_of_id = name_of_id, is_project_interface = is_project_interface, is_listed = is_listed }
