const path = require("node:path")
const ShortcutModel = require("./ShortcutModel.js")

function normalize(value) {
  return String(value || "").toLowerCase().replace(/\.desktop$/i, "").replace(/[^a-z0-9]+/g, "")
}

function normalizeCommand(value) {
  return String(value || "").trim().replace(/\s+/g, " ")
}

function canonicalUrl(value) {
  try {
    const url = new URL(String(value || ""))
    const pathname = url.pathname.replace(/\/+$/, "") || "/"
    return url.origin.toLowerCase() + pathname + url.search
  } catch (_) {
    return ""
  }
}

function urlsIn(value) {
  return (String(value || "").match(/https?:\/\/[^\s"']+/g) || []).map(canonicalUrl).filter(Boolean)
}

function executableIn(command) {
  const words = String(command || "").trim().match(/(?:[^\s"']+|"[^"]*"|'[^']*')+/g) || []
  for (let i = 0; i < words.length; i++) {
    const word = words[i].replace(/^['"]|['"]$/g, "")
    if (!word || word === "env" || word === "uwsm-app" || word === "--" || /^[A-Z_][A-Z0-9_]*=/.test(word)) continue
    return path.basename(word)
  }
  return ""
}

function parseCombo(value) {
  const combo = String(value || "").trim()
  const separator = combo.lastIndexOf(" + ")
  if (separator < 0) return null
  const modifierKey = ShortcutModel.modifierKey(combo.substring(0, separator))
  const key = combo.substring(separator + 3).trim().toUpperCase()
  if (!modifierKey || !key) return null
  return { modifierKey, key, shortcut: modifierKey + " + " + key }
}

function bindingSignature(binding) {
  return String(binding.modifierKey || "") + "\u001f" + String(binding.key || "").toUpperCase()
    + "\u001f" + normalize(binding.description)
}

function parseEffectiveBindings(output) {
  return ShortcutModel.parseBindings(String(output || "")).map(binding => ({
    modifierKey: binding.modifierKey,
    key: String(binding.key || "").toUpperCase(),
    shortcut: binding.modifierKey + " + " + String(binding.key || "").toUpperCase(),
    description: binding.description
  }))
}

function parseMenuJsonc(raw) {
  const stripped = String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
  if (!stripped.trim()) return {}
  try {
    const parsed = JSON.parse(stripped)
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {}
    const source = parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items)
      ? parsed.items : parsed
    return source
  } catch (_) {
    return {}
  }
}

function mergeMenuSources(defaultItems, userItems) {
  const merged = {}
  for (const source of [defaultItems || {}, userItems || {}]) {
    for (const [itemId, item] of Object.entries(source)) {
      if (!item || typeof item !== "object" || Array.isArray(item)) continue
      merged[itemId] = { ...(merged[itemId] || {}), ...item }
    }
  }
  return merged
}

function luaField(raw, name) {
  const match = String(raw || "").match(new RegExp("\\b" + name + "\\s*=\\s*([\"'])(.*?)\\1"))
  return match ? match[2] : ""
}

function parseLauncherBindings(lua, source) {
  const bindings = []
  const lines = String(lua || "").split(/\r?\n/)
  for (let lineNumber = 0; lineNumber < lines.length; lineNumber++) {
    const match = lines[lineNumber].match(/\bo\.bind\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*(.+)\)\s*$/)
    if (!match) continue
    const combo = parseCombo(match[1])
    if (!combo) continue

    const raw = match[3].trim()
    const action = {
      webapp: luaField(raw, "webapp"),
      omarchy: luaField(raw, "omarchy"),
      launch: luaField(raw, "launch"),
      tui: luaField(raw, "tui"),
      command: ""
    }
    const command = raw.match(/^(["'])(.*?)\1(?:\s*,|\s*$)/)
    if (command) action.command = command[2]
    if (!action.webapp && !action.omarchy && !action.launch && !action.command) continue

    bindings.push({
      ...combo,
      description: match[2],
      action,
      source: source || "",
      line: lineNumber + 1
    })
  }
  return bindings
}

function parseDesktopEntry(content, desktopId) {
  const entry = { desktopId: String(desktopId || "").replace(/\.desktop$/i, ""), name: "", genericName: "", exec: "" }
  let inDesktopEntry = false
  for (const line of String(content || "").split(/\r?\n/)) {
    if (line === "[Desktop Entry]") {
      inDesktopEntry = true
      continue
    }
    if (inDesktopEntry && /^\[/.test(line)) break
    if (!inDesktopEntry) continue
    const separator = line.indexOf("=")
    if (separator < 1) continue
    const key = line.substring(0, separator)
    const value = line.substring(separator + 1)
    if (key === "Name") entry.name = value
    else if (key === "GenericName") entry.genericName = value
    else if (key === "Exec") entry.exec = value
  }
  return entry
}

function luaQuote(value) {
  return '"' + String(value || "").replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
}

function desktopLaunchCommand(value) {
  return String(value || "")
    .replace(/\s+%[fFuUdDnNickvm]/g, "")
    .replace(/\s+--\s*$/, "")
    .trim()
}

function bindingDraft(desktopId, name, desktop) {
  const id = String(desktopId || "").replace(/[^A-Za-z0-9._-]+/g, "-")
  const label = String(name || desktopId || "Application")
  const exec = String(desktop && desktop.exec || "")
  const executable = executableIn(exec)
  const launchCommand = desktopLaunchCommand(exec) || String(desktopId || "application")
  const webappUrl = executable === "omarchy-launch-webapp" ? urlsIn(exec)[0] : ""
  const action = webappUrl
    ? "{ webapp = " + luaQuote(webappUrl) + " }"
    : "{ launch = " + luaQuote(launchCommand) + " }"
  return [
    "-- omacoach-draft:" + id,
    "-- Choose a free key, remove the leading '-- ', then save:",
    '-- o.bind("SUPER + SHIFT + ?", ' + luaQuote(label) + ", " + action + ")"
  ].join("\n")
}

function reasonFor(app, binding, defaults) {
  const action = binding.action
  const appIds = [app.desktopId, app.name, app.desktop && app.desktop.name].map(normalize).filter(Boolean)
  const desktopExec = executableIn(app.desktop && app.desktop.exec)
  const desktopUrls = urlsIn(app.desktop && app.desktop.exec)

  if (action.webapp) {
    const target = canonicalUrl(action.webapp)
    if (target && desktopUrls.includes(target)) return { confidence: 100, evidence: "webapp-url" }
  }

  const omarchy = String(action.omarchy || "").trim().split(/\s+/)[0]
  if (omarchy === "browser" && normalize(defaults.defaultBrowserId) === normalize(app.desktopId)) {
    return { confidence: 100, evidence: "default-browser" }
  }
  if (omarchy === "terminal" && normalize(defaults.defaultTerminal) === normalize(desktopExec)) {
    return { confidence: 100, evidence: "default-terminal" }
  }
  if (omarchy === "editor" && normalize(defaults.defaultEditor) === normalize(desktopExec)) {
    return { confidence: 100, evidence: "default-editor" }
  }
  if (omarchy && (appIds.includes(normalize(omarchy)) || normalize(desktopExec) === normalize(omarchy))) {
    return { confidence: 95, evidence: "omarchy-launcher" }
  }

  const launchExecutable = executableIn(action.launch || action.command)
  if (launchExecutable && normalize(launchExecutable) === normalize(desktopExec)) {
    return { confidence: 95, evidence: "executable" }
  }

  if ((!app.desktop || !app.desktop.exec) && appIds.includes(normalize(binding.description))) {
    return { confidence: 70, evidence: "launcher-label" }
  }
  return null
}

function matchSearchedApps(options) {
  const searches = options.searches || {}
  const defaults = options.defaults || {}
  const effective = options.effectiveBindings || []
  const effectiveBySignature = new Set(effective.map(bindingSignature))
  const launcherBindings = (options.launcherBindings || []).filter(binding => effectiveBySignature.has(bindingSignature(binding)))
  const desktops = options.desktops || {}
  const results = []

  for (const desktopId of Object.keys(searches)) {
    const observed = searches[desktopId] || {}
    const app = {
      desktopId,
      name: String(observed.name || desktopId),
      count: Number(observed.count) || 0,
      desktop: desktops[desktopId] || null
    }
    const matches = []
    const seen = new Set()
    for (const binding of launcherBindings) {
      const reason = reasonFor(app, binding, defaults)
      if (!reason || seen.has(binding.shortcut)) continue
      seen.add(binding.shortcut)
      matches.push({
        shortcut: binding.shortcut,
        description: binding.description,
        confidence: reason.confidence,
        evidence: reason.evidence,
        source: binding.source,
        line: binding.line
      })
    }
    matches.sort((left, right) => right.confidence - left.confidence || left.shortcut.localeCompare(right.shortcut))
    results.push({ desktopId, name: app.name, count: app.count, matches })
  }

  return results.sort((left, right) => right.count - left.count || left.name.localeCompare(right.name))
}

function matchSearchedMenuItems(options) {
  const searches = options.searches || {}
  const menuItems = options.menuItems || {}
  const effective = options.effectiveBindings || []
  const effectiveBySignature = new Set(effective.map(bindingSignature))
  const commandBindings = (options.launcherBindings || []).filter(binding =>
    binding.action.command && effectiveBySignature.has(bindingSignature(binding)))
  const results = []

  for (const itemId of Object.keys(searches)) {
    const observed = searches[itemId] || {}
    const menuItem = menuItems[itemId] || {}
    const action = normalizeCommand(menuItem.action)
    const matches = []
    const seen = new Set()
    if (action) {
      for (const binding of commandBindings) {
        if (normalizeCommand(binding.action.command) !== action || seen.has(binding.shortcut)) continue
        seen.add(binding.shortcut)
        matches.push({
          shortcut: binding.shortcut,
          description: binding.description,
          confidence: 100,
          evidence: "menu-action",
          source: binding.source,
          line: binding.line
        })
      }
    }
    matches.sort((left, right) => left.shortcut.localeCompare(right.shortcut))
    results.push({
      itemId,
      name: String(observed.path || observed.label || itemId),
      count: Number(observed.count) || 0,
      matches
    })
  }

  return results.sort((left, right) => right.count - left.count || left.name.localeCompare(right.name))
}

module.exports = {
  canonicalUrl,
  executableIn,
  normalizeCommand,
  parseEffectiveBindings,
  parseMenuJsonc,
  mergeMenuSources,
  parseLauncherBindings,
  parseDesktopEntry,
  desktopLaunchCommand,
  bindingDraft,
  matchSearchedApps,
  matchSearchedMenuItems
}
