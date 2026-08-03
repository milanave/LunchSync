# LunchSync Mirror Server

Reference FastAPI server for the iOS app's "Mirror Server" feature
(see [PR #7](https://github.com/milanave/LunchSync/pull/7)). The app POSTs
JSON snapshots of FinanceKit accounts and transactions to this server, which
logs each packet and appends it to `received_packets.jsonl`.

## Endpoints

### `POST /finance-kit-sync`

Request body (`schema_version` is currently `1`):

    {
      "schema_version": 1,
      "accounts": [
        {"id": "acct-1", "name": "Checking", "institution": "Bank", "balance": 100.0, "currency": "USD"}
      ],
      "transactions": [
        {"id": "txn-1", "account_id": "acct-1", "date": "2026-08-01T12:00:00Z",
         "amount": -4.5, "currency": "USD", "payee": "Coffee", "status": "pending",
         "notes": "", "category": "Food", "metadata": {}}
      ]
    }

`status` is `"pending"` or `"posted"`; `metadata` is arbitrary nested JSON.
Responds `200` with `{"status": "ok", "accounts_received": N, "transactions_received": N}`.

### `GET /health`

Returns `{"status": "ok"}`.

## Sync semantics

A real implementation must honor the app's delivery model:

- The app sends the full FinanceKit history in batches of up to 500
  transactions, oldest first.
- Delivery is at-least-once: batches that never got a 2xx are retried on later
  syncs, and transactions whose content changed are re-sent. Treat transaction
  `id` as the upsert key — insert or replace, never blindly append.
- Every packet includes all accounts. When there are no new transactions the
  app still sends an accounts-only packet with an empty `transactions` array.

## Run

    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    uvicorn main:app --host 0.0.0.0 --port 8000

## Production notes

This is a reference implementation only: it just logs packets and appends them
to `received_packets.jsonl`, with no auth and no real persistence. The iOS app
requires an https base URL, so for real use put the server behind TLS (a
reverse proxy such as Caddy or nginx, or a tunnel like ngrok or Tailscale) and
add authentication. Plain http is fine for testing locally with curl.
