daukle.plugin{ api = 1, uses = { "provision", "exec" } }

local cmakes = daukle.require("lib/cmakes")

local function config_of(context)
  return context.toolchain ~= nil and context.toolchain.config or context.config
end

local function version_of(context)
  local version = (context.toolchain ~= nil and context.toolchain.version)
                  or config_of(context).version
  if version == nil then
    error('a cmake toolchain needs a "version": which CMake to provision is not inferred', 0)
  end
  if string.match(version, "^%d+%.%d+$") == nil then
    error('a cmake toolchain version must be an exact major.minor version such as "4.4",'
          .. ' not a range: this plugin pins its releases and does not match ranges', 0)
  end
  return version
end

daukle.toolchain{
  name = "cmake",
  generate = function(context)
    cmakes.for_host{ os = context.host.os, arch = context.host.arch,
                     version = version_of(context) }
    return {}
  end,
}
