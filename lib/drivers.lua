-- One release, not a table keyed by version: which Ninja drives the build is
-- not a user choice, so there is nothing to match and no range to resolve.
local RELEASE = "1.13.2"

-- ninja names every asset by platform alone, and ships ONE universal binary
-- for macOS: its Mach-O header is cafebabe with an architecture count of 2,
-- read from the published zip. The two macOS rows are the same asset on
-- purpose rather than by the coincidence lib/cmakes warns about.
local ASSETS = {
  ["linux/x86_64"]    = "ninja-linux.zip",
  ["linux/aarch64"]   = "ninja-linux-aarch64.zip",
  ["macos/x86_64"]    = "ninja-mac.zip",
  ["macos/aarch64"]   = "ninja-mac.zip",
  ["windows/x86_64"]  = "ninja-win.zip",
  ["windows/aarch64"] = "ninja-winarm64.zip",
}

-- COMPUTED from the published assets rather than transcribed, because ninja
-- publishes no checksum beside them. That makes this a weaker pin than
-- lib/cmakes': it is only as good as the download it was taken from. Retake it
-- from the forge, never from a working tree, which would hash whatever the
-- checkout did to the bytes.
local DIGESTS = {
  ["linux/x86_64"]    = "5749cbc4e668273514150a80e387a957f933c6ed3f5f11e03fb30955e2bbead6",
  ["linux/aarch64"]   = "fd2cacc8050a7f12a16a2e48f9e06fca5c14fc4c2bee2babb67b58be17a607fc",
  ["macos/x86_64"]    = "c99048673aa765960a99cf10c6ddb9f1fad506099ff0a0e137ad8960a88f321b",
  ["macos/aarch64"]   = "c99048673aa765960a99cf10c6ddb9f1fad506099ff0a0e137ad8960a88f321b",
  ["windows/x86_64"]  = "07fc8261b42b20e71d1720b39068c2e14ffcee6396b76fb7a795fb460b78dc65",
  ["windows/aarch64"] = "e52f0bdef9dfb1003229dbd6508a508c4073fd017247002adc66e5e806cb0391",
}

local BASE = "https://github.com/ninja-build/ninja/releases/download/v%s/%s"

local function for_host(request)
  local key = tostring(request.os) .. "/" .. tostring(request.arch)
  local asset = ASSETS[key]
  local digest = DIGESTS[key]
  if asset == nil or digest == nil then
    error(string.format('no pinned Ninja for os "%s" and architecture "%s"',
                        tostring(request.os), tostring(request.arch)), 0)
  end
  return {
    url = string.format(BASE, RELEASE, asset),
    sha256 = digest,
    -- The archive carries the binary at its root with no top-level directory,
    -- so unlike every other table here there is no home to join.
    executable = "ninja",
    full = RELEASE,
  }
end

return { for_host = for_host }
