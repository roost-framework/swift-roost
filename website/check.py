#!/usr/bin/env python3
"""Check the static site's local assets, fragments, and enhancement targets."""
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import re

ROOT = Path(__file__).resolve().parent


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.ids = []
        self.urls = []
        self.targets = []
        self.images = []
        self.feed(text)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if "id" in attrs:
            self.ids.append(attrs["id"])
        self.urls.extend(attrs[key] for key in ("href", "src") if key in attrs)
        self.targets.extend(attrs[key] for key in ("data-copy", "data-panel") if key in attrs)
        if tag == "img":
            self.images.append(attrs)


errors = []
for path in ROOT.glob("*.html"):
    page = Page(path.read_text())
    errors.extend(f"{path.name}: duplicate id {key}" for key, count in Counter(page.ids).items() if count > 1)
    errors.extend(f"{path.name}: missing target #{target}" for target in page.targets if target not in page.ids)
    for image in page.images:
        if "alt" not in image:
            errors.append(f"{path.name}: image without alt text: {image.get('src')}")
    for address in page.urls:
        url = urlsplit(address)
        if url.scheme or url.netloc:
            continue
        if url.path == "/swift-roost/":  # Project Pages root used by the 404 document.
            continue
        target = ROOT / (url.path or path.name)
        if url.path and not target.exists():
            errors.append(f"{path.name}: missing file {url.path}")
        if url.fragment and target.is_file() and target.suffix == ".html":
            if url.fragment not in Page(target.read_text()).ids:
                errors.append(f"{path.name}: missing fragment {address}")

for asset in re.findall(r"url\(['\"]?([^)'\"]+)", (ROOT / "style.css").read_text()):
    if not urlsplit(asset).scheme and not (ROOT / asset).is_file():
        errors.append(f"style.css: missing asset {asset}")

if errors:
    raise SystemExit("\n".join(errors))
print("Site check passed: local links, fragments, images, fonts, and enhancement targets.")
