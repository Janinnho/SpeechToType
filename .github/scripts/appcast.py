#!/usr/bin/env python3
"""Helpers for the Sparkle appcast (appcast.xml in the repo root).

  appcast.py next-build <appcast.xml>
      Prints max(sparkle:version) + 1 (the next CFBundleVersion / CURRENT_PROJECT_VERSION).

  appcast.py add-item <appcast.xml> --version 3.1 --build 19 --url URL \
      --length BYTES --signature SIG --notes-html notes.html [--min-os 26.2]
      Inserts a new <item> above the newest existing one. Existing items are not touched.
"""
import argparse
import re
import sys
from email.utils import format_datetime
from datetime import datetime, timezone
from xml.sax.saxutils import escape, quoteattr

VERSION_RE = re.compile(r"<sparkle:version>\s*([^<]+?)\s*</sparkle:version>")


def build_numbers(text):
    nums = []
    for raw in VERSION_RE.findall(text):
        try:
            nums.append(int(float(raw)))
        except ValueError:
            pass
    return nums


def cmd_next_build(args):
    with open(args.appcast, encoding="utf-8") as f:
        nums = build_numbers(f.read())
    print((max(nums) if nums else 0) + 1)


def cmd_add_item(args):
    with open(args.appcast, encoding="utf-8") as f:
        text = f.read()
    with open(args.notes_html, encoding="utf-8") as f:
        notes = f.read().strip().replace("]]>", "]]]]><![CDATA[>")

    if any(n >= int(args.build) for n in build_numbers(text)):
        sys.exit(f"error: build {args.build} is not greater than existing sparkle:version entries")
    if f"<sparkle:shortVersionString>{args.version}</sparkle:shortVersionString>" in text:
        sys.exit(f"error: version {args.version} is already in the appcast")

    pub_date = format_datetime(datetime.now(timezone.utc).astimezone())
    ind = "        "
    item = (
        f"{ind}<item>\n"
        f"{ind}    <title>Version {escape(args.version)}</title>\n"
        f"{ind}    <pubDate>{pub_date}</pubDate>\n"
        f"{ind}    <sparkle:version>{escape(str(args.build))}</sparkle:version>\n"
        f"{ind}    <sparkle:shortVersionString>{escape(args.version)}</sparkle:shortVersionString>\n"
        f"{ind}    <sparkle:minimumSystemVersion>{escape(args.min_os)}</sparkle:minimumSystemVersion>\n"
        f"{ind}    <description><![CDATA[\n{notes}\n{ind}    ]]></description>\n"
        f"{ind}    <enclosure\n"
        f"{ind}        url={quoteattr(args.url)}\n"
        f"{ind}        sparkle:edSignature={quoteattr(args.signature)}\n"
        f"{ind}        length={quoteattr(str(args.length))}\n"
        f"{ind}        type=\"application/octet-stream\" />\n"
        f"{ind}</item>\n\n"
    )

    m = re.search(r"^[ \t]*<item>", text, re.MULTILINE)
    if m:
        pos = m.start()
    else:
        pos = text.index("</channel>")
        item = item + ind[:4]
    text = text[:pos] + item + text[pos:]

    with open(args.appcast, "w", encoding="utf-8") as f:
        f.write(text)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    nb = sub.add_parser("next-build")
    nb.add_argument("appcast")
    nb.set_defaults(func=cmd_next_build)
    ai = sub.add_parser("add-item")
    ai.add_argument("appcast")
    ai.add_argument("--version", required=True)
    ai.add_argument("--build", required=True, type=int)
    ai.add_argument("--url", required=True)
    ai.add_argument("--length", required=True, type=int)
    ai.add_argument("--signature", required=True)
    ai.add_argument("--notes-html", required=True)
    ai.add_argument("--min-os", default="26.2")
    ai.set_defaults(func=cmd_add_item)
    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
