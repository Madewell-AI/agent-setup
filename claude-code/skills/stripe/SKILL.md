---
name: stripe
description: Stripe API for invoicing, customers, subscriptions, and payment links. Use when asked to create invoices, manage billing, or set up recurring payments.
---

# Stripe Skill

Manage invoicing, customers, subscriptions, and payment links via the Stripe API.

## Setup

Add to `~/.agent/.env`:
```
STRIPE_RESTRICTED_KEY=rk_live_...
```

Use a restricted key with only the permissions you need (invoices, customers, products, prices, subscriptions, payment links).

## Script

All operations go through the CLI wrapper:
```bash
python3 ~/.agent/scripts/stripe.py <command> [args...]
```

## Common Workflows

### Send a one-time invoice
```bash
# 1. Create or find the customer
python3 ~/.agent/scripts/stripe.py create-customer "Client Name" "client@example.com"

# 2. Create a draft invoice
python3 ~/.agent/scripts/stripe.py create-invoice <customer_id> --description "Project work" --due-days 14

# 3. Add line items
python3 ~/.agent/scripts/stripe.py add-invoice-item <invoice_id> 500000 "Website development"

# 4. Finalize and send
python3 ~/.agent/scripts/stripe.py finalize-invoice <invoice_id>
python3 ~/.agent/scripts/stripe.py send-invoice <invoice_id>
```

### Set up recurring billing
```bash
# 1. Create a product and recurring price
python3 ~/.agent/scripts/stripe.py create-product "Monthly Retainer"
python3 ~/.agent/scripts/stripe.py create-price <product_id> 250000 --recurring monthly

# 2. Create a subscription
python3 ~/.agent/scripts/stripe.py create-subscription <customer_id> <price_id>
```

### Generate a payment link
```bash
python3 ~/.agent/scripts/stripe.py payment-link <price_id> --quantity 1
```

### Cancel after N billing cycles
```bash
python3 ~/.agent/scripts/stripe.py create-subscription <customer_id> <price_id> \
  --cancel-after 6 --interval-hint weekly
```

## Available Commands

`customers`, `customer`, `create-customer`, `products`, `create-product`, `create-price`, `create-invoice`, `add-invoice-item`, `finalize-invoice`, `send-invoice`, `void-invoice`, `invoices`, `invoice`, `create-subscription`, `subscriptions`, `cancel-subscription`, `payment-link`

## Safety Rules

- Always confirm before sending invoices or creating charges
- Never expose the API key in responses or logs
- Use restricted keys, never the full secret key
- Double-check amounts before finalizing (amounts are in cents)
