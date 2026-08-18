import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "components"
import "ShortcutModel.js" as ShortcutModel

Item {
  id: root

  property bool opened: false
  property var manifest: null
  property var shell: null
  property string targetMonitor: ""
  property string currentModifierKey: "SUPER"
  property var bindingGroups: ({})
  property var currentBindings: []
  property var visibleBindings: []
  property var modifierBranches: []
  property var modifierStates: []
  property int hiddenBindingCount: 0
  property var keycodeMap: ({})
  property var attemptStats: ({})
  property var appSearchStats: ({})
  property var menuSearchStats: ({})
  property var coachDecisions: ({})
  property var appBindingMatches: ({})
  property bool statsLoaded: false
  property bool measurementEnabled: true
  property string sortOrder: "none"
  property string fillOrder: "columns"
  property var triggerModifiers: ({ SUPER: true, SHIFT: true, CTRL: true, ALT: true })
  property double visibilitySequence: 0
  property bool pinned: false
  readonly property int revealDelayMs: 180
  readonly property int maximumBindings: 40
  readonly property var currentModifiers: ShortcutModel.normalizeModifiers(currentModifierKey)
  readonly property string pluginDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property string stateDir: stateHome + "/omacoach"
  readonly property string statsPath: stateDir + "/attempts.json"
  readonly property string launcherHookIssueUrl: "https://github.com/FilipHarald/omacoach/issues/17"

  onPluginDirChanged: {
    if (pluginDir && !keymapProcess.running) {
      keymapProcess.command = [pluginDir + "/scripts/keymap"]
      keymapProcess.running = true
    }
    if (pluginDir) coachMatchRefreshTimer.restart()
  }

  function updateModel(modifiers) {
    currentModifierKey = ShortcutModel.modifierKey(modifiers) || "SUPER"
    var grouped = ShortcutModel.groupForDisplay(ShortcutModel.bindingsFor(bindingGroups, currentModifierKey))
    currentBindings = ShortcutModel.sortBindings(grouped, sortOrder, function(binding) {
      return root.attemptCount(binding)
    })
    modifierBranches = ShortcutModel.branchCounts(bindingGroups, currentModifierKey)
    var branchCounts = {}
    for (var i = 0; i < modifierBranches.length; i++) {
      branchCounts[modifierBranches[i].modifier] = Number(modifierBranches[i].count) || 0
    }
    var states = []
    var modifierOrder = ["SUPER", "SHIFT", "CTRL", "ALT"]
    for (var j = 0; j < modifierOrder.length; j++) {
      var modifier = modifierOrder[j]
      var pressed = currentModifiers.indexOf(modifier) !== -1
      states.push({
        modifier: modifier,
        pressed: pressed,
        count: pressed ? -1 : (branchCounts[modifier] || 0)
      })
    }
    modifierStates = states
    var capped = ShortcutModel.cappedBindings(currentBindings, maximumBindings)
    visibleBindings = capped.visible
    hiddenBindingCount = capped.hiddenCount
  }

  function loadBindings(output) {
    var parsed = ShortcutModel.parseBindings(String(output || ""))
    bindingGroups = ShortcutModel.groupBindings(parsed)
    updateModel(currentModifierKey)
  }

  function loadKeymap(output) {
    var map = {}
    var lines = String(output || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length === 2 && fields[0] && fields[1]) map[String(fields[0])] = String(fields[1]).toUpperCase()
    }
    keycodeMap = map
  }

  function bindingSignature(binding) {
    return String(binding.modifierKey || "") + "\u001f" + String(binding.key || "").toUpperCase()
  }

  function attemptCount(binding) {
    if (binding.grouped === true) return 0
    var entry = attemptStats[bindingSignature(binding)]
    return entry && Number(entry.count) > 0 ? Number(entry.count) : 0
  }

  function loadStats(raw) {
    if (statsLoaded) return
    var parsed = null
    try { parsed = JSON.parse(String(raw || "")) } catch (e) { parsed = null }
    measurementEnabled = !parsed || parsed.enabled !== false
    sortOrder = parsed && ["alphabetical", "measurements"].indexOf(parsed.sortOrder) !== -1
      ? parsed.sortOrder : "none"
    fillOrder = parsed && parsed.fillOrder === "rows" ? "rows" : "columns"
    var parsedTriggers = parsed && parsed.triggerModifiers && typeof parsed.triggerModifiers === "object"
      ? parsed.triggerModifiers : ({})
    triggerModifiers = {
      SUPER: parsedTriggers.SUPER !== false,
      SHIFT: parsedTriggers.SHIFT !== false,
      CTRL: parsedTriggers.CTRL !== false,
      ALT: parsedTriggers.ALT !== false
    }
    var supportedVersion = parsed && (parsed.version === 1 || parsed.version === 2)
    attemptStats = supportedVersion && parsed.bindings && typeof parsed.bindings === "object"
      ? parsed.bindings : ({})
    appSearchStats = supportedVersion && parsed.appSearches && typeof parsed.appSearches === "object"
      ? parsed.appSearches : ({})
    menuSearchStats = parsed && parsed.version === 2 && parsed.menuSearches && typeof parsed.menuSearches === "object"
      ? parsed.menuSearches : ({})
    coachDecisions = supportedVersion && parsed.coachDecisions && typeof parsed.coachDecisions === "object"
      ? parsed.coachDecisions : ({})
    statsLoaded = true
    updateModel(currentModifierKey)
    coachMatchRefreshTimer.restart()
  }

  function saveStats() {
    if (!statsLoaded) return
    statsFile.setText(JSON.stringify({
      version: 2,
      enabled: measurementEnabled,
      sortOrder: sortOrder,
      fillOrder: fillOrder,
      triggerModifiers: triggerModifiers,
      bindings: attemptStats,
      appSearches: appSearchStats,
      menuSearches: menuSearchStats,
      coachDecisions: coachDecisions
    }, null, 2) + "\n")
  }

  function scheduleStatsSave() {
    if (statsLoaded) statsSaveTimer.restart()
  }

  function setMeasurementEnabled(enabled) {
    measurementEnabled = enabled === true
    scheduleStatsSave()
  }

  function setSortOrder(order) {
    sortOrder = ["alphabetical", "measurements"].indexOf(order) !== -1 ? order : "none"
    updateModel(currentModifierKey)
    scheduleStatsSave()
  }

  function setFillOrder(order) {
    fillOrder = order === "rows" ? "rows" : "columns"
    scheduleStatsSave()
  }

  function setTriggerModifier(modifier, enabled) {
    var key = String(modifier || "").toUpperCase()
    if (["SUPER", "SHIFT", "CTRL", "ALT"].indexOf(key) === -1) return
    var next = Object.assign({}, triggerModifiers)
    next[key] = enabled === true
    triggerModifiers = next
    scheduleStatsSave()
  }

  function triggerEnabled(modifiers) {
    return ShortcutModel.shouldTrigger(modifiers, triggerModifiers)
  }

  function resetStats() {
    attemptStats = ({})
    appSearchStats = ({})
    menuSearchStats = ({})
    coachDecisions = ({})
    appBindingMatches = ({})
    if (sortOrder === "measurements") updateModel(currentModifierKey)
    scheduleStatsSave()
  }

  function ignoreCoachApp(desktopId) {
    var id = String(desktopId || "").trim()
    if (!id) return
    var next = Object.assign({}, coachDecisions)
    next[id] = { ignored: true }
    coachDecisions = next
    scheduleStatsSave()
  }

  function ignoreCoachInsight(insight) {
    var key = insight ? String(insight.decisionKey || "").trim() : ""
    if (!key) return
    var next = Object.assign({}, coachDecisions)
    next[key] = { ignored: true }
    coachDecisions = next
    scheduleStatsSave()
  }

  function resetCoachDecisions() {
    coachDecisions = ({})
    scheduleStatsSave()
  }

  function coachDecisionCount() {
    var count = 0
    for (var desktopId in coachDecisions) {
      if (coachDecisions[desktopId] && coachDecisions[desktopId].ignored === true) count++
    }
    return count
  }

  function loadAppBindingMatches(output) {
    var parsed = null
    try { parsed = JSON.parse(String(output || "")) } catch (e) { parsed = null }
    var next = {}
    if (Array.isArray(parsed)) {
      for (var i = 0; i < parsed.length; i++) {
        var app = parsed[i]
        if (!app || !app.desktopId) continue
        next[String(app.desktopId)] = Array.isArray(app.matches) ? app.matches : []
      }
    }
    appBindingMatches = next
  }

  function refreshAppBindingMatches() {
    if (!pluginDir || coachMatcherProcess.running) return
    coachMatcherProcess.command = [pluginDir + "/scripts/match-searched-app-bindings", "--json"]
    coachMatcherProcess.running = true
  }

  function openAddKeybind(app) {
    if (!pinned || addKeybindProcess.running) return
    togglePinned("")
    addKeybindProcess.command = [
      pluginDir + "/scripts/add-app-keybind",
      String(app.desktopId || ""),
      String(app.name || app.desktopId || "")
    ]
    addKeybindProcess.running = true
  }

  function openLearnKeybindings(app) {
    if (!pinned || learnKeybindingsProcess.running) return
    togglePinned("")
    learnKeybindingsProcess.command = [
      pluginDir + "/scripts/show-app-keybindings",
      String(app.desktopId || ""),
      String(app.name || app.desktopId || "")
    ]
    learnKeybindingsProcess.running = true
  }

  function talkAboutCoachInsights() {
    if (!pinned || !pluginDir || talkAboutCoachInsightsProcess.running) return
    var measurements = {
      schemaVersion: 2,
      measurementEnabled: measurementEnabled,
      bindings: attemptStats,
      appSearches: appSearchStats,
      menuSearches: menuSearchStats
    }
    togglePinned("")
    talkAboutCoachInsightsProcess.command = [
      pluginDir + "/scripts/talk-about-coach-insights",
      JSON.stringify(measurements)
    ]
    talkAboutCoachInsightsProcess.running = true
  }

  function recordAttempt(modifiers, keycode) {
    if (!statsLoaded || !measurementEnabled) return false
    var key = keycodeMap[String(keycode)]
    if (!key) return false

    var candidates = ShortcutModel.bindingsFor(bindingGroups, modifiers)
    var matched = null
    for (var i = 0; i < candidates.length; i++) {
      if (String(candidates[i].key || "").toUpperCase() !== key) continue
      if (matched) return false
      matched = candidates[i]
    }
    if (!matched) return false

    var signature = bindingSignature(matched)
    var next = Object.assign({}, attemptStats)
    var previous = next[signature]
    next[signature] = { count: (previous ? Number(previous.count) : 0) + 1 }
    attemptStats = next
    if (sortOrder === "measurements") updateModel(currentModifierKey)
    scheduleStatsSave()
    return true
  }

  function observedBindingCount() {
    var count = 0
    for (var signature in attemptStats) {
      if (attemptStats[signature] && Number(attemptStats[signature].count) > 0) count++
    }
    return count
  }

  function totalAttemptCount() {
    var count = 0
    for (var signature in attemptStats) {
      if (attemptStats[signature]) count += Number(attemptStats[signature].count) || 0
    }
    return count
  }

  function totalAppSelectionCount() {
    var count = 0
    for (var desktopId in appSearchStats) {
      if (appSearchStats[desktopId]) count += Number(appSearchStats[desktopId].count) || 0
    }
    return count
  }

  function totalMenuSelectionCount() {
    var count = totalAppSelectionCount()
    for (var itemId in menuSearchStats) {
      if (menuSearchStats[itemId]) count += Number(menuSearchStats[itemId].count) || 0
    }
    return count
  }

  function menuSelectionIdentityCount() {
    var count = searchedAppsSummary(true).length
    for (var itemId in menuSearchStats) {
      if (menuSearchStats[itemId] && Number(menuSearchStats[itemId].count) > 0) count++
    }
    return count
  }

  function recordSearchedApp(desktopId, name) {
    if (!statsLoaded || !measurementEnabled) return false
    var id = String(desktopId || "").trim()
    var label = String(name || "").trim()
    if (!id || !label) return false

    var next = Object.assign({}, appSearchStats)
    var previous = next[id]
    next[id] = {
      name: label,
      count: (previous ? Number(previous.count) : 0) + 1
    }
    appSearchStats = next
    scheduleStatsSave()
    coachMatchRefreshTimer.restart()
    return true
  }

  function recordMenuSelection(event) {
    if (!event || Number(event.schemaVersion) !== 1) return false
    var kind = String(event.kind || "").trim()
    var label = String(event.label || "").trim()
    if (kind === "app") return recordSearchedApp(event.desktopId, label)
    if (!statsLoaded || !measurementEnabled) return false
    if (["action", "link", "menu"].indexOf(kind) === -1) return false
    var itemId = String(event.itemId || "").trim()
    var path = String(event.path || "").trim()
    if (!itemId || !label || !path) return false

    var next = Object.assign({}, menuSearchStats)
    var previous = next[itemId]
    next[itemId] = {
      kind: kind,
      label: label,
      path: path,
      count: (previous ? Number(previous.count) : 0) + 1
    }
    menuSearchStats = next
    scheduleStatsSave()
    return true
  }

  function searchedAppsSummary(includeIgnored) {
    var apps = []
    for (var desktopId in appSearchStats) {
      var entry = appSearchStats[desktopId]
      if (!entry || Number(entry.count) <= 0) continue
      if (includeIgnored !== true && coachDecisions[desktopId] && coachDecisions[desktopId].ignored === true) continue
      apps.push({
        desktopId: desktopId,
        name: String(entry.name || desktopId),
        count: Number(entry.count),
        matches: appBindingMatches[desktopId] || [],
        kind: "app",
        decisionKey: desktopId
      })
    }
    apps.sort(function(left, right) {
      if (left.count !== right.count) return right.count - left.count
      return left.name.localeCompare(right.name)
    })
    return apps
  }

  function coachInsightsSummary(includeIgnored) {
    var insights = searchedAppsSummary(includeIgnored)
    for (var itemId in menuSearchStats) {
      var entry = menuSearchStats[itemId]
      var decisionKey = "menu:" + itemId
      if (!entry || Number(entry.count) <= 0) continue
      if (includeIgnored !== true && coachDecisions[decisionKey] && coachDecisions[decisionKey].ignored === true) continue
      insights.push({
        itemId: itemId,
        name: String(entry.path || entry.label || itemId),
        count: Number(entry.count),
        matches: [],
        kind: String(entry.kind || "action"),
        decisionKey: decisionKey
      })
    }
    insights.sort(function(left, right) {
      if (left.count !== right.count) return right.count - left.count
      return left.name.localeCompare(right.name)
    })
    return insights
  }

  function armHints(modifiers, monitor) {
    if (pinned) {
      updateModel(modifiers)
      return
    }
    targetMonitor = String(monitor || "")
    updateModel(modifiers)
    if (!triggerEnabled(modifiers)) {
      revealTimer.stop()
      opened = false
      return
    }
    opened = false
    revealTimer.restart()
  }

  function updateHints(modifiers, monitor) {
    if (pinned) {
      updateModel(modifiers)
      return
    }
    if (monitor) targetMonitor = String(monitor)
    updateModel(modifiers)
    if (!triggerEnabled(modifiers)) {
      hideHints()
    } else if (!opened && !revealTimer.running) {
      revealTimer.restart()
    }
  }

  function hideHints() {
    revealTimer.stop()
    if (pinned) {
      updateModel("SUPER")
      return
    }
    opened = false
  }

  function acceptVisibilitySequence(sequence) {
    var value = Number(sequence)
    if (!isFinite(value) || value <= visibilitySequence) return false
    visibilitySequence = value
    return true
  }

  function togglePinned(monitor) {
    revealTimer.stop()
    if (pinned) {
      pinned = false
      opened = false
      return
    }
    targetMonitor = String(monitor || targetMonitor)
    updateModel("SUPER")
    pinned = true
    opened = true
  }

  function reloadBindings() {
    hideHints()
    if (!bindingProcess.running) bindingProcess.running = true
  }

  function columnCount(count) {
    if (count > 18) return 4
    if (count > 10) return 3
    if (count > 5) return 2
    return 1
  }

  Timer {
    id: revealTimer
    interval: root.revealDelayMs
    repeat: false
    onTriggered: root.opened = true
  }

  Process {
    id: bindingProcess
    command: ["omarchy-menu-keybindings", "--print"]
    onExited: coachMatchRefreshTimer.restart()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadBindings(text)
    }
  }

  Process {
    id: keymapProcess
    command: root.pluginDir ? [root.pluginDir + "/scripts/keymap"] : []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadKeymap(text)
    }
  }

  Process {
    id: ensureStateDirProcess
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      if (exitCode === 0) statsFile.reload()
      else root.loadStats("")
    }
  }

  Process {
    id: coachMatcherProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadAppBindingMatches(text)
    }
  }

  Process {
    id: addKeybindProcess
  }

  Process {
    id: learnKeybindingsProcess
  }

  Process {
    id: talkAboutCoachInsightsProcess
  }

  FileView {
    id: statsFile
    path: root.statsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadStats(text())
    onLoadFailed: root.loadStats("")
  }

  Timer {
    id: statsSaveTimer
    interval: 200
    repeat: false
    onTriggered: root.saveStats()
  }

  Timer {
    id: coachMatchRefreshTimer
    interval: 400
    repeat: false
    onTriggered: root.refreshAppBindingMatches()
  }

  IpcHandler {
    target: "omacoach"

    function arm(sequence: string, modifiers: string, monitor: string): string {
      if (!root.acceptVisibilitySequence(sequence)) return "stale"
      root.armHints(modifiers, monitor)
      return "ok"
    }

    function update(sequence: string, modifiers: string, monitor: string): string {
      if (!root.acceptVisibilitySequence(sequence)) return "stale"
      root.updateHints(modifiers, monitor)
      return "ok"
    }

    function hide(sequence: string): string {
      if (!root.acceptVisibilitySequence(sequence)) return "stale"
      root.hideHints()
      return "ok"
    }

    function attempt(modifiers: string, keycode: string): string {
      return root.recordAttempt(modifiers, Number(keycode)) ? "recorded" : "ignored"
    }

    function measurement(value: string): string {
      var normalized = String(value || "").toLowerCase()
      if (normalized === "on") root.setMeasurementEnabled(true)
      else if (normalized === "off") root.setMeasurementEnabled(false)
      return root.measurementEnabled ? "on" : "off"
    }

    function resetAttempts(): string {
      root.resetStats()
      return "ok"
    }

    function attempts(): string {
      return JSON.stringify({
        enabled: root.measurementEnabled,
        observedBindings: root.observedBindingCount(),
        totalAttempts: root.totalAttemptCount()
      })
    }

    function searchedApp(desktopId: string, name: string): string {
      return root.recordSearchedApp(desktopId, name) ? "recorded" : "ignored"
    }

    function searchedApps(): string {
      return JSON.stringify(root.searchedAppsSummary())
    }

    function menuSelections(): string {
      return JSON.stringify(root.coachInsightsSummary(true))
    }

    function togglePinned(monitor: string): string {
      root.togglePinned(monitor)
      return root.pinned ? "open" : "closed"
    }

    function reload(): string {
      root.reloadBindings()
      return "ok"
    }

    function preview(modifiers: string, monitor: string): string {
      root.targetMonitor = String(monitor || "")
      root.updateModel(modifiers || "SUPER")
      revealTimer.stop()
      root.opened = true
      return "ok"
    }

    function state(): string {
      return root.pinned ? "pinned" : (root.opened ? root.currentModifierKey : "closed")
    }
  }

  Component.onCompleted: {
    if (!bindingProcess.running) bindingProcess.running = true
    if (root.pluginDir && !keymapProcess.running) keymapProcess.running = true
    if (!ensureStateDirProcess.running) ensureStateDirProcess.running = true
  }

  Connections {
    target: root.shell
    enabled: root.shell !== null
    ignoreUnknownSignals: true

    function onMenuSelectionAfterSearch(event) {
      root.recordMenuSelection(event)
    }

    function onAppSelectedAfterSearch(event) {
      if (!event || Number(event.schemaVersion) !== 1) return
      root.recordSearchedApp(event.desktopId, event.name)
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      readonly property bool isTarget: String(modelData.name || "") === root.targetMonitor
      readonly property int columns: root.columnCount(root.visibleBindings.length)
      readonly property real desiredWidth: columns * Style.space(270)
        + Math.max(0, columns - 1) * Style.space(22)
        + Style.spacing.panelPadding * 2

      screen: modelData
      visible: isTarget && (root.opened || card.opacity > 0.01)
      anchors { top: true; right: true; bottom: true; left: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region {
        x: root.pinned ? card.x : 0
        y: root.pinned ? card.y : 0
        width: root.pinned ? card.width : 0
        height: root.pinned ? panel.height - card.y : 0
      }

      WlrLayershell.namespace: "omacoach-shortcuts"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: root.pinned ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      BorderSurface {
        id: card

        width: Math.min(panel.width - Style.space(48), Math.max(panel.width * 0.5, panel.desiredWidth))
        height: content.implicitHeight + Style.spacing.panelPadding * 2 + borderTop + borderBottom
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.pinned
          ? panel.height * 0.2
          : Math.max(Style.space(12), Math.min(panel.height * 0.5, panel.height - (root.opened ? Style.space(26) : Style.space(12)) - height))
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius
        opacity: root.opened ? 1 : 0

        Behavior on opacity {
          NumberAnimation { duration: root.opened ? 110 : 75; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
          id: content
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          focus: root.pinned
          spacing: Style.space(12)

          Keys.onEscapePressed: root.togglePinned("")

          Rectangle {
            id: topCloseControl

            visible: root.pinned
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(28)
            radius: Style.space(6)
            color: topCloseMouse.containsMouse ? Util.alpha(Color.urgent, 0.1) : "transparent"

            Text {
              anchors.centerIn: parent
              text: "To exit: [SUPER CTRL K] or [ESC]"
              color: Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: "x"
              color: Color.urgent
              font.family: Style.font.family
              font.pixelSize: Style.space(20)
              font.bold: true
            }

            MouseArea {
              id: topCloseMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.togglePinned("")
            }
          }

          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(8)

            Repeater {
              model: root.modifierStates
              ModifierChip {
                required property var modelData
                label: String(modelData.modifier)
                count: !modelData.pressed && Number(modelData.count) > 0 ? Number(modelData.count) : -1
                branch: !modelData.pressed && Number(modelData.count) > 0
                muted: !modelData.pressed && Number(modelData.count) === 0
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Util.alpha(Color.popups.border, 0.5)
          }

          GridLayout {
            Layout.fillWidth: true
            columns: panel.columns
            rows: Math.ceil(root.visibleBindings.length / panel.columns)
            flow: root.fillOrder === "columns" ? GridLayout.TopToBottom : GridLayout.LeftToRight
            columnSpacing: Style.space(22)
            rowSpacing: Style.space(5)

            Repeater {
              model: root.visibleBindings
              BindingRow {
                required property var modelData
                binding: modelData
                attemptCount: root.attemptCount(modelData)
                Layout.fillWidth: true
              }
            }
          }

          Text {
            visible: root.currentBindings.length === 0
            Layout.alignment: Qt.AlignHCenter
            text: "No described shortcuts for this combination"
            color: Util.alpha(Color.popups.text, 0.68)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.hiddenBindingCount > 0
            Layout.alignment: Qt.AlignHCenter
            text: "+ " + root.hiddenBindingCount + " more bindings"
            color: Util.alpha(Color.popups.text, 0.62)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Util.alpha(Color.popups.border, 0.5)
          }

          RowLayout {
            visible: !root.pinned
            Layout.fillWidth: true
            spacing: Style.space(8)

            Item { Layout.fillWidth: true }

            Keycap {
              label: "SUPER CTRL K"
            }

            Text {
              text: "to open controls"
              color: Util.alpha(Color.popups.text, 0.5)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Item { Layout.fillWidth: true }
          }

          RowLayout {
            visible: !root.pinned
            Layout.fillWidth: true
            spacing: Style.space(18)

            ColumnLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
              spacing: Style.space(5)

              Text {
                Layout.fillWidth: true
                text: "Coach"
                horizontalAlignment: Text.AlignHCenter
                color: Util.alpha(Color.popups.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                Layout.fillWidth: true
                text: root.coachInsightsSummary(true).length > 0
                  ? (root.coachInsightsSummary().length > 0 ? "Available insights" : "No active coach suggestions")
                  : "No insights yet. Make sure the Omarchy launcher has the supported hooks. "
                    + "Read more in GitHub issue #17 from the permanent panel."
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: Util.alpha(Color.popups.text, 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              Layout.preferredWidth: 1
              Layout.fillHeight: true
              color: Util.alpha(Color.popups.border, 0.5)
            }

            ColumnLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
              spacing: Style.space(5)

              Text {
                Layout.fillWidth: true
                text: "Data"
                horizontalAlignment: Text.AlignHCenter
                color: Util.alpha(Color.popups.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                Layout.fillWidth: true
                text: root.observedBindingCount() + " bindings observed · " + root.totalAttemptCount() + " attempts"
                horizontalAlignment: Text.AlignHCenter
                color: Util.alpha(Color.popups.text, 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                Layout.fillWidth: true
                text: root.menuSelectionIdentityCount() + " searched items · " + root.totalMenuSelectionCount() + " selections"
                horizontalAlignment: Text.AlignHCenter
                color: Util.alpha(Color.popups.text, 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Rectangle {
              Layout.preferredWidth: 1
              Layout.fillHeight: true
              color: Util.alpha(Color.popups.border, 0.5)
            }

            ColumnLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.alignment: Qt.AlignTop | Qt.AlignHCenter
              spacing: Style.space(5)

              Text {
                Layout.fillWidth: true
                text: "Settings"
                horizontalAlignment: Text.AlignHCenter
                color: Util.alpha(Color.popups.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                Layout.fillWidth: true
                visible: root.measurementEnabled
                text: "Data collecting is enabled"
                horizontalAlignment: Text.AlignHCenter
                color: Util.alpha(Color.popups.text, 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }

          RowLayout {
            id: footerSections
            visible: root.pinned
            Layout.fillWidth: true
            spacing: Style.space(18)

            ColumnLayout {
              id: coachPane
              readonly property var apps: root.coachInsightsSummary().slice(0, 3)
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.fillHeight: true
              spacing: Style.space(6)

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Coach"
                color: Util.alpha(Color.popups.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                Layout.fillWidth: true
                visible: coachPane.apps.length === 0 && root.coachInsightsSummary(true).length > 0
                text: "No active coach suggestions"
                horizontalAlignment: Text.AlignHCenter
                color: Util.alpha(Color.popups.text, 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                Layout.fillWidth: true
                visible: root.coachInsightsSummary(true).length === 0
                text: "No insights yet. Make sure the Omarchy launcher has the supported hooks."
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                color: Util.alpha(Color.popups.text, 0.5)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Rectangle {
                id: launcherHookIssueControl
                property bool hovered: false
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(28)
                radius: Math.min(Style.cornerRadius, Style.space(5))
                color: hovered ? Util.alpha(Color.accent, 0.13) : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: "Read more (opens GitHub issue)"
                  color: launcherHookIssueControl.hovered ? Color.accent : Util.alpha(Color.popups.text, 0.62)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: root.pinned
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onContainsMouseChanged: launcherHookIssueControl.hovered = containsMouse
                  onClicked: {
                    Qt.openUrlExternally(root.launcherHookIssueUrl)
                    root.togglePinned("")
                  }
                }
              }

              Rectangle {
                id: talkAboutCoachInsightsControl
                property bool hovered: false
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(28)
                radius: Math.min(Style.cornerRadius, Style.space(5))
                color: hovered ? Util.alpha(Color.accent, 0.13) : "transparent"

                RowLayout {
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Text {
                    text: "󱚣"
                    color: talkAboutCoachInsightsControl.hovered
                      ? Color.accent
                      : Util.alpha(Color.popups.text, 0.62)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: "Talk about coach insights with agent"
                    color: talkAboutCoachInsightsControl.hovered
                      ? Color.accent
                      : Util.alpha(Color.popups.text, 0.62)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: root.pinned && root.statsLoaded && !talkAboutCoachInsightsProcess.running
                  hoverEnabled: true
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onContainsMouseChanged: talkAboutCoachInsightsControl.hovered = containsMouse
                  onClicked: root.talkAboutCoachInsights()
                }
              }

              Repeater {
                model: coachPane.apps
                RowLayout {
                  required property var modelData
                  Layout.fillWidth: true

                  Text {
                    Layout.fillWidth: true
                    text: String(parent.modelData.name || parent.modelData.desktopId || "")
                    color: Util.alpha(Color.popups.text, 0.62)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Text {
                    text: "×" + Number(parent.modelData.count || 0)
                    color: Util.alpha(Color.accent, 0.62)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  PanelActionButton {
                    enabled: root.pinned
                    iconText: "\uf070"
                    tooltipText: "Ignore " + String(parent.modelData.name || parent.modelData.desktopId || "insight")
                    foreground: Util.alpha(Color.popups.text, 0.62)
                    hoverColor: Color.popups.text
                    fontSize: Style.font.caption
                    size: Style.space(22)
                    onClicked: root.ignoreCoachInsight(parent.modelData)
                  }

                  PanelActionButton {
                    visible: parent.modelData.kind === "app"
                    enabled: root.pinned
                    iconText: "\uf067"
                    tooltipText: "Add keybind"
                    foreground: Util.alpha(Color.popups.text, 0.62)
                    hoverColor: Color.accent
                    fontSize: Style.font.caption
                    size: Style.space(22)
                    onClicked: root.openAddKeybind(parent.modelData)
                  }

                  PanelActionButton {
                    visible: parent.modelData.kind === "app"
                    enabled: root.pinned && parent.modelData.matches.length > 0
                    iconText: "\uf11c"
                    tooltipText: parent.modelData.matches.length > 0
                      ? "Show keybinding: " + String(parent.modelData.matches[0].shortcut || "")
                      : "No existing keybinding found"
                    foreground: Util.alpha(Color.popups.text, 0.62)
                    hoverColor: Color.accent
                    fontSize: Style.font.caption
                    size: Style.space(22)
                    onClicked: root.openLearnKeybindings(parent.modelData)
                  }
                }
              }

              Item {
                Layout.fillHeight: true
              }

              Rectangle {
                id: resetCoachControl
                property bool hovered: false
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(28)
                radius: Math.min(Style.cornerRadius, Style.space(5))
                color: hovered ? Util.alpha(Color.popups.text, 0.08) : "transparent"

                RowLayout {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(8)

                  Text {
                    text: "\uf2ea"
                    color: root.pinned && root.coachDecisionCount() > 0
                      ? Util.alpha(Color.popups.text, 0.62)
                      : Util.alpha(Color.popups.text, 0.35)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: "Reset coach decisions"
                    color: root.pinned && root.coachDecisionCount() > 0
                      ? Util.alpha(Color.popups.text, 0.62)
                      : Util.alpha(Color.popups.text, 0.35)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  enabled: root.pinned && root.coachDecisionCount() > 0
                  hoverEnabled: true
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onContainsMouseChanged: resetCoachControl.hovered = containsMouse
                  onClicked: root.resetCoachDecisions()
                }
              }
            }

            Rectangle {
              Layout.preferredWidth: 1
              Layout.fillHeight: true
              color: Util.alpha(Color.popups.border, 0.5)
            }

            ColumnLayout {
              id: dataPane
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.fillHeight: true
              spacing: Style.space(5)

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Data"
                color: Util.alpha(Color.popups.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.observedBindingCount() + " bindings observed · " + root.totalAttemptCount() + " attempts"
                color: Util.alpha(Color.popups.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.menuSelectionIdentityCount() + " searched items · " + root.totalMenuSelectionCount() + " selections"
                color: Util.alpha(Color.popups.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Item {
                Layout.fillHeight: true
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(56)
                spacing: 0

                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.space(28)
                  radius: Math.min(Style.cornerRadius, Style.space(5))
                  color: "transparent"

                  RowLayout {
                    anchors.centerIn: parent
                    spacing: Style.space(8)

                    Text {
                      text: "Collect data"
                      color: Util.alpha(Color.popups.text, 0.62)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }

                    ToggleSwitch {
                      checked: root.measurementEnabled
                      interactive: root.pinned
                      foreground: Util.alpha(Color.popups.text, 0.62)
                      accent: Color.accent
                      trackHeight: Style.space(18)
                      onToggled: root.setMeasurementEnabled(!root.measurementEnabled)
                    }
                  }
                }

                Rectangle {
                  id: deleteStatsControl
                  property bool hovered: false
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.space(28)
                  radius: Math.min(Style.cornerRadius, Style.space(5))
                  color: hovered ? Util.alpha(Color.urgent, 0.13) : "transparent"

                  RowLayout {
                    anchors.centerIn: parent
                    spacing: Style.space(8)

                    Text {
                      text: "\uf1f8"
                      color: deleteStatsControl.hovered ? Color.urgent : Util.alpha(Color.popups.text, 0.62)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      text: "Delete data"
                      color: deleteStatsControl.hovered ? Color.urgent : Util.alpha(Color.popups.text, 0.62)
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    enabled: root.pinned
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onContainsMouseChanged: deleteStatsControl.hovered = containsMouse
                    onClicked: root.resetStats()
                  }
                }
              }
            }

            Rectangle {
              Layout.preferredWidth: 1
              Layout.fillHeight: true
              color: Util.alpha(Color.popups.border, 0.5)
            }

            ColumnLayout {
              id: settingsPane
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.fillHeight: true
              spacing: Style.space(8)

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Settings"
                color: Util.alpha(Color.popups.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                text: "Trigger popover"
                color: Util.alpha(Color.popups.text, 0.62)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: ["SUPER", "SHIFT", "CTRL", "ALT"]

                RowLayout {
                  required property string modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.space(26)
                  spacing: Style.space(10)

                  Text {
                    Layout.fillWidth: true
                    text: parent.modelData
                    color: Util.alpha(Color.popups.text, 0.62)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  ToggleSwitch {
                    checked: root.triggerModifiers[parent.modelData] !== false
                    interactive: root.pinned
                    foreground: Util.alpha(Color.popups.text, 0.62)
                    accent: Color.accent
                    trackHeight: Style.space(16)
                    onToggled: root.setTriggerModifier(parent.modelData, !checked)
                  }
                }
              }

              Text {
                text: "Sorting"
                color: root.pinned ? Util.alpha(Color.popups.text, 0.62) : Util.alpha(Color.popups.text, 0.45)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Dropdown {
                id: sortingDropdown

                Layout.fillWidth: true
                Layout.preferredHeight: Style.spacing.controlHeight
                enabled: root.pinned
                opacity: root.pinned ? 1 : 0.45
                showLabel: false
                foreground: Util.alpha(Color.popups.text, 0.62)
                accent: Color.accent
                options: [
                  { value: "none", label: "None" },
                  { value: "alphabetical", label: "Alphabetically" },
                  { value: "measurements", label: "Measurements" }
                ]
                value: root.sortOrder
                onChanged: function(value) { root.setSortOrder(value) }
              }

              Text {
                text: "Sorting appearance"
                color: root.pinned ? Util.alpha(Color.popups.text, 0.62) : Util.alpha(Color.popups.text, 0.45)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Dropdown {
                id: fillOrderDropdown

                Layout.fillWidth: true
                Layout.preferredHeight: Style.spacing.controlHeight
                enabled: root.pinned
                opacity: root.pinned ? 1 : 0.45
                showLabel: false
                foreground: Util.alpha(Color.popups.text, 0.62)
                accent: Color.accent
                options: [
                  { value: "columns", label: "Columns first" },
                  { value: "rows", label: "Rows first" }
                ]
                value: root.fillOrder
                onChanged: function(value) { root.setFillOrder(value) }
              }
            }
          }
        }
      }
    }
  }
}
