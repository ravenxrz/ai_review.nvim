local ws = require("ai_review.workspace")

describe("workspace._resolve", function()
  it("resolves folders to git roots, dedups, labels by basename", function()
    local fake_find_root = function(path)
      if path == "/w/proj_a/sub" then return "/w/proj_a" end
      if path == "/w/proj_a" then return "/w/proj_a" end
      if path == "/w/proj_b" then return "/w/proj_b" end
      return nil, "not a git repo"
    end
    local roots, errs = ws._resolve({ "/w/proj_a/sub", "/w/proj_a", "/w/proj_b", "/w/nope" }, fake_find_root)
    assert.are.equal(2, #roots)
    assert.are.equal("/w/proj_a", roots[1].root)
    assert.are.equal("proj_a", roots[1].label)
    assert.are.equal("/w/proj_b", roots[2].root)
    assert.are.equal("proj_b", roots[2].label)
    assert.are.equal(1, #errs)
  end)

  it("returns empty for no folders", function()
    local roots, errs = ws._resolve({}, function() return nil end)
    assert.are.equal(0, #roots)
    assert.are.equal(0, #errs)
  end)

  it("collects an error per non-git folder", function()
    local roots, errs = ws._resolve({ "/a", "/b" }, function(_) return nil, "boom" end)
    assert.are.equal(0, #roots)
    assert.are.equal(2, #errs)
  end)
end)
