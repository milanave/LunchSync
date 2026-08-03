"""Minimal FastAPI mirror server for LunchSync transaction-mirror packets.

The iOS app POSTs a JSON snapshot of accounts and transactions to
POST /finance-kit-sync (see LMPlayground/Api/MirrorAPI.swift).
"""
import json
import logging
from pathlib import Path
from typing import Any

from fastapi import FastAPI
from pydantic import BaseModel

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("mirror-server")

PACKETS_FILE = Path(__file__).parent / "received_packets.jsonl"

app = FastAPI(title="LunchSync Mirror Server")


class MirrorAccount(BaseModel):
    id: str
    name: str
    institution: str
    balance: float
    currency: str


class MirrorTransaction(BaseModel):
    id: str
    account_id: str
    date: str
    amount: float
    currency: str
    payee: str
    status: str
    notes: str
    category: str
    metadata: Any = None


class MirrorPacket(BaseModel):
    schema_version: int
    accounts: list[MirrorAccount]
    transactions: list[MirrorTransaction]


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/finance-kit-sync")
def finance_kit_sync(packet: MirrorPacket) -> dict:
    logger.info(
        "Received packet (schema v%d): %d account(s), %d transaction(s)",
        packet.schema_version,
        len(packet.accounts),
        len(packet.transactions),
    )
    for txn in packet.transactions:
        logger.info("  %s %.2f %s (%s)", txn.payee, txn.amount, txn.currency.upper(), txn.status)

    with PACKETS_FILE.open("a") as f:
        f.write(json.dumps(packet.model_dump()) + "\n")

    return {
        "status": "ok",
        "accounts_received": len(packet.accounts),
        "transactions_received": len(packet.transactions),
    }
