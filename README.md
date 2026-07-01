# ai_review.nvim

[中文文档](README.zh-CN.md) | English

A Neovim sidebar for reviewing AI/Codex-generated changes with Git-backed accept/reject operations.

The plugin treats your working tree as an AI review queue:

- pending = unstaged Git diff
- accepted = hunk staged into the Git index during the current sidebar session
- rejected = hunk reverse-applied during the current sidebar session
- manual refresh clears processed rows and shows only remaining pending hunks

It also provides an inline conflict-style preview in the source buffer using virtual lines. The preview is inspired by merge-conflict UIs, but it never writes conflict markers into your files.

## Features

- Polished left sidebar listing changed files and hunks.
- Hunk accept/reject via Git patch operations.
- Undo accepted/rejected hunk before refresh.
- Source-buffer preview using virtual lines:
  - `<<<<<<< ORIGINAL`
  - `======= CURRENT`
  - `>>>>>>> END`
- `[g` / `]g` hunk navigation with automatic inline preview.
- Manual refresh clears processed hunks and keeps the sidebar focused on unresolved changes.

## Requirements

- Neovim with Lua support and extmark `virt_lines` support.
- Git.
- Optional: `nvim-tree/nvim-web-devicons` for file icons.
- Optional: `gitsigns.nvim`; source buffers remain compatible with gitsigns, but current accept/reject uses Git patch operations directly.

## Installation

### lazy.nvim

```lua
{
  "your-name/ai_review.nvim",
  dependencies = {
    "lewis6991/gitsigns.nvim",
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    { "<leader>ar", function() require("ai_review").toggle() end, desc = "AI Review" },
  },
  config = function()
    require("ai_review").setup({
      sidebar = {
        side = "left",
        width = 50,
      },
    })
  end,
}
```

For local development:

```lua
{
  dir = "/path/to/ai_review.nvim",
  name = "ai-review.nvim",
  dependencies = {
    "lewis6991/gitsigns.nvim",
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    { "<leader>ar", function() require("ai_review").toggle() end, desc = "AI Review" },
  },
  config = function()
    require("ai_review").setup()
  end,
}
```


## Configuration

Full default configuration:

```lua
require("ai_review").setup({
  sidebar = {
    side = "left", -- "left" or "right"
    width = 50,
    winfixbuf = true,
    auto_restore_width = false,
  },
  icons = {
    title = "󰚩",
    git = "",
    file = "󰈙",
    pending = "●",
    accepted = "✓",
    rejected = "✗",
    expanded = "▾",
    collapsed = "▸",
    added = "+",
    deleted = "-",
  },
  keymaps = {
    jump = { "<CR>", "o" },
    preview = "p",
    accept = { "a", "s" },
    reject = { "x", "r" },
    unstage = "u",
    accept_file = "A",
    reject_file = "X",
    unstage_file = "U",
    refresh = "R",
    filter = "F",
    help = "?",
    close = "q",
    next_hunk = "]g",
    prev_hunk = "[g",
    expand_all = "zR",
    collapse_all = "zM",
    toggle_submodules = "S",
  },
  git = {
    root_cache = true,
    max_diff_lines = 20000,
  },
  submodules = {
    enabled = true,
    recursive = true,
    max_depth = nil, -- nil means unlimited recursion
    include_untracked = true,
    max_untracked_files = 200,
    max_untracked_file_size = 256 * 1024,
  },
  scanner = {
    async = true,
    concurrency = 8,
    render_debounce_ms = 80,
    git_timeout_ms = 5000,
  },
})
```

### `sidebar`

Controls sidebar placement, width, and optional `winfixbuf` isolation.

Note: AI Review restores its configured sidebar width on `WinResized` / `VimResized`, which helps it coexist with other sidebars such as NvimTree.


### `icons`

Controls symbols used in the sidebar. You can replace them with ASCII-only symbols if your terminal font does not support icons.

### `keymaps`

Controls buffer-local mappings inside the AI Review sidebar. Values can be either a string or a list of strings.

### `git`

- `root_cache`: cache Git root lookup results in the current Neovim session.
- `max_diff_lines`: truncate very large diff output to avoid UI stalls.

### `submodules`

- `enabled`: scan initialized Git submodules.

Note: `submodules.enabled` controls the initial state only. You can toggle submodule scanning at runtime with `S` in the sidebar or `:AiReviewToggleSubmodules`.

- `recursive`: scan nested submodules recursively.
- `max_depth`: recursion limit. `nil` means unlimited, `1` means first-level submodules only.
- `include_untracked`: include untracked ordinary files.
- `max_untracked_files`: per-repository untracked file limit.
- `max_untracked_file_size`: skip untracked files larger than this size in bytes.

### `scanner`

- `async`: enable asynchronous repo/submodule scanning.
- `concurrency`: maximum number of repositories scanned concurrently.
- `render_debounce_ms`: debounce sidebar redraws when scan results stream in.
- `git_timeout_ms`: timeout for Git commands used by the async scanner.

## Commands

- `:AiReviewOpen`
- `:AiReviewClose`
- `:AiReviewToggle`
- `:AiReviewRefresh`
- `:AiReviewToggleSubmodules`
- `:AiReviewToggleConflictDiff`
- `:AiReviewFocus`
- `:AiReviewFocusSidebar`
- `:AiReviewFocusSource`

## Sidebar keys

| Key | Action |
| --- | --- |
| `<CR>` / `o` | Jump to hunk, or expand/collapse file |
| `p` | Show inline conflict-style preview for current hunk |
| `]g` | Next hunk and auto preview |
| `[g` | Previous hunk and auto preview |
| `a` / `s` | Accept current pending hunk |
| `x` / `r` | Reject current pending hunk |
| `u` | Undo accepted/rejected hunk |
| `A` | Accept current file |
| `X` | Reject current file |
| `U` | Unstage current file |
| `F` | Cycle filter |
| `R` | Refresh; clears processed rows |
| `zR` | Expand all |
| `zM` | Collapse all |
| `S` | Toggle submodule scanning |
| `?` | Help |
| `q` | Close sidebar |

## Workflow

1. Start from a clean worktree when possible.
2. Let your AI tool modify files.
3. Open AI Review with `:AiReviewToggle` or your keymap.
4. Navigate hunks with `[g` / `]g`.
5. Inspect inline conflict-style preview in the source buffer.
6. Use `a` to accept, `x` to reject, `u` to undo.
7. Press `R` to refresh and remove processed hunks.

## Notes

This plugin does not store persistent review history. Git remains the source of truth.
