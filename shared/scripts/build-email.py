#!/usr/bin/env python3
"""
Build a base64url-encoded RFC 2822 email for Gmail API send.

ALWAYS use this script — never hand-construct email strings with echo/base64.
Python's email library handles RFC 2047 header encoding for non-ASCII chars
(em dashes, smart quotes, accents) so subjects don't turn into mojibake.

Usage:
    build-email.py --from FROM --to TO --subject SUBJ --body TEXT
    build-email.py --from FROM --to TO --subject SUBJ --html PATH_OR_DASH
    cat email.html | build-email.py --from F --to T --subject S --html -

Outputs: base64url-encoded raw message ready for Gmail API users.messages.send.

Example (with gws CLI):
    RAW=$(~/.agent/scripts/build-email.py \
      --from "Name <you@example.com>" \
      --to "client@example.com" \
      --subject "Quarterly update — March" \
      --body "Hi,\n\nUpdate body.\n\n— Name")
    gws gmail users messages send --params '{"userId":"me"}' --json "{\"raw\":\"$RAW\"}"
"""
import argparse
import base64
import sys
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--from", dest="from_", required=True)
    p.add_argument("--to", required=True, help="comma-separated")
    p.add_argument("--cc", default="", help="comma-separated")
    p.add_argument("--bcc", default="", help="comma-separated")
    p.add_argument("--subject", required=True)
    p.add_argument("--body", help="plain text body (use \\n for newlines)")
    p.add_argument("--html", help="HTML body: file path, or '-' to read stdin")
    p.add_argument("--in-reply-to", default="")
    p.add_argument("--references", default="")
    args = p.parse_args()

    if not args.body and not args.html:
        sys.exit("error: must provide --body or --html")

    html_content = None
    if args.html:
        if args.html == "-":
            html_content = sys.stdin.read()
        else:
            with open(args.html, "r", encoding="utf-8") as f:
                html_content = f.read()

    text_body = args.body.replace("\\n", "\n") if args.body else None

    if html_content and text_body:
        msg = MIMEMultipart("alternative")
        msg.attach(MIMEText(text_body, "plain", "utf-8"))
        msg.attach(MIMEText(html_content, "html", "utf-8"))
    elif html_content:
        msg = MIMEText(html_content, "html", "utf-8")
    else:
        msg = MIMEText(text_body, "plain", "utf-8")

    msg["From"] = args.from_
    msg["To"] = args.to
    if args.cc:
        msg["Cc"] = args.cc
    if args.bcc:
        msg["Bcc"] = args.bcc
    msg["Subject"] = args.subject
    if args.in_reply_to:
        msg["In-Reply-To"] = args.in_reply_to
    if args.references:
        msg["References"] = args.references

    raw = base64.urlsafe_b64encode(msg.as_bytes()).decode()
    print(raw)


if __name__ == "__main__":
    main()
