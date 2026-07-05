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
    -- Buffer-local mappings installed on the source file buffer while the
    -- Cursor-style inline preview is active. Values may be a string, a list of
    -- strings, or false to disable that mapping.
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
  preview = {
    -- While the sidebar is open, automatically render inline hunk previews for
    -- every source buffer you enter (no need to press `p` first).
    auto_preview_on_bufenter = true,
    -- Deleted lines are shown as virtual lines, which indent-guide plugins
    -- (e.g. hlchunk/indent-blankline) cannot decorate. Draw matching indent
    -- guides ourselves so deleted virt_lines line up with real buffer lines.
    indent_guide = {
      enabled = true,
      char = "│",
      hl = "Whitespace",
    },
    -- Event-driven indent-guide plugins (e.g. hlchunk) only repaint on
    -- TextChanged/WinScrolled. When we jump+center a source buffer from the
    -- sidebar, fire a WinScrolled so those plugins repaint immediately instead
    -- of only after you scroll manually.
    nudge_indent_plugins = true,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
