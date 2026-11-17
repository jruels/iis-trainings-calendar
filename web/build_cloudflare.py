"""Build the Cloudflare copy of the calendar page into ../cloudflare/public.

The page source (web/index.html) is written for claude.ai, which adds the
<html>/<head> skeleton at publish time. This wraps it in that skeleton plus
the bits iOS needs to run it full screen from the Home Screen.

Run after editing web/index.html: python3 web/build_cloudflare.py
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
body = (root / "web" / "index.html").read_text()

head = """<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="Trainings">
<meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#000000" media="(prefers-color-scheme: dark)">
<meta name="robots" content="noindex">
<link rel="manifest" href="manifest.webmanifest">
<link rel="apple-touch-icon" href="icon-180.png">
<link rel="icon" type="image/png" href="icon-512.png">
<style>:root{padding:env(safe-area-inset-top,0px) 0 env(safe-area-inset-bottom,0px)}body{margin:0}[hidden]{display:none!important}img{max-width:100%}</style>
</head><body>
"""
(root / "cloudflare" / "public" / "index.html").write_text(head + body + "\n</body></html>\n")
print("wrote cloudflare/public/index.html")
