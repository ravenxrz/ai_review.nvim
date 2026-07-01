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
  - `======= AI / CURRENT`
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

## Commands

- `:AiReviewOpen`
- `:AiReviewClose`
- `:AiReviewToggle`
- `:AiReviewRefresh`

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
