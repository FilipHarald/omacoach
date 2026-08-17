const assert = require("node:assert/strict")
const model = require("../ShortcutModel.js")

const output = [
  "SUPER + SPACE → Omarchy menu",
  "SUPER SHIFT + RETURN → Browser",
  "SUPER ALT + SPACE → Apps menu",
  "SUPER + LEFT MOUSE BUTTON → Move window",
  "ALT + TAB → Focus next",
  "SUPER + SPACE → Duplicate ignored"
].join("\n")

const bindings = model.parseBindings(output)
assert.equal(bindings.length, 3)
assert.deepEqual(model.normalizeModifiers("alt super shift"), ["SUPER", "SHIFT", "ALT"])

const groups = model.groupBindings(bindings)
assert.deepEqual(model.bindingsFor(groups, "SUPER").map(binding => binding.key), ["SPACE"])
assert.deepEqual(model.branchCounts(groups, "SUPER"), [
  { modifier: "SHIFT", count: 1 },
  { modifier: "ALT", count: 1 }
])
assert.deepEqual(model.cappedBindings(bindings, 2), {
  visible: bindings.slice(0, 2),
  hiddenCount: 1
})

console.log("model tests passed")
