[[toc]]

# ai_review.nvim

[中文文档](README.zh-CN.md) | English

A Neovim sidebar for reviewing AI/Codex-generated changes with Git-backed accept/reject operations.

The plugin treats your working tree as an AI review queue:

- pending = unstaged Git diff
- accepted = hunk staged into the Git index during the current sidebar session
- rejected = hunk reverse-applied during the current sidebar session
- manual refresh clears processed rows and shows only remaining pending hunks

It also provides a Cursor-style inline diff preview in the source buffer using virtual lines and buffer highlights. Removed lines are rendered as red virtual lines (never written to your files), while added lines are highlighted directly on the real buffer text so there is no duplicated "after" code and you can keep editing it live.

## Features

- Polished left sidebar listing changed files and hunks.
- Hunk accept/reject via Git patch operations.
- Undo accepted/rejected hunk before refresh.
- Cursor-style inline preview in the source buffer:
  - removed lines shown as red virtual lines (not written to disk)
  - added lines highlighted on the real, editable buffer text
  - no duplicated "after" code
- Accept/reject the hunk under the cursor directly from the source buffer, even after editing it.
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
  "ravenxrz/ai_review.nvim",
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
    inline = {
      accept = "<leader>aa",
      reject = "<leader>ax",
      undo = "<leader>au",
    },
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

### `keymaps.inline`

Controls buffer-local mappings installed on the source file buffer while the Cursor-style inline preview is active. Values can be a string, a list of strings, or `false` to disable. `accept` accepts the hunk under the cursor (stages it), `reject` rejects it (reverts the working-tree change), and `undo` rolls back the most recent inline accept/reject. Both accept and reject save the buffer first, then re-diff, so they stay correct even after you edit the "after" code.

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
- `:AiReviewFocus`
- `:AiReviewFocusSidebar`
- `:AiReviewFocusSource`

## Sidebar keys

| Key | Action |
| --- | --- |
| `<CR>` / `o` | Jump to hunk, or expand/collapse file |
| `p` | Show Cursor-style inline diff preview for current hunk |
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
5. Inspect the Cursor-style inline preview in the source buffer: removed lines appear as red virtual lines, added lines are highlighted on the real editable text.
6. Use `a` to accept, `x` to reject, `u` to undo from the sidebar, or accept/reject the hunk under the cursor directly in the source buffer with the `keymaps.inline` mappings.
7. Press `R` to refresh and remove processed hunks.

## Notes

This plugin does not store persistent review history. Git remains the source of truth.

For a quick, standalone view of a single hunk you can still use `gitsigns.nvim`, e.g. map `require("gitsigns").preview_hunk` to a key such as `<leader>gp`.
