local M = {
  root = nil,
  roots = {},
  files = {},
  expanded = {},
  rejected_log = {},
  filter = "all",
  sidebar_win = nil,
  sidebar_buf = nil,
  source_win = nil,
  line_map = {},
  submodules_enabled = true,
  scan = {
    id = 0,
    running = false,
    pending_jobs = 0,
    finished_jobs = 0,
    total_jobs = 0,
    errors = {},
  },
}

function M.set_submodules_enabled(enabled)
  M.submodules_enabled = enabled and true or false
end

function M.toggle_submodules_enabled()
  M.submodules_enabled = not M.submodules_enabled
  return M.submodules_enabled
end

function M.begin_scan(roots)
  -- roots: string (单 root，向后兼容) 或 { {root,label}, ... }
  local list = {}
  if type(roots) == "string" then
    list = { { root = roots, label = nil } }
  else
    list = roots or {}
  end
  M.roots = list
  M.root = list[1] and list[1].root or nil
  M.files = {}
  M.expanded = {}
  M.rejected_log = {}
  M.filter = "all"
  M.line_map = {}
  M.scan.id = M.scan.id + 1
  M.scan.running = true
  M.scan.pending_jobs = 0
  M.scan.finished_jobs = 0
  M.scan.total_jobs = 0
  M.scan.errors = {}
  return M.scan.id
end

function M.finish_scan(scan_id)
  if scan_id ~= M.scan.id then
    return
  end
  M.scan.running = false
end

function M.add_scan_error(scan_id, err)
  if scan_id ~= M.scan.id or not err or err == "" then
    return
  end
  table.insert(M.scan.errors, err)
end

function M.merge_files(new_files)
  local by_key = {}
  local merged = {}

  local function add_file(file)
    local key = (file.repo_root or "") .. "::" .. (file.display_path or file.path)
    if not by_key[key] then
      by_key[key] = {
        path = file.path,
        display_path = file.display_path or file.path,
        repo_root = file.repo_root,
        submodule = file.submodule,
        group_kind = file.group_kind,
        status = file.status or "modified",
        added = 0,
        deleted = 0,
        pending = {},
        accepted = {},
        rejected = {},
      }
      table.insert(merged, by_key[key])
    end
    local target = by_key[key]
    target.added = target.added + (file.added or 0)
    target.deleted = target.deleted + (file.deleted or 0)
    for _, field in ipairs({ "pending", "accepted", "rejected" }) do
      for _, hunk in ipairs(file[field] or {}) do
        table.insert(target[field], hunk)
      end
    end
  end

  for _, file in ipairs(M.files or {}) do
    add_file(file)
  end
  for _, file in ipairs(new_files or {}) do
    add_file(file)
  end

  table.sort(merged, function(a, b)
    local ga = a.submodule or ""
    local gb = b.submodule or ""
    if ga ~= gb then return ga < gb end
    return (a.display_path or a.path) < (b.display_path or b.path)
  end)
  M.files = merged
end

function M.reset_for_root(root)
  if M.root ~= root then
    M.root = root
    M.files = {}
    M.expanded = {}
    M.rejected_log = {}
    M.filter = "all"
    M.line_map = {}
  end
end

local function patch_signature(hunk)
  return table.concat(hunk and hunk.patch or {}, "\n")
end

function M.mark_hunk_status(hunk, status)
  if not hunk or not status then
    return
  end
  hunk.status = status
  if status == "accepted" then
    hunk.id = hunk.file .. ":accepted:" .. tostring(vim.loop.hrtime())
  elseif status == "rejected" then
    hunk.id = hunk.file .. ":rejected:" .. tostring(vim.loop.hrtime())
    hunk.patch_signature = patch_signature(hunk)
  end
end

function M.add_rejected(hunk)
  if not hunk then
    return
  end
  local copy = vim.deepcopy(hunk)
  copy.status = "rejected"
  copy.id = copy.file .. ":rejected:" .. tostring(vim.loop.hrtime())
  copy.patch_signature = patch_signature(copy)
  table.insert(M.rejected_log, 1, copy)
end

function M.remove_rejected(hunk)
  if not hunk then
    return
  end
  local sig = hunk.patch_signature or patch_signature(hunk)
  for i = #M.rejected_log, 1, -1 do
    local item = M.rejected_log[i]
    if item.id == hunk.id or (item.file == hunk.file and (item.patch_signature or patch_signature(item)) == sig) then
      table.remove(M.rejected_log, i)
      return
    end
  end
end

function M.rejected_files()
  local pending_signatures = {}
  for _, file in ipairs(M.files or {}) do
    for _, hunk in ipairs(file.pending or {}) do
      pending_signatures[patch_signature(hunk)] = true
    end
  end

  local by_path = {}
  local files = {}
  for _, hunk in ipairs(M.rejected_log) do
    local sig = hunk.patch_signature or patch_signature(hunk)
    if not pending_signatures[sig] then
      if not by_path[hunk.file] then
        by_path[hunk.file] = {
          path = hunk.file,
          status = "modified",
          added = 0,
          deleted = 0,
          pending = {},
          accepted = {},
          rejected = {},
        }
        table.insert(files, by_path[hunk.file])
      end
      table.insert(by_path[hunk.file].rejected, hunk)
    end
  end
  return files
end

function M.counts()
  local files, pending, accepted, rejected = 0, 0, 0, 0
  for _, file in ipairs(M.files or {}) do
    files = files + 1
    pending = pending + #file.pending
    accepted = accepted + #file.accepted
    rejected = rejected + #file.rejected
  end
  return files, pending, accepted, rejected
end

return M
