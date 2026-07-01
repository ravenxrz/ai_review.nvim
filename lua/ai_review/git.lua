local config = require("ai_review.config")

local M = {}
local root_cache = {}

local function normalize(path)
  if not path or path == "" then
    return path
  end
  return vim.fn.fnamemodify(path, ":p"):gsub("/+$", "")
end

local function systemlist(cmd)
  local out = vim.fn.systemlist(cmd)
  local code = vim.v.shell_error
  return code, out
end

function M.find_root(start_path)
  local path = start_path
  if not path or path == "" then
    path = vim.api.nvim_buf_get_name(0)
  end
  if path == "" then
    path = vim.loop.cwd()
  end
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ":h")
  dir = normalize(dir)

  if config.options.git.root_cache and root_cache[dir] then
    return root_cache[dir]
  end

  local code, out = systemlist({ "git", "-C", dir, "rev-parse", "--show-toplevel" })
  if code ~= 0 or not out[1] or out[1] == "" then
    return nil, table.concat(out, "\n")
  end
  local root = normalize(out[1])
  if config.options.git.root_cache then
    root_cache[dir] = root
  end
  return root
end

function M.run(root, args)
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, args)
  local code, out = systemlist(cmd)
  return code, out
end

function M.run_async(root, args, cb, opts)
  opts = opts or {}
  local timeout_ms = opts.timeout_ms or ((config.options.scanner or {}).git_timeout_ms) or 5000
  local cmd = { "git", "-C", root }
  vim.list_extend(cmd, args)

  local done = false
  local timer = timeout_ms and vim.loop.new_timer() or nil
  local function finish(code, lines)
    if done then return end
    done = true
    if timer then
      timer:stop()
      timer:close()
    end
    cb(code, lines or {})
  end

  if vim.system then
    local handle
    if timer then
      timer:start(timeout_ms, 0, function()
        if handle then pcall(function() handle:kill(15) end) end
        vim.schedule(function()
          finish(124, { "git command timed out after " .. tostring(timeout_ms) .. "ms: " .. table.concat(cmd, " ") })
        end)
      end)
    end
    handle = vim.system(cmd, { text = true }, function(obj)
      vim.schedule(function()
        local stdout = obj.stdout or ""
        local stderr = obj.stderr or ""
        local lines = stdout ~= "" and vim.split(stdout, "\n", { plain = true, trimempty = true }) or {}
        if obj.code ~= 0 and stderr ~= "" then
          for _, line in ipairs(vim.split(stderr, "\n", { plain = true, trimempty = true })) do
            table.insert(lines, line)
          end
        end
        finish(obj.code or 0, lines)
      end)
    end)
  else
    local output = {}
    local job
    if timer then
      timer:start(timeout_ms, 0, function()
        if job then pcall(vim.fn.jobstop, job) end
        vim.schedule(function()
          finish(124, { "git command timed out after " .. tostring(timeout_ms) .. "ms: " .. table.concat(cmd, " ") })
        end)
      end)
    end
    job = vim.fn.jobstart(cmd, {
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, data)
        for _, line in ipairs(data or {}) do
          if line ~= "" then table.insert(output, line) end
        end
      end,
      on_stderr = function(_, data)
        for _, line in ipairs(data or {}) do
          if line ~= "" then table.insert(output, line) end
        end
      end,
      on_exit = function(_, code)
        vim.schedule(function() finish(code, output) end)
      end,
    })
  end
end

local function limited(out)
  local max_lines = config.options.git.max_diff_lines
  if max_lines and #out > max_lines then
    local trimmed = vim.list_slice(out, 1, max_lines)
    table.insert(trimmed, "")
    table.insert(trimmed, "[ai-review] diff truncated because it exceeded max_diff_lines")
    return trimmed
  end
  return out
end

function M.diff(root)
  local code, out = M.run(root, { "diff", "--unified=0", "--no-ext-diff", "--no-color" })
  return code, limited(out)
end

function M.cached_diff(root)
  local code, out = M.run(root, { "diff", "--cached", "--unified=0", "--no-ext-diff", "--no-color" })
  return code, limited(out)
end

function M.status(root)
  return M.run(root, { "status", "--porcelain=v1" })
end

function M.add_file(root, file)
  return M.run(root, { "add", "--", file })
end

function M.restore_file(root, file)
  return M.run(root, { "restore", "--", file })
end

function M.unstage_file(root, file)
  return M.run(root, { "restore", "--staged", "--", file })
end

local function quote_patch_path(path)
  -- Keep simple relative paths readable. Git accepts a/ and b/ prefixes here.
  return path
end

local function build_hunk_patch(hunk)
  if not hunk or not hunk.file or not hunk.patch or #hunk.patch == 0 then
    return nil, "empty hunk patch"
  end

  local file = quote_patch_path(hunk.file)
  local lines = {
    "diff --git a/" .. file .. " b/" .. file,
    "--- a/" .. file,
    "+++ b/" .. file,
  }
  vim.list_extend(lines, hunk.patch)

  local patch = table.concat(lines, "\n")
  if not patch:match("\n$") then
    patch = patch .. "\n"
  end
  return patch
end

local function apply_hunk_patch(root, hunk, opts)
  local patch, err = build_hunk_patch(hunk)
  if not patch then
    return 1, { err }
  end
  opts = opts or {}
  local cmd = { "git", "-C", root, "apply", "--unidiff-zero", "--whitespace=nowarn" }
  if opts.cached then
    table.insert(cmd, "--cached")
  end
  if opts.reverse then
    table.insert(cmd, "--reverse")
  end
  table.insert(cmd, "-")
  local out = vim.fn.systemlist(cmd, patch)
  return vim.v.shell_error, out
end

function M.apply_reverse_hunk(root, hunk)
  return apply_hunk_patch(root, hunk, { reverse = true })
end

function M.apply_hunk(root, hunk)
  return apply_hunk_patch(root, hunk, {})
end

function M.apply_hunk_to_index(root, hunk)
  return apply_hunk_patch(root, hunk, { cached = true })
end

function M.unapply_hunk_from_index(root, hunk)
  return apply_hunk_patch(root, hunk, { cached = true, reverse = true })
end

function M.delete_untracked(root, file)
  local full = root .. "/" .. file
  return vim.fn.delete(full)
end

function M.is_git_repo(root)
  local code, out = M.run(root, { "rev-parse", "--show-toplevel" })
  if code ~= 0 or not out[1] then
    return false
  end
  return M.realpath(out[1]) == M.realpath(root)
end

function M.realpath(path)
  return vim.loop.fs_realpath(path) or vim.fn.fnamemodify(path, ":p"):gsub("/+$", "")
end

function M.submodules(root)
  local code, out = M.run(root, { "config", "--file", ".gitmodules", "--get-regexp", "path" })
  if code ~= 0 then
    return {}
  end
  local result = {}
  for _, line in ipairs(out) do
    local path = line:match("%S+%.path%s+(.+)$")
    if path and path ~= "" then
      table.insert(result, { path = path, root = root .. "/" .. path })
    end
  end
  return result
end

function M.untracked_files(root, opts)
  opts = opts or {}
  local code, out = M.status(root)
  if code ~= 0 then
    return {}
  end
  local result = {}
  local max_files = opts.max_files or 200
  local max_size = opts.max_file_size or (256 * 1024)
  for _, line in ipairs(out) do
    local path = line:match("^%?%?%s+(.+)$")
    if path and path ~= "" then
      local full = root .. "/" .. path
      if vim.fn.filereadable(full) == 1 then
        local stat = vim.loop.fs_stat(full)
        if stat and stat.type == "file" and stat.size <= max_size then
          table.insert(result, path)
          if #result >= max_files then
            break
          end
        end
      end
    end
  end
  return result
end

function M.read_file_lines(root, file)
  local full = root .. "/" .. file
  local lines = vim.fn.readfile(full)
  if vim.v.shell_error ~= 0 then
    return {}
  end
  return lines
end

return M
