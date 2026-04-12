---
name: cloudflare
description: Cloudflare API access for DNS record management. Use when asked to add, update, delete, or list DNS records on a managed domain.
---

# Cloudflare DNS Skill

API access for managing DNS records via the Cloudflare API.

## Credentials

Loaded from `~/.agent/.env`:
- `CLOUDFLARE_API_TOKEN` — API token with DNS edit permissions
- `CLOUDFLARE_ACCOUNT_ID` — Your account ID

Always source the env before running commands:
```bash
source ~/.agent/.env
```

## Known Zones

| Domain | Zone ID |
|---|---|
| {{YOUR_DOMAIN}} | {{YOUR_ZONE_ID}} |

To list all zones:
```bash
curl -s "https://api.cloudflare.com/client/v4/zones?per_page=50" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  | jq -r '.result[] | "\(.name)\t\(.id)"'
```

## DNS Records — Common Operations

All DNS endpoints are scoped to a zone:
`https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records`

### List records

```bash
curl -s "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=100" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  | jq -r '.result[] | "\(.type)\t\(.name)\t\(.content)\t\(.id)"'
```

### Create a record

```bash
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "CNAME",
    "name": "app.example.com",
    "content": "cname.vercel-dns.com",
    "ttl": 1,
    "proxied": false
  }'
```

`ttl: 1` = automatic. `proxied: true` enables Cloudflare's CDN/WAF (only for HTTP/HTTPS).

### Update a record

```bash
curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"content": "new-value.example.com"}'
```

### Delete a record

```bash
curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN"
```

## Record Type Cheatsheet

- **A** — IPv4. Can be proxied.
- **AAAA** — IPv6. Can be proxied.
- **CNAME** — Alias. Don't proxy for Vercel/Netlify/external hosts.
- **TXT** — Verification, SPF, DKIM, DMARC.
- **MX** — Mail. Requires `priority` field.

## Proxied vs DNS-only

- **DNS-only (`proxied: false`)**: mail records, Vercel/Netlify, non-HTTP services
- **Proxied (`proxied: true`)**: HTTP/HTTPS origins where you want CDN/WAF

Default to `proxied: false` unless explicitly requested.

## Safety Rules

- Confirm before deleting any record — deletion can break production
- Confirm before modifying MX, NS, or apex records
- Never expose the API token in responses or logs
- Adding new CNAME/TXT records is safe to do directly when requested
