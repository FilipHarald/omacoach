import QtQuick
import qs.Commons

Rectangle {
  id: root

  required property string label

  implicitWidth: Math.max(Style.space(32), labelText.implicitWidth + Style.space(16))
  implicitHeight: Style.space(26)
  radius: Math.min(Style.cornerRadius, Style.space(6))
  color: Util.alpha(Color.popups.text, 0.08)
  border.width: Math.max(1, Style.spacing.hairline)
  border.color: Util.alpha(Color.popups.border, 0.72)

  Text {
    id: labelText
    anchors.centerIn: parent
    text: root.label
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
  }
}
