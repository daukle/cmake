--[[ Two lines, and they are on opposite sides of a BEHAVIOUR boundary rather
     than being old and new. Measured 2026-10-06 against the provisioned
     binaries: CMake 4.4.3 REFUSES a project whose cmake_minimum_required is
     below 3.5, exiting 1 with a CMake Error, where 3.31 accepts every floor
     and only warns below 3.10. A tree of 23 CMakeLists here declares floors
     from 2.8 to 4.3, so pinning 4.4 alone makes the oldest unbuildable by
     this plugin at all. D-112. ]]
local RELEASES = {
  ["3.31"] = "3.31.12",
  ["4.4"] = "4.4.3",
}

-- The unpacker strips no leading component, so a member path carries the
-- archive's own top-level directory. macOS keeps the binaries inside an app
-- bundle, folded in here so a caller composes one string on every platform.
local HOMES = {
  linux = "cmake-%s-linux-%s",
  windows = "cmake-%s-windows-%s",
  macos = "cmake-%s-macos-universal/CMake.app/Contents",
}

-- Written out although it is the identity today: a table that is right by
-- coincidence is one nobody checks when a row is added, which is how the java
-- plugin shipped an "x64" key that missed on every ordinary host.
local ASSET_ARCH = { x86_64 = "x86_64", aarch64 = "aarch64" }
local WINDOWS_ARCH = { x86_64 = "x86_64", aarch64 = "arm64" }
local EXTENSIONS = { linux = "tar.gz", windows = "zip", macos = "tar.gz" }

-- Transcribed from cmake-<version>-SHA-256.txt, which Kitware publishes beside
-- the assets. Never computed from a file on disk.
local DIGESTS = {
  ["3.31"] = {
    ["linux/x86_64"]    = "0dc2e9a6860f06bf10bd8fadc03e35d9eeb4df46e33763a7e480e987758f385c",
    ["linux/aarch64"]   = "83f8fd91d2038a56556e1400390fcfe42f79602940c494f6c6f1cdae7f9e7f40",
    -- One universal archive serves both Mac architectures, which is why these
    -- two digests are equal on purpose rather than by a copy-paste slip.
    ["macos/x86_64"]    = "799af7fd545db9bf1b9cfe72f8095880e727a2d4e0df0e3dffc3bc7b95c2d3b0",
    ["macos/aarch64"]   = "799af7fd545db9bf1b9cfe72f8095880e727a2d4e0df0e3dffc3bc7b95c2d3b0",
    ["windows/x86_64"]  = "0c4baa40f28b3f8225eb3fdf6946c987b4fe901403b4eaf2fbbd9378100aaa0c",
    ["windows/aarch64"] = "e4160c1842dea858ad376ff2ec17587104515b51714eca5963b8bdd798105553",
  },
  ["4.4"] = {
    ["linux/x86_64"]    = "d6c83076c575bc00b823522ac974bda66d0af05d6ddc30e739c12385cf32c6cc",
    ["linux/aarch64"]   = "2efc974dbd63b4444c0e8494b92f2e80c2d7e635b4b80eac2916985ddd8f72a6",
    ["macos/x86_64"]    = "0c5d65251c14cc884bfa16bdbed3c263ce5bffe2e21c0d0d00962cb0610464fa",
    ["macos/aarch64"]   = "0c5d65251c14cc884bfa16bdbed3c263ce5bffe2e21c0d0d00962cb0610464fa",
    ["windows/x86_64"]  = "4d52ebab7193a698651639ed80d8d04fd903358843572cf44c7fd234cb7c26ab",
    ["windows/aarch64"] = "7b410ddd00e24c7250eec7452da2348a4a70437aa87e9cda0a20d6a85662fcff",
  },
}

local BASE = "https://github.com/Kitware/CMake/releases/download/v%s/%s"

-- An explicit branch rather than "windows and A[x] or B[x]", which would fall
-- back to the non-Windows spelling for a missing Windows row and reintroduce
-- exactly the coincidence the table above exists to avoid.
local function spelled_arch(host_os, arch)
  if host_os == "windows" then return WINDOWS_ARCH[arch] end
  return ASSET_ARCH[arch]
end

local function asset_name(host_os, arch, full)
  if host_os == "macos" then
    return string.format("cmake-%s-macos-universal.tar.gz", full)
  end
  return string.format("cmake-%s-%s-%s.%s", full, host_os,
                       spelled_arch(host_os, arch), EXTENSIONS[host_os])
end

local function home_of(host_os, arch, full)
  if host_os == "macos" then
    return string.format(HOMES.macos, full)
  end
  return string.format(HOMES[host_os], full, spelled_arch(host_os, arch))
end

local function assert_host(request)
  local host_os, arch, version = request.os, request.arch, request.version
  local full = RELEASES[version]
  if full == nil then
    error(string.format('this plugin pins its CMake releases and has none for version "%s"',
                        tostring(version)), 0)
  end
  local digests = DIGESTS[version]
  local digest = digests ~= nil and digests[host_os .. "/" .. arch] or nil
  if digest == nil then
    error(string.format('no pinned CMake %s for os "%s" and architecture "%s"',
                        version, tostring(host_os), tostring(arch)), 0)
  end
  local name = asset_name(host_os, arch, full)
  return {
    url = string.format(BASE, full, name),
    sha256 = digest,
    home = home_of(host_os, arch, full),
    full = full,
  }
end

return { assert_host = assert_host }
