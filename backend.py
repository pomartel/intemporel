# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "icalendar>=6.3,<7",
#   "recurring-ical-events>=3.8,<4",
# ]
# ///
"""Intemporel's shared JSON-lines calendar worker (never runs on the UI thread)."""

from __future__ import annotations

from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import sys
import tempfile
import threading
from urllib.parse import urlsplit, unquote
from zoneinfo import ZoneInfo

import icalendar
import recurring_ical_events

MAX_FEED_BYTES = 16 * 1024 * 1024
MAX_OCCURRENCES = 10000
PROCESSING_SECONDS = 5


class CalendarError(ValueError):
    """A safe error message, without feed URLs or calendar content."""


@contextmanager
def processing_budget():
    """A pathological recurrence must not hang the worker indefinitely."""
    def expired(*_):
        raise CalendarError("Calendar processing took too long")

    previous = signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, PROCESSING_SECONDS)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)


def local_timezone():
    name = os.environ.get("TZ", "").removeprefix(":")
    if name:
        try:
            return ZoneInfo(name)
        except (ValueError, KeyError):
            pass
    with open("/etc/localtime", "rb") as handle:
        return ZoneInfo.from_file(handle)


def parse_feed(raw: str):
    if len(raw.encode("utf-8")) > MAX_FEED_BYTES:
        raise CalendarError("Calendar feed is too large")
    text = raw.lstrip("\ufeff").strip()
    if not text.startswith("BEGIN:VCALENDAR") or not text.endswith("END:VCALENDAR"):
        raise CalendarError("Response is not an iCalendar document")
    try:
        calendar = icalendar.Calendar.from_ical(text)
        if calendar.name != "VCALENDAR" or str(calendar.get("VERSION", "")) != "2.0":
            raise CalendarError("Unsupported calendar format")
        for component in calendar.walk():
            if component.errors:
                raise CalendarError("Calendar contains invalid properties")
            if component.name != "VEVENT":
                continue
            if not component.get("UID"):
                raise CalendarError("Calendar event has no UID")
            # Cancellation exceptions may omit DTSTART; their RECURRENCE-ID
            # supplies the original start needed by the recurrence library.
            if "DTSTART" not in component and "RECURRENCE-ID" in component and str(component.get("STATUS", "")).upper() == "CANCELLED":
                component.add("DTSTART", component["RECURRENCE-ID"].dt)
            if "DTSTART" not in component:
                raise CalendarError("Calendar event has no start date")
            for name in ("DTSTART", "DTEND", "RECURRENCE-ID"):
                value = component.get(name)
                if value is None:
                    continue
                if not isinstance(value.dt, (date, datetime)):
                    raise CalendarError("Invalid event date")
                if value.params.get("TZID") and isinstance(value.dt, datetime) and value.dt.tzinfo is None:
                    raise CalendarError("Unknown calendar timezone")
        # A query preserves VTIMEZONE, recurrence exceptions, RDATE and EXDATE.
        return recurring_ical_events.of(calendar)
    except CalendarError:
        raise
    except Exception as error:
        raise CalendarError("Could not parse calendar feed") from error


def address(value):
    return str(value).strip().casefold().removeprefix("mailto:")


def declined_by_viewer(event, config):
    if not config.get("excludeDeclined", True):
        return False
    identities = {address(value) for value in config.get("emails", [])}
    if not identities:
        return False  # A public feed does not identify the current viewer.
    attendees = event.get("ATTENDEE", [])
    if not isinstance(attendees, list):
        attendees = [attendees]
    return any(address(attendee) in identities and str(attendee.params.get("PARTSTAT", "")).upper() == "DECLINED" for attendee in attendees)


def as_local(value, zone):
    if not isinstance(value, datetime):
        return datetime.combine(value, time(), zone)
    return value.replace(tzinfo=zone) if value.tzinfo is None else value.astimezone(zone)


def expand_feed(query, config, start: date, stop: date, zone):
    """Return only the requested days, with ISO timestamps for Qt to format."""
    lower = datetime.combine(start, time(), zone)
    upper = datetime.combine(stop, time(), zone)
    result = {}
    occurrences = query.between(lower, upper)
    if len(occurrences) > MAX_OCCURRENCES:
        raise CalendarError("Too many calendar occurrences")
    rows = 0
    for event in occurrences:
        if str(event.get("STATUS", "")).upper() == "CANCELLED" or declined_by_viewer(event, config):
            continue
        original_start = event["DTSTART"].dt
        all_day = not isinstance(original_start, datetime)
        begins = as_local(original_start, zone)
        end_property = event.get("DTEND")
        ends = as_local(end_property.dt, zone) if end_property else begins + (timedelta(days=1) if all_day else timedelta())
        if begins >= upper or (ends <= lower if ends > begins else begins < lower):
            continue
        if ends < begins:
            raise CalendarError("Event ends before it starts")
        entry = {
            "calendar": config["name"], "color": config.get("color", ""),
            "summary": str(event.get("SUMMARY", "(untitled)"))[:1000],
            "location": str(event.get("LOCATION", ""))[:2000], "allDay": all_day,
            "start": begins.isoformat(), "end": ends.isoformat(),
        }
        last = (ends - timedelta(microseconds=1)).date() if ends > begins else begins.date()
        day = max(begins.date(), start)
        while day <= min(last, stop - timedelta(days=1)):
            rows += 1
            if rows > MAX_OCCURRENCES:
                raise CalendarError("Too many displayed calendar entries")
            result.setdefault(day.isoformat(), []).append(entry)
            day += timedelta(days=1)
    return result


def download(url):
    parsed = urlsplit(url)
    if parsed.scheme == "file":
        if parsed.netloc not in {"", "localhost"}:
            raise CalendarError("Local calendar URL must refer to this computer")
        try:
            with Path(unquote(parsed.path)).open("rb") as stream:
                raw = stream.read(MAX_FEED_BYTES + 1)
            if len(raw) > MAX_FEED_BYTES:
                raise CalendarError("Calendar feed is too large")
            return raw.decode("utf-8-sig")
        except (OSError, UnicodeError) as error:
            raise CalendarError("Could not read local calendar") from error
    if parsed.scheme not in {"http", "https"}:
        raise CalendarError("Calendar URL must use HTTP, HTTPS or file")
    try:
        response = subprocess.run(
            ["curl", "-fsSL", "--proto", "=http,https", "--proto-redir", "=http,https",
             "--max-time", "15", "--max-filesize", str(MAX_FEED_BYTES), "--", url],
            capture_output=True, timeout=20, check=True,
        )
        return response.stdout.decode("utf-8-sig")
    except (subprocess.SubprocessError, UnicodeError, OSError) as error:
        raise CalendarError("Could not download calendar feed") from error


@dataclass(frozen=True)
class FetchRequest:
    generation: int
    url: str


class CalendarWorker:
    def __init__(self, cache_path, emit, zone=None):
        self.cache_path = Path(cache_path)
        self.emit = emit
        self.zone = zone or local_timezone()
        self.generation = 0
        self.configs = []
        self.raw_feeds = self.read_cache()
        self.parsed = {}
        self.windows = OrderedDict()
        self.views = {}
        self.pending = set()
        self.failures = set()

    def read_cache(self):
        try:
            if self.cache_path.stat().st_size > 64 * 1024 * 1024:
                return {}
            feeds = json.loads(self.cache_path.read_text()).get("feeds", {})
            return {url: raw for url, raw in feeds.items() if isinstance(raw, str) and len(raw.encode()) <= MAX_FEED_BYTES}
        except (OSError, ValueError, AttributeError):
            return {}

    def save_cache(self):
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        handle, name = tempfile.mkstemp(prefix=".intemporel-", dir=self.cache_path.parent)
        try:
            with os.fdopen(handle, "w") as stream:
                json.dump({"version": 1, "feeds": self.raw_feeds}, stream)
            os.replace(name, self.cache_path)
        finally:
            if os.path.exists(name):
                os.unlink(name)

    def status(self, state):
        self.emit({"type": "status", "generation": self.generation, "state": state})

    def configure(self, generation, configs):
        self.generation = generation
        self.configs = configs
        self.pending.clear()
        self.failures.clear()
        self.windows.clear()
        self.views.clear()
        urls = {config["url"] for config in configs}
        self.raw_feeds = {url: raw for url, raw in self.raw_feeds.items() if url in urls}
        self.parsed = {url: parsed for url, parsed in self.parsed.items() if url in urls}
        for url in urls:
            raw = self.raw_feeds.get(url)
            if raw and url not in self.parsed:
                try:
                    with processing_budget():
                        self.parsed[url] = parse_feed(raw)
                except CalendarError:
                    self.failures.add(url)
        self.status("noCalendarsConfigured" if not configs else "cachedData")

    def begin_refresh(self):
        if self.pending or not self.configs:
            return []
        self.failures.clear()
        requests = [FetchRequest(self.generation, url) for url in dict.fromkeys(c["url"] for c in self.configs)]
        self.pending = set(requests)
        self.status("updating")
        return requests

    def finish_fetch(self, request, raw=None, error=False):
        if request.generation != self.generation or request not in self.pending:
            return  # The config changed; never associate a response with a new index.
        self.pending.remove(request)
        try:
            if error or raw is None:
                raise CalendarError("Download failed")
            if raw != self.raw_feeds.get(request.url) or request.url not in self.parsed:
                with processing_budget():
                    parsed = parse_feed(raw)
                # Only replace the last good response after successful validation.
                self.parsed[request.url] = parsed
                self.raw_feeds[request.url] = raw
                self.windows.clear()
                try:
                    self.save_cache()
                except OSError:
                    self.failures.add(request.url)
        except CalendarError:
            self.failures.add(request.url)
        if not self.pending:
            for key, (start, stop) in list(self.views.items()):
                self.publish_window(key, start, stop)
            self.status("refreshFailed" if self.failures else "updated")

    def publish_window(self, key, start, stop):
        start, stop = date.fromisoformat(start), date.fromisoformat(stop)
        if not 0 < (stop - start).days <= 62:
            raise CalendarError("Calendar window must be at most 62 days")
        self.views[key] = (start.isoformat(), stop.isoformat())
        while len(self.views) > 6:
            del self.views[next(iter(self.views))]
        cache_key = (start, stop)
        if cache_key not in self.windows:
            combined = {}
            row_count = 0
            for config in self.configs:
                query = self.parsed.get(config["url"])
                if query is None:
                    continue
                try:
                    with processing_budget():
                        days = expand_feed(query, config, start, stop, self.zone)
                    new_rows = sum(len(events) for events in days.values())
                    if row_count + new_rows > MAX_OCCURRENCES:
                        raise CalendarError("Too many displayed calendar entries")
                    row_count += new_rows
                    for day, events in days.items():
                        combined.setdefault(day, []).extend(events)
                except (CalendarError, ValueError, TypeError, KeyError):
                    self.failures.add(config["url"])
            for events in combined.values():
                events.sort(key=lambda event: (datetime.fromisoformat(event["start"]).timestamp(), event["summary"], event["calendar"]))
            self.windows[cache_key] = combined
            while len(self.windows) > 6:
                self.windows.popitem(last=False)
        self.emit({"type": "window", "generation": self.generation, "key": key, "days": self.windows[cache_key]})
        if self.failures and not self.pending:
            self.status("refreshFailed")


def serve():
    messages = queue.Queue()
    pool = ThreadPoolExecutor(max_workers=3)

    def emit(value):
        print(json.dumps(value, separators=(",", ":")), flush=True)

    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "intemporel-calendar-cache.json"
    worker = CalendarWorker(cache, emit)

    def read_input():
        for line in sys.stdin:
            try:
                messages.put(json.loads(line))
            except ValueError:
                pass
        messages.put(None)

    def fetch(request):
        if request.generation != worker.generation:
            return
        try:
            messages.put({"type": "fetched", "request": request, "raw": download(request.url)})
        except CalendarError:
            messages.put({"type": "fetched", "request": request, "error": True})

    threading.Thread(target=read_input, daemon=True).start()
    emit({"type": "ready"})
    try:
        while True:
            message = messages.get()
            if message is None:
                break
            try:
                kind = message["type"]
                if kind == "configure":
                    worker.configure(message["generation"], message["calendars"])
                elif kind == "fetched":
                    worker.finish_fetch(message["request"], message.get("raw"), message.get("error", False))
                elif message.get("generation") == worker.generation:
                    if kind == "refresh":
                        for request in worker.begin_refresh():
                            pool.submit(fetch, request)
                    elif kind == "window":
                        worker.publish_window(message["key"], message["start"], message["stop"])
            except Exception:
                # Keep IPC alive, and do not leak feed URLs/content into shell logs.
                worker.status("refreshFailed")
    finally:
        pool.shutdown(wait=False, cancel_futures=True)


if __name__ == "__main__":
    if "--test" in sys.argv:
        import unittest
        suite = unittest.defaultTestLoader.discover(str(Path(__file__).parent / "tests"), pattern="test_*.py")
        sys.exit(not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful())
    serve()
