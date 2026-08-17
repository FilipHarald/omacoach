import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
  id: root

  required property var binding

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
  }
}
