local file_api = daukle.require("lib/file_api")
local plan = daukle.require("lib/plan")

local READ_DIR = "migrate-read"
local CMAKE_VERSION = "4.4"
local BUILD_TYPE = "Debug"

local function climb_of(dir)
  local climb = ""
  for segment in string.gmatch(dir or "", "[^/]+") do
    if segment ~= "." then climb = climb .. "../" end
  end
  return climb
end

local function derived_of(context)
  return "build/daukle/" .. context.instance
end

--- The path from the project's own directory to the read's build directory.
local function read_dir_from_project(context)
  return climb_of(context.dir) .. derived_of(context) .. "/" .. READ_DIR
end

--- The project root's absolute path, from the source directory CMake reported for the instance.
local function project_root_of(context, reply)
  local climb = climb_of(context.dir)
  if climb == "" then return reply.source_root end
  return reply.source_root .. "/" .. climb
end

--- Configures the project's own CMake files once, with a file API query, and writes the old side
--- of the proof's plan.
--- @param provision_cmake function(context, version) -> tool handle of `cmake`
--- @return reply, project_root, the read's build directory relative to the project root
local function read(context, provision_cmake)
  file_api.write_query(READ_DIR)
  local cmake = provision_cmake(context, CMAKE_VERSION)
  daukle.exec(cmake, { "-S", ".", "-B", read_dir_from_project(context), "-DCMAKE_BUILD_TYPE=" .. BUILD_TYPE },
              { cwd = context.dir or "." })
  local build_dir = derived_of(context) .. "/" .. READ_DIR
  local reply = file_api.read_reply(build_dir, BUILD_TYPE)
  local root = project_root_of(context, reply)
  daukle.write{ path = READ_DIR .. "/" .. plan.FILE, text = plan.text(reply, root) }
  return reply, root, build_dir
end

return { read = read, READ_DIR = READ_DIR, CMAKE_VERSION = CMAKE_VERSION, BUILD_TYPE = BUILD_TYPE,
         derived_of = derived_of }
