import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: root

  required property var binding
  property int attemptCount: 0

  implicitWidth: Style.space(220)
  implicitHeight: Style.space(32)

  RowLayout {
    anchors.fill: parent
    spacing: Style.space(10)

    Keycap {
      label: String(root.binding.key || "")
      Layout.alignment: Qt.AlignVCenter
    }

    Text {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
      text: String(root.binding.description || "")
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      maximumLineCount: 1
    }

    Text {
      visible: root.attemptCount > 0
      Layout.alignment: Qt.AlignVCenter
      text: "×" + root.attemptCount
      color: Util.alpha(Color.accent, 0.9)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }
}
