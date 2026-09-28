import json
import tempfile
import unittest
from datetime import date
from pathlib import Path
from unittest.mock import patch
from zoneinfo import ZoneInfo

import backend

ZONE = ZoneInfo("America/Montreal")
CONFIG = {"url": "https://example.test/work.ics", "name": "Work", "color": "blue", "excludeDeclined": True, "emails": ["me@example.test"]}


def event(body):
    return "BEGIN:VEVENT\r\n" + body.replace("\n", "\r\n") + "\r\nEND:VEVENT\r\n"


def feed(*events, extra=""):
    return "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Intemporel tests//EN\r\n" + extra + "".join(events) + "END:VCALENDAR\r\n"


def expand(raw, start="2026-09-01", stop="2026-10-01", config=None):
    return backend.expand_feed(backend.parse_feed(raw), config or CONFIG, date.fromisoformat(start), date.fromisoformat(stop), ZONE)


class CalendarTests(unittest.TestCase):
    def test_named_timezone_converts_to_display_timezone(self):
        days = expand(feed(event("UID:tz\nDTSTART;TZID=Europe/Paris:20260928T090000\nSUMMARY:Paris")))
        self.assertEqual(days["2026-09-28"][0]["start"], "2026-09-28T03:00:00-04:00")

    def test_floating_time_stays_local(self):
        days = expand(feed(event("UID:floating\nDTSTART:20260928T090000")))
        self.assertEqual(days["2026-09-28"][0]["start"], "2026-09-28T09:00:00-04:00")

    def test_utc_recurrence_stays_utc_across_dst(self):
        days = expand(feed(event("UID:utc\nDTSTART:20261031T130000Z\nRRULE:FREQ=DAILY;COUNT=3")), "2026-10-30", "2026-11-04")
        self.assertEqual(days["2026-10-31"][0]["start"], "2026-10-31T09:00:00-04:00")
        self.assertEqual(days["2026-11-01"][0]["start"], "2026-11-01T08:00:00-05:00")

    def test_weekly_byday_and_count(self):
        days = expand(feed(event("UID:weekly\nDTSTART:20260907T090000\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4")))
        self.assertEqual(sorted(days), ["2026-09-07", "2026-09-09", "2026-09-14", "2026-09-16"])

    def test_monthly_invalid_dates_are_skipped(self):
        days = expand(feed(event("UID:monthly\nDTSTART:20260131T090000\nRRULE:FREQ=MONTHLY;COUNT=3")), "2026-03-01", "2026-04-01")
        self.assertEqual(list(days), ["2026-03-31"])

    def test_bysetpos_last_weekday(self):
        days = expand(feed(event("UID:last\nDTSTART:20260731T090000\nRRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1")))
        self.assertEqual(list(days), ["2026-09-30"])

    def test_rdate_exdate_and_moved_occurrence(self):
        raw = feed(event("UID:series\nDTSTART:20260907T090000\nRRULE:FREQ=WEEKLY;COUNT=3\nEXDATE:20260914T090000\nRDATE:20260925T090000"),
                   event("UID:series\nRECURRENCE-ID:20260921T090000\nDTSTART:20260922T100000\nSUMMARY:Moved"))
        days = expand(raw)
        self.assertEqual(sorted(days), ["2026-09-07", "2026-09-22", "2026-09-25"])
        self.assertEqual(days["2026-09-22"][0]["summary"], "Moved")

    def test_cancelled_master_is_hidden(self):
        self.assertEqual(expand(feed(event("UID:cancel\nDTSTART:20260928T090000\nSTATUS:CANCELLED"))), {})

    def test_cancelled_exception_without_dtstart_is_hidden(self):
        raw = feed(event("UID:cancel\nDTSTART:20260907T090000\nRRULE:FREQ=WEEKLY;COUNT=3"),
                   event("UID:cancel\nRECURRENCE-ID:20260914T090000\nSTATUS:CANCELLED"))
        self.assertEqual(sorted(expand(raw)), ["2026-09-07", "2026-09-21"])

    def test_other_attendee_decline_does_not_hide_meeting(self):
        raw = feed(event("UID:meeting\nDTSTART:20260928T090000\nATTENDEE;PARTSTAT=ACCEPTED:mailto:me@example.test\nATTENDEE;PARTSTAT=DECLINED:mailto:other@example.test"))
        self.assertIn("2026-09-28", expand(raw))

    def test_viewer_decline_is_hidden_only_when_enabled(self):
        raw = feed(event("UID:meeting\nDTSTART:20260928T090000\nATTENDEE;PARTSTAT=DECLINED:MAILTO:ME@example.test"))
        self.assertEqual(expand(raw), {})
        self.assertIn("2026-09-28", expand(raw, config={**CONFIG, "excludeDeclined": False}))
        self.assertIn("2026-09-28", expand(raw, config={**CONFIG, "emails": []}))

    def test_declined_exception_does_not_resurrect_master(self):
        raw = feed(event("UID:series\nDTSTART:20260907T090000\nRRULE:FREQ=WEEKLY;COUNT=2"),
                   event("UID:series\nRECURRENCE-ID:20260914T090000\nDTSTART:20260914T090000\nATTENDEE;PARTSTAT=DECLINED:mailto:me@example.test"))
        self.assertEqual(list(expand(raw)), ["2026-09-07"])

    def test_alarm_cannot_overwrite_event_fields(self):
        raw = feed(event("UID:alarm\nDTSTART:20260928T090000\nSUMMARY:Meeting\nBEGIN:VALARM\nACTION:EMAIL\nTRIGGER:-PT15M\nSUMMARY:Reminder\nEND:VALARM"))
        self.assertEqual(expand(raw)["2026-09-28"][0]["summary"], "Meeting")

    def test_valid_empty_calendar_and_invalid_response(self):
        self.assertEqual(expand(feed()), {})
        for raw in ["<html>login</html>", "BEGIN:VCALENDAR\nVERSION:2.0", feed(event("UID:bad\nDTSTART:not-a-date"))]:
            with self.subTest(raw=raw), self.assertRaises(backend.CalendarError):
                backend.parse_feed(raw)

    def test_unknown_timezone_is_not_silently_local(self):
        with self.assertRaises(backend.CalendarError):
            backend.parse_feed(feed(event("UID:unknown\nDTSTART;TZID=Invalid/Unknown:20260928T090000")))

    def test_all_day_exclusive_end_and_duration(self):
        raw = feed(event("UID:all-day\nDTSTART;VALUE=DATE:20260928\nDTEND;VALUE=DATE:20260930"),
                   event("UID:duration\nDTSTART:20260930T233000\nDURATION:PT2H"))
        days = expand(raw, stop="2026-10-03")
        self.assertEqual(sorted(days), ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"])
        self.assertTrue(days["2026-09-28"][0]["allDay"])

    def test_event_without_end_does_not_leak_into_later_windows(self):
        raw = feed(event("UID:old\nDTSTART:20200101T090000"))
        self.assertEqual(expand(raw), {})

    def test_long_event_is_clipped_to_requested_window(self):
        raw = feed(event("UID:long\nDTSTART;VALUE=DATE:20200101\nDTEND;VALUE=DATE:20300101"))
        self.assertEqual(len(expand(raw)), 30)

    def test_embedded_timezone_is_used(self):
        zone = ("BEGIN:VTIMEZONE\r\nTZID:Custom/Fixed\r\nBEGIN:STANDARD\r\n"
                "DTSTART:19700101T000000\r\nTZOFFSETFROM:+0200\r\nTZOFFSETTO:+0200\r\n"
                "END:STANDARD\r\nEND:VTIMEZONE\r\n")
        days = expand(feed(event("UID:custom\nDTSTART;TZID=Custom/Fixed:20260928T090000"), extra=zone))
        self.assertEqual(days["2026-09-28"][0]["start"], "2026-09-28T03:00:00-04:00")

    def test_prototype_names_are_valid_uids(self):
        raw = feed(event("UID:constructor\nDTSTART:20260928T090000"))
        self.assertIn("2026-09-28", expand(raw))


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.messages = []
        self.worker = backend.CalendarWorker(Path(self.temp.name) / "cache.json", self.messages.append, ZONE)
        self.raw = feed(event("UID:shared\nDTSTART:20260928T090000\nSUMMARY:Original"))
        self.worker.configure(1, [CONFIG])

    def accept(self, raw=None):
        request, = self.worker.begin_refresh()
        self.worker.finish_fetch(request, raw or self.raw)

    def test_stale_response_cannot_replace_new_configuration(self):
        request, = self.worker.begin_refresh()
        self.worker.configure(2, [{**CONFIG, "url": "https://example.test/new.ics"}])
        self.worker.finish_fetch(request, self.raw)
        self.assertEqual(self.worker.raw_feeds, {})
        self.assertEqual(self.worker.parsed, {})
        self.assertFalse(self.worker.cache_path.exists())

    def test_invalid_download_retains_previous_cache_and_events(self):
        self.accept()
        self.accept("<html>Login</html>")
        self.assertEqual(self.worker.raw_feeds[CONFIG["url"]], self.raw)
        self.assertEqual(json.loads(self.worker.cache_path.read_text())["feeds"][CONFIG["url"]], self.raw)
        self.assertEqual(self.messages[-1]["state"], "refreshFailed")

    def test_sources_with_same_uid_remain_distinct(self):
        other = {**CONFIG, "url": "https://example.test/other.ics", "name": "Family"}
        self.worker.configure(2, [CONFIG, other])
        for request in self.worker.begin_refresh():
            self.worker.finish_fetch(request, self.raw)
        self.worker.publish_window("month", "2026-09-01", "2026-10-01")
        self.assertEqual({event["calendar"] for event in self.messages[-1]["days"]["2026-09-28"]}, {"Work", "Family"})

    def test_unchanged_feed_and_window_do_not_repeat_parsing_or_expansion(self):
        self.accept()
        with patch.object(backend, "parse_feed", side_effect=AssertionError("reparsed")):
            self.accept()
        self.worker.publish_window("month", "2026-09-01", "2026-10-01")
        with patch.object(backend, "expand_feed", side_effect=AssertionError("expanded again")):
            self.worker.publish_window("month", "2026-09-01", "2026-10-01")

    def test_old_cache_format_loads(self):
        self.worker.cache_path.write_text(json.dumps({"version": 1, "feeds": {CONFIG["url"]: self.raw}}))
        restored = backend.CalendarWorker(self.worker.cache_path, self.messages.append, ZONE)
        restored.configure(2, [CONFIG])
        restored.publish_window("month", "2026-09-01", "2026-10-01")
        self.assertEqual(len(self.messages[-1]["days"]["2026-09-28"]), 1)

    def test_config_filter_changes_apply_without_reparsing(self):
        self.accept(feed(event("UID:declined\nDTSTART:20260928T090000\nATTENDEE;PARTSTAT=DECLINED:mailto:me@example.test")))
        self.worker.publish_window("month", "2026-09-01", "2026-10-01")
        self.assertEqual(self.messages[-1]["days"], {})
        with patch.object(backend, "parse_feed", side_effect=AssertionError("reparsed")):
            self.worker.configure(2, [{**CONFIG, "excludeDeclined": False}])
        self.worker.publish_window("month", "2026-09-01", "2026-10-01")
        self.assertIn("2026-09-28", self.messages[-1]["days"])

    def test_repeated_refresh_is_coalesced(self):
        self.assertEqual(len(self.worker.begin_refresh()), 1)
        self.assertEqual(self.worker.begin_refresh(), [])

    def test_invalid_window_rejected(self):
        with self.assertRaises(backend.CalendarError):
            self.worker.publish_window("huge", "2020-01-01", "2030-01-01")

    def test_local_feed_remains_supported(self):
        path = Path(self.temp.name) / "local calendar.ics"
        path.write_text(self.raw)
        self.assertEqual(backend.download(path.as_uri()), self.raw)

    def test_repeated_dst_hour_is_sorted_by_instant(self):
        self.accept(feed(event("UID:first\nDTSTART:20261101T053000Z"), event("UID:second\nDTSTART:20261101T061500Z")))
        self.worker.publish_window("dst", "2026-11-01", "2026-11-02")
        self.assertEqual([e["start"] for e in self.messages[-1]["days"]["2026-11-01"]],
                         ["2026-11-01T01:30:00-04:00", "2026-11-01T01:15:00-05:00"])

    def test_cache_is_written_atomically_and_private(self):
        self.accept()
        self.assertEqual(self.worker.cache_path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(len(list(self.worker.cache_path.parent.iterdir())), 1)
