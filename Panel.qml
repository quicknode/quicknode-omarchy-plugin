import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// QuickNode detail popup: credit usage for the current billing period, a
// filterable endpoint list with per-chain usage and copyable RPC/WSS
// addresses, and inline Admin API key management.
Panel {
  id: root
  moduleName: "sebs.quicknode"
  ipcTarget: "sebs.quicknode"
  manageIpc: false

  property var anchorItem: null
  property bool openedFromHotkey: false

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel, so everything the bar identifies a panel by has to be that
  // widget (popout coordinator, switchPanelFrom).
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    root.refresh()
  }

  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    root.refresh()
    // Set after showing: showing hands the popout coordinator over, which
    // closes whichever panel was open, and that close clears the shared flag.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingKey) root.cancelEditingKey()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- Data. Last-good reports are kept on failure so stale numbers stay
  //      visible instead of blanking while the network is down.
  property var usage: null
  property var endpoints: []
  property var chainUsage: ({})
  property string errorMessage: ""
  property int usageRetries: 0
  property int endpointsRetries: 0
  property int chainUsageRetries: 0

  readonly property string apiKey: String(setting("apiKey", ""))
  readonly property bool hasKey: apiKey !== ""
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)

  readonly property var percent: Model.usagePercent(usage)
  readonly property string label: root.hasKey ? Model.barLabel(percent) : ""
  readonly property bool overLimit: !!usage && ((usage.overages !== null && usage.overages > 0) || (percent !== null && percent >= 100))
  readonly property bool nearLimit: percent !== null && percent >= 90

  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color mutedText: Qt.darker(foreground, 1.5)

  // Click-to-edit state for the API key.
  property bool editingKey: false

  // Endpoint list filter and the transient "copied" flash on a copy button
  // (keyed by endpoint id + kind so only the pressed button reacts).
  property string filterText: ""
  property string copiedKey: ""
  readonly property var visibleEndpoints: Model.filterEndpoints(endpoints, filterText)

  function refresh() {
    if (!root.hasKey) return
    usageRetries = 0
    endpointsRetries = 0
    chainUsageRetries = 0
    if (!usageProc.running) usageProc.running = true
    if (!endpointsProc.running) endpointsProc.running = true
    if (!chainUsageProc.running) chainUsageProc.running = true
  }

  function startEditingKey() {
    editingKey = true
    Qt.callLater(function() {
      keyField.text = root.apiKey
      keyField.selectAll()
      keyField.forceActiveFocus()
    })
  }

  function cancelEditingKey() {
    editingKey = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Persist the key inline on this widget's shell.json entry (the same
  // mechanism the clock uses to store a cycled format). An empty commit is
  // treated as a cancel so the stored key can't be lost by accident.
  function commitKey() {
    var key = String(keyField.text || "").trim()
    if (key === "" || key === root.apiKey) {
      cancelEditingKey()
      return
    }

    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry.apiKey = key

    // Applied locally first so the panel reacts on the commit itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)

    usage = null
    endpoints = []
    chainUsage = {}
    errorMessage = ""
    cancelEditingKey()
    Qt.callLater(root.refresh)
  }

  function focusFilter() {
    filterField.forceActiveFocus()
  }

  function blurFilter() {
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  function copyText(key, text) {
    if (!text) return
    copyProc.payload = text
    copyProc.running = true
    copiedKey = key
    copiedTimer.restart()
  }

  function scheduleUsageRetry() {
    if (usageRetries >= 3) return
    usageRetries++
    usageRetryTimer.restart()
  }

  function scheduleEndpointsRetry() {
    if (endpointsRetries >= 3) return
    endpointsRetries++
    endpointsRetryTimer.restart()
  }

  function scheduleChainUsageRetry() {
    if (chainUsageRetries >= 3) return
    chainUsageRetries++
    chainUsageRetryTimer.restart()
  }

  // The Admin API key travels via the child environment, not argv, so it
  // never shows up in the process list.
  Process {
    id: usageProc
    environment: ({ QN_ADMIN_KEY: root.apiKey })
    command: ["sh", "-c", "exec curl -sS --max-time 10 -H \"x-api-key: $QN_ADMIN_KEY\" -H 'accept: application/json' 'https://api.quicknode.com/v0/usage/rpc'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseUsage(text)
        if (!parsed) {
          root.errorMessage = "Could not reach the QuickNode API"
          root.scheduleUsageRetry()
          return
        }
        if (parsed.error) {
          root.errorMessage = parsed.error
          return
        }
        root.usage = parsed
        root.errorMessage = ""
        root.usageRetries = 0
      }
    }
  }

  Timer {
    id: usageRetryTimer
    interval: 3000
    onTriggered: if (!usageProc.running) usageProc.running = true
  }

  Process {
    id: endpointsProc
    environment: ({ QN_ADMIN_KEY: root.apiKey })
    command: ["sh", "-c", "exec curl -sS --max-time 10 -H \"x-api-key: $QN_ADMIN_KEY\" -H 'accept: application/json' 'https://api.quicknode.com/v0/endpoints?limit=50&offset=0'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseEndpoints(text)
        if (!parsed) {
          root.scheduleEndpointsRetry()
          return
        }
        if (parsed.error) return
        root.endpoints = parsed
        root.endpointsRetries = 0
      }
    }
  }

  Timer {
    id: endpointsRetryTimer
    interval: 3000
    onTriggered: if (!endpointsProc.running) endpointsProc.running = true
  }

  Process {
    id: chainUsageProc
    environment: ({ QN_ADMIN_KEY: root.apiKey })
    command: ["sh", "-c", "exec curl -sS --max-time 10 -H \"x-api-key: $QN_ADMIN_KEY\" -H 'accept: application/json' 'https://api.quicknode.com/v0/usage/rpc/by-chain'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseChainUsage(text)
        if (!parsed) {
          root.scheduleChainUsageRetry()
          return
        }
        if (parsed.error) return
        root.chainUsage = parsed
        root.chainUsageRetries = 0
      }
    }
  }

  Timer {
    id: chainUsageRetryTimer
    interval: 3000
    onTriggered: if (!chainUsageProc.running) chainUsageProc.running = true
  }

  // Endpoint URLs embed the auth token, so they go to wl-copy over a pipe
  // rather than as an argument.
  Process {
    id: copyProc
    property string payload: ""
    environment: ({ COPY_TEXT: copyProc.payload })
    command: ["sh", "-c", "printf %s \"$COPY_TEXT\" | wl-copy"]
  }

  Timer {
    id: copiedTimer
    interval: 1500
    onTriggered: root.copiedKey = ""
  }

  // hasKey gates the timer, so the first fetch fires the moment a key is
  // configured and nothing runs while there is none.
  Timer {
    interval: root.refreshMinutes * 60 * 1000
    running: root.hasKey
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function edit(): void { root.openFromHotkey(); root.startEditingKey() }
    function refresh(): void { root.refresh() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingKey || filterField.activeFocus
      onReturnRequested: root.startEditingKey()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "/") root.focusFilter() }

      Flickable {
        id: contentScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: contentScroll.width
          spacing: Style.space(14)

          // ---- Hero row: big usage percentage left, stats stacked right.
          Item {
            visible: root.hasKey
            width: parent.width
            height: Math.max(heroLeft.height, heroRight.height)

            Row {
              id: heroLeft
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(12)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰆧"
                color: root.foreground
                font.family: root.fontFamily
                // Decorative brand glyph; intentionally larger than the
                // Style.font.* scale, matching the weather hero.
                font.pixelSize: 44
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.percent === null ? "—" : root.percent + "%"
                color: root.overLimit || root.nearLimit ? Color.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: 44
                font.bold: true
              }
            }

            Row {
              id: heroRight
              anchors.right: parent.right
              anchors.rightMargin: Style.space(20)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(28)

              Column {
                spacing: Style.space(5)
                Text {
                  text: "USED"
                  color: root.mutedText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }
                Text {
                  text: root.usage ? Model.formatCredits(root.usage.creditsUsed) : "—"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
              }

              Column {
                spacing: Style.space(5)
                Text {
                  text: "LIMIT"
                  color: root.mutedText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }
                Text {
                  text: root.usage ? Model.formatCredits(root.usage.limit) : "—"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
              }

              Column {
                spacing: Style.space(5)
                Text {
                  text: "RESETS"
                  color: root.mutedText
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }
                Text {
                  text: root.usage ? Model.resetShort(root.usage.startTime, Date.now()) : "—"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
              }
            }
          }

          // ---- Usage progress bar for the billing period. Track and fill
          //      are siblings: a child fill would inherit the track's
          //      washed-out opacity.
          Item {
            visible: root.hasKey && root.percent !== null
            width: parent.width
            height: Style.space(6)

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(16)
              anchors.rightMargin: Style.space(16)
              height: parent.height
              radius: height / 2
              color: root.foreground
              opacity: 0.12
            }

            Rectangle {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              width: (parent.width - Style.space(32)) * Math.min(root.percent === null ? 0 : root.percent, 100) / 100
              height: parent.height
              radius: height / 2
              color: root.overLimit || root.nearLimit ? Color.urgent : Color.accent
            }
          }

          Text {
            visible: root.hasKey && root.overLimit && !!root.usage && root.usage.overages !== null && root.usage.overages > 0
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            text: Model.formatCredits(root.usage ? root.usage.overages : null) + " credits over the plan limit"
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.hasKey && !root.usage && root.errorMessage === ""
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            text: "Fetching usage…"
            color: root.mutedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }

          Text {
            visible: root.errorMessage !== ""
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            width: parent.width - Style.space(32)
            text: root.errorMessage
            wrapMode: Text.WordWrap
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // ---- API key: prompt when unset, masked click-to-edit row when set.
          Column {
            visible: !root.hasKey && !root.editingKey
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            spacing: Style.space(6)

            Text {
              text: "QUICKNODE"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.letterSpacing: 1
            }
            Text {
              width: contentColumn.width - Style.space(32)
              wrapMode: Text.WordWrap
              text: "Paste an Admin API key to see credit usage and endpoints."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Row {
              spacing: Style.space(6)

              TapHandler {
                onTapped: root.startEditingKey()
              }
              HoverHandler {
                cursorShape: Qt.PointingHandCursor
              }

              Text {
                text: "󰌆"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              Text {
                text: "Set API key"
                color: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Row {
            visible: root.editingKey
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            spacing: Style.space(6)

            TextField {
              id: keyField
              width: Style.space(300)
              password: true
              placeholderText: "QuickNode Admin API key"
              foreground: root.foreground
              font.family: root.fontFamily

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.cancelEditingKey()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitKey()
                  event.accepted = true
                }
              }
            }

            Rectangle {
              width: Style.space(18)
              height: Style.space(18)
              anchors.verticalCenter: parent.verticalCenter
              radius: Math.min(4, Style.cornerRadius)
              color: cancelKeyArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"

              Text {
                anchors.centerIn: parent
                text: "✕"
                font.family: root.fontFamily
                color: Qt.darker(root.foreground, 1.4)
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: cancelKeyArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.cancelEditingKey()
              }
            }
          }

          // ---- Endpoints: header with filter, then one row per endpoint.
          Rectangle {
            visible: root.hasKey && root.endpoints.length > 0
            width: parent.width
            height: Style.spacing.hairline
            color: root.foreground
            opacity: 0.12
          }

          Item {
            visible: root.hasKey && root.endpoints.length > 0
            width: parent.width
            height: filterField.implicitHeight

            Row {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "ENDPOINTS"
                color: root.mutedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.visibleEndpoints.length === root.endpoints.length
                  ? String(root.endpoints.length)
                  : root.visibleEndpoints.length + "/" + root.endpoints.length
                color: Qt.darker(root.foreground, 2)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            TextField {
              id: filterField
              anchors.right: parent.right
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(190)
              verticalPadding: Style.space(3)
              placeholderText: "Filter chain or name  /"
              foreground: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall

              onTextChanged: root.filterText = text

              // Escape clears a non-empty filter first; a second press hands
              // focus back so the panel's own Escape (close) works again.
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  if (text !== "") text = ""
                  else root.blurFilter()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.blurFilter()
                  event.accepted = true
                }
              }
            }
          }

          Text {
            visible: root.hasKey && root.endpoints.length > 0 && root.visibleEndpoints.length === 0
            anchors.left: parent.left
            anchors.leftMargin: Style.space(16)
            text: "No endpoints match “" + root.filterText + "”"
            color: root.mutedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: true
          }

          Column {
            visible: root.hasKey && root.visibleEndpoints.length > 0
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: root.visibleEndpoints

              Rectangle {
                id: endpointRow
                required property var modelData
                readonly property var badge: Model.chainBadge(modelData.chain)
                readonly property string iconPath: Model.chainIcon(modelData.chain)
                readonly property var credits: Model.chainCredits(root.chainUsage, modelData.chain)

                width: parent.width
                height: rowLeft.implicitHeight + Style.space(16)
                radius: Style.cornerRadius
                color: rowHover.hovered ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"

                HoverHandler {
                  id: rowHover
                }

                Row {
                  id: rowLeft
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(10)

                  // Chain logo from icons/ when bundled; otherwise a
                  // brand-colored badge with the chain's glyph or initial.
                  // Paused endpoints are dimmed either way.
                  Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(28)
                    height: Style.space(28)
                    opacity: endpointRow.modelData.active ? 1 : 0.45

                    Image {
                      id: chainLogo
                      anchors.fill: parent
                      source: endpointRow.iconPath ? Qt.resolvedUrl(endpointRow.iconPath) : ""
                      // Rasterize the SVG above display size so it stays
                      // crisp on HiDPI outputs.
                      sourceSize.width: Style.space(28) * 2
                      sourceSize.height: Style.space(28) * 2
                      fillMode: Image.PreserveAspectFit
                      smooth: true
                      visible: status === Image.Ready
                    }

                    Rectangle {
                      anchors.fill: parent
                      visible: chainLogo.status !== Image.Ready
                      radius: Style.space(7)
                      color: endpointRow.badge.color

                      Text {
                        anchors.centerIn: parent
                        text: endpointRow.badge.symbol
                        color: "#ffffff"
                        font.family: root.fontFamily
                        font.pixelSize: endpointRow.badge.symbol.length > 1 ? Style.font.caption : Style.font.body
                        font.bold: true
                      }
                    }
                  }

                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    Text {
                      text: endpointRow.modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      width: Math.min(implicitWidth, Style.space(220))
                    }
                    Row {
                      spacing: Style.space(6)
                      Text {
                        text: Model.endpointLocation(endpointRow.modelData)
                        color: root.mutedText
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                      Text {
                        visible: !endpointRow.modelData.active
                        text: "paused"
                        color: Color.urgent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }
                  }
                }

                Column {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  // Per-chain credits this billing period; shared by every
                  // endpoint on that chain.
                  Row {
                    anchors.right: parent.right
                    spacing: Style.space(4)
                    visible: endpointRow.credits !== null

                    Text {
                      id: creditsValue
                      text: Model.formatCredits(endpointRow.credits)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      text: "credits"
                      color: root.mutedText
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      anchors.baseline: creditsValue.baseline
                    }
                  }

                  // Copy-to-clipboard chips for the RPC / WSS addresses.
                  Row {
                    anchors.right: parent.right
                    spacing: Style.space(4)

                    Repeater {
                      model: [
                        { label: "RPC", key: endpointRow.modelData.id + ":http", payload: endpointRow.modelData.httpUrl },
                        { label: "WSS", key: endpointRow.modelData.id + ":wss", payload: endpointRow.modelData.wssUrl }
                      ]

                      Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool copied: root.copiedKey === modelData.key

                        visible: modelData.payload !== ""
                        width: chipText.implicitWidth + Style.space(12)
                        height: chipText.implicitHeight + Style.space(6)
                        radius: Math.min(4, Style.cornerRadius)
                        color: chipArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                        border.width: 1
                        border.color: chip.copied ? Color.accent : Qt.darker(root.foreground, 2.2)

                        Text {
                          id: chipText
                          anchors.centerIn: parent
                          text: chip.copied ? "󰄬 copied" : chip.modelData.label
                          color: chip.copied ? Color.accent : root.mutedText
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          font.letterSpacing: 1
                        }

                        MouseArea {
                          id: chipArea
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.copyText(chip.modelData.key, chip.modelData.payload)
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // ---- Footer: masked key + dashboard link.
          Item {
            visible: root.hasKey
            width: parent.width
            height: footerLeft.implicitHeight + Style.space(4)

            Row {
              id: footerLeft
              anchors.left: parent.left
              anchors.leftMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              visible: !root.editingKey

              TapHandler {
                onTapped: root.startEditingKey()
              }
              HoverHandler {
                cursorShape: Qt.PointingHandCursor
              }

              Text {
                text: "󰌆"
                color: root.mutedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                text: Model.maskedKey(root.apiKey)
                color: root.mutedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Row {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(20)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              TapHandler {
                onTapped: if (root.bar) root.bar.run("xdg-open https://dashboard.quicknode.com")
              }
              HoverHandler {
                cursorShape: Qt.PointingHandCursor
              }

              Text {
                text: "DASHBOARD"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }
              Text {
                text: "󰈁"
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }
}
