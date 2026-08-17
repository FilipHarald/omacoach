import QtQuick
import QtQuick.Layouts
import qs.Commons

Rectangle {
  id: root

  required property string label
  property int count: -1
  property bool branch: false

  implicitWidth: chipRow.implicitWidth + Style.space(16)
  implicitHeight: Style.space(26)
  radius: Math.min(Style.cornerRadius, Style.space(6))
  color: branch ? Util.alpha(Color.accent, 0.14) : Util.alpha(Color.popups.text, 0.08)
  border.width: Math.max(1, Style.spacing.hairline)
  border.color: branch ? Util.alpha(Color.accent, 0.72) : Util.alpha(Color.popups.border, 0.72)

  RowLayout {
    id: chipRow
    anchors.centerIn: parent
    spacing: Style.space(5)

    Text {
      visible: root.branch
      text: "+"
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Text {
      text: root.label
      color: root.branch ? Color.accent : Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Text {
      visible: root.count >= 0
      text: String(root.count)
      color: Util.alpha(Color.popups.text, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
