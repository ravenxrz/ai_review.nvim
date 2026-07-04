[[toc]]

# ai_review.nvim

[English](README.md) | 中文文档

一个用于 review AI/Codex 生成代码改动的 Neovim 侧边栏插件。

它把 Git working tree 当成一个 AI review 队列：

- pending：尚未处理的 unstaged Git diff
- accepted：当前 sidebar 会话中已 accept、已 stage 到 Git index 的 hunk
- rejected：当前 sidebar 会话中已 reject、已从 working tree 回退的 hunk
- 手动 refresh：清理已处理 hunk，只显示剩余 pending hunk

插件还支持在源码 buffer 中显示 Cursor 风格的行内 diff 预览：删除行以红色 virtual lines 显示（不会写入真实文件），新增行则直接在真实 buffer 文本上高亮，因此不会重复显示「改后代码」，而且你可以随时实时编辑它。

## 功能特性

- 左侧 sidebar 显示改动文件和 hunk。
- 基于 Git patch 的 hunk accept/reject。
- 在 refresh 前，可以 undo accepted/rejected hunk。
- 源码 buffer 内 Cursor 风格行内预览：
  - 删除行以红色 virtual lines 显示（不写入磁盘）
  - 新增行在真实、可编辑的 buffer 文本上高亮
  - 不重复显示「改后代码」
- 可直接在源码 buffer 上 accept/reject 光标所在 hunk，编辑后依然正确。
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


## 配置项

完整默认配置：

```lua
require("ai_review").setup({
  sidebar = {
    side = "left", -- "left" 或 "right"
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
    max_depth = nil, -- nil 表示无限递归
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

控制 sidebar 的位置、宽度，以及可选的 `winfixbuf` 隔离。

说明：AI Review 会在 `WinResized` / `VimResized` 后恢复配置的 sidebar 宽度，便于和 NvimTree 等其他侧边栏共存。


### `icons`

控制 sidebar 中使用的符号。如果终端字体不支持图标，可以替换成纯 ASCII 字符。

### `keymaps`

控制 AI Review sidebar 内的 buffer-local 快捷键。配置值可以是字符串，也可以是字符串列表。

### `keymaps.inline`

控制行内预览生效时，安装在源码文件 buffer 上的 buffer-local 快捷键。配置值可以是字符串、字符串列表，或 `false` 表示禁用。`accept` 会 accept 光标所在 hunk（stage 到 index），`reject` 会 reject 它（回退 working tree 改动），`undo` 会撤销最近一次 inline accept/reject。accept 和 reject 都会先保存 buffer 再重新 diff，因此即使你编辑过「改后代码」也依然正确。

### `git`

- `root_cache`：在当前 Neovim session 中缓存 Git root 查找结果。
- `max_diff_lines`：限制超大 diff 输出，避免 UI 卡顿。

### `submodules`

- `enabled`：是否扫描已初始化的 Git submodule。

说明：`submodules.enabled` 只控制初始状态。可以在 sidebar 中按 `S` 或执行 `:AiReviewToggleSubmodules` 在运行时切换 submodule 扫描。

- `recursive`：是否递归扫描 nested submodule。
- `max_depth`：递归深度限制。`nil` 表示无限递归，`1` 表示只扫描第一层 submodule。
- `include_untracked`：是否包含未跟踪的普通文件。
- `max_untracked_files`：每个 repo 最多读取多少个 untracked 文件。
- `max_untracked_file_size`：跳过大于该字节数的 untracked 文件。

### `scanner`

- `async`：启用异步 repo/submodule 扫描。
- `concurrency`：最多同时扫描多少个 repo。
- `render_debounce_ms`：扫描结果流式返回时，sidebar 重绘的 debounce 时间。
- `git_timeout_ms`：异步扫描中 Git 命令的超时时间。

## 命令

- `:AiReviewOpen`：打开 sidebar
- `:AiReviewClose`：关闭 sidebar
- `:AiReviewToggle`：切换 sidebar
- `:AiReviewRefresh`：刷新 sidebar
- `:AiReviewToggleSubmodules`：开关 submodule 扫描并刷新 sidebar
- `:AiReviewFocus`：在 sidebar/source 窗口之间切换焦点
- `:AiReviewFocusSidebar`：聚焦 AI Review sidebar
- `:AiReviewFocusSource`：聚焦源码窗口

## Sidebar 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `<CR>` / `o` | 跳转到 hunk，或展开/折叠文件 |
| `p` | 显示当前 hunk 的 Cursor 风格源码内行内预览 |
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
| `zR` | 展开全部 |
| `zM` | 收起全部 |
| `S` | 开关 submodule 扫描 |
| `?` | 帮助 |
| `q` | 关闭 sidebar |

## 推荐工作流

1. 尽量从干净 working tree 开始。
2. 让 AI/Codex 修改代码。
3. 使用 `:AiReviewToggle` 或你的快捷键打开 AI Review。
4. 使用 `[g` / `]g` 在 hunk 间导航。
5. 在源码 buffer 中查看 Cursor 风格行内预览：删除行显示为红色 virtual lines，新增行在真实可编辑文本上高亮。
6. 在 sidebar 中用 `a` accept、`x` reject、`u` undo，或用 `keymaps.inline` 直接在源码 buffer 上 accept/reject 光标所在 hunk。
7. 使用 `R` refresh，清理已处理 hunk。

## 设计说明

这个插件不会持久化 review 历史。Git 是唯一真实状态来源。

accepted/rejected 状态只在当前 sidebar 会话中临时显示，方便你在 refresh 前撤销操作。按 `R` refresh 后，sidebar 会清掉已处理 hunk，只保留当前仍 pending 的改动。

源码中的行内预览使用 virtual lines 和 buffer 高亮实现，不会写入真实文件，也不会改变 Git diff。

如果你想快速、独立地查看单个 hunk，仍可以使用 `gitsigns.nvim`，例如把 `require("gitsigns").preview_hunk` 映射到 `<leader>gp` 之类的快捷键。
