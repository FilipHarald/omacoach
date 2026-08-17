const assert = require("node:assert/strict")
const Matcher = require("../AppBindingMatcher.js")

const effective = Matcher.parseEffectiveBindings([
  "SUPER SHIFT + G -> Signal",
  "SUPER SHIFT + A -> ChatGPT",
  "SUPER SHIFT + B -> Browser",
  "SUPER SHIFT + C -> Calendar",
  "SUPER CTRL ALT + D -> Calendar",
  "SUPER SHIFT + O -> Obsidian"
].join("\n"))

const launchers = Matcher.parseLauncherBindings([
  'o.bind("SUPER + SHIFT + G", "Signal", { omarchy = "signal" })',
  'o.bind("SUPER + SHIFT + A", "ChatGPT", { webapp = "https://chatgpt.com" })',
  'o.bind("SUPER + SHIFT + B", "Browser", { omarchy = "browser" })',
  'o.bind("SUPER + SHIFT + C", "Calendar", { webapp = "https://calendar.example.com/app" })',
  'o.bind("SUPER + SHIFT + O", "Obsidian", { launch = "obsidian" })'
].join("\n"), "applications.lua")

const searches = {
  signal: { name: "Signal", count: 3 },
  ChatGPT: { name: "ChatGPT", count: 2 },
  chromium: { name: "Chromium", count: 1 },
  calendar: { name: "Calendar", count: 1 },
  "calendar-other": { name: "Calendar", count: 1 },
  obsidian: { name: "Obsidian", count: 1 },
  slack: { name: "Slack", count: 1 }
}
const desktops = {
  signal: Matcher.parseDesktopEntry("[Desktop Entry]\nName=Signal\nExec=signal-desktop -- %u", "signal"),
  ChatGPT: Matcher.parseDesktopEntry("[Desktop Entry]\nName=ChatGPT\nExec=omarchy-launch-webapp https://chatgpt.com/", "ChatGPT"),
  chromium: Matcher.parseDesktopEntry("[Desktop Entry]\nName=Chromium\nExec=/usr/bin/chromium %U", "chromium"),
  calendar: Matcher.parseDesktopEntry("[Desktop Entry]\nName=Calendar\nExec=omarchy-launch-webapp https://calendar.example.com/app/", "calendar"),
  "calendar-other": Matcher.parseDesktopEntry("[Desktop Entry]\nName=Calendar\nExec=omarchy-launch-webapp https://other.example.com/", "calendar-other"),
  obsidian: Matcher.parseDesktopEntry("[Desktop Entry]\nName=Obsidian\nExec=obsidian %U", "obsidian")
}

const results = Matcher.matchSearchedApps({
  searches,
  desktops,
  effectiveBindings: effective,
  launcherBindings: launchers,
  defaults: { defaultBrowserId: "chromium.desktop" }
})
const byId = Object.fromEntries(results.map(result => [result.desktopId, result]))

assert.equal(byId.signal.matches[0].shortcut, "SUPER SHIFT + G")
assert.equal(byId.signal.matches[0].evidence, "omarchy-launcher")
assert.equal(byId.ChatGPT.matches[0].evidence, "webapp-url")
assert.equal(byId.chromium.matches[0].evidence, "default-browser")
assert.deepEqual(byId.calendar.matches.map(match => match.shortcut), ["SUPER SHIFT + C"])
assert.deepEqual(byId["calendar-other"].matches, [])
assert.equal(byId.obsidian.matches[0].evidence, "executable")
assert.deepEqual(byId.slack.matches, [])

console.log("app binding matcher tests passed")
