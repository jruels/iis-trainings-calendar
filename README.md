# IIS classes to Fantastical calendar feed

Publishes a filtered `.ics` feed of the classes assigned to you across three
Monday boards, so Fantastical can subscribe to it.

All board and column IDs are already filled in. You only supply an API token.

## Sources

| Board | ID | Where your assignment is read from |
|---|---|---|
| Trainings | `18402638125` | Parent Instructor column (`color_mm15thk1`) |
| Completed Courses | `18408627394` | Parent Instructor column (`color_mm15thk1`) |
| Bootcamps/Multi-Instructor courses | `18407475639` | **Subitem** Instructor column (`color_mm25xv4v`) |

The bootcamp board is the reason this is not a simple three-board loop. Those
parent items are labeled "Multiple Instructors", and the real per-instructor
assignment lives in subitems, each with its own Timeline. The script reads
those subitems and inherits Start Time, End Time, and Timezone from the parent
course, since subitems do not carry their own.

A bootcamp week appears in your calendar as
`SRE Bootcamp | TEKsystems (Week 3-4 Kubernetes)`.

## How events are generated

- **Multi-day ranges** become one event recurring Monday through Friday until
  the end date. A five-week block produces 25 weekday sessions, not one solid
  35-day bar. This matches the Class Dates columns, which are set to hide
  weekends.
- **No Start/End Time** falls back to all-day events spanning the range.
- **No dates set** items are skipped and listed in the run log, so you can see
  which of your assignments still need dates.
- **Non-person Instructor labels** are ignored: Unassigned, Requested Dates,
  Tentative, Holiday, Cancelled, Pending Reschedule, Multiple Instructors,
  Bootcamp/Multi-Instructor, and the blank placeholder labels.
- **Excluded statuses** default to Cancelled and Pending Reschedule.
- **UIDs are keyed on the Monday item ID**, not the board. Monday preserves
  item IDs when an item moves between boards, so a class moving from Trainings
  to Completed Courses updates in place rather than appearing twice.

## Setup

### 1. Create the repo

Create a **public** GitHub repo (for example `iis-trainings-calendar`) and push
these files.

Public is the practical choice: Fantastical's subscription refresh runs on
Flexibits' servers, not your Mac, so it needs a URL fetchable without auth.
The feed carries class titles, dates, statuses, opportunity numbers, and
delivery type. No rates, contracts, or client contacts. To drop the
opportunity numbers, remove the `Opportunity:` line from the description
blocks in `generate_ics.py`.

### 2. Get a Monday API token

Monday, then avatar (bottom left), then **Developers**, then **My access
tokens**. Generate a personal API v2 token.

### 3. Add the repo secret

Repo, then **Settings**, then **Secrets and variables**, then **Actions**,
then **New repository secret**:

- Name: `MONDAY_API_TOKEN`
- Value: the token

That is the only required secret.

### 4. Test

Repo, then **Actions**, then **Sync IIS classes to iCal feed**, then **Run
workflow**.

The log prints a per-board breakdown, a total, and any of your assignments
missing dates. On success it commits `jason_classes.ics`.

### 5. Subscribe in Fantastical

```
https://raw.githubusercontent.com/<your-username>/<repo>/main/jason_classes.ics
```

Fantastical, then **File**, then **New Calendar Subscription**. Paste the URL,
set the refresh interval, pick a color.

## Adjusting

Env vars in the workflow file:

- `TARGET_INSTRUCTOR` — must match the Instructor label exactly.
- `EXCLUDE_STATUSES` — comma-separated class statuses to omit.
- `DEFAULT_TZ` — fallback when Timezone is empty.
- `OUTPUT_FILE` — change if generating more than one feed.

To add a fourth board, append an entry to the `SOURCES` list in
`generate_ics.py` with `mode` set to `parent` or `subitem`.

## Known data issues on the boards

These are board hygiene problems, not script bugs. The script handles them
without crashing, but they cost accuracy.

1. **Timezone dropdowns are inconsistent across boards.** Trainings uses EST,
   EDT, PST, CST, CDT, MDT, India, Singapore, London, Paris. Bootcamps and
   Completed use US Eastern, US Central, US Mountain, US Pacific, UTC, Europe
   Western/Central/Eastern, Asia Pacific, plus some abbreviations. The script
   maps all known labels, but standardizing on one set is worth doing.
2. **Mixing standard and daylight labels** (EST vs EDT) means the label is not
   a reliable record of intent. Both map to `America/New_York` and the zone
   resolves the offset by date, so output stays correct.
3. **"Multiple Instructros" is misspelled** and appears on all three boards.
   Both spellings are handled.
4. **Completed bootcamps lose per-week attribution.** The Completed Courses
   subitem board has no Instructor column, unlike the live Bootcamps board. A
   bootcamp that finishes and moves to Completed will only appear in your feed
   if the parent Instructor is set to you, which for a multi-instructor course
   it usually is not. Past bootcamp weeks you taught will drop out of the feed
   once the course is marked complete.
5. **Several Instructor labels are blank placeholders.** Items set to those are
   treated as unassigned.
