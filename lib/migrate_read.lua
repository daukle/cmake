local file_api = daukle.require("lib/file_api")
local plan = daukle.require("lib/plan")
local migrate_tests = daukle.require("lib/migrate_tests")

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

--- The directory every path of the translation is relative to: the instance's own, which CMake
--- reports as the source directory and `daukle/cmake` resolves an instance's paths against.
local function instance_root_of(reply)
  return reply.source_root
end

--- The tests ctest lists in `build_dir`, building it first when ctest cannot name a program yet.
--- @param build_dir relative to the directory the task or migrator runs in
local function tests_of(cmake, ctest, build_dir, configuration)
  local listed = migrate_tests.listed(ctest, build_dir, configuration)
  if migrate_tests.needs_build(listed) then
    daukle.exec(cmake, { "--build", build_dir, "--config", configuration })
    listed = migrate_tests.listed(ctest, build_dir, configuration)
  end
  return listed
end

local function plan_lines(tests)
  local lines = {}
  for _, test in ipairs(tests) do lines[#lines + 1] = migrate_tests.plan_line(test) end
  return lines
end

--- Configures the project's own CMake files once, with a file API query, and writes the old side
--- of the proof's plan.
--- @param provision function(context, version, program) -> tool handle of `cmake` or `ctest`
--- @return { reply, root, tests, test_blockers }
local function read(context, provision)
  file_api.write_query(READ_DIR)
  local cmake = provision(context, CMAKE_VERSION, "cmake")
  daukle.exec(cmake, { "-S", ".", "-B", read_dir_from_project(context), "-DCMAKE_BUILD_TYPE=" .. BUILD_TYPE },
              { cwd = context.dir or "." })
  local reply = file_api.read_reply(derived_of(context) .. "/" .. READ_DIR, BUILD_TYPE)
  local root = instance_root_of(reply)
  local listed = tests_of(cmake, provision(context, CMAKE_VERSION, "ctest"), READ_DIR, BUILD_TYPE)
  local tests, test_blockers = migrate_tests.of(listed, reply, root)
  daukle.write{ path = READ_DIR .. "/" .. plan.FILE, text = plan.text(reply, root, plan_lines(tests)) }
  return { reply = reply, root = root, tests = tests, test_blockers = test_blockers }
end

return { read = read, tests_of = tests_of, plan_lines = plan_lines, READ_DIR = READ_DIR, CMAKE_VERSION = CMAKE_VERSION, BUILD_TYPE = BUILD_TYPE,
         derived_of = derived_of }
