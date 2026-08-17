var MODIFIER_ORDER = ["SUPER", "SHIFT", "CTRL", "ALT"]
var BRANCH_ORDER = ["SHIFT", "CTRL", "ALT"]

function trim(value) {
  return String(value === undefined || value === null ? "" : value)
    .replace(/^\s+|\s+$/g, "")
}

function normalizeModifier(value) {
  var modifier = trim(value).toUpperCase()
  if (modifier === "CONTROL") return "CTRL"
  if (modifier === "META" || modifier === "WIN" || modifier === "MOD4") return "SUPER"
  return MODIFIER_ORDER.indexOf(modifier) === -1 ? "" : modifier
}

function normalizeModifiers(value) {
  var source = Array.isArray(value) ? value : trim(value).split(/[+\s]+/)
  var present = {}
  var result = []

  for (var i = 0; i < source.length; i++) {
    var modifier = normalizeModifier(source[i])
    if (modifier) present[modifier] = true
  }

  for (var j = 0; j < MODIFIER_ORDER.length; j++) {
    if (present[MODIFIER_ORDER[j]]) result.push(MODIFIER_ORDER[j])
  }
  return result
}

function modifierKey(value) {
  return normalizeModifiers(value).join(" ")
}

function parseLine(line) {
  var match = String(line || "").match(/^\s*(.*?)\s*(?:→|->)\s*(.*?)\s*$/)
  if (!match) return null

  var combo = trim(match[1])
  var description = trim(match[2])
  var separator = combo.lastIndexOf(" + ")
  if (separator < 0 || !description || description === "-" || description === "—") return null

  var modifiers = normalizeModifiers(combo.substring(0, separator))
  var key = trim(combo.substring(separator + 3))
  var upperKey = key.toUpperCase()

  if (modifiers.indexOf("SUPER") === -1) return null
  if (!key || upperKey.indexOf("XF86") === 0 || upperKey.indexOf("MOUSE") !== -1) return null
  if (/^CODE:[0-9]+$/i.test(key)) return null

  return {
    modifiers: modifiers,
    modifierKey: modifiers.join(" "),
    key: key,
    description: description
  }
}

function parseBindings(output) {
  var lines = String(output || "").split(/\r?\n/)
  var bindings = []
  var seen = {}

  for (var i = 0; i < lines.length; i++) {
    var binding = parseLine(lines[i])
    if (!binding) continue

    var signature = binding.modifierKey + "\u001f" + binding.key.toUpperCase()
    if (seen[signature]) continue
    seen[signature] = true
    bindings.push(binding)
  }

  return bindings
}

function groupBindings(bindings) {
  var groups = {}
  var source = Array.isArray(bindings) ? bindings : []

  for (var i = 0; i < source.length; i++) {
    var key = modifierKey(source[i].modifiers)
    if (!groups[key]) groups[key] = []
    groups[key].push(source[i])
  }
  return groups
}

function bindingsFor(groups, modifiers) {
  var bindings = groups && groups[modifierKey(modifiers)]
  return Array.isArray(bindings) ? bindings.slice() : []
}

function branchCounts(groups, modifiers) {
  var current = normalizeModifiers(modifiers)
  var branches = []

  for (var i = 0; i < BRANCH_ORDER.length; i++) {
    var modifier = BRANCH_ORDER[i]
    if (current.indexOf(modifier) !== -1) continue
    var count = bindingsFor(groups, current.concat([modifier])).length
    if (count > 0) branches.push({ modifier: modifier, count: count })
  }
  return branches
}

function cappedBindings(bindings, limit) {
  var source = Array.isArray(bindings) ? bindings : []
  var maximum = Math.max(0, Math.floor(Number(limit) || 0))
  return {
    visible: source.slice(0, maximum),
    hiddenCount: Math.max(0, source.length - maximum)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    normalizeModifiers: normalizeModifiers,
    modifierKey: modifierKey,
    parseLine: parseLine,
    parseBindings: parseBindings,
    groupBindings: groupBindings,
    bindingsFor: bindingsFor,
    branchCounts: branchCounts,
    cappedBindings: cappedBindings
  }
}
