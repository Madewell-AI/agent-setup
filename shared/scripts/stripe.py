#!/usr/bin/env python3
"""
Stripe API helper — invoicing, customers, subscriptions, and payment links.

No external dependencies — uses only Python stdlib (urllib, json, base64).

Usage:
  python3 ~/.agent/scripts/stripe.py customers [--email EMAIL] [--limit N]
  python3 ~/.agent/scripts/stripe.py customer <customer_id>
  python3 ~/.agent/scripts/stripe.py create-customer "Name" "email@example.com"
  python3 ~/.agent/scripts/stripe.py products [--limit N]
  python3 ~/.agent/scripts/stripe.py create-product "Product Name"
  python3 ~/.agent/scripts/stripe.py create-price <product_id> <amount_cents> [--currency usd] [--recurring monthly|yearly]
  python3 ~/.agent/scripts/stripe.py create-invoice <customer_id> [--description "desc"] [--due-days 30] [--auto-advance]
  python3 ~/.agent/scripts/stripe.py add-invoice-item <invoice_id> <amount_cents> "Description" [--price PRICE_ID]
  python3 ~/.agent/scripts/stripe.py finalize-invoice <invoice_id>
  python3 ~/.agent/scripts/stripe.py send-invoice <invoice_id>
  python3 ~/.agent/scripts/stripe.py void-invoice <invoice_id>
  python3 ~/.agent/scripts/stripe.py invoices [--customer CUSTOMER_ID] [--status draft|open|paid|void] [--limit N]
  python3 ~/.agent/scripts/stripe.py invoice <invoice_id>
  python3 ~/.agent/scripts/stripe.py create-subscription <customer_id> <price_id> [--anchor-day 1]
  python3 ~/.agent/scripts/stripe.py subscriptions [--customer CUSTOMER_ID] [--limit N]
  python3 ~/.agent/scripts/stripe.py cancel-subscription <subscription_id> [--at-period-end]
  python3 ~/.agent/scripts/stripe.py payment-link <price_id> [--quantity 1]

All Stripe operations should go through this script — never use raw curl.

Setup:
  Add STRIPE_RESTRICTED_KEY to ~/.agent/.env
  Use a restricted key with only the permissions you need (invoices, customers, etc.)
"""

import sys
import os
import json
import urllib.request
import urllib.error
import urllib.parse
from base64 import b64encode

ENV_FILE = os.path.expanduser("~/.agent/.env")
BASE_URL = "https://api.stripe.com/v1"


def load_api_key():
    try:
        with open(ENV_FILE) as f:
            for line in f:
                line = line.strip()
                if line.startswith("STRIPE_RESTRICTED_KEY="):
                    return line.split("=", 1)[1]
    except FileNotFoundError:
        pass
    print("ERROR: STRIPE_RESTRICTED_KEY not found in", ENV_FILE, file=sys.stderr)
    sys.exit(1)


def api_request(method, endpoint, params=None):
    key = load_api_key()
    url = f"{BASE_URL}/{endpoint}"

    if method == "GET" and params:
        url += "?" + urllib.parse.urlencode(params, doseq=True)
        data = None
    elif params:
        data = urllib.parse.urlencode(params, doseq=True).encode()
    else:
        data = None

    auth = b64encode(f"{key}:".encode()).decode()
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Basic {auth}",
    })

    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            err = json.loads(body)
            print(f"ERROR {e.code}: {err.get('error', {}).get('message', body)}", file=sys.stderr)
        except json.JSONDecodeError:
            print(f"ERROR {e.code}: {body}", file=sys.stderr)
        sys.exit(1)


def fmt_money(amount_cents, currency="usd"):
    if currency.lower() == "usd":
        return f"${amount_cents / 100:,.2f}"
    return f"{amount_cents / 100:,.2f} {currency.upper()}"


def cmd_customers(args):
    params = {"limit": "20"}
    i = 0
    while i < len(args):
        if args[i] == "--email":
            params["email"] = args[i + 1]; i += 2
        elif args[i] == "--limit":
            params["limit"] = args[i + 1]; i += 2
        else:
            i += 1
    result = api_request("GET", "customers", params)
    for c in result.get("data", []):
        print(f"  {c['id']}  {c.get('name', '(no name)'):<30}  {c.get('email', '(no email)')}")
    print(f"\n{len(result['data'])} customers shown (has_more: {result.get('has_more', False)})")


def cmd_customer(args):
    result = api_request("GET", f"customers/{args[0]}")
    print(json.dumps(result, indent=2))


def cmd_create_customer(args):
    result = api_request("POST", "customers", {"name": args[0], "email": args[1]})
    print(f"Created customer: {result['id']} — {result['name']} <{result['email']}>")


def cmd_products(args):
    params = {"limit": "20", "active": "true"}
    i = 0
    while i < len(args):
        if args[i] == "--limit":
            params["limit"] = args[i + 1]; i += 2
        else:
            i += 1
    result = api_request("GET", "products", params)
    for p in result.get("data", []):
        print(f"  {p['id']}  {p['name']}")
    print(f"\n{len(result['data'])} products shown")


def cmd_create_product(args):
    result = api_request("POST", "products", {"name": args[0]})
    print(f"Created product: {result['id']} — {result['name']}")


def cmd_create_price(args):
    product_id = args[0]
    amount = args[1]
    params = {"product": product_id, "unit_amount": amount, "currency": "usd"}
    i = 2
    while i < len(args):
        if args[i] == "--currency":
            params["currency"] = args[i + 1]; i += 2
        elif args[i] == "--recurring":
            params["recurring[interval]"] = args[i + 1]; i += 2
        else:
            i += 1
    result = api_request("POST", "prices", params)
    recurring = result.get("recurring")
    label = f" (recurring {recurring['interval']})" if recurring else " (one-time)"
    print(f"Created price: {result['id']} — {fmt_money(result['unit_amount'], result['currency'])}{label}")


def cmd_create_invoice(args):
    customer_id = args[0]
    params = {"customer": customer_id, "collection_method": "send_invoice", "days_until_due": "30"}
    i = 1
    while i < len(args):
        if args[i] == "--description":
            params["description"] = args[i + 1]; i += 2
        elif args[i] == "--due-days":
            params["days_until_due"] = args[i + 1]; i += 2
        elif args[i] == "--auto-advance":
            params["auto_advance"] = "true"; i += 1
        elif args[i] == "--auto-pay":
            params["collection_method"] = "charge_automatically"; i += 1
            params.pop("days_until_due", None)
        else:
            i += 1
    result = api_request("POST", "invoices", params)
    print(f"Created draft invoice: {result['id']} — status: {result['status']}")
    if result.get("hosted_invoice_url"):
        print(f"URL: {result['hosted_invoice_url']}")


def cmd_add_invoice_item(args):
    invoice_id = args[0]
    amount = args[1]
    description = args[2]
    params = {"invoice": invoice_id, "amount": amount, "currency": "usd", "description": description}
    i = 3
    while i < len(args):
        if args[i] == "--price":
            params.pop("amount", None)
            params.pop("currency", None)
            params["price"] = args[i + 1]; i += 2
        else:
            i += 1
    result = api_request("POST", "invoiceitems", params)
    print(f"Added line item: {result['id']} — {result.get('description', '')} {fmt_money(result['amount'])}")


def cmd_finalize_invoice(args):
    result = api_request("POST", f"invoices/{args[0]}/finalize")
    print(f"Finalized: {result['id']} — status: {result['status']}")
    if result.get("hosted_invoice_url"):
        print(f"Pay URL: {result['hosted_invoice_url']}")


def cmd_send_invoice(args):
    result = api_request("POST", f"invoices/{args[0]}/send")
    print(f"Sent: {result['id']} — status: {result['status']} — emailed to {result.get('customer_email', 'customer')}")


def cmd_void_invoice(args):
    result = api_request("POST", f"invoices/{args[0]}/void")
    print(f"Voided: {result['id']} — status: {result['status']}")


def cmd_invoices(args):
    params = {"limit": "20"}
    i = 0
    while i < len(args):
        if args[i] == "--customer":
            params["customer"] = args[i + 1]; i += 2
        elif args[i] == "--status":
            params["status"] = args[i + 1]; i += 2
        elif args[i] == "--limit":
            params["limit"] = args[i + 1]; i += 2
        else:
            i += 1
    result = api_request("GET", "invoices", params)
    for inv in result.get("data", []):
        total = fmt_money(inv.get("amount_due", 0))
        cname = inv.get("customer_name") or inv.get("customer_email") or inv.get("customer", "")
        print(f"  {inv['id']}  {inv['status']:<8}  {total:>12}  {cname}")
    print(f"\n{len(result['data'])} invoices shown (has_more: {result.get('has_more', False)})")


def cmd_invoice(args):
    inv = api_request("GET", f"invoices/{args[0]}")
    print(json.dumps(inv, indent=2))


def cmd_create_subscription(args):
    customer_id, price_id = args[0], args[1]
    params = {"customer": customer_id, "items[0][price]": price_id}
    i = 2
    while i < len(args):
        if args[i] == "--anchor-day":
            params["billing_cycle_anchor_config[day_of_month]"] = args[i + 1]; i += 2
        elif args[i] == "--cancel-after":
            import time
            periods = int(args[i + 1])
            interval = "month"
            i += 2
            for j in range(i, len(args)):
                if args[j] == "--interval-hint":
                    interval = args[j + 1]
                    break
            interval_seconds = {
                "day": 86400, "week": 604800, "month": 2592000, "year": 31536000
            }.get(interval, 2592000)
            cancel_ts = int(time.time()) + ((periods - 1) * interval_seconds) + 86400
            params["cancel_at"] = str(cancel_ts)
        else:
            i += 1
    result = api_request("POST", "subscriptions", params)
    cancel_info = ""
    if result.get("cancel_at"):
        from datetime import datetime
        cancel_date = datetime.fromtimestamp(result["cancel_at"]).strftime("%Y-%m-%d")
        cancel_info = f" — auto-cancels {cancel_date}"
    print(f"Created subscription: {result['id']} — status: {result['status']}{cancel_info}")


def cmd_subscriptions(args):
    params = {"limit": "20"}
    i = 0
    while i < len(args):
        if args[i] == "--customer":
            params["customer"] = args[i + 1]; i += 2
        elif args[i] == "--limit":
            params["limit"] = args[i + 1]; i += 2
        else:
            i += 1
    result = api_request("GET", "subscriptions", params)
    for s in result.get("data", []):
        print(f"  {s['id']}  {s['status']:<12}  customer: {s['customer']}")
    print(f"\n{len(result['data'])} subscriptions shown")


def cmd_cancel_subscription(args):
    sub_id = args[0]
    if "--at-period-end" in args:
        result = api_request("POST", f"subscriptions/{sub_id}", {"cancel_at_period_end": "true"})
        print(f"Subscription {result['id']} will cancel at period end")
    else:
        result = api_request("DELETE", f"subscriptions/{sub_id}")
        print(f"Canceled subscription: {result['id']} — status: {result['status']}")


def cmd_payment_link(args):
    price_id = args[0]
    params = {"line_items[0][price]": price_id, "line_items[0][quantity]": "1"}
    i = 1
    while i < len(args):
        if args[i] == "--quantity":
            params["line_items[0][quantity]"] = args[i + 1]; i += 2
        else:
            i += 1
    result = api_request("POST", "payment_links", params)
    print(f"Payment link: {result['url']}")


COMMANDS = {
    "customers": cmd_customers,
    "customer": cmd_customer,
    "create-customer": cmd_create_customer,
    "products": cmd_products,
    "create-product": cmd_create_product,
    "create-price": cmd_create_price,
    "create-invoice": cmd_create_invoice,
    "add-invoice-item": cmd_add_invoice_item,
    "finalize-invoice": cmd_finalize_invoice,
    "send-invoice": cmd_send_invoice,
    "void-invoice": cmd_void_invoice,
    "invoices": cmd_invoices,
    "invoice": cmd_invoice,
    "create-subscription": cmd_create_subscription,
    "subscriptions": cmd_subscriptions,
    "cancel-subscription": cmd_cancel_subscription,
    "payment-link": cmd_payment_link,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print("Usage: stripe.py <command> [args...]")
        print("Commands:", ", ".join(sorted(COMMANDS)))
        sys.exit(1)
    COMMANDS[sys.argv[1]](sys.argv[2:])
