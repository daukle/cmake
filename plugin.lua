daukle.plugin{ api = 1, uses = { "provision", "exec" } }

local manifest = daukle.require("lib/manifest")
local cmakes = daukle.require("lib/cmakes")
local generate = daukle.require("lib/generate")

daukle.toolchain{
  name = "cmake",
  generate = function(context)
    local spec = manifest.read(context)
    cmakes.for_host{ os = context.host.os, arch = context.host.arch, version = spec.version }
    return { ["CMakeLists.txt"] = generate.render(spec) }
  end,
}
