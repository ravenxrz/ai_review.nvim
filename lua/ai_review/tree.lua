local config = require("ai_review.config")

local M = {}

local function split_path(path)
  local parts = {}
  for part in tostring(path or ""):gmatch("[^/]+") do
    table.insert(parts, part)
  end
  return parts
end

local function new_node(kind, name, key)
  return {
    kind = kind,
    name = name,
    key = key,
    children = {},
    child_map = {},
    added = 0,
    deleted = 0,
    pending_count = 0,
    accepted_count = 0,
    rejected_count = 0,
  }
end

local function count_hunks(file)
  return #(file.pending or {}), #(file.accepted or {}), #(file.rejected or {})
end

local function add_counts(node, file)
  local p, a, r = count_hunks(file)
  node.added = node.added + (file.added or 0)
  node.deleted = node.deleted + (file.deleted or 0)
  node.pending_count = node.pending_count + p
  node.accepted_count = node.accepted_count + a
  node.rejected_count = node.rejected_count + r
end

local function child(parent, kind, name, key)
  if not parent.child_map[key] then
    local node = new_node(kind, name, key)
    parent.child_map[key] = node
    table.insert(parent.children, node)
  end
  return parent.child_map[key]
end

local function sorted_children(node)
  table.sort(node.children, function(a, b)
    if a.kind ~= b.kind then
      local order = { dir = 1, file = 2, submodule = 3, hunk = 4 }
      return (order[a.kind] or 99) < (order[b.kind] or 99)
    end
    return a.name < b.name
  end)
  return node.children
end

function M.build(files)
  local root = new_node("root", "root", "root::")
  for _, file in ipairs(files or {}) do
    local group = file.submodule or ""
    local parent = root
    if group ~= "" then
      local key = "submodule::" .. group
      parent = child(root, "submodule", group, key)
      parent.submodule = group
      add_counts(parent, file)
    end

    local display = file.display_path or file.path
    local parts = split_path(display)
    local accum = ""
    for i = 1, math.max(#parts - 1, 0) do
      accum = accum == "" and parts[i] or (accum .. "/" .. parts[i])
      local key = "dir::" .. group .. "::" .. accum
      parent = child(parent, "dir", parts[i], key)
      add_counts(parent, file)
    end

    local file_name = parts[#parts] or display
    local file_key = "file::" .. group .. "::" .. display
    local file_node = child(parent, "file", file_name, file_key)
    file_node.file = file
    file_node.path = file.path
    file_node.display_path = display
    file_node.repo_root = file.repo_root
    file_node.submodule = file.submodule
    add_counts(file_node, file)

    local hunks = {}
    vim.list_extend(hunks, file.pending or {})
    vim.list_extend(hunks, file.accepted or {})
    vim.list_extend(hunks, file.rejected or {})
    table.sort(hunks, function(a, b)
      return (a.new_start or 0) < (b.new_start or 0)
    end)
    for _, hunk in ipairs(hunks) do
      local hkey = "hunk::" .. group .. "::" .. display .. "::" .. tostring(hunk.id or hunk.index)
      local hnode = new_node("hunk", "H" .. tostring(hunk.index or "?"), hkey)
      hnode.hunk = hunk
      hnode.file = file
      table.insert(file_node.children, hnode)
    end
  end
  return root
end

local function has_visible_hunks(node, filter)
  if node.kind == "hunk" then
    return filter == "all" or node.hunk.status == filter
  end
  for _, c in ipairs(node.children or {}) do
    if has_visible_hunks(c, filter) then
      return true
    end
  end
  return false
end

local function status_icon(status)
  if status == "accepted" then
    return config.options.icons.accepted
  elseif status == "rejected" then
    return config.options.icons.rejected
  end
  return config.options.icons.pending
end

local function counts_text(node)
  if (node.added or 0) == 0 and (node.deleted or 0) == 0 then
    return ""
  end
  return string.format("+%d -%d", node.added or 0, node.deleted or 0)
end

local function truncate(text, width)
  if #text <= width then
    return text
  end
  return "…" .. text:sub(#text - width + 2)
end

local function add_line(out, line_map, text, ref)
  table.insert(out, text)
  table.insert(line_map, ref)
end

local function flatten_node(node, expanded, filter, out, line_map, depth)
  if node.kind ~= "root" and not has_visible_hunks(node, filter) then
    return
  end

  local indent = string.rep("  ", depth)
  if node.kind == "submodule" then
    local is_expanded = expanded[node.key] ~= false
    local arrow = is_expanded and config.options.icons.expanded or config.options.icons.collapsed
    add_line(out, line_map, string.format("%s%s [submodule] %s", indent, arrow, node.name), { kind = "group", key = node.key, group = node.name })
    if not is_expanded then return end
  elseif node.kind == "dir" then
    local is_expanded = expanded[node.key] ~= false
    local arrow = is_expanded and config.options.icons.expanded or config.options.icons.collapsed
    add_line(out, line_map, string.format("%s%s %s", indent, arrow, node.name), { kind = "dir", key = node.key })
    if not is_expanded then return end
  elseif node.kind == "file" then
    local is_expanded = expanded[node.key] ~= false
    local arrow = is_expanded and config.options.icons.expanded or config.options.icons.collapsed
    local ct = counts_text(node)
    local label = string.format("%s%s %s", indent, arrow, node.name)
    if ct ~= "" then
      local width = math.max(12, config.options.sidebar.width - #ct - 2)
      label = string.format("%-" .. tostring(width) .. "s %s", truncate(label, width), ct)
    end
    add_line(out, line_map, label, { kind = "file", key = node.key, file = node.path, file_obj = node.file })
    if not is_expanded then return end
  elseif node.kind == "hunk" then
    local h = node.hunk
    if filter ~= "all" and h.status ~= filter then return end
    local icon = status_icon(h.status)
    local summary = h.summary or "changed lines"
    local max_summary = math.max(12, config.options.sidebar.width - depth * 2 - 22)
    if #summary > max_summary then
      summary = summary:sub(1, max_summary - 3) .. "..."
    end
    add_line(out, line_map, string.format("%s%s H%d  line %-5s %s", indent, icon, h.index or 0, tostring(math.max(h.new_start or 1, 1)), summary), { kind = "hunk", file = h.file, hunk = h })
    return
  end

  for _, c in ipairs(sorted_children(node)) do
    flatten_node(c, expanded, filter, out, line_map, depth + (node.kind == "root" and 0 or 1))
  end
end

function M.flatten(root, expanded, filter)
  local lines = {}
  local line_map = {}
  flatten_node(root, expanded or {}, filter or "all", lines, line_map, 0)
  return lines, line_map
end

return M
