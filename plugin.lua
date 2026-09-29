daukle.plugin{ api = 1, uses = { "provision", "exec" } }

local function config_of(context)
  return context.toolchain ~= nil and context.toolchain.config or context.config
end

local function version_of(context)
  local version = (context.toolchain ~= nil and context.toolchain.version)
                  or config_of(context).version
  if version == nil then
    error('a cmake toolchain needs a "version": which CMake to provision is not inferred', 0)
  end
  return version
end

daukle.toolchain{
  name = "cmake",
  generate = function(context)
    version_of(context)
    return {}
  end,
}
