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

  it("collects added lines for char diff pairing", function()
    local hunk = {
      old_start = 1, old_count = 1, new_start = 1, new_count = 1,
      header = "@@ -1,1 +1,1 @@",
      patch = { "@@ -1,1 +1,1 @@", "-foo bar", "+foo BAR" },
    }
    local d = inline.compute_decorations(hunk)
    assert.are.same({ "foo bar" }, d.deleted)
    assert.are.same({ "foo BAR" }, d.added)
  end)
end)

describe("inline_diff.char_diff", function()
  it("returns nil for identical strings", function()
    assert.is_nil(inline.char_diff("same", "same"))
  end)

  it("finds changed middle segment (byte ranges, exclusive end)", function()
    -- "foo bar" vs "foo BAR": common prefix "foo ", differing "bar"/"BAR"
    local d = inline.char_diff("foo bar", "foo BAR")
    assert.are.same({ 4, 7 }, d.a) -- bytes 4..7 -> "bar"
    assert.are.same({ 4, 7 }, d.b) -- bytes 4..7 -> "BAR"
  end)

  it("pure insertion: added chars only on b side", function()
    local d = inline.char_diff("ab", "aXb")
    assert.are.equal(d.a[1], d.a[2]) -- empty range on a
    assert.are.same({ 1, 2 }, d.b) -- "X"
  end)

  it("pure deletion: removed chars only on a side", function()
    local d = inline.char_diff("aXb", "ab")
    assert.are.same({ 1, 2 }, d.a) -- "X"
    assert.are.equal(d.b[1], d.b[2]) -- empty range on b
  end)

  it("utf-8 safe: differing multibyte char", function()
    local d = inline.char_diff("héllo", "hallo")
    -- prefix "h", then é(2 bytes) vs a(1 byte)
    assert.are.equal(1, d.a[1])
    assert.are.equal(1, d.b[1])
  end)
end)
