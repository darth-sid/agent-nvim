# agent.nvim

Lightweight Neovim plugin for spawning and managing Codex or Claude agents in dedicated terminal buffers.

## Features

- Spawn multiple agent sessions as hidden terminal buffers
- Focus existing sessions in horizontal, vertical, or floating windows
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
  keymaps = {
    spawn = "<leader>as",
    list = "<leader>al",
    kill = "<leader>ak",
    focus = "<leader>af",
  },
  split = "horizontal",
})
```

Set `keymaps = false` to disable all default mappings.

## Commands

- `:AgentSpawn [type]`
- `:AgentList`
- `:AgentKill {id}`
- `:AgentKillAll`
- `:AgentFocus {id}`

## Default Keymaps

- `<leader>as` spawns the default agent
- `<leader>al` opens the agent manager
- `<leader>ak` picks and kills an agent
- `<leader>af` picks and focuses an agent

## Agent Manager

Run `:AgentList` to open the floating manager UI.

- `<CR>` focuses the selected agent
- `x` kills the selected agent
- `q` or `<Esc>` closes the manager

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

## Roadmap Gaps

- No built-in command yet for sending the current buffer, visual selection, or clipboard into an agent session
- No release automation yet beyond CI

## License

No license file is included yet. Pick one before publishing for public reuse.
