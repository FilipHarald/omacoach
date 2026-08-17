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
  property string targetMonitor: ""
  property string currentModifierKey: "SUPER"
  property var bindingGroups: ({})
  property var currentBindings: []
  property var visibleBindings: []
  property var modifierBranches: []
  property int hiddenBindingCount: 0
  readonly property int revealDelayMs: 180
  readonly property int maximumBindings: 24
  readonly property var currentModifiers: ShortcutModel.normalizeModifiers(currentModifierKey)

  function updateModel(modifiers) {
    currentModifierKey = ShortcutModel.modifierKey(modifiers) || "SUPER"
    currentBindings = ShortcutModel.bindingsFor(bindingGroups, currentModifierKey)
    modifierBranches = ShortcutModel.branchCounts(bindingGroups, currentModifierKey)
    var capped = ShortcutModel.cappedBindings(currentBindings, maximumBindings)
    visibleBindings = capped.visible
    hiddenBindingCount = capped.hiddenCount
  }

  function loadBindings(output) {
    var parsed = ShortcutModel.parseBindings(String(output || ""))
    bindingGroups = ShortcutModel.groupBindings(parsed)
    updateModel(currentModifierKey)
  }

  function armHints(modifiers, monitor) {
    targetMonitor = String(monitor || "")
    updateModel(modifiers)
    opened = false
    revealTimer.restart()
  }

  function updateHints(modifiers, monitor) {
    if (monitor) targetMonitor = String(monitor)
    updateModel(modifiers)
  }

  function hideHints() {
    revealTimer.stop()
    opened = false
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
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadBindings(text)
    }
  }

  IpcHandler {
    target: "omacoach"

    function arm(modifiers: string, monitor: string): string {
      root.armHints(modifiers, monitor)
      return "ok"
    }

    function update(modifiers: string, monitor: string): string {
      root.updateHints(modifiers, monitor)
      return "ok"
    }

    function hide(): string {
      root.hideHints()
      return "ok"
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
      return root.opened ? root.currentModifierKey : "closed"
    }
  }

  Component.onCompleted: if (!bindingProcess.running) bindingProcess.running = true

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData

      readonly property bool isTarget: String(modelData.name || "") === root.targetMonitor
      readonly property int columns: root.columnCount(root.visibleBindings.length)
      readonly property real desiredWidth: columns * Style.space(224)
        + Math.max(0, columns - 1) * Style.space(22)
        + Style.spacing.panelPadding * 2

      screen: modelData
      visible: isTarget && (root.opened || card.opacity > 0.01)
      anchors { top: true; right: true; bottom: true; left: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region {}

      WlrLayershell.namespace: "omacoach-shortcuts"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      BorderSurface {
        id: card

        width: Math.min(panel.width - Style.space(48), Math.max(Style.space(330), panel.desiredWidth))
        height: content.implicitHeight + Style.spacing.panelPadding * 2 + borderTop + borderBottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.opened ? Style.space(26) : Style.space(12)
        color: Color.popups.background
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
        radius: Style.cornerRadius
        opacity: root.opened ? 1 : 0

        Behavior on opacity {
          NumberAnimation { duration: root.opened ? 110 : 75; easing.type: Easing.OutCubic }
        }

        Behavior on anchors.bottomMargin {
          NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }

        ColumnLayout {
          id: content
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.space(12)

          RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(7)

            Repeater {
              model: root.currentModifiers
              ModifierChip { required property string modelData; label: modelData }
            }
          }

          GridLayout {
            Layout.fillWidth: true
            columns: panel.columns
            columnSpacing: Style.space(22)
            rowSpacing: Style.space(5)

            Repeater {
              model: root.visibleBindings
              BindingRow {
                required property var modelData
                binding: modelData
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

          RowLayout {
            visible: root.modifierBranches.length > 0
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.space(9)

            Text {
              text: "Hold another modifier"
              color: Util.alpha(Color.popups.text, 0.58)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.modifierBranches
              ModifierChip {
                required property var modelData
                label: String(modelData.modifier)
                count: Number(modelData.count)
                branch: true
              }
            }
          }
        }
      }
    }
  }
}
