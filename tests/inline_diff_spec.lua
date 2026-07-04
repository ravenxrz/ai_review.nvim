local inline = require("ai_review.inline_diff")

describe("inline_diff.compute_decorations", function()
  it("replace hunk: deleted lines + added range", function()
    local hunk = {
      old_start = 10, old_count = 2, new_start = 10, new_count = 3,
      header = "@@ -10,2 +10,3 @@",
      patch = { "@@ -10,2 +10,3 @@", "-old a", "-old b", "+new a", "+new b", "+new c" },
    }
    local d = inline.compute_decorations(hunk)
    assert.are.same({ "old a", "old b" }, d.deleted)
    assert.are.equal(10, d.add_start)
    assert.are.equal(3, d.add_count)
    assert.is_true(d.anchor_above)
    assert.are.equal(9, d.anchor_row) -- 0-indexed new_start-1
  end)

  it("pure add hunk: no deleted, only added range", function()
    local hunk = {
      old_start = 5, old_count = 0, new_start = 6, new_count = 2,
      header = "@@ -5,0 +6,2 @@",
      patch = { "@@ -5,0 +6,2 @@", "+x", "+y" },
    }
    local d = inline.compute_decorations(hunk)
    assert.are.same({}, d.deleted)
    assert.are.equal(6, d.add_start)
    assert.are.equal(2, d.add_count)
  end)

  it("pure delete hunk: deleted lines, zero added range", function()
    local hunk = {
      old_start = 3, old_count = 2, new_start = 2, new_count = 0,
      header = "@@ -3,2 +2,0 @@",
      patch = { "@@ -3,2 +2,0 @@", "-gone1", "-gone2" },
    }
    local d = inline.compute_decorations(hunk)
    assert.are.same({ "gone1", "gone2" }, d.deleted)
    assert.are.equal(0, d.add_count)
  end)

  it("delete at file top: new_start 0 clamps anchor to row 0", function()
    local hunk = {
      old_start = 1, old_count = 1, new_start = 0, new_count = 0,
      header = "@@ -1,1 +0,0 @@",
      patch = { "@@ -1,1 +0,0 @@", "-first" },
    }
    local d = inline.compute_decorations(hunk)
    assert.are.equal(0, d.anchor_row)
    assert.is_true(d.anchor_above)
  end)
end)
