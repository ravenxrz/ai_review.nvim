local config = require("ai_review.config")
local state = require("ai_review.state")
local highlights = require("ai_review.highlights")
local git = require("ai_review.git")
local parser = require("ai_review.parser")

local M = {}

M.ns = nil
M.decorated = {} -- [bufnr] = true, buffers currently decorated
M.undo_stack = {} -- history of inline accept/reject ops, most recent last

-- Pure core: turn a parsed diff hunk into an inline decoration spec.
-- deleted     : list of removed original line texts (shown as virt_lines)
-- added       : list of added line texts (for intra-line char diff pairing)
-- add_start   : 1-indexed first added line in the current buffer
-- add_count   : number of added lines (0 for pure delete)
-- anchor_row  : 0-indexed row to attach the deleted virt_lines
-- anchor_above: whether virt_lines render above anchor_row
function M.compute_decorations(hunk)
  local deleted = {}
  local added = {}
  for _, line in ipairs(hunk.patch or {}) do
    local prefix = line:sub(1, 1)
    if prefix == "-" and not line:match("^%-%-%-") then
      table.insert(deleted, line:sub(2))
    elseif prefix == "+" and not line:match("^%+%+%+") then
      table.insert(added, line:sub(2))
    end
  end
  local new_start = hunk.new_start or 0
  local add_count = hunk.new_count or 0
  local add_start = new_start > 0 and new_start or 1
  local anchor_row = math.max(new_start - 1, 0)
  return {
    deleted = deleted,
    added = added,
    add_start = add_start,
    add_count = add_count,
    anchor_row = anchor_row,
    anchor_above = true,
  }
end

-- Byte offset (0-indexed) of the start of the k-th UTF-8 char in `s`.
-- For k == #pos + 1 returns #s (one past the end).
local function byteoff(pos, s, k)
  if k > #pos then
    return #s
  end
  return pos[k] - 1
end

-- Pure: intra-line char diff of two strings via common prefix/suffix trimming.
-- Returns nil if identical, otherwise byte ranges [start, stop) of the differing
-- middle region on each side: { a = { a_s, a_e }, b = { b_s, b_e } }.
function M.char_diff(a, b)
  if a == b then
    return nil
  end
  local pa = vim.str_utf_pos(a)
  local pb = vim.str_utf_pos(b)
  local na, nb = #pa, #pb

  local function char_at(s, pos, n, k)
    local sb = byteoff(pos, s, k)
    local eb = byteoff(pos, s, k + 1)
    return s:sub(sb + 1, eb)
  end

  local prefix = 0
  while prefix < na and prefix < nb
    and char_at(a, pa, na, prefix + 1) == char_at(b, pb, nb, prefix + 1) do
    prefix = prefix + 1
  end
  local suffix = 0
  while suffix < (na - prefix) and suffix < (nb - prefix)
    and char_at(a, pa, na, na - suffix) == char_at(b, pb, nb, nb - suffix) do
    suffix = suffix + 1
  end

  local a_s = byteoff(pa, a, prefix + 1)
  local a_e = (na - suffix >= prefix) and byteoff(pa, a, na - suffix + 1) or a_s
  local b_s = byteoff(pb, b, prefix + 1)
  local b_e = (nb - suffix >= prefix) and byteoff(pb, b, nb - suffix + 1) or b_s
  return { a = { a_s, a_e }, b = { b_s, b_e } }
end

local function ensure_ns()
  if not M.ns then
    M.ns = vim.api.nvim_create_namespace("ai_review_inline_diff")
  end
  return M.ns
end

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "AI Review" })
end

-- Find the loaded source buffer that backs a given hunk file.
local function buffer_for_file(root, file)
  local full = (root or state.root) .. "/" .. file
  local normalized = vim.fn.fnamemodify(full, ":p")
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf)
      and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p") == normalized then
      return buf
    end
  end
  return nil
end

-- Re-diff a buffer's file against the index using fresh disk content.
-- Returns { file = relpath, root = repo_root, hunks = {...} }.
local function rediff_buffer(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then
    return nil, "buffer has no file"
  end
  local root, err = git.find_root(file)
  if not root then
    return nil, err or "not a git repo"
  end
  local rel = vim.fn.fnamemodify(file, ":p"):sub(#root + 2)
  local code, diff_lines = git.diff(root)
  if code ~= 0 then
    return nil, table.concat(diff_lines, "\n")
  end
  local files = parser.parse(diff_lines, "pending", { repo_root = root })
  local hunks = {}
  for _, f in ipairs(files) do
    if f.path == rel then
      hunks = f.pending or {}
      break
    end
  end
  return { file = rel, root = root, hunks = hunks }
end

-- Pick the pending hunk under (or nearest to) the cursor.
local function hunk_at_cursor(info)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local nearest, best
  for _, h in ipairs(info.hunks or {}) do
    local start_line = math.max(h.new_start or 1, 1)
    local count = math.max(h.new_count or 1, 1)
    if cursor >= start_line and cursor <= start_line + count - 1 then
      return h
    end
    local dist = math.abs(cursor - start_line)
    if not best or dist < best then
      nearest, best = h, dist
    end
  end
  return nearest
end

-- Pure: build an indent-guide string matching a line's leading whitespace.
-- Places `char` at every indent stop (multiples of sw) and spaces elsewhere,
-- expanding tabs by `ts`, so deleted virt_lines line up like real buffer lines.
function M.indent_guide_string(indent_text, sw, ts, char)
  ts = (ts and ts > 0) and ts or 8
  sw = (sw and sw > 0) and sw or ts
  char = char or "│"
  local width = 0
  for i = 1, #indent_text do
    if indent_text:sub(i, i) == "\t" then
      width = width + (ts - (width % ts))
    else
      width = width + 1
    end
  end
  local cells = {}
  for col = 0, width - 1 do
    cells[col + 1] = (col % sw == 0) and char or " "
  end
  return table.concat(cells)
end

local function place_hunk(buf, ns, hunk)
  local d = M.compute_decorations(hunk)

  -- Pair deleted[i] with added[i] for intra-line (char-level) diff. Only pairs
  -- that both exist are compared; extra deleted/added lines are shown plainly.
  local del_diffs, add_diffs = {}, {}
  local pairs_n = math.min(#d.deleted, #d.added)
  for i = 1, pairs_n do
    local cd = M.char_diff(d.deleted[i], d.added[i])
    if cd then
      del_diffs[i] = cd.a
      add_diffs[i] = cd.b
    end
  end

  -- Deleted (ORIGINAL) lines are shown as virt_lines only; never written back.
  -- Base red background, with the changed characters emphasized brighter.
  -- Indent-guide plugins can't decorate virt_lines, so we draw guides ourselves.
  local ig = (config.options.preview or {}).indent_guide or {}
  local sw = vim.bo[buf].shiftwidth
  local ts = vim.bo[buf].tabstop
  if sw == 0 then sw = ts end

  local function indent_prefix(text)
    if not ig.enabled then
      return nil
    end
    local lead = text:match("^[ \t]*") or ""
    if lead == "" then
      return nil
    end
    local guide = M.indent_guide_string(lead, sw, ts, ig.char or "│")
    return { guide, ig.hl or "Whitespace" }
  end

  local virt_lines = {}
  if #d.deleted > 0 then
    for i, text in ipairs(d.deleted) do
      -- Body is the line with its leading whitespace stripped; the guide prefix
      -- reproduces that indent with guide chars so alignment matches real lines.
      local guide = indent_prefix(text)
      local body = guide and text:gsub("^[ \t]*", "") or text
      local base_off = guide and (#text - #body) or 0
      local seg = del_diffs[i]
      local chunks = {}
      if guide then table.insert(chunks, guide) end
      if seg and seg[2] > seg[1] then
        -- Shift char-diff byte offsets to account for stripped indent.
        local s = math.max(seg[1] - base_off, 0)
        local e = math.max(seg[2] - base_off, 0)
        local before = body:sub(1, s)
        local mid = body:sub(s + 1, e)
        local after = body:sub(e + 1)
        if before ~= "" then table.insert(chunks, { before, "AiReviewInlineDelete" }) end
        table.insert(chunks, { mid, "AiReviewInlineDeleteText" })
        if after ~= "" then table.insert(chunks, { after, "AiReviewInlineDelete" }) end
      else
        table.insert(chunks, { body ~= "" and body or " ", "AiReviewInlineDelete" })
      end
      table.insert(virt_lines, chunks)
    end
  end

  local line_count = vim.api.nvim_buf_line_count(buf)
  local anchor = math.min(d.anchor_row, math.max(line_count - 1, 0))
  if #virt_lines > 0 then
    vim.api.nvim_buf_set_extmark(buf, ns, anchor, 0, {
      virt_lines = virt_lines,
      virt_lines_above = d.anchor_above,
      hl_mode = "combine",
      priority = 200,
    })
  end

  -- Added (CURRENT) lines are highlighted directly in the real buffer, editable.
  -- Full line gets a soft green background; changed characters get a stronger one.
  if d.add_count > 0 then
    local last = math.min(d.add_start + d.add_count - 1, line_count)
    for line = d.add_start, last do
      vim.api.nvim_buf_set_extmark(buf, ns, line - 1, 0, {
        line_hl_group = "AiReviewInlineAdd",
        sign_text = "▎",
        sign_hl_group = "AiReviewInlineSign",
        priority = 190,
      })
      local seg = add_diffs[line - d.add_start + 1]
      if seg and seg[2] > seg[1] then
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, line - 1, seg[1], {
          end_row = line - 1,
          end_col = seg[2],
          hl_group = "AiReviewInlineAddText",
          priority = 195,
        })
      end
    end
  end
end

local function normalize_keys(value)
  if value == false or value == nil then
    return {}
  end
  if type(value) == "table" then
    return value
  end
  return { value }
end

local function attach_keymaps(buf)
  if vim.b[buf].ai_review_inline_keys then
    return
  end
  vim.b[buf].ai_review_inline_keys = true
  local km = ((config.options.keymaps or {}).inline or {})
  local opt = { buffer = buf, silent = true, nowait = true }
  for _, lhs in ipairs(normalize_keys(km.accept)) do
    vim.keymap.set("n", lhs, M.accept_at_cursor,
      vim.tbl_extend("force", opt, { desc = "AI Review accept hunk (inline)" }))
  end
  for _, lhs in ipairs(normalize_keys(km.reject)) do
    vim.keymap.set("n", lhs, M.reject_at_cursor,
      vim.tbl_extend("force", opt, { desc = "AI Review reject hunk (inline)" }))
  end
  for _, lhs in ipairs(normalize_keys(km.undo)) do
    vim.keymap.set("n", lhs, M.undo_last,
      vim.tbl_extend("force", opt, { desc = "AI Review undo last inline accept/reject" }))
  end
end

local redraw_timer

local function schedule_redraw(buf)
  if redraw_timer then
    redraw_timer:stop()
    redraw_timer:close()
  end
  redraw_timer = vim.loop.new_timer()
  redraw_timer:start(150, 0, function()
    vim.schedule(function()
      if redraw_timer then
        redraw_timer:stop()
        redraw_timer:close()
        redraw_timer = nil
      end
      if is_valid_buf(buf) and M.decorated[buf] then
        M.render_buffer(buf)
      end
    end)
  end)
end

local autocmd_installed = false

local function install_autocmds()
  if autocmd_installed then
    return
  end
  autocmd_installed = true
  local group = vim.api.nvim_create_augroup("AiReviewInlineDiff", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = group,
    callback = function(args)
      if M.decorated[args.buf] then
        schedule_redraw(args.buf)
      end
    end,
  })
end

-- Auto-preview: while the sidebar is open, render inline hunks for every source
-- buffer the user enters, so previews appear without pressing `p`.
M.auto_preview_group = nil

local function is_previewable_source_buf(buf)
  if not is_valid_buf(buf) then
    return false
  end
  if vim.bo[buf].buftype ~= "" then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return false
  end
  local ui = require("ai_review.ui")
  -- Reuse the sidebar's source-window filter to skip trees/help/etc.
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return ui.is_source_win(win)
    end
  end
  return true
end

function M.enable_auto_preview()
  if not ((config.options.preview or {}).auto_preview_on_bufenter) then
    return
  end
  if M.auto_preview_group then
    return
  end
  M.auto_preview_group = vim.api.nvim_create_augroup("AiReviewAutoPreview", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    group = M.auto_preview_group,
    callback = function(args)
      local buf = args.buf
      vim.schedule(function()
        if not is_valid_buf(buf) or M.decorated[buf] then
          return
        end
        if is_previewable_source_buf(buf) then
          M.render_buffer(buf)
        end
      end)
    end,
  })
  -- Also decorate the buffer that is already current when the sidebar opens.
  local cur = vim.api.nvim_get_current_buf()
  if is_previewable_source_buf(cur) and not M.decorated[cur] then
    M.render_buffer(cur)
  end
end

function M.disable_auto_preview()
  if M.auto_preview_group then
    pcall(vim.api.nvim_del_augroup_by_id, M.auto_preview_group)
    M.auto_preview_group = nil
  end
end

function M.clear_buffer(buf)
  if not is_valid_buf(buf) then
    return
  end
  local ns = ensure_ns()
  pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
  M.decorated[buf] = nil
end

function M.render_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not is_valid_buf(buf) then
    return
  end
  highlights.setup()
  local ns = ensure_ns()
  pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
  local info = rediff_buffer(buf)
  if not info or #info.hunks == 0 then
    M.decorated[buf] = nil
    return
  end
  for _, hunk in ipairs(info.hunks) do
    place_hunk(buf, ns, hunk)
  end
  attach_keymaps(buf)
  install_autocmds()
  M.decorated[buf] = true
end

function M.close_all()
  for buf in pairs(M.decorated) do
    M.clear_buffer(buf)
  end
  M.decorated = {}
end

-- Compatibility alias for old diff_view call sites.
function M.close()
  M.close_all()
end

-- Event-driven indent-guide plugins (hlchunk, indent-blankline) only repaint on
-- TextChanged/BufWinEnter/WinScrolled. After we jump+center a source window they
-- may still show the pre-scroll indent guides until the user scrolls. hlchunk's
-- WinScrolled handler reads per-window data from vim.v.event, which cannot be
-- populated via nvim_exec_autocmds; its BufWinEnter handler instead recomputes
-- the visible range on its own, so we fire BufWinEnter to force a repaint.
local function nudge_indent_plugins(win)
  if not ((config.options.preview or {}).nudge_indent_plugins) then
    return
  end
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
    pcall(vim.api.nvim_win_call, win, function()
      pcall(vim.api.nvim_exec_autocmds, "BufWinEnter", {
        buffer = buf,
        modeline = false,
      })
    end)
  end)
end

-- Called from sidebar preview/navigation: decorate the hunk's file and center
-- the source window cursor on the hunk.
function M.show(hunk, opts)
  opts = opts or {}
  if not hunk then
    return
  end
  local buf = buffer_for_file(hunk.repo_root or state.root, hunk.file)
    or vim.api.nvim_get_current_buf()
  if not is_valid_buf(buf) then
    return
  end
  M.render_buffer(buf)

  local target_line = math.max(hunk.new_start or 1, 1)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf and win ~= state.sidebar_win then
      local lc = vim.api.nvim_buf_line_count(buf)
      pcall(vim.api.nvim_win_set_cursor, win, { math.min(target_line, lc), 0 })
      pcall(vim.api.nvim_win_call, win, function() vim.cmd("normal! zz") end)
      nudge_indent_plugins(win)
      break
    end
  end

  if opts.focus_sidebar ~= false
    and state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
    vim.api.nvim_set_current_win(state.sidebar_win)
  end
end

-- Save the buffer (if it has unsaved edits) so disk == buffer before diffing.
local function save_if_modified(buf)
  if vim.bo[buf].modified then
    pcall(vim.api.nvim_buf_call, buf, function()
      vim.cmd("silent noautocmd write")
    end)
  end
end

function M.accept_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  save_if_modified(buf)
  local info, err = rediff_buffer(buf)
  if not info then
    notify(err or "rediff failed", vim.log.levels.WARN)
    return
  end
  local hunk = hunk_at_cursor(info)
  if not hunk then
    notify("光标不在任何 pending hunk 上", vim.log.levels.WARN)
    return
  end
  hunk.file = info.file
  hunk.repo_root = info.root
  local code, out = git.apply_hunk_to_index(info.root, hunk)
  if code ~= 0 then
    notify("accept 失败:\n" .. table.concat(out, "\n"), vim.log.levels.ERROR)
    return
  end
  table.insert(M.undo_stack, {
    op = "accept",
    root = info.root,
    file = info.file,
    hunk = vim.deepcopy(hunk),
  })
  M.render_buffer(buf)
  pcall(function() require("ai_review").refresh() end)
end

function M.reject_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  save_if_modified(buf)
  local info, err = rediff_buffer(buf)
  if not info then
    notify(err or "rediff failed", vim.log.levels.WARN)
    return
  end
  local hunk = hunk_at_cursor(info)
  if not hunk then
    notify("光标不在任何 pending hunk 上", vim.log.levels.WARN)
    return
  end
  hunk.file = info.file
  hunk.repo_root = info.root
  local code, out = git.apply_reverse_hunk(info.root, hunk)
  if code ~= 0 then
    notify("reject 失败:\n" .. table.concat(out, "\n"), vim.log.levels.ERROR)
    return
  end
  table.insert(M.undo_stack, {
    op = "reject",
    root = info.root,
    file = info.file,
    hunk = vim.deepcopy(hunk),
  })
  vim.cmd("checktime")
  M.render_buffer(buf)
  pcall(function() require("ai_review").refresh() end)
end

-- Undo the most recent inline accept/reject.
--   accept  -> unstage the hunk from the index (git apply --cached --reverse)
--   reject  -> re-apply the hunk to the working tree (git apply)
function M.undo_last()
  local entry = table.remove(M.undo_stack)
  if not entry then
    notify("没有可撤销的 inline accept/reject 操作", vim.log.levels.WARN)
    return
  end
  local code, out
  if entry.op == "accept" then
    code, out = git.unapply_hunk_from_index(entry.root, entry.hunk)
  else
    code, out = git.apply_hunk(entry.root, entry.hunk)
  end
  if code ~= 0 then
    -- Put it back so the user can retry or resolve manually.
    table.insert(M.undo_stack, entry)
    notify("撤销失败:\n" .. table.concat(out or {}, "\n"), vim.log.levels.ERROR)
    return
  end
  vim.cmd("checktime")
  local buf = buffer_for_file(entry.root, entry.file)
  if is_valid_buf(buf) then
    M.render_buffer(buf)
  end
  notify("已撤销上一个 inline " .. entry.op .. " 操作")
  pcall(function() require("ai_review").refresh() end)
end

function M.is_open()
  return next(M.decorated) ~= nil
end

return M
