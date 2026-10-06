daukle.plugin{
  api = 1,
  uses = { "provision", "exec" },
  requires = {
    lifecycle = {
      url = "https://github.com/daukle/lifecycle/releases/download/1.0.0/plugin.lua",
      sha256 = "cc6b7bded429c0259db4c84f450b5f47f8202a75fe5944188037475d77d3d60d",
    },
    -- "cc" and not "c": core refuses a one-letter alias, because a letter
    -- before a colon is a Windows drive letter and daukle.require("c:...")
    -- could never reach it. It is also what the architecture calls this
    -- toolchain.
    cc = {
      url = "https://github.com/daukle/c/releases/download/1.0.0/plugin.lua",
      sha256 = "e87dcffd52e768b0edc736c5727de15b52574d822818840ff0d8e467cfc3f57e",
    },
  },
}

-- A base and its dependents release in lockstep: this digest is the whole of
-- the pin, so any lifecycle release that changes lib/names needs a release
-- here to adopt it. See AUTHORING.md.
local names = daukle.require("lifecycle:lib/names")
local compilers = daukle.require("cc:lib/compilers")
local manifest = daukle.require("lib/manifest")
local cmakes = daukle.require("lib/cmakes")
local drivers = daukle.require("lib/drivers")
local generate = daukle.require("lib/generate")

daukle.toolchain{
  name = "cmake",
  generate = function(context)
    local spec = manifest.read(context)
    cmakes.assert_host{ os = context.host.os, arch = context.host.arch, version = spec.version }
    -- Both are pure table lookups, and both raise here rather than at configure
    -- time, so a host this plugin cannot serve is named by sync and not by a
    -- CMake invocation several steps later.
    if spec.compiler ~= nil then
      compilers.for_host{ os = context.host.os, arch = context.host.arch, version = spec.compiler }
      drivers.for_host{ os = context.host.os, arch = context.host.arch }
    end
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

local function executable_suffix(context)
  return context.host.os == "windows" and ".exe" or ""
end

-- root:path and not root:tool: a tool handle is opaque and only ever
-- executable, and these two are NAMED to CMake as arguments rather than run by
-- daukle. CMake reads a cache value with backslashes as escapes, so a Windows
-- path is spelled the way CMake spells its own.
local function named_path(root, member)
  return (string.gsub(root:path(member), "\\", "/"))
end

local function provision_compiler(context, spec)
  local pick = compilers.for_host{ os = context.host.os, arch = context.host.arch,
                                   version = spec.compiler }
  local root = daukle.provision{
    url = pick.url,
    sha256 = pick.sha256,
    -- The same label daukle/c uses, so a project with both toolchains
    -- provisions one clang rather than two identical trees.
    as = "clang " .. spec.compiler,
  }
  return named_path(root, pick.home .. "/bin/clang" .. executable_suffix(context))
end

local function provision_ninja(context)
  local pick = drivers.for_host{ os = context.host.os, arch = context.host.arch }
  local root = daukle.provision{ url = pick.url, sha256 = pick.sha256,
                                 as = "ninja " .. pick.full }
  return named_path(root, pick.executable .. executable_suffix(context))
end

-- The whole of what "compiler" does, kept in one place because the three
-- settings are one decision: a provisioned compiler is unreachable without a
-- generator that honours it, and that generator is unusable without a build
-- program the host does not have.
local function append_toolchain(argv, context, spec)
  if spec.compiler == nil then
    if spec.generator ~= nil then
      argv[#argv + 1] = "-G"
      argv[#argv + 1] = spec.generator
    end
    return argv
  end
  argv[#argv + 1] = "-G"
  argv[#argv + 1] = "Ninja"
  argv[#argv + 1] = "-DCMAKE_MAKE_PROGRAM=" .. provision_ninja(context)
  argv[#argv + 1] = "-DCMAKE_C_COMPILER=" .. provision_compiler(context, spec)
  return argv
end

--[[ The ambiguity lives here rather than in generation, because a project with
     two executables and no favourite is a buildable project: refusing it when
     the file is written would take cmake:build down with cmake:run.
     @implNote the remedy named is "default" and not a per-target task,
     because there is no per-target task yet and an error message that names
     one would be a lie. D-110 carries why: registering one costs every
     project using this plugin the requirement that its manifest be called
     daukle.toml, which is a coverage loss to buy a convenience. ]]
local function refuse_an_unrunnable_project(spec)
  if spec.default ~= nil then return end

  local runnable = {}
  for index = 1, #spec.targets do
    local target = spec.targets[index]
    if target.kind == "executable" then runnable[#runnable + 1] = target.name end
  end
  if #runnable == 0 then
    error("this project declares no executable target, so there is nothing for cmake:run to run",
          0)
  end
  error('this project declares ' .. #runnable .. ' executable targets, so "cmake:run" does not'
        .. ' name one: set "default" to the one it should mean, out of '
        .. table.concat(runnable, ", "), 0)
end

daukle.task{
  name = "cmake:configure",
  run = function(context)
    local spec = manifest.read(context)
    local cmake = provision_cmake(context, spec)
    local argv = { "-S", ".", "-B", "_b", "-DCMAKE_BUILD_TYPE=" .. spec.buildType }
    append_toolchain(argv, context, spec)
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
    refuse_an_unrunnable_project(spec)
    local cmake = provision_cmake(context, spec)
    daukle.exec(cmake, append({ "--build", "_b", "--target", "run",
                                "--config", spec.buildType }, spec.runArgs))
  end,
}))
