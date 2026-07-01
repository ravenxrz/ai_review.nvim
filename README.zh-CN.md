# ai_review.nvim

[English](README.md) | 中文文档

一个用于 review AI/Codex 生成代码改动的 Neovim 侧边栏插件。

它把 Git working tree 当成一个 AI review 队列：

- pending：尚未处理的 unstaged Git diff
- accepted：当前 sidebar 会话中已 accept、已 stage 到 Git index 的 hunk
- rejected：当前 sidebar 会话中已 reject、已从 working tree 回退的 hunk
- 手动 refresh：清理已处理 hunk，只显示剩余 pending hunk

插件还支持在源码 buffer 中用 virtual lines 显示 conflict-style preview。这个预览受 merge conflict UI 启发，但不会把 conflict marker 写进真实文件。

## 功能特性

- 左侧 sidebar 显示改动文件和 hunk。
- 基于 Git patch 的 hunk accept/reject。
- 在 refresh 前，可以 undo accepted/rejected hunk。
- 源码 buffer 内 conflict-style 预览：
  - `<<<<<<< ORIGINAL`
  - `======= AI / CURRENT`
  - `>>>>>>> END`
- `[g` / `]g` hunk 导航，并自动打开/更新源码内预览。
- 手动 `R` refresh 会清理已处理 hunk，让 sidebar 只关注剩余未处理改动。

## 依赖要求

- 支持 Lua 和 extmark `virt_lines` 的 Neovim。
- Git。
- 可选：`nvim-tree/nvim-web-devicons`，用于文件图标。
- 可选：`gitsigns.nvim`。当前 accept/reject 直接使用 Git patch 操作；源码 buffer 仍兼容 gitsigns。

## 安装

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

本地开发配置示例：

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

## 命令

- `:AiReviewOpen`：打开 sidebar
- `:AiReviewClose`：关闭 sidebar
- `:AiReviewToggle`：切换 sidebar
- `:AiReviewRefresh`：刷新 sidebar

## Sidebar 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `<CR>` / `o` | 跳转到 hunk，或展开/折叠文件 |
| `p` | 显示当前 hunk 的源码内 conflict-style preview |
| `]g` | 下一个 hunk，并自动 preview |
| `[g` | 上一个 hunk，并自动 preview |
| `a` / `s` | accept 当前 pending hunk |
| `x` / `r` | reject 当前 pending hunk |
| `u` | undo accepted/rejected hunk |
| `A` | accept 当前文件 |
| `X` | reject 当前文件 |
| `U` | unstage 当前文件 |
| `F` | 切换 filter |
| `R` | refresh，并清理已处理 hunk |
| `?` | 帮助 |
| `q` | 关闭 sidebar |

## 推荐工作流

1. 尽量从干净 working tree 开始。
2. 让 AI/Codex 修改代码。
3. 使用 `:AiReviewToggle` 或你的快捷键打开 AI Review。
4. 使用 `[g` / `]g` 在 hunk 间导航。
5. 在源码 buffer 中查看 conflict-style preview。
6. 使用 `a` accept，使用 `x` reject，使用 `u` undo。
7. 使用 `R` refresh，清理已处理 hunk。

## 设计说明

这个插件不会持久化 review 历史。Git 是唯一真实状态来源。

accepted/rejected 状态只在当前 sidebar 会话中临时显示，方便你在 refresh 前撤销操作。按 `R` refresh 后，sidebar 会清掉已处理 hunk，只保留当前仍 pending 的改动。

源码中的 conflict-style preview 使用 virtual lines 实现，不会写入真实文件，也不会改变 Git diff。
