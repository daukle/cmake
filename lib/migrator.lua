local migrate_read = daukle.require("lib/migrate_read")
local migrate_translate = daukle.require("lib/migrate_translate")
local plan = daukle.require("lib/plan")

local ROOT_FILE = "CMakeLists.txt"

local function within(dir, name)
  if dir == nil or dir == "." then return name end
  return dir .. "/" .. name
end

--- @param provision_cmake function(context, version) -> the provisioned `cmake` tool
local function run_with(provision_cmake)
  return function(context)
    local reply, root = migrate_read.read(context, provision_cmake)
    local translated = migrate_translate.translate(reply, root, migrate_read.BUILD_TYPE,
                                                   daukle.read(within(context.dir, ROOT_FILE)),
                                                   migrate_read.CMAKE_VERSION)
    local derived = migrate_read.derived_of(context)
    return {
      manifest = { project = translated.project, version = translated.version,
                   toolchains = { [context.instance] = translated.config } },
      foreign = {},
      blockers = {},
      owned = {},
      proof = { task = context.instance .. ":plan",
                compare = { { old = derived .. "/" .. migrate_read.READ_DIR .. "/" .. plan.FILE,
                              new = derived .. "/" .. plan.FILE, as = "bytes" } } },
    }
  end
end

return { run_with = run_with }
