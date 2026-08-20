"""
Generate a filtered .ics calendar feed of Jason Smith's classes from the
IIS monday.com boards.

Three sources, two shapes:

  1. Trainings (18402638125)         - parent-level Instructor column
  2. Completed Courses (18408627394) - parent-level Instructor column
  3. Bootcamps/Multi-Instructor      - SUBITEM-level Instructor column.
     (18407475639)                     Parent reads "Multiple Instructors";
                                       each subitem is one instructor's
                                       teaching block with its own Timeline.
                                       Times and timezone come from parent.

Multi-day ranges become weekday-recurring events, since the Class Dates
timeline columns are configured to hide weekends.
"""

import os
import sys
import json
import zoneinfo
from datetime import date, datetime, time, timedelta

import requests
from icalendar import Calendar, Event

API_URL = "https://api.monday.com/v2"
API_VERSION = "2024-10"
API_TOKEN = os.environ.get("MONDAY_API_TOKEN", "")

TARGET_INSTRUCTOR = os.environ.get("TARGET_INSTRUCTOR", "Jason Smith")
OUTPUT_FILE = os.environ.get("OUTPUT_FILE", "jason_classes.ics")
DEFAULT_TZ = os.environ.get("DEFAULT_TZ", "America/Los_Angeles")

# Instructor labels that are not real assignments.
NON_PERSON_LABELS = {
    "unassigned", "requested dates", "tentative", "holiday", "cancelled",
    "pending reschedule", "multiple instructors", "multiple instructros",
    "bootcamp/mulit-instructor", "bootcamp/multi-instructor", "",
}

# Class statuses to leave out of the feed.
EXCLUDE_STATUSES = {
    s.strip().casefold()
    for s in os.environ.get("EXCLUDE_STATUSES", "Cancelled,Pending Reschedule").split(",")
    if s.strip()
}

ACCOUNT = "innovativeio-company"

# --------------------------------------------------------------------------
# Source definitions
# --------------------------------------------------------------------------

# Shared parent column ids (identical across all three boards).
P = {
    "instructor": "color_mm15thk1",
    "status": "color_mm1bshmb",
    "timeline": "timerange_mm1cf8pp",
    "start_time": "hour_mm15ypeg",
    "end_time": "hour_mm15xbd2",
    "timezone": "dropdown_mm158c1g",
    "opportunity": "text_mm2125xz",
    "delivery": "color_mm21f51p",
    "location": "location_mm2nbxj9",
}

SOURCES = [
    {
        "name": "Trainings",
        "board_id": "18402638125",
        "mode": "parent",
        "cols": P,
    },
    {
        "name": "Completed Courses",
        "board_id": "18408627394",
        "mode": "parent",
        "cols": P,
    },
    {
        "name": "Bootcamps/Multi-Instructor courses",
        "board_id": "18407475639",
        "mode": "subitem",
        "cols": P,
        # Subitem columns on board 18407475641.
        "sub_cols": {
            "instructor": "color_mm25xv4v",
            "timeline": "timerange_mm2517h7",
            "status": "status",
        },
    },
]

# Timezone dropdown labels differ per board. This map covers all of them.
TZ_MAP = {
    "est": "America/New_York",
    "edt": "America/New_York",
    "us eastern": "America/New_York",
    "cst": "America/Chicago",
    "cdt": "America/Chicago",
    "us central": "America/Chicago",
    "mst": "America/Denver",
    "mdt": "America/Denver",
    "us mountain": "America/Denver",
    "pst": "America/Los_Angeles",
    "pdt": "America/Los_Angeles",
    "us pacific": "America/Los_Angeles",
    "utc": "UTC",
    "london": "Europe/London",
    "europe western": "Europe/London",
    "paris": "Europe/Paris",
    "europe central": "Europe/Paris",
    "europe eastern": "Europe/Bucharest",
    "india": "Asia/Kolkata",
    "singapore": "Asia/Singapore",
    "asia pacific": "Asia/Singapore",
}


# --------------------------------------------------------------------------
# API
# --------------------------------------------------------------------------

QUERY_PARENT = """
query ($boardId: ID!, $cursor: String) {
  boards(ids: [$boardId]) {
    items_page(limit: 100, cursor: $cursor) {
      cursor
      items { id name column_values { id text value } }
    }
  }
}
"""

QUERY_WITH_SUBITEMS = """
query ($boardId: ID!, $cursor: String) {
  boards(ids: [$boardId]) {
    items_page(limit: 50, cursor: $cursor) {
      cursor
      items {
        id
        name
        column_values { id text value }
        subitems { id name column_values { id text value } }
      }
    }
  }
}
"""


def api_post(query, variables):
    headers = {
        "Authorization": API_TOKEN,
        "API-Version": API_VERSION,
        "Content-Type": "application/json",
    }
    resp = requests.post(
        API_URL, headers=headers,
        json={"query": query, "variables": variables}, timeout=45,
    )
    resp.raise_for_status()
    payload = resp.json()
    if "errors" in payload:
        sys.exit(f"Monday API error: {payload['errors']}")
    return payload


def fetch_board(board_id, with_subitems=False):
    query = QUERY_WITH_SUBITEMS if with_subitems else QUERY_PARENT
    items, cursor = [], None
    while True:
        payload = api_post(query, {"boardId": board_id, "cursor": cursor})
        boards = payload.get("data", {}).get("boards") or []
        if not boards:
            sys.exit(f"Board {board_id} returned no data. Check ID and token scope.")
        page = boards[0]["items_page"]
        items.extend(page["items"])
        cursor = page.get("cursor")
        if not cursor:
            break
    return items


# --------------------------------------------------------------------------
# Parsing helpers
# --------------------------------------------------------------------------

def cmap(item):
    return {c["id"]: c for c in item.get("column_values", [])}


def jval(col):
    if not col or not col.get("value"):
        return None
    try:
        return json.loads(col["value"])
    except (json.JSONDecodeError, TypeError):
        return None


def text_of(cols, key):
    return (cols.get(key) or {}).get("text") or ""


def parse_timeline(col):
    data = jval(col)
    if not data or not data.get("from"):
        return None, None
    try:
        start = date.fromisoformat(data["from"])
        end = date.fromisoformat(data.get("to") or data["from"])
    except ValueError:
        return None, None
    if end < start:
        start, end = end, start
    return start, end


def parse_hour(col):
    data = jval(col)
    if not data or data.get("hour") is None:
        return None
    return time(int(data["hour"]), int(data.get("minute") or 0))


def resolve_tz(label):
    key = (label or "").split(",")[0].strip().casefold()
    name = TZ_MAP.get(key, DEFAULT_TZ)
    try:
        return zoneinfo.ZoneInfo(name)
    except zoneinfo.ZoneInfoNotFoundError:
        return zoneinfo.ZoneInfo("UTC")


def is_target(label):
    label = (label or "").strip()
    if label.casefold() in NON_PERSON_LABELS:
        return False
    return label.casefold() == TARGET_INSTRUCTOR.strip().casefold()


def first_weekday_on_or_after(d):
    while d.weekday() >= 5:
        d += timedelta(days=1)
    return d


# --------------------------------------------------------------------------
# Event construction
# --------------------------------------------------------------------------

def make_event(uid, summary, start_date, end_date, start_time, end_time, tz,
               description_lines, location=None):
    ev = Event()
    ev.add("uid", uid)
    ev.add("summary", summary)
    ev.add("dtstamp", datetime.now(tz=zoneinfo.ZoneInfo("UTC")))
    ev.add("description", "\n".join(description_lines))
    if location:
        ev.add("location", location)

    if start_time and end_time:
        first_day = first_weekday_on_or_after(start_date)
        if first_day > end_date:
            first_day = start_date
        dtstart = datetime.combine(first_day, start_time, tzinfo=tz)
        dtend = datetime.combine(first_day, end_time, tzinfo=tz)
        if dtend <= dtstart:
            dtend = dtstart + timedelta(hours=1)
        ev.add("dtstart", dtstart)
        ev.add("dtend", dtend)
        if end_date > first_day:
            until = datetime.combine(end_date, time(23, 59), tzinfo=tz).astimezone(
                zoneinfo.ZoneInfo("UTC")
            )
            ev.add("rrule", {
                "FREQ": "WEEKLY",
                "BYDAY": ["MO", "TU", "WE", "TH", "FR"],
                "UNTIL": until,
            })
    else:
        ev.add("dtstart", start_date)
        ev.add("dtend", end_date + timedelta(days=1))
    return ev


def build_calendar():
    cal = Calendar()
    cal.add("prodid", "-//Innovation in Software//Trainings Feed//EN")
    cal.add("version", "2.0")
    cal.add("x-wr-calname", f"IIS Classes - {TARGET_INSTRUCTOR}")
    cal.add("x-wr-timezone", DEFAULT_TZ)
    cal.add("method", "PUBLISH")

    seen_uids = set()
    totals = {}
    no_dates = []

    for src in SOURCES:
        board_id = src["board_id"]
        cols_def = src["cols"]
        want_subs = src["mode"] == "subitem"
        items = fetch_board(board_id, with_subitems=want_subs)
        print(f"  {src['name']}: fetched {len(items)} items")
        kept = 0

        for item in items:
            pc = cmap(item)
            class_status = text_of(pc, cols_def["status"])
            if class_status.strip().casefold() in EXCLUDE_STATUSES:
                continue

            tz = resolve_tz(text_of(pc, cols_def["timezone"]))
            start_time = parse_hour(pc.get(cols_def["start_time"]))
            end_time = parse_hour(pc.get(cols_def["end_time"]))
            opp = text_of(pc, cols_def["opportunity"])
            delivery = text_of(pc, cols_def["delivery"])
            location = text_of(pc, cols_def.get("location", ""))
            item_url = f"https://{ACCOUNT}.monday.com/boards/{board_id}/pulses/{item['id']}"

            if not want_subs:
                if not is_target(text_of(pc, cols_def["instructor"])):
                    continue
                s, e = parse_timeline(pc.get(cols_def["timeline"]))
                if not s:
                    no_dates.append(f"{src['name']}: {item['name']}")
                    continue

                # UID keyed on item id only. Monday preserves item ids when an
                # item moves between boards, so a class moving from Trainings
                # to Completed updates in place instead of duplicating.
                uid = f"monday-training-{item['id']}@innovationinsoftware.com"
                if uid in seen_uids:
                    continue
                seen_uids.add(uid)

                desc = []
                if class_status:
                    desc.append(f"Status: {class_status}")
                if opp:
                    desc.append(f"Opportunity: {opp}")
                if delivery:
                    desc.append(f"Delivery: {delivery}")
                desc.append(item_url)

                cal.add_component(make_event(
                    uid, item["name"], s, e, start_time, end_time, tz,
                    desc, location or None,
                ))
                kept += 1

            else:
                sub_def = src["sub_cols"]
                for sub in item.get("subitems") or []:
                    sc = cmap(sub)
                    if not is_target(text_of(sc, sub_def["instructor"])):
                        continue
                    s, e = parse_timeline(sc.get(sub_def["timeline"]))
                    if not s:
                        no_dates.append(f"{src['name']}: {item['name']} / {sub['name']}")
                        continue

                    uid = f"monday-bootcamp-{sub['id']}@innovationinsoftware.com"
                    if uid in seen_uids:
                        continue
                    seen_uids.add(uid)

                    # Bootcamp weeks get the parent course name plus the
                    # segment name, so the calendar entry is self-explanatory.
                    summary = f"{item['name']} ({sub['name']})"

                    desc = [f"Bootcamp segment: {sub['name']}"]
                    seg_status = text_of(sc, sub_def["status"])
                    if seg_status:
                        desc.append(f"Segment status: {seg_status}")
                    if class_status:
                        desc.append(f"Course status: {class_status}")
                    if opp:
                        desc.append(f"Opportunity: {opp}")
                    if delivery:
                        desc.append(f"Delivery: {delivery}")
                    desc.append(item_url)

                    cal.add_component(make_event(
                        uid, summary, s, e, start_time, end_time, tz,
                        desc, location or None,
                    ))
                    kept += 1

        totals[src["name"]] = kept

    print(f"\nMatched classes for {TARGET_INSTRUCTOR}:")
    for name, n in totals.items():
        print(f"  {name}: {n}")
    print(f"  TOTAL: {sum(totals.values())}")

    if no_dates:
        print(f"\nSkipped {len(no_dates)} assigned to you with no dates set:")
        for n in no_dates:
            print(f"  - {n}")

    return cal


def main():
    if not API_TOKEN:
        sys.exit("MONDAY_API_TOKEN is not set.")
    print("Fetching boards...")
    cal = build_calendar()
    with open(OUTPUT_FILE, "wb") as f:
        f.write(cal.to_ical())
    print(f"\nWrote {OUTPUT_FILE}")


if __name__ == "__main__":
    main()
