# IIS Trainings: chalkboard calendar for iPhone

A native SwiftUI app that shows **every class** on the same three monday
boards behind the monday **Calendar** dashboard. It's drawn as a chalkboard.

| Board | ID | What it contributes |
|---|---|---|
| Trainings | `18402638125` | Every scheduled / in-scheduling class |
| Bootcamps/Multi-Instructor courses | `18407475639` | One entry per **subitem** (each instructor's week), with times, zone, and customer taken from the parent course |
| Completed Courses | `18408627394` | Past classes (can be hidden with a toggle) |

## What it does

- **Month and Week views**, switched with the pill at the top. Swipe
  sideways or use the arrows to page, and tap **Today** to jump back.
- **Auto-expanding days.** Every class is drawn as a chalk bar across the
  days it meets. Week rows grow as tall as they need to, so nothing is ever
  hidden behind "+3 more". Tally marks in each day show how many classes it has.
- **Tap a day to zoom in.** The day zooms open with the iOS zoom transition
  and lists every class in time order. A "your time" ruler at the top shows
  overlaps and time-zone shifts at a glance. Swipe to go to the next or
  previous day.
- **Tap a class to expand it in place.** You get the dates, "Day 3 of 5"
  progress dots, the class time plus the same time converted to your zone,
  instructor, status, delivery, location (with a Map button), customer,
  client, client contact, opportunity, the Confirmed checkbox, and the board
  and group. There are also **Open in monday** and **Share** buttons.
  Tapping a bar in the month grid zooms to that day with the class already open.
- **Foldable / dual-screen layout.** When the screen is at least 700 pt wide
  (an unfolded foldable, landscape, or iPad), the app splits along the hinge:
  the calendar is on one side and the zoomed day on the other. Tapping a day
  or class updates the second half instead of pushing a new screen. Unfolding
  while zoomed in moves that day into the side pane. On wide screens the
  week view switches to side-by-side day columns.
- **Filters:** everyone, **Just me**, or any one instructor (with counts),
  plus search across course, customer, opportunity and location. You can
  also hide cancelled or pending-reschedule classes, include or exclude
  Completed Courses, and show or hide weekends. Weekends are hidden by
  default, which matches the boards' Class Dates setting and leaves wider
  columns on a phone.
- **Live data:** loads on launch, refreshes when you return to the app if
  the data is more than 5 minutes old, and supports pull-to-refresh. The
  last sync is cached on the device, so the calendar opens instantly and
  works offline.
- **Chalkboard look:** slate board with eraser smudges and chalk dust,
  Chalkduster and Chalkboard SE type, hand-drawn boxes, a circle around
  today, underlines that draw themselves in, and bars that sweep in when a
  month appears. Each instructor keeps their monday label color, softened to
  a chalk pastel. Bars for classes still In Scheduling are dashed, and
  cancelled ones are struck through.

## Build and run

Requirements: a Mac with **Xcode 26 or later** and an iPhone on iOS 26 or
later. It runs on iOS 27 as is.

1. Open `ios/IISTrainings.xcodeproj`.
2. Select the **IISTrainings** target, then **Signing & Capabilities**, and
   choose your Team. Change the bundle id
   (`com.innovationinsoftware.IISTrainings`) if Xcode asks.
3. Pick your iPhone (or a simulator) and press **Run**.

To require iOS 27, set **iOS Deployment Target** to 27.0 in the target's
Build Settings. Nothing in the code needs to change.

The project uses Xcode's folder-synced groups, so any file you add under
`ios/IISTrainings/` is picked up automatically.

## Connect to monday

The app starts with **sample classes** so you can see the design straight
away. To load the real boards:

1. In monday, open your avatar, then **Developers**, then **My access
   tokens**, and copy the token. (This is the same kind of token the
   `MONDAY_API_TOKEN` GitHub secret uses.)
2. In the app, tap the **gear**, paste the token, and tap **Save & sync**.
3. Under **You**, check that your name matches your Instructor label
   exactly. That's what the **Just me** filter uses.

The token is stored in the iOS Keychain and only ever sent to
`api.monday.com`.

## Code map

```
ios/IISTrainings/
  App/IISTrainingsApp.swift      app entry, refresh on launch / foreground
  Model/DayKey.swift             time-zone-free calendar days + clock times
  Model/Training.swift           one class or bootcamp week; time-zone map
  Model/CalendarLayout.swift     month/week math and bar lane packing
  Services/MondayClient.swift    GraphQL queries + column parsing
  Services/TrainingStore.swift   state, disk cache, filters
  Services/KeychainStore.swift   token storage
  Services/SampleData.swift      demo classes
  Theme/Chalk.swift              colors, fonts, hand-drawn shapes, board texture
  Views/RootView.swift           single vs dual-pane layout, navigation, paging
  Views/MonthGrid.swift          auto-expanding month grid and chalk bars
  Views/WeekBoard.swift          week view (list or columns)
  Views/DayContent.swift         zoomed day, time ruler
  Views/EventCard.swift          expandable class card and details
  Views/FilterSheet.swift, SettingsView.swift, CalendarHeader.swift, Components.swift
```

### Rules carried over from `generate_ics.py`

- Classes meet **weekdays only** across their date range (the boards hide
  weekends), unless the range falls entirely on a weekend.
- The Timezone dropdown labels from all three boards (EST, US Eastern,
  Singapore, Europe Central, and so on) map to real time zones, so the
  "your time" conversion is correct across DST.
- Bootcamp subitems named like `Dave Nicolette | Week 3` become
  "Course · Week 3". If a subitem's Instructor label is blank, the name in
  the subitem title is used instead.
