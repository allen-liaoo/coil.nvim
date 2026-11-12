local layout = require("coil.view.layout")

describe("layout.compute_widths", function()
  it("splits the columns left after the two separators by ratio", function()
    assert.same({ 9, 39, 30 }, layout.compute_widths(80, { 1, 4, 3 }))
    assert.same({ 39, 39, 40 }, layout.compute_widths(120, { 1, 1, 1 }))
  end)

  it("never returns a width below one", function()
    assert.same({ 1, 1, 1 }, layout.compute_widths(3, { 1, 4, 3 }))
  end)
end)
