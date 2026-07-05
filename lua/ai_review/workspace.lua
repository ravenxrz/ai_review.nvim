local git = require("ai_review.git")

local M = {}

local function nvim_tree_ws()
  local ok, mod = pcall(require, "nvim-tree.workspace")
  if not ok then
    return nil
  end
  return mod
end

function M.is_active()
  local mod = nvim_tree_ws()
  if not mod or not mod.is_active then
    return false
  end
  local ok, active = pcall(mod.is_active)
  return ok and active == true
end

function M.folders()
  local mod = nvim_tree_ws()
  if not mod or not mod.folders then
    return {}
  end
  local ok, folders = pcall(mod.folders)
  if not ok or type(folders) ~= "table" then
    return {}
  end
  return folders
end

-- Pure, injectable core for testing.
-- @param folders string[] absolute workspace folder paths
-- @param find_root fun(path):string?,string? resolves a path to its git toplevel
-- @return roots {root:string,label:string}[], errors string[]
function M._resolve(folders, find_root)
  find_root = find_root or git.find_root
  local roots, errors = {}, {}
  local seen = {}
  for _, folder in ipairs(folders or {}) do
    local root, err = find_root(folder)
    if root then
      if not seen[root] then
        seen[root] = true
        table.insert(roots, { root = root, label = vim.fn.fnamemodify(root, ":t") })
      end
    else
      table.insert(errors, folder .. ": " .. (err or "not a git repository"))
    end
  end
  return roots, errors
end

function M.roots()
  return M._resolve(M.folders())
end

return M
