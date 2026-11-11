local migrate_read = daukle.require("lib/migrate_read")
local migrate_translate = daukle.require("lib/migrate_translate")
local plan = daukle.require("lib/plan")
local migrate_blockers = daukle.require("lib/migrate_blockers")
local migrate_notes = daukle.require("lib/migrate_notes")
local migrate_owned = daukle.require("lib/migrate_owned")
local migrate_tests = daukle.require("lib/migrate_tests")

local ROOT_FILE = "CMakeLists.txt"

local function within(dir, name)
  if dir == nil or dir == "." then return name end
  return dir .. "/" .. name
end

local function append(list, more)
  for _, item in ipairs(more) do list[#list + 1] = item end
  return list
end

--- @param provision function(context, version, program) -> the provisioned `cmake` or `ctest`
local function run_with(provision)
  return function(context)
    local read = migrate_read.read(context, provision)
    local reply, root = read.reply, read.root
    local translated = migrate_translate.translate(reply, root, migrate_read.BUILD_TYPE,
                                                   daukle.read(within(context.dir, ROOT_FILE)),
                                                   migrate_read.CMAKE_VERSION)
    if #read.tests > 0 then translated.config.tests = migrate_tests.manifest_entries(read.tests) end
    local derived = migrate_read.derived_of(context)
    return {
      manifest = { project = translated.project, version = translated.version,
                   toolchains = { [context.instance] = translated.config } },
      foreign = {},
      blockers = append(migrate_blockers.of(reply, root, translated), read.test_blockers),
      notes = migrate_notes.of(reply, root, translated),
      owned = migrate_owned.paths(context, reply, root),
      proof = { task = context.instance .. ":plan",
                compare = { { old = derived .. "/" .. migrate_read.READ_DIR .. "/" .. plan.FILE,
                              new = derived .. "/" .. plan.FILE, as = "bytes" } } },
    }
  end
end

return { run_with = run_with }
