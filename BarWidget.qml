import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// QuickNode pill for the bar: the QuickNode symbol plus the billing
// period's credit usage percentage, with the detail popup hosted in
// Panel.qml.
//
// Left click toggles the panel, middle click refreshes, right click opens
// the panel straight into API key editing.
BarWidget {
  id: root
  moduleName: "sebs.quicknode"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root). Open maps to the
  // panel's hotkey path so summoning suppresses the center hover reveal.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property string percentText: panelLoader.item ? panelLoader.item.label : ""
  readonly property bool overLimit: panelLoader.item ? panelLoader.item.overLimit === true : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    active: root.overLimit
    tooltipText: "QuickNode"

    // The button's own label is text-only; the logo + percentage row below
    // replaces it, so the button just sizes itself around that row.
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : content.implicitWidth + button.scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? content.implicitHeight + button.scaledVerticalPadding * 2 : -1

    readonly property color contentColor: button.active && button.useActiveColor ? button.activeColor : button.foreground

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.spaceReal(5)

      // Sized to the bar's icon font rather than its icon canvas so the
      // logo reads as an inline glyph next to the number.
      Item {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.bar.iconFont
        height: Style.bar.iconFont

        // Hidden layer the effect samples; the effect paints it in the
        // bar's foreground (or urgent) color.
        Image {
          id: logo
          anchors.fill: parent
          source: Qt.resolvedUrl("assets/quicknode.svg")
          sourceSize.width: Style.bar.iconFont * 2
          sourceSize.height: Style.bar.iconFont * 2
          fillMode: Image.PreserveAspectFit
          smooth: true
          visible: false
          layer.enabled: true
        }

        MultiEffect {
          anchors.fill: logo
          source: logo
          colorization: 1.0
          colorizationColor: button.contentColor
        }
      }

      // Vertical bars only have room for the logo.
      Text {
        visible: !root.vertical && root.percentText !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.percentText
        color: button.contentColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }
    }

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton) {
        root.open()
        if (panelLoader.item && panelLoader.item.startEditingKey) panelLoader.item.startEditingKey()
      }
      else root.togglePanel()
    }
  }
}
