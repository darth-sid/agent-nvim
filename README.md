# agent.nvim

Lightweight Neovim plugin for spawning and managing Codex or Claude agents in dedicated terminal buffers.

## Features

- Spawn multiple agent sessions as hidden terminal buffers
- Default session names to their numeric IDs and let you rename them later
- Prompt for a unique session name when creating a new agent
- Focus existing sessions in the current window, splits, or floating windows
- List and kill running agents from commands or keymaps
- No runtime dependencies beyond Neovim

## Requirements

- Neovim 0.9+
- CLI binaries for any agent types you configure, such as `codex` or `claude`

## Installation

### lazy.nvim

```lua
{
  "sid/agent.nvim",
  config = function()
    require("agent").setup()
  end,
}
```

### packer.nvim

```lua
use({
  "sid/agent.nvim",
  config = function()
    require("agent").setup()
  end,
})
```

## Configuration

```lua
require("agent").setup({
  default_agent = "claude",
  commands = {
    claude = "claude",
    codex = "codex",
  },
  git_worktree = {
    enabled = false,
    root = ".agent-worktrees",
    branch_prefix = "agent/",
  },
  keymaps = {
    spawn = "<leader>as",
    list = "<leader>al",
    kill = "<leader>ak",
    focus = "<leader>af",
  },
  split = "horizontal",
  -- "horizontal" | "vertical" | "float" | "current"
})
```

Set `keymaps = false` to disable all default mappings.

Set `git_worktree.enabled = true` to always spawn agents in fresh git
worktrees rooted under `root`. By default worktrees are created as sibling
checkouts under `.agent-worktrees/` with branches named
`agent/{id}-{label-slug}`.

## Commands

- `:AgentSpawn[!] [type]`
- `:AgentList`
- `:AgentKill {id|name}`
- `:AgentKillAll`
- `:AgentFocus {id|name}`
- `:AgentRename {id|name} [label]`

`{name}` lookups are exact matches against running agent labels. New labels must
be unique among running agents.

Use `:AgentSpawn!` to force the new session into a fresh git worktree for the
current repository even when `git_worktree.enabled = false`.

## Default Keymaps

- `<leader>as` spawns the default agent in the current checkout
- `<leader>al` opens the agent manager
- `<leader>ak` picks and kills an agent
- `<leader>af` picks and focuses an agent

## Agent Manager

Run `:AgentList` to open the floating manager UI.

- Session rows always include the numeric ID and current label
- Agent terminal buffer names include ID, label, type, and status so standard statuslines show the full session info
- `<CR>` focuses the selected agent
- `r` renames the selected agent
- `x` kills the selected agent
- `q` or `<Esc>` closes the manager

When `:AgentSpawn` opens its prompt, pressing `<CR>` with a blank value falls
back to the next numeric ID and cancelling the prompt creates nothing.

When a session is spawned in a git worktree, the terminal job starts with its
working directory set to that worktree path. The worktree is left on disk after
the agent exits.

## Clipboard and Terminal Tips

- Leave terminal-insert mode with `Ctrl-\ Ctrl-n`
- Paste Neovim’s clipboard register into the current terminal job with:

```lua
vim.keymap.set("t", "<leader>vp", function()
  vim.fn.chansend(vim.b.terminal_job_id, vim.fn.getreg("+"))
end, { desc = "Paste clipboard into terminal" })
```

## Testing

Run the test suite from the repo root:

```bash
bash scripts/test.sh
```

The script expects `nvim`, `luarocks`, and the `luacov` rock to be available.
It refreshes `luacov.stats.out` and writes a text coverage report to
`luacov.report.out`.

## Roadmap Gaps

- No built-in command yet for sending the current buffer, visual selection, or clipboard into an agent session
- No release automation yet beyond CI

## License

MIT
