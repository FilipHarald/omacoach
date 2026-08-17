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

assert.equal(model.bindingsFor(groups, "SUPER ALT")[0].description, "Apps menu")

const displayBindings = model.groupForDisplay(model.parseBindings([
  "SUPER + 1 → Switch to workspace 1",
  "SUPER + 2 → Switch to workspace 2",
  "SUPER + 0 → Switch to workspace 10",
  "SUPER + W → Close window"
].join("\n")))
assert.deepEqual(displayBindings.map(binding => [binding.key, binding.description, binding.grouped === true]), [
  ["[nbr]", "Switch to workspace [nbr]", true],
  ["W", "Close window", false]
])

const singleDisplayBinding = model.groupForDisplay(model.parseBindings(
  "SUPER + 1 → Switch to workspace 1"
))
assert.equal(singleDisplayBinding[0].key, "1")

console.log("model tests passed")
