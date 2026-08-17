import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Launcher + badge do nchat. O backend fica vivo numa sessão tmux gerenciada
// por nchat-session.sh; fechar o terminal visível não encerra as notificações.
BarWidget {
  id: root
  moduleName: "ibrunomendes.nchat"

  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    return url.replace(/^file:\/\//, "").replace(/\/$/, "")
  }
  readonly property string helperPath: pluginDir + "/nchat-session.sh"
  readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") !== ""
    ? Quickshell.env("XDG_CACHE_HOME") : Quickshell.env("HOME") + "/.cache"
  readonly property string statePath: cacheHome + "/nchat-plugin/state.json"

  property int count: 0
  property string lastSender: ""
  property string lastText: ""
  property bool backendOnline: false
  property bool backendConfigured: false
  property bool backendManaged: false
  property bool backendExternal: false
  property bool backendStarting: true
  property string backendError: ""
  property string _statusOutput: ""
  property string _processError: ""

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function parseState(content) {
    try {
      var obj = JSON.parse(String(content || ""))
      root.count = Math.max(0, parseInt(obj.count, 10) || 0)
      root.lastSender = String(obj.sender || "")
      root.lastText = String(obj.text || "")
    } catch (e) {
      root.resetStateView()
    }
  }

  function resetStateView() {
    root.count = 0
    root.lastSender = ""
    root.lastText = ""
  }

  function clear() {
    root.resetStateView()
    if (!clearProcess.running)
      clearProcess.exec({ command: [root.helperPath, "clear"] })
  }

  function ensureBackend() {
    if (ensureProcess.running || root.helperPath === "") return
    root.backendStarting = true
    root._processError = ""
    ensureProcess.exec({ command: [root.helperPath, "ensure"] })
  }

  function refreshStatus() {
    if (statusProcess.running || root.helperPath === "") return
    root._statusOutput = ""
    statusProcess.exec({ command: [root.helperPath, "status"] })
  }

  function openChat() {
    if (openProcess.running) return
    root._processError = ""
    openProcess.exec({ command: [root.helperPath, "open"] })
  }

  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseState(text())
    onLoadFailed: root.resetStateView()
  }

  Process {
    id: ensureProcess
    stderr: SplitParser {
      onRead: function(data) { root._processError += data }
    }
    onExited: function(exitCode) {
      root.backendStarting = false
      if (exitCode !== 0 && root._processError.trim() !== "")
        root.backendError = root._processError.trim()
      root.refreshStatus()
    }
  }

  Process {
    id: statusProcess
    stdout: SplitParser {
      onRead: function(data) { root._statusOutput += data }
    }
    onExited: function(exitCode) {
      root.backendStarting = false
      if (exitCode !== 0) {
        root.backendOnline = false
        root.backendManaged = false
        return
      }

      try {
        var status = JSON.parse(root._statusOutput.trim())
        root.backendOnline = status.online === true
        root.backendConfigured = status.configured === true
        root.backendManaged = status.managed === true
        root.backendExternal = status.external === true
        if (root.backendManaged) root.backendError = ""
        else if (root.backendExternal)
          root.backendError = "nchat já está rodando fora da sessão persistente"
      } catch (e) {
        root.backendOnline = false
        root.backendManaged = false
        root.backendError = "status inválido do backend"
      }
    }
  }

  Process {
    id: openProcess
    stderr: SplitParser {
      onRead: function(data) { root._processError += data }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.clear()
        root.refreshStatus()
      } else {
        root.backendError = root._processError.trim() || ("falha ao abrir nchat (exit " + exitCode + ")")
        root.refreshStatus()
      }
    }
  }

  Process {
    id: clearProcess
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.ensureBackend()
  }

  IpcHandler {
    target: "ibrunomendes.nchat"
    // Um único handler é eleito pelo shell. Não usar broadcast aqui: comandos
    // com efeito colateral abririam um terminal por monitor.
    function clear(): void { root.clear() }
    function open(): void { root.openChat() }
    function ensure(): void { root.ensureBackend() }
    function refresh(): void { root.refreshStatus() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      if (root.backendStarting) return "nchat — verificando integração…"
      if (!root.backendConfigured) return "nchat — configuração inicial necessária\nClique: configurar e abrir"
      if (root.backendExternal) return "nchat — aberto fora da sessão persistente\nFeche-o e clique para migrar"
      if (!root.backendOnline)
        return "nchat — offline" + (root.backendError !== "" ? "\n" + root.backendError : "") + "\nClique: iniciar e abrir"
      if (root.count > 0)
        return root.count + (root.count === 1 ? " nova mensagem" : " novas mensagens")
          + (root.lastSender !== "" ? " · " + root.lastSender + ": " + root.lastText : "")
          + "\nClique: abrir nchat · Direito: limpar"
      return "nchat — online, sem novas mensagens\nClique: abrir"
    }
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: "\uf075" // nf-fa-comment
          color: root.count > 0 ? root.urgent : (root.backendOnline && root.backendConfigured ? root.dim : root.urgent)
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

        Rectangle {
          visible: root.count === 0
          width: Style.space(4)
          height: width
          radius: width / 2
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          color: root.backendOnline && root.backendConfigured ? root.foreground : root.urgent
        }
      }
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) root.clear()
      else if (b === Qt.MiddleButton) root.ensureBackend()
      else root.openChat()
    }
  }
}
