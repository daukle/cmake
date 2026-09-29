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

local function provision_cmake(context, spec)
  local pick = cmakes.for_host{ os = context.host.os, arch = context.host.arch,
                                version = spec.version }
  local root = daukle.provision{
    url = pick.url,
    sha256 = pick.sha256,
    as = "cmake " .. pick.full,
  }
  local suffix = context.host.os == "windows" and ".exe" or ""
  return root:tool(pick.home .. "/bin/cmake" .. suffix)
end

local function append(argv, extra)
  if extra == nil then return argv end
  for index = 1, #extra do argv[#argv + 1] = extra[index] end
  return argv
end

daukle.task{
  name = "cmake:configure",
  run = function(context)
    local spec = manifest.read(context)
    local cmake = provision_cmake(context, spec)
    local argv = { "-S", ".", "-B", "_b", "-DCMAKE_BUILD_TYPE=" .. spec.buildType }
    if spec.generator ~= nil then
      argv[#argv + 1] = "-G"
      argv[#argv + 1] = spec.generator
    end
    daukle.exec(cmake, append(argv, spec.configureArgs))
  end,
}

daukle.task{
  name = "cmake:build",
  dependsOn = { "cmake:configure" },
  run = function(context)
    local spec = manifest.read(context)
    local cmake = provision_cmake(context, spec)
    -- Both the cache variable at configure and --config here are always passed,
    -- and exactly one takes effect: a single-config generator honours the first
    -- and ignores the second, a multi-config generator does the reverse.
    daukle.exec(cmake, append({ "--build", "_b", "--config", spec.buildType }, spec.buildArgs))
  end,
}

daukle.task{
  name = "cmake:run",
  dependsOn = { "cmake:build" },
  run = function(context)
    local spec = manifest.read(context)
    if spec.kind ~= "executable" then
      error('"kind" is "library", so there is nothing for cmake:run to run', 0)
    end
    local cmake = provision_cmake(context, spec)
    daukle.exec(cmake, append({ "--build", "_b", "--target", "run",
                                "--config", spec.buildType }, spec.runArgs))
  end,
}
