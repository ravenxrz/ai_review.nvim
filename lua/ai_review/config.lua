local M = {}

M.defaults = {
  sidebar = {
    side = "left",
    width = 50,
    winfixbuf = true,
    auto_restore_width = false,
    preserve_widths = {
      NvimTree = 40,
      ["neo-tree"] = 40,
      Outline = 25,
    },
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
    max_depth = nil,
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
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
