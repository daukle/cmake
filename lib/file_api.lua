local QUERIES = { "codemodel-v2", "cache-v2", "cmakeFiles-v1" }

--- @param build_dir relative to the derived directory, where `daukle.write` writes
local function write_query(build_dir)
  for _, query in ipairs(QUERIES) do
    daukle.write{ path = build_dir .. "/.cmake/api/v1/query/" .. query, text = "" }
  end
end

local function read_json(directory, name)
  return daukle.json_parse(daukle.read(directory .. "/" .. name))
end

--- @implNote the index's name carries a timestamp, so the latest by name is the one the last
--- configure wrote; an earlier configure's index may still sit beside it.
local function latest_index(reply_dir)
  local latest = nil
  for _, entry in ipairs(daukle.list(reply_dir) or {}) do
    if entry.kind == "file" and string.match(entry.name, "^index%-.*%.json$")
       and (latest == nil or entry.name > latest) then
      latest = entry.name
    end
  end
  if latest == nil then
    error("CMake wrote no file API reply in " .. reply_dir .. ", so there is no model to read", 0)
  end
  return latest
end

local function configuration_of(codemodel, wanted)
  for _, configuration in ipairs(codemodel.configurations) do
    if configuration.name == wanted then return configuration end
  end
  return codemodel.configurations[1]
end

local function cache_of(reply_dir, file)
  local entries = read_json(reply_dir, file).entries
  local values = {}
  for _, entry in ipairs(entries) do values[entry.name] = entry.value end
  return values, entries
end

--- The model a configure of `build_dir` left, for one configuration.
--- @param build_dir relative to the project root, where `daukle.read` and `daukle.list` look
--- @return { targets = { [name] = target }, abstract = { [name] = target }, cache = { [name] = value },
---           cache_entries = list, directories = list, cmake_inputs = list, source_root = string,
---           build_root = string }
local function read_reply(build_dir, configuration_name)
  local reply_dir = build_dir .. "/.cmake/api/v1/reply"
  local index = read_json(reply_dir, latest_index(reply_dir))
  local codemodel = read_json(reply_dir, index.reply["codemodel-v2"].jsonFile)
  local configuration = configuration_of(codemodel, configuration_name)
  local cache, cache_entries = cache_of(reply_dir, index.reply["cache-v2"].jsonFile)
  local inputs = read_json(reply_dir, index.reply["cmakeFiles-v1"].jsonFile).inputs
  local reply = { targets = {}, abstract = {}, source_root = codemodel.paths.source,
                  build_root = codemodel.paths.build, cache = cache, cache_entries = cache_entries,
                  directories = configuration.directories or {}, cmake_inputs = inputs }
  for _, entry in ipairs(configuration.targets) do
    reply.targets[entry.name] = read_json(reply_dir, entry.jsonFile)
  end
  for _, entry in ipairs(configuration.abstractTargets or {}) do
    reply.abstract[entry.name] = read_json(reply_dir, entry.jsonFile)
  end
  return reply
end

return { write_query = write_query, read_reply = read_reply }
