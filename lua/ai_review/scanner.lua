local config = require("ai_review.config")
local git = require("ai_review.git")
local parser = require("ai_review.parser")
local state = require("ai_review.state")

local M = {}

local queue = {}
local active = 0
local render_timer = nil

local function opts()
  local sub = config.options.submodules or {}
  local sc = config.options.scanner or {}
  return {
    submodules = {
      enabled = (sub.enabled ~= false) and (state.submodules_enabled ~= false),
      recursive = sub.recursive ~= false,
      max_depth = sub.max_depth,
      include_untracked = sub.include_untracked ~= false,
    },
    scanner = {
      concurrency = sc.concurrency or 8,
      render_debounce_ms = sc.render_debounce_ms or 80,
      git_timeout_ms = sc.git_timeout_ms or 5000,
    },
  }
end

local function schedule_render()
  local ui = require("ai_review.ui")
  local delay = (config.options.scanner or {}).render_debounce_ms or 80
  if render_timer then
    render_timer:stop()
    render_timer:close()
  end
  render_timer = vim.loop.new_timer()
  render_timer:start(delay, 0, function()
    vim.schedule(function()
      if render_timer then
        render_timer:stop()
        render_timer:close()
        render_timer = nil
      end
      ui.render()
    end)
  end)
end

local function collect_untracked(node, out, include_untracked)
  if not include_untracked then
    return
  end
  local sub_opts = config.options.submodules or {}
  for _, file in ipairs(git.untracked_files(node.root, {
    max_files = sub_opts.max_untracked_files,
    max_file_size = sub_opts.max_untracked_file_size,
  })) do
    local lines = git.read_file_lines(node.root, file)
    table.insert(out, parser.untracked_file(file, lines, "pending", {
      repo_root = node.root,
      display_prefix = "",
      submodule = node.submodule,
      group = node.submodule,
    }))
  end
end

local function parse_repo_result(node, diff_lines, submodules, include_untracked)
  local submodule_paths = {}
  for _, sm in ipairs(submodules) do
    submodule_paths[sm.path] = true
  end

  local parsed = parser.parse(diff_lines, "pending", {
    repo_root = node.root,
    display_prefix = "",
    submodule = node.submodule,
    group = node.submodule,
  })
  local out = {}
  for _, file in ipairs(parsed) do
    if not submodule_paths[file.path] then
      table.insert(out, file)
    end
  end
  collect_untracked(node, out, include_untracked)
  return out
end

local function should_descend(node, sub_opts)
  if not sub_opts.enabled then
    return false
  end
  if sub_opts.max_depth ~= nil and node.depth >= sub_opts.max_depth then
    return false
  end
  if not sub_opts.recursive and node.depth >= 1 then
    return false
  end
  return true
end

local function enqueue(scan_id, node, visited)
  local real = git.realpath(node.root)
  if visited[real] then
    return
  end
  visited[real] = true
  table.insert(queue, { scan_id = scan_id, node = node, visited = visited })
  state.scan.total_jobs = state.scan.total_jobs + 1
  state.scan.pending_jobs = state.scan.pending_jobs + 1
end

local function maybe_done(scan_id)
  if scan_id ~= state.scan.id then
    return
  end
  if active == 0 and #queue == 0 and state.scan.pending_jobs == 0 then
    state.finish_scan(scan_id)
    require("ai_review.ui").render()
  end
end

local run_next

local function finish_job(scan_id)
  active = active - 1
  state.scan.finished_jobs = state.scan.finished_jobs + 1
  state.scan.pending_jobs = math.max(0, state.scan.total_jobs - state.scan.finished_jobs)
  run_next(scan_id)
  maybe_done(scan_id)
end

local function scan_job(job)
  local scan_id = job.scan_id
  local node = job.node
  local o = opts()

  vim.schedule(function()
    if scan_id ~= state.scan.id then finish_job(scan_id) return end

    local submodules = git.submodules(node.root)
    local diff_code, diff_lines = git.diff(node.root)
    if diff_code ~= 0 then
      state.add_scan_error(scan_id, table.concat(diff_lines or {}, "\n"))
    else
      local files = parse_repo_result(node, diff_lines or {}, submodules, o.submodules.include_untracked)
      state.merge_files(files)
      schedule_render()
    end

    if should_descend(node, o.submodules) then
      for _, sm in ipairs(submodules) do
        local child_root = node.root .. "/" .. sm.path
        if git.is_git_repo(child_root) then
          local display = node.submodule and (node.submodule .. "/" .. sm.path) or sm.path
          enqueue(scan_id, {
            root = child_root,
            depth = node.depth + 1,
            submodule = display,
          }, job.visited)
        end
      end
    end

    finish_job(scan_id)
  end)
end

run_next = function(scan_id)
  local concurrency = opts().scanner.concurrency
  while active < concurrency and #queue > 0 do
    local job = table.remove(queue, 1)
    if job.scan_id == scan_id and scan_id == state.scan.id then
      active = active + 1
      scan_job(job)
    end
  end
end

function M.scan(root)
  queue = {}
  active = 0
  local scan_id = state.begin_scan(root)
  enqueue(scan_id, { root = root, depth = 0, submodule = nil }, {})
  require("ai_review.ui").render()
  run_next(scan_id)
  maybe_done(scan_id)
end

return M
