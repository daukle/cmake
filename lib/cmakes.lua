local RELEASES = {
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

local function asset_name(host_os, arch, full)
  if host_os == "macos" then
    return string.format("cmake-%s-macos-universal.tar.gz", full)
  end
  local spelled = host_os == "windows" and WINDOWS_ARCH[arch] or ASSET_ARCH[arch]
  return string.format("cmake-%s-%s-%s.%s", full, host_os, spelled, EXTENSIONS[host_os])
end

local function home_of(host_os, arch, full)
  if host_os == "macos" then
    return string.format(HOMES.macos, full)
  end
  local spelled = host_os == "windows" and WINDOWS_ARCH[arch] or ASSET_ARCH[arch]
  return string.format(HOMES[host_os], full, spelled)
end

local function for_host(request)
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

return { for_host = for_host }
