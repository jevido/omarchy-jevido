import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "omarchy.media"

  // This clone's own service when it is the one mounted, the built-in when the
  // clone is switched off.
  readonly property var mediaService: bar?.shell
    ? (bar.shell.serviceFor("jevido.media") || bar.shell.serviceFor("omarchy.media"))
    : null
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string playIcon: activePlayer && activePlayer.isPlaying ? "󰝚" : "󰏤"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property bool volumeSupported: activePlayer ? activePlayer.volumeSupported === true : false
  readonly property real playerVolume: activePlayer && activePlayer.volume !== undefined ? activePlayer.volume : 0

  property bool popupOpen: false

  // Shape the bar looks for when routing shell summon/hide/toggle.
  readonly property bool opened: popupOpen
  function open() { popupOpen = true }
  function close() { popupOpen = false }
  function toggle() { popupOpen = !popupOpen }
  property real maxLabelWidth: 180
  readonly property bool scrolling: labelText.needsScroll && button.tooltipHovered
    && !popupOpen && bar && !bar.vertical

  visible: hasMedia
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // A now-playing chip is something you read, so the plain click opens the
  // panel; playback stays on the buttons that cannot be hit by accident.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.hasMedia
    fixedWidth: root.vertical ? -1 : content.implicitWidth + Style.spaceReal(button.horizontalMargin) * 2
    tooltipText: root.hasMedia ? (root.title + (root.artist ? "  —  " + root.artist : "")) : ""

    onPressed: function(b) {
      if (!root.activePlayer) return
      if (b === Qt.RightButton) {
        if (root.mediaService) root.mediaService.runAction("playPause", false)
      } else if (b === Qt.MiddleButton) {
        if (root.mediaService) root.mediaService.runAction("next", false)
      } else {
        root.popupOpen = !root.popupOpen
      }
    }

    onWheelMoved: function(delta) {
      if (!root.activePlayer || !root.mediaService) return
      root.mediaService.runAction(delta > 0 ? "previous" : "next", false)
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(7)

      // Optically centred: the nerd-font note has its own side bearings, so
      // a plain Text lands off-centre next to the label.
      OpticalGlyph {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        width: Style.bar.iconSlot
        height: Style.bar.iconSlot
        text: root.playIcon
        fontFamily: button.fontFamily
        fontSize: Style.font.body
        color: root.activePlayer && root.activePlayer.isPlaying
          ? root.bar.barForeground
          : Qt.darker(root.bar.barForeground, 1.5)

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }

      // The clip box takes the icon slot rather than the glyph's own height,
      // so descenders survive and the label shares the bar's centre line.
      Item {
        id: scrollClip
        width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
        height: Style.bar.iconSlot
        clip: true
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.bar.vertical && root.title !== ""

        // Parked and elided at rest, scrolling only while the pointer is on
        // it: a marquee running forever next to static icons is what made the
        // bar look restless.
        Text {
          id: labelText
          text: root.title + (root.artist ? "  ·  " + root.artist : "")
          color: root.bar.barForeground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
          anchors.verticalCenter: parent.verticalCenter
          width: root.scrolling ? implicitWidth : scrollClip.width
          elide: root.scrolling ? Text.ElideNone : Text.ElideRight

          property bool needsScroll: implicitWidth > scrollClip.width

          NumberAnimation on x {
            id: scrollAnim
            running: root.scrolling
            loops: Animation.Infinite
            duration: Math.max(6000, labelText.implicitWidth * 25)
            from: scrollClip.width
            to: -labelText.implicitWidth
            easing.type: Easing.Linear
            onRunningChanged: if (!running) labelText.x = 0
          }
        }
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        spacing: Style.space(10)
        width: parent.width

        BorderSurface {
          width: Style.space(64)
          height: Style.space(64)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.bar.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)

          Image {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
            visible: source !== ""
          }

          Text {
            anchors.centerIn: parent
            visible: !root.activePlayer || !root.activePlayer.trackArtUrl
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          spacing: Style.space(4)
          width: parent.width - Style.space(74)

          Text {
            text: root.title || "Nothing playing"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: root.artist
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            text: root.activePlayer && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: "󰒮"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: "󰒭"
          foreground: root.bar.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
        }
      }

      // Player volume over MPRIS, so it moves Spotify's own level and leaves
      // the rest of the system where it was. Hidden for players that do not
      // publish a settable Volume.
      Row {
        width: parent.width
        spacing: Style.space(8)
        visible: root.volumeSupported

        Text {
          id: volumeIcon
          text: root.playerVolume <= 0.005 ? "󰝟" : (root.playerVolume < 0.5 ? "󰖀" : "󰕾")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          width: Style.space(22)
          horizontalAlignment: Text.AlignHCenter
          anchors.verticalCenter: parent.verticalCenter
        }

        PanelSlider {
          id: volumeSlider
          bar: root.bar
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - volumeIcon.width - volumePct.width - Style.space(16)
          minimum: 0
          maximum: 1
          step: 0.05
          value: root.playerVolume
          onMoved: function(v) { if (root.activePlayer) root.activePlayer.volume = v }
        }

        Text {
          id: volumePct
          text: Math.round((volumeSlider.dragging ? volumeSlider.liveValue : root.playerVolume) * 100) + "%"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          width: Style.space(36)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      PanelSeparator {
        visible: root.sourcePlayers.length > 1
        foreground: root.bar.foreground
      }

      Column {
        id: sourceList
        visible: root.sourcePlayers.length > 1
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.sourcePlayers

          BorderSurface {
            id: sourceRow
            required property var modelData

            readonly property var player: modelData
            readonly property bool selected: root.activePlayer && player
              && root.mediaService.playerKey(root.activePlayer) === root.mediaService.playerKey(player)
            readonly property string sourceTitle: player ? (player.trackTitle || player.identity || player.desktopEntry || "Media source") : "Media source"
            readonly property string sourceDetail: player && player.trackArtist ? player.trackArtist : (player && player.identity ? player.identity : "")

            width: sourceList.width
            height: sourceInner.implicitHeight + Style.space(10)
            radius: Style.spacing.labelGap
            color: selected ? Style.selectedFillFor(root.bar.foreground, Color.accent) : "transparent"
            borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, Color.accent) : Border.none()

            Row {
              id: sourceInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: sourceRow.borderLeft + Style.space(8)
              anchors.rightMargin: sourceRow.borderRight + Style.space(8)
              spacing: Style.space(8)

              Text {
                text: sourceRow.player && sourceRow.player.isPlaying ? "󰏤" : "󰐊"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                width: Style.space(18)
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(26)
                spacing: Style.space(1)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  text: sourceRow.sourceTitle
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: sourceRow.selected
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  text: sourceRow.sourceDetail
                  color: Qt.darker(root.bar.foreground, 1.5)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                  visible: text !== ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.selectPlayer(root.mediaService.playerKey(sourceRow.player))
            }
          }
        }
      }
    }
  }
}
