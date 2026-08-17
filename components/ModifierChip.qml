import QtQuick
import QtQuick.Layouts
import qs.Commons

Rectangle {
  id: root

  required property string label
  property int count: -1
  property bool branch: false
  property bool muted: false
  readonly property string countLabel: {
    if (count < 0) return "    "
    var value = count >= 100 ? "99+" : String(count)
    return ("    " + value).slice(-4)
  }

  implicitWidth: chipRow.implicitWidth + Style.space(16)
  implicitHeight: Style.space(26)
  radius: Math.min(Style.cornerRadius, Style.space(6))
  color: branch
    ? Util.alpha(Color.accent, 0.14)
    : Util.alpha(Color.popups.text, muted ? 0.025 : 0.08)
  border.width: Math.max(1, Style.spacing.hairline)
  border.color: branch
    ? Util.alpha(Color.accent, 0.72)
    : Util.alpha(Color.popups.border, muted ? 0.28 : 0.72)

  RowLayout {
    id: chipRow
    anchors.centerIn: parent
    spacing: Style.space(5)

    Text {
      text: root.label
      color: root.branch
        ? Color.accent
        : Util.alpha(Color.popups.text, root.muted ? 0.38 : 1)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Text {
      text: root.countLabel
      color: Util.alpha(Color.popups.text, 0.5)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
