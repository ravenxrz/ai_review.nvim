local M = {}

local function parse_range(start, count)
  return tonumber(start) or 0, tonumber(count) or 1
end

local function parse_hunk_header(line)
  local old_start, old_count, new_start, new_count, tail = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@%s*(.*)$")
  if not old_start then
    return nil
  end
  local os, oc = parse_range(old_start, old_count ~= "" and old_count or "1")
  local ns, nc = parse_range(new_start, new_count ~= "" and new_count or "1")
  return {
    old_start = os,
    old_count = oc,
    new_start = ns,
    new_count = nc,
    header = line,
    tail = tail or "",
  }
end

local function summarize(lines)
  for _, line in ipairs(lines) do
    local prefix = line:sub(1, 1)
    if prefix == "+" or prefix == "-" then
      if not line:match("^%+%+%+") and not line:match("^%-%-%-") then
        local text = vim.trim(line:sub(2))
        if text ~= "" then
          if #text > 38 then
            text = text:sub(1, 35) .. "..."
          end
          if prefix == "-" then
            return "remove: " .. text
          end
          return text
        end
      end
    end
  end
  return "changed lines"
end

local function add_file(files, by_path, path, opts)
  opts = opts or {}
  if not path or path == "" then
    return nil
  end
  if not by_path[path] then
    by_path[path] = {
      path = path,
      display_path = (opts.display_prefix or "") .. path,
      repo_root = opts.repo_root,
      submodule = opts.submodule,
      status = opts.file_status or "modified",
      added = 0,
      deleted = 0,
      pending = {},
      accepted = {},
      rejected = {},
    }
    table.insert(files, by_path[path])
  end
  return by_path[path]
end

function M.parse(lines, status, opts)
  opts = opts or {}
  local files = {}
  local by_path = {}
  local current_file = nil
  local current_hunk = nil
  local hunk_index = {}

  local function finish_hunk()
    if current_file and current_hunk then
      current_hunk.summary = summarize(current_hunk.patch)
      hunk_index[current_file.path] = (hunk_index[current_file.path] or 0) + 1
      current_hunk.index = hunk_index[current_file.path]
      current_hunk.id = current_file.path .. ":" .. current_hunk.status .. ":" .. current_hunk.index .. ":" .. current_hunk.new_start
      table.insert(current_file[status], current_hunk)
      current_hunk = nil
    end
  end

  for _, line in ipairs(lines or {}) do
    if line:match("^diff %-%-git ") then
      finish_hunk()
      local b = line:match(" b/(.+)$")
      current_file = add_file(files, by_path, b, opts)
    elseif line:match("^%+%+%+ ") then
      local path = line:match("^%+%+%+ b/(.+)$")
      if path then
        current_file = add_file(files, by_path, path, opts)
      end
    elseif line:match("^@@ ") then
      finish_hunk()
      local parsed = parse_hunk_header(line)
      if parsed and current_file then
        parsed.file = current_file.path
        parsed.display_file = current_file.display_path
        parsed.repo_root = current_file.repo_root
        parsed.submodule = current_file.submodule
        parsed.status = status
        parsed.patch = { line }
        parsed.summary = "changed lines"
        current_hunk = parsed
      end
    elseif current_hunk then
      table.insert(current_hunk.patch, line)
      local first = line:sub(1, 1)
      if first == "+" and not line:match("^%+%+%+") then
        current_file.added = current_file.added + 1
      elseif first == "-" and not line:match("^%-%-%-") then
        current_file.deleted = current_file.deleted + 1
      end
    end
  end
  finish_hunk()
  return files
end

function M.merge_files(pending_files, accepted_files, rejected_files)
  local files = {}
  local by_path = {}

  local function ensure(file)
    local key = (file.repo_root or "") .. "::" .. (file.display_path or file.path)
    if not by_path[key] then
      by_path[key] = {
        path = file.path,
        display_path = file.display_path or file.path,
        repo_root = file.repo_root,
        submodule = file.submodule,
        status = file.status or "modified",
        added = 0,
        deleted = 0,
        pending = {},
        accepted = {},
        rejected = {},
      }
      table.insert(files, by_path[key])
    end
    return by_path[key]
  end

  local function merge(list, field)
    for _, file in ipairs(list or {}) do
      local target = ensure(file)
      target.added = target.added + (file.added or 0)
      target.deleted = target.deleted + (file.deleted or 0)
      for _, hunk in ipairs(file[field] or {}) do
        table.insert(target[field], hunk)
      end
    end
  end

  merge(pending_files, "pending")
  merge(accepted_files, "accepted")
  merge(rejected_files, "rejected")
  table.sort(files, function(a, b)
    local ga = a.submodule or ""
    local gb = b.submodule or ""
    if ga ~= gb then return ga < gb end
    return (a.display_path or a.path) < (b.display_path or b.path)
  end)
  return files
end


function M.untracked_file(file_path, lines, status, opts)
  opts = opts or {}
  status = status or "pending"
  local file = {
    path = file_path,
    display_path = (opts.display_prefix or "") .. file_path,
    repo_root = opts.repo_root,
    submodule = opts.submodule,
    status = "untracked",
    added = #lines,
    deleted = 0,
    pending = {},
    accepted = {},
    rejected = {},
  }
  local patch = { string.format("@@ -0,0 +1,%d @@", #lines) }
  for _, line in ipairs(lines) do
    table.insert(patch, "+" .. line)
  end
  local hunk = {
    id = file.display_path .. ":" .. status .. ":1:1",
    file = file.path,
    display_file = file.display_path,
    repo_root = file.repo_root,
    submodule = file.submodule,
    status = status,
    kind = "untracked",
    new_file = true,
    index = 1,
    old_start = 0,
    old_count = 0,
    new_start = 1,
    new_count = #lines,
    header = patch[1],
    summary = "new file",
    patch = patch,
  }
  table.insert(file[status], hunk)
  return file
end

return M
