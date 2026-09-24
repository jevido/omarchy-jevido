import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "jevido.clock"
  ipcTarget: "jevido.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // ---- The feeds. omarchy-calendar-sync (a systemd user timer, every ten
  //      minutes) reads the ICS URLs in ~/.config/omarchy/calendars.json and
  //      flattens them into one day-keyed file. This panel only ever reads
  //      that file: nothing here writes back to Google or Outlook, so a
  //      reminder set below is a local notification and not an invitation.
  readonly property string home: Quickshell.env("HOME")
  readonly property string eventsPath: home + "/.local/share/omarchy-calendar/events.json"

  property var calendarPayload: Model.parsePayload("")
  readonly property var feedAccounts: calendarPayload.calendars || []
  readonly property var brokenAccounts: (calendarPayload.calendars || []).filter(function(a) {
    return !Model.accountOk(a)
  })
  readonly property var eventsByDay: calendarPayload.days || ({})
  readonly property string generatedAt: String(calendarPayload.generatedAt || "")
  readonly property string lastRefreshed: generatedAt === ""
    ? "never refreshed"
    : "last refreshed " + Qt.formatDateTime(new Date(generatedAt), "d MMM HH:mm")

  // The one thing the stock panel refuses to have: a per-day cursor. It is
  // what a reminder needs a day to hang off, so the grid becomes a picker.
  property string selectedKey: todayKey
  readonly property date selectedDate: Model.dateFromKey(selectedKey)
  readonly property var selectedEvents: eventsByDay[selectedKey] || []

  // A long day is trimmed rather than scrolled: the panel scrolling is what
  // the month wheel wants, and one of the two has to give.
  readonly property int eventLimit: 8
  readonly property var visibleEvents: selectedEvents.slice(0, eventLimit)
  readonly property int hiddenEventCount: Math.max(0, selectedEvents.length - eventLimit)

  // ---- Settings. Right-clicking the bar label lands here; the format list
  //      it replaced was a ring you had to click past to read.
  property bool settingsOpen: false
  readonly property bool barVertical: hostWidget ? hostWidget.vertical === true : false
  readonly property string formatKey: barVertical ? "verticalFormat" : "format"
  readonly property string currentFormat: setting(formatKey, barVertical ? "HH\n—\nmm" : "dddd HH:mm")
  readonly property var formatPresets: Model.clockFormats(barVertical)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)


  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    root.settingsOpen = false
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  // Omarchy 4.0.4 hands plugins a PluginBarApi facade where the property is
  // read-only; assigning it throws, and in close() that throw skipped the
  // hide, leaving the popup holding the pointer. The setter comes first.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
    root.selectDay(root.todayKey)
    eventsFile.reload()
  }

  // Every route in — the bar label, a hotkey, the popout coordinator handing
  // over from another panel — ends at the panel becoming visible, and not all
  // of them go through open(). Reopening on the month you wandered off to
  // last week is not where "what is the date?" is answered, so today is what
  // a fresh look always shows.
  onOpenedChanged: {
    if (!root.opened) return
    root.today = new Date()
    root.goToToday()
    root.selectDay(root.todayKey)
    eventsFile.reload()
  }

  function openSettings() {
    root.open()
    root.settingsOpen = true
  }

  function closeSettings() {
    root.settingsOpen = false
  }

  function applyFormat(value) {
    var next = String(value || "").trim()
    if (next === "" || next === String(root.currentFormat)) return
    var values = {}
    values[root.formatKey] = next
    persistSettings(values)
  }

  // What the bar would read with that format, so the list is examples rather
  // than a column of Qt format strings.
  function formatPreview(value) {
    var literal = Model.isoWeekLiteral(root.today.getFullYear(), root.today.getMonth(), root.today.getDate())
    return Qt.formatDateTime(root.today, String(value).replace(/ww/g, literal)).replace(/\n/g, " ")
  }

  function eventsOn(key) {
    return root.eventsByDay[key] || []
  }

  function selectDay(key) {
    root.selectedKey = key
    // The time field is only ever a default until it is typed in, and a
    // default that has already passed is worse than no default at all.
    reminderTimeField.text = Model.defaultReminderTime(key, new Date())
  }

  function applyPayload(raw) {
    root.calendarPayload = Model.parsePayload(raw)
  }

  function refreshFeeds() {
    syncProcess.running = true
  }

  function setReminder() {
    if (root.remind(root.selectedKey, String(reminderTimeField.text).trim(),
                    String(reminderTextField.text).trim()))
      reminderTextField.text = ""
  }

  // The helper decides between a transient timer and an installed one, and
  // both end up named omarchy-reminder-*, so `omarchy reminder show` and the
  // bar's own indicator count these alongside the ones it set itself.
  function remind(day, at, message) {
    if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(String(day))) return false
    if (!/^[0-9]{1,2}:[0-9]{2}$/.test(String(at))) return false

    var text = String(message || "").trim()
    if (text === "") text = "Reminder"

    reminderProcess.command = [
      root.home + "/.local/bin/omarchy-calendar-reminder", String(day), String(at), text
    ]
    reminderProcess.running = true
    return true
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  // A target of its own: jevido.clock is already claimed by the panel base's
  // own handler, and these are calls about the calendar rather than the clock.
  IpcHandler {
    target: "jevido.calendar"

    function refresh(): void { root.refreshFeeds() }
    function settings(): void { root.openSettings() }
    function stepMonth(delta: int): void { root.moveMonth(delta) }
    function calendar(): void { root.closeSettings() }
    function selectDay(key: string): void { root.selectDay(key) }
    function remind(day: string, at: string, message: string): void {
      root.remind(day, at, message)
    }
  }

  // The sync writes atomically, so a change here is always a whole file.
  FileView {
    id: eventsFile
    path: root.eventsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyPayload(text())
    onFileChanged: reload()
  }

  Process {
    id: syncProcess
    command: [root.home + "/.local/bin/omarchy-calendar-sync"]
    running: false
    onExited: eventsFile.reload()
  }

  Process {
    id: reminderProcess
    running: false
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Typing into the reminder fields must not reach the panel's own
      // single-key shortcuts, where "t" jumps to today and "w" flips the
      // week start out from under you mid-word.
      blocked: root.editingLife || reminderTimeField.activeFocus || reminderTextField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // The wheel means "next month" over the calendar, so the panel must
        // not also take it — the day list is capped instead of scrolled. The
        // settings view has no month to step and keeps ordinary scrolling.
        interactive: root.settingsOpen && (contentHeight > height || contentWidth > width)

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            visible: !root.settingsOpen
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          Item {
            visible: !root.settingsOpen
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: !root.settingsOpen && root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            visible: !root.settingsOpen
            width: parent.width
            height: gridColumn.y + gridColumn.height

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      id: dayCell
                      required property var modelData

                      readonly property var dayEvents: root.eventsOn(modelData.key)
                      readonly property bool selected: modelData.key === root.selectedKey

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      // Today is outlined, not filled: a lit-up block shouts
                      // over a grid this quiet. The selected day is the one
                      // exception, because it has to answer for the list
                      // underneath the grid.
                      color: dayCell.selected
                        ? Style.selectionFillFor(root.contentForeground, Color.accent)
                        : (dayMouse.containsMouse
                          ? Style.hoverFillFor(root.contentForeground, Color.accent)
                          : "transparent")
                      border.width: modelData.today ? Style.spacing.hairline : 0
                      border.color: Style.normalBorderFor(root.contentForeground, Color.accent)

                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        // Lifted by the height of the dot rail below, so a
                        // day with events and one without still read off the
                        // same line.
                        anchors.verticalCenterOffset: -Style.space(2)
                        text: modelData.day
                        color: modelData.inMonth
                          ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                          : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.today
                      }

                      // One dot per event to three, coloured by the account
                      // it came from. A count would need reading; a rail of
                      // dots is a busy day at a glance.
                      Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(4)
                        spacing: Style.space(3)

                        Repeater {
                          model: Math.min(3, dayCell.dayEvents.length)

                          Rectangle {
                            required property int index
                            width: Style.space(4)
                            height: Style.space(4)
                            radius: width / 2
                            color: dayCell.dayEvents[index].color
                            opacity: dayCell.dayEvents[index].cancelled
                              ? 0.25
                              : (dayCell.modelData.inMonth ? 1 : 0.45)
                          }
                        }
                      }

                      MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectDay(dayCell.modelData.key)

                        // Belt and braces: the overlay above the grid accepts
                        // the wheel when it is sized right, so this only ever
                        // runs if that one is not there.
                        onWheel: function(wheel) {
                          if (wheel.angleDelta.y === 0) {
                            wheel.accepted = false
                            return
                          }
                          root.moveMonth(wheel.angleDelta.y > 0 ? -1 : 1)
                          wheel.accepted = true
                        }
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "MAY" to "SEPTEMBER".
          Item {
            visible: !root.settingsOpen
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- The selected day. A list of what is on it and one field to
          //      add a reminder to it: the two things a click on a date can
          //      mean, on the surface the click happened on.
          Item {
            visible: !root.settingsOpen
            width: parent.width
            height: dayBlock.y + dayBlock.height

            Column {
              id: dayBlock
              y: Style.space(10)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(6)

              Item {
                width: parent.width
                height: Math.max(dayHeading.implicitHeight, Style.space(16))

                Text {
                  id: dayHeading
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: Qt.formatDate(root.selectedDate, "dddd d MMMM").toUpperCase()
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                PanelActionButton {
                  anchors.right: parent.right
                  anchors.rightMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰑐"
                  tooltipText: "Refresh calendars"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.refreshFeeds()
                }
              }

              Text {
                visible: root.selectedEvents.length === 0
                text: "Nothing scheduled"
                color: Qt.darker(root.contentForeground, 2.0)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: root.visibleEvents

                Rectangle {
                  id: eventRow
                  required property var modelData

                  readonly property bool cancelled: modelData.cancelled === true
                  // One colour for the whole row rather than three ways of
                  // saying "cancelled": the strike is the statement, the
                  // grey keeps it from competing with what is still on.
                  readonly property color eventForeground: eventRow.cancelled
                    ? Qt.darker(root.contentForeground, 2.4)
                    : root.contentForeground

                  width: dayBlock.width
                  height: Style.space(26)
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b,
                                 eventRow.cancelled ? 0.02 : 0.05)

                  Rectangle {
                    x: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(3)
                    height: parent.height - Style.space(10)
                    radius: width / 2
                    color: modelData.color
                    opacity: eventRow.cancelled ? 0.35 : 1
                  }

                  Text {
                    id: eventTime
                    x: Style.space(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(84)
                    text: Model.eventTimeLabel(modelData)
                    color: eventRow.cancelled
                      ? eventRow.eventForeground
                      : Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.strikeout: eventRow.cancelled
                  }

                  Text {
                    anchors.left: eventTime.right
                    anchors.right: eventWhere.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.title
                    elide: Text.ElideRight
                    color: eventRow.eventForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.strikeout: eventRow.cancelled
                  }

                  Text {
                    id: eventWhere
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Style.space(120))
                    horizontalAlignment: Text.AlignRight
                    text: modelData.location
                    elide: Text.ElideRight
                    color: Qt.darker(root.contentForeground, eventRow.cancelled ? 2.6 : 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.strikeout: eventRow.cancelled
                  }
                }
              }

              Text {
                visible: root.hiddenEventCount > 0
                text: "+" + root.hiddenEventCount + " more"
                color: Qt.darker(root.contentForeground, 2.0)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              // ---- The reminder. A local notification on a systemd timer,
              //      not an event written back to an account: the feeds are
              //      read-only, and a reminder nobody else can see is what
              //      was asked for.
              Row {
                width: parent.width
                spacing: Style.space(8)

                TextField {
                  id: reminderTimeField
                  width: Style.space(64)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "09:00"
                  placeholderText: "09:00"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily

                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.setReminder()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                      keyCatcher.forceActiveFocus()
                      event.accepted = true
                    }
                  }
                }

                TextField {
                  id: reminderTextField
                  width: parent.width - Style.space(64) - reminderButton.width - Style.space(16)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "Remind me to…"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily

                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.setReminder()
                      event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                      keyCatcher.forceActiveFocus()
                      event.accepted = true
                    }
                  }
                }

                Button {
                  id: reminderButton
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Remind"
                  bordered: true
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.setReminder()
                }
              }

              // A feed that is broken still has to say so, but a working one
              // says nothing: a running total of events is a number with no
              // decision behind it. The settings view keeps the full status.
              Repeater {
                model: root.brokenAccounts

                Row {
                  required property var modelData
                  spacing: Style.space(6)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(6)
                    height: Style.space(6)
                    radius: width / 2
                    color: modelData.color
                    opacity: 0.35
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name + " · " + Model.accountLine(modelData)
                    color: Style.hoverStateColor(root.contentForeground, Color.accent)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // ---- Settings. Reached by right-clicking the bar label, which
          //      used to cycle the format one click at a time: a ring you
          //      have to walk to read is a list nobody can see. Everything
          //      here writes straight to shell.json through persistSettings,
          //      so a choice made here is the choice after a restart.
          Item {
            visible: root.settingsOpen
            width: parent.width
            height: settingsBlock.y + settingsBlock.height

            Column {
              id: settingsBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(10)

              Item {
                width: parent.width
                height: Math.max(settingsHeading.implicitHeight, Style.space(20))

                PanelActionButton {
                  anchors.left: parent.left
                  anchors.leftMargin: -Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰅁"
                  tooltipText: "Back to the calendar"
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.closeSettings()
                }

                Text {
                  id: settingsHeading
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: parent.verticalCenter
                  text: "SETTINGS"
                  color: Qt.darker(root.contentForeground, 1.4)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.letterSpacing: 1
                }
              }

              Text {
                text: root.barVertical ? "BAR FORMAT (VERTICAL BAR)" : "BAR FORMAT"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              // The field takes any Qt date format, so a format nobody
              // thought to preset is still one press away. The presets under
              // it write into this same field, which is what makes the list a
              // starting point rather than the whole choice.
              Row {
                width: parent.width
                spacing: Style.space(8)

                TextField {
                  id: formatField
                  width: parent.width - applyFormatButton.width - Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.currentFormat
                  placeholderText: "dddd HH:mm"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily

                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                      root.applyFormat(formatField.text)
                      event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                      formatField.text = root.currentFormat
                      keyCatcher.forceActiveFocus()
                      event.accepted = true
                    }
                  }
                }

                Button {
                  id: applyFormatButton
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Apply"
                  bordered: true
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: root.applyFormat(formatField.text)
                }
              }

              Repeater {
                model: root.formatPresets

                Button {
                  required property var modelData

                  width: settingsBlock.width
                  text: root.formatPreview(modelData)
                  leftAlign: true
                  bordered: true
                  selected: String(modelData) === String(root.currentFormat)
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onClicked: {
                    formatField.text = modelData
                    root.applyFormat(modelData)
                  }
                }
              }

              Toggle {
                width: parent.width
                label: "Start weeks on " + root.nextWeekStartLabel
                description: "The grid's W column heading does the same thing"
                checked: root.weekStart === 1
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.toggleWeekStart()
              }

              Text {
                text: "CALENDARS"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Repeater {
                model: root.feedAccounts

                Row {
                  required property var modelData
                  spacing: Style.space(6)

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(6)
                    height: Style.space(6)
                    radius: width / 2
                    color: modelData.color
                    opacity: Model.accountOk(modelData) ? 1 : 0.35
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.accountSummary(modelData)
                    color: Model.accountOk(modelData)
                      ? Qt.darker(root.contentForeground, 1.9)
                      : Style.hoverStateColor(root.contentForeground, Color.accent)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Text {
                text: root.lastRefreshed
                color: Qt.darker(root.contentForeground, 2.0)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              // The feeds are ICS URLs in a file rather than a field here:
              // they are secrets, and a panel that can be summoned over a
              // shared screen is the wrong place to keep one readable.
              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Feeds are configured in ~/.config/omarchy/calendars.json"
                color: Qt.darker(root.contentForeground, 2.0)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
              }

              Button {
                text: "Refresh calendars now"
                bordered: true
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.refreshFeeds()
              }
            }
          }
        }

        // The wheel means "next month" anywhere over the calendar — the hero
        // and the day list are part of "the calendar" to anyone using it.
        //
        // A MouseArea and not a WheelHandler: every wheel in this shell that
        // works is a MouseArea (the tray, the media widget, PanelSlider), and
        // a handler nested this deep under the panel's card never saw the
        // event. Declared after the content so it is above it, because a
        // plain MouseArea consumes the wheel whether or not it does anything
        // with it, and the day cells each have one. acceptedButtons is
        // NoButton so a click still lands on the day underneath.
        MouseArea {
          // Sized off the column and never `anchors.fill: parent`: a child
          // declared inside a Flickable is reparented onto its contentItem,
          // which Flickable never gives a size — so filling the parent is
          // filling nothing, and a zero-sized MouseArea is hit by no pointer
          // anywhere. That is what ate the first two attempts at this.
          x: 0
          y: 0
          width: calendarColumn.width
          height: calendarColumn.height
          z: 10
          enabled: !root.settingsOpen
          acceptedButtons: Qt.NoButton
          propagateComposedEvents: true

          onWheel: function(wheel) {
            // Horizontal wheels and touchpad side-scrolls report y === 0;
            // without this they would every one read as "next month".
            if (wheel.angleDelta.y === 0) {
              wheel.accepted = false
              return
            }
            root.moveMonth(wheel.angleDelta.y > 0 ? -1 : 1)
            wheel.accepted = true
          }
        }
      }
    }
  }
}
