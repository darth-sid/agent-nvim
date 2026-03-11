local T = require("tests.helpers")

T.test("config.setup loads defaults for nil and false", function()
  local config = T.reload("agent.config")

  config.setup(nil)
  T.eq(config.opts.default_agent, "claude")
  T.eq(config.opts.commands.codex, "codex")
  T.eq(config.opts.git_worktree.enabled, false)
  T.eq(config.opts.git_worktree.root, ".agent-worktrees")
  T.eq(config.opts.split, "horizontal")

  config.setup(false)
  T.eq(config.opts.keymaps.focus, "<leader>af")
end)

T.test("config.setup deep merges nested tables", function()
  local config = T.reload("agent.config")

  config.setup({
    default_agent = "codex",
    commands = { claude = "claude --dangerously-skip-permissions" },
    keymaps = { spawn = "zs" },
    split = "current",
  })

  T.eq(config.opts.default_agent, "codex")
  T.eq(config.opts.commands.claude, "claude --dangerously-skip-permissions")
  T.eq(config.opts.commands.codex, "codex")
  T.eq(config.opts.keymaps.spawn, "zs")
  T.eq(config.opts.keymaps.list, "<leader>al")
  T.eq(config.opts.split, "current")
end)
