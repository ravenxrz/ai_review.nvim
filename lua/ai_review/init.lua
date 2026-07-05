local config = require("ai_review.config")
local git = require("ai_review.git")
local parser = require("ai_review.parser")
local state = require("ai_review.state")
local ui = require("ai_review.ui")
local highlights = require("ai_review.highlights")
local workspace = require("ai_review.workspace")

local M = {}

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "AI Review" })
end

-- 解析扫描目标：workspace 激活时用所有 project roots，否则回退到当前 buffer 的 git root。
-- @return roots {root,label}[]|nil, errors string[]|nil, fatal_err string|nil
local function resolve_scan_roots()
  if workspace.is_active() then
    local roots, errs = workspace.roots()
    if #roots > 0 then
      return roots, errs, nil
    end
  end
  local root, err = git.find_root(vim.api.nvim_buf_get_name(0))
  if not root then
    return nil, nil, err
  end
  return { { root = root, label = nil } }, nil, nil
end

function M.refresh()
  local roots, errs, fatal = resolve_scan_roots()
  if not roots then
    notify("Not inside a Git repository: " .. (fatal or ""), vim.log.levels.WARN)
    return
  end
  require("ai_review.inline_diff").close_all()
  require("ai_review.scanner").scan(roots)
  if errs and #errs > 0 then
    notify("Some workspace folders were skipped:\n" .. table.concat(errs, "\n"), vim.log.levels.WARN)
  end
end

function M.open()
  local roots, _, fatal = resolve_scan_roots()
  if not roots then
    notify("Not inside a Git repository: " .. (fatal or ""), vim.log.levels.WARN)
    return
  end
  ui.ensure_sidebar()
  M.refresh()
  ui.focus()
end

function M.close()
  ui.close()
end

function M.toggle()
  if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
    M.close()
  else
    M.open()
  end
end

function M.setup(opts)
  config.setup(opts)
  state.set_submodules_enabled(config.options.submodules.enabled ~= false)
  highlights.setup()

  vim.api.nvim_create_user_command("AiReviewOpen", M.open, {})
  vim.api.nvim_create_user_command("AiReviewClose", M.close, {})
  vim.api.nvim_create_user_command("AiReviewToggle", M.toggle, {})
  vim.api.nvim_create_user_command("AiReviewRefresh", M.refresh, {})
  vim.api.nvim_create_user_command("AiReviewToggleSubmodules", function() require("ai_review.actions").toggle_submodules() end, {})
  vim.api.nvim_create_user_command("AiReviewFocusSidebar", function() require("ai_review.ui").focus() end, {})
  vim.api.nvim_create_user_command("AiReviewFocusSource", function() require("ai_review.ui").focus_source() end, {})
  vim.api.nvim_create_user_command("AiReviewFocus", function() require("ai_review.ui").toggle_focus() end, {})
end

return M
