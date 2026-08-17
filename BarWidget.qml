import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Badge de mensagens não lidas do nchat. Lê ~/.cache/nchat-plugin/state.json
// (gravado pelo ~/.config/nchat/notify-hook.sh via desktop_notify_command) com
// watch de arquivo — sem polling. Clique esquerdo abre/foca o nchat e limpa o
// contador; clique direito só limpa.
BarWidget {
  id: root
  moduleName: "ibrunomendes.nchat"

  readonly property string statePath: Quickshell.env("HOME") + "/.cache/nchat-plugin/state.json"

  property int count: 0
  property string lastSender: ""
  property string lastText: ""

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function parse(content) {
    try {
      var obj = JSON.parse(String(content || ""))
      root.count = Math.max(0, parseInt(obj.count, 10) || 0)
      root.lastSender = String(obj.sender || "")
      root.lastText = String(obj.text || "")
    } catch (e) {
      root.count = 0
      root.lastSender = ""
      root.lastText = ""
    }
  }

  function clear() {
    root.count = 0
    root.lastSender = ""
    root.lastText = ""
    if (root.bar) root.bar.run("rm -f " + root.statePath)
  }

  function openChat() {
    if (root.bar) root.bar.run("omarchy launch or focus tui --app-id=nchat nchat")
    root.clear()
  }

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: {
      root.count = 0
      root.lastSender = ""
      root.lastText = ""
    }
  }

  IpcHandler {
    target: "ibrunomendes.nchat"
    function clear(): void { root.broadcast("clear") }
    function open(): void { root.broadcast("openChat") }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.count > 0
      ? root.count + (root.count === 1 ? " mensagem não lida" : " mensagens não lidas")
        + (root.lastSender !== "" ? " · " + root.lastSender + ": " + root.lastText : "")
        + "\nClique: abrir nchat · Direito: limpar"
      : "nchat — sem mensagens não lidas\nClique: abrir"
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: "\uf075" // nf-fa-comment
          color: root.count > 0 ? root.urgent : root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          visible: root.count > 0
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: -Style.space(4)
          anchors.topMargin: -Style.space(3)
          implicitWidth: Math.max(Style.space(11), badgeLabel.implicitWidth + Style.space(6))
          implicitHeight: Style.space(11)
          radius: implicitHeight / 2
          color: root.urgent

          Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: root.count > 99 ? "99+" : String(root.count)
            color: Color.background
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption - 2
            font.bold: true
          }
        }
      }
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) root.clear()
      else root.openChat()
    }
  }
}
