local state = require("ai_review.state")
local highlights = require("ai_review.highlights")
local git = require("ai_review.git")
local parser = require("ai_review.parser")

local M = {
  ns = nil,
  buf = nil,
  mark_id = nil,
  hunk = nil,
}

local function ensure_ns()
  if not M.ns then
    M.ns = vim.api.nvim_create_namespace("ai_review_diff_view")
  end
  return M.ns
end

local function is_valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function strip_prefix(line)
  return line:sub(2)
end

local function split_hunk(hunk)
  local original = {}
  local current = {}
  local header = hunk.header or ""

  for _, line in ipairs(hunk.patch or {}) do
    local prefix = line:sub(1, 1)
    if line:match("^@@") then
      header = line
    elseif prefix == "-" and not line:match("^%-%-%-") then
      table.insert(original, strip_prefix(line))
    elseif prefix == "+" and not line:match("^%+%+%+") then
      table.insert(current, strip_prefix(line))
    elseif prefix == " " then
      local text = strip_prefix(line)
      table.insert(original, text)
      table.insert(current, text)
    end
  end

  if #original == 0 then
    table.insert(original, "∅")
  end
  if #current == 0 then
    table.insert(current, "∅")
  end

  return header, original, current
end

local function virt_line(text, group)
  return { { text, group } }
end

local function build_virtual_lines(hunk)
  local header, original, current = split_hunk(hunk)
  local lines = {}

  table.insert(lines, virt_line(
    string.format("AI Review Diff Preview: %s  H%s  line %s  [%s]", (hunk.submodule and (hunk.submodule .. "/" .. hunk.file) or (hunk.display_file or hunk.file or "")), tostring(hunk.index or "?"), tostring(hunk.new_start or "?"), hunk.status or "pending"),
    "AiReviewDiffHeader"
  ))
  if header ~= "" then
    table.insert(lines, virt_line(header, "AiReviewMuted"))
  end
  table.insert(lines, virt_line("<<<<<<< ORIGINAL", "AiReviewDiffOriginalLabel"))
  for _, line in ipairs(original) do
    table.insert(lines, virt_line(line, "AiReviewDiffOriginal"))
  end
  table.insert(lines, virt_line("======= AI / CURRENT", "AiReviewDiffCurrentLabel"))
  for _, line in ipairs(current) do
    table.insert(lines, virt_line(line, "AiReviewDiffCurrent"))
  end
  table.insert(lines, virt_line(">>>>>>> END", "AiReviewDiffEndLabel"))

  return lines
end

local function target_buffer_for_hunk(hunk)
  if not hunk or not state.root then
    return nil
  end
  local full = (hunk.repo_root or state.root) .. "/" .. hunk.file
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == full then
      return buf
    end
  end
  return nil
end

function M.close()
  local ns = ensure_ns()
  if is_valid_buf(M.buf) then
    pcall(vim.api.nvim_buf_clear_namespace, M.buf, ns, 0, -1)
  end
  M.buf = nil
  M.mark_id = nil
  M.hunk = nil
end

function M.show(hunk, opts)
  opts = opts or {}
  if not hunk then
    return
  end
  highlights.setup()

  -- Reuse the source buffer that actions.preview()/navigation has just opened.
  local buf = target_buffer_for_hunk(hunk) or vim.api.nvim_get_current_buf()
  if not is_valid_buf(buf) then
    return
  end

  M.close()

  local ns = ensure_ns()
  local line = math.max((hunk.new_start or 1) - 1, 0)
  local line_count = vim.api.nvim_buf_line_count(buf)
  line = math.min(line, math.max(line_count - 1, 0))

  M.mark_id = vim.api.nvim_buf_set_extmark(buf, ns, line, 0, {
    virt_lines = build_virtual_lines(hunk),
    virt_lines_above = true,
    hl_mode = "combine",
  })
  M.buf = buf
  M.hunk = hunk

  if opts.focus_sidebar ~= false and state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
    vim.api.nvim_set_current_win(state.sidebar_win)
  end
end


local function current_buffer_hunk()
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  if file == "" then
    return nil, "current buffer has no file"
  end
  local root, err = git.find_root(file)
  if not root then
    return nil, err or "not inside git repository"
  end
  local rel = vim.fn.fnamemodify(file, ":p"):sub(#root + 2)
  local code, diff_lines = git.diff(root)
  if code ~= 0 then
    return nil, table.concat(diff_lines, "\n")
  end
  local files = parser.parse(diff_lines, "pending", { repo_root = root })
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  for _, f in ipairs(files) do
    if f.path == rel then
      for _, h in ipairs(f.pending or {}) do
        local start_line = math.max(h.new_start or 1, 1)
        local count = math.max(h.new_count or 1, 1)
        local end_line = start_line + count - 1
        if cursor >= start_line and cursor <= end_line then
          return h
        end
      end
      -- If cursor is just above/below a zero-context hunk, choose nearest hunk in file.
      local nearest, best = nil, nil
      for _, h in ipairs(f.pending or {}) do
        local dist = math.abs(cursor - math.max(h.new_start or 1, 1))
        if not best or dist < best then
          nearest, best = h, dist
        end
      end
      return nearest
    end
  end
  return nil, "no pending hunk found for current cursor"
end

function M.toggle_current_hunk()
  local hunk, err = current_buffer_hunk()
  if not hunk then
    vim.notify(err or "No current hunk", vim.log.levels.WARN, { title = "AI Review" })
    return
  end
  if M.is_open() and M.buf == vim.api.nvim_get_current_buf() and M.hunk and M.hunk.id == hunk.id then
    M.close()
    return
  end
  M.show(hunk, { focus_sidebar = false })
end

function M.refresh_if_open(hunk)
  if M.is_open() then
    M.show(hunk)
  end
end

function M.is_open()
  return is_valid_buf(M.buf) and M.mark_id ~= nil
end

return M
