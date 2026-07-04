local M = {}

local links = {
  AiReviewTitle = "Title",
  AiReviewRoot = "Directory",
  AiReviewSeparator = "Comment",
  AiReviewFile = "Directory",
  AiReviewStats = "Comment",
  AiReviewSubmoduleStats = "Comment",
  AiReviewHelp = "Comment",
  AiReviewPending = "DiagnosticWarn",
  AiReviewAccepted = "DiffAdd",
  AiReviewRejected = "DiffDelete",
  AiReviewMuted = "Comment",
  AiReviewLineNr = "LineNr",
  AiReviewDiffFooter = "Comment",
  AiReviewDiffCurrentLabel = "DiffAdd",
  AiReviewDiffOriginalLabel = "DiffDelete",
  AiReviewDiffSeparator = "Comment",
  AiReviewDiffEndLabel = "DiffText",
  AiReviewDiffHeader = "Title",
  AiReviewInlineSign = "DiffAdd",
  AiReviewInlineDeleteSign = "DiffDelete",
  AiReviewInlineHint = "Comment",
}

local function set_link(group, target)
  vim.api.nvim_set_hl(0, group, { link = target, default = true })
end

local function set_soft_diff_highlights()
  if vim.o.background == "dark" then
    vim.api.nvim_set_hl(0, "AiReviewDiffOriginal", { bg = "#4a2c2f", default = true })
    vim.api.nvim_set_hl(0, "AiReviewDiffCurrent", { bg = "#2d432d", default = true })
    vim.api.nvim_set_hl(0, "AiReviewInlineAdd", { bg = "#2d432d", default = true })
    vim.api.nvim_set_hl(0, "AiReviewInlineDelete", { bg = "#4a2c2f", fg = "#e0a0a0", default = true })
    vim.api.nvim_set_hl(0, "AiReviewInlineAddText", { bg = "#3d6a3d", default = true })
    vim.api.nvim_set_hl(0, "AiReviewInlineDeleteText", { bg = "#6e3236", fg = "#f2c0c0", default = true })
  else
    vim.api.nvim_set_hl(0, "AiReviewDiffOriginal", { bg = "#ffd6d6", default = true })
    vim.api.nvim_set_hl(0, "AiReviewDiffCurrent", { bg = "#d6efd6", default = true })
    vim.api.nvim_set_hl(0, "AiReviewInlineAdd", { bg = "#d6efd6", default = true })
    vim.api.nvim_set_hl(0, "AiReviewInlineDelete", { bg = "#ffd6d6", fg = "#a04040", default = true })
    vim.api.nvim_set_hl(0, "AiReviewInlineAddText", { bg = "#a6e3a1", default = true })
    vim.api.nvim_set_hl(0, "AiReviewInlineDeleteText", { bg = "#f5a9a9", fg = "#7a1f1f", default = true })
  end
end

function M.setup()
  for group, target in pairs(links) do
    set_link(group, target)
  end
  vim.api.nvim_set_hl(0, "AiReviewSubmoduleStats", { link = "Comment", italic = true, default = true })
  set_soft_diff_highlights()
end

return M
