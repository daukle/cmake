daukle.plugin{
  api = 1,
  uses = { "provision", "exec" },
  requires = {
    lifecycle = {
      url = "https://github.com/daukle/lifecycle/releases/download/1.0.0/plugin.lua",
      sha256 = "cc6b7bded429c0259db4c84f450b5f47f8202a75fe5944188037475d77d3d60d",
    },
  },
}

-- A base and its dependents release in lockstep: this digest is the whole of
-- the pin, so any lifecycle release that changes lib/names needs a release
-- here to adopt it. See AUTHORING.md.
local names = daukle.require("lifecycle:lib/names")
local manifest = daukle.require("lib/manifest")
local cmakes = daukle.require("lib/cmakes")
local generate = daukle.require("lib/generate")

daukle.toolchain{
  name = "cmake",
  generate = function(context)
    local spec = manifest.read(context)
    cmakes.assert_host{ os = context.host.os, arch = context.host.arch, version = spec.version }
    return { ["CMakeLists.txt"] = generate.render(spec) }
  end,
}

local function provision_cmake(context, spec)
  local pick = cmakes.assert_host{ os = context.host.os, arch = context.host.arch,
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

daukle.task(names.assert_contract(names.BUILD, {
  name = names.qualify("cmake", names.BUILD),
  dependsOn = { "cmake:configure" },
  run = function(context)
    local spec = manifest.read(context)
    local cmake = provision_cmake(context, spec)
    -- Exactly one of the configure-time cache variable and --config takes
    -- effect, and which one depends on the generator, so both are always sent.
    daukle.exec(cmake, append({ "--build", "_b", "--config", spec.buildType }, spec.buildArgs))
  end,
}))

daukle.task(names.assert_contract(names.RUN, {
  name = names.qualify("cmake", names.RUN),
  dependsOn = { names.qualify("cmake", names.BUILD) },
  run = function(context)
    local spec = manifest.read(context)
    if spec.kind ~= "executable" then
      error('"kind" is "library", so there is nothing for cmake:run to run', 0)
    end
    local cmake = provision_cmake(context, spec)
    daukle.exec(cmake, append({ "--build", "_b", "--target", "run",
                                "--config", spec.buildType }, spec.runArgs))
  end,
}))
