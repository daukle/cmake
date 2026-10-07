-- No daukle.toml beside this file, which core accepts: with no primary
-- manifest it falls back to the overlay, so daukle.manifest names a Lua file
-- and daukle.parse refuses to run one. Parsing it unguarded was fatal on
-- EVERY command, not merely on the per-target tasks that wanted it.
daukle.config.schema = 1
daukle.config.project = "example/app"
daukle.config.version = "1.0.0"
daukle.config.modules = {}
daukle.config.plugins = { cmake = "./plugins/cmake" }
daukle.config.toolchains = {
  cmake = {
    version = "4.4",
    targets = {
      { name = "Greeter", kind = "library", sources = { "src/lib/*.c" } },
      { name = "app", sources = { "src/app/*.c" }, links = { "Greeter" } },
    },
  },
}
