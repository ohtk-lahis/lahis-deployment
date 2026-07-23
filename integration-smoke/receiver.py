#!/usr/bin/env python3
"""Small signed-webhook receiver used only by the LAHIS integration smoke."""

import hashlib
import hmac
import json
import os
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


class ReceiptStore:
    def __init__(self):
        self._condition = threading.Condition()
        self._by_report_id = {}
        self._event_ids = set()

    def record(self, receipt):
        event_id = receipt["eventId"]
        report_id = receipt["reportId"]
        with self._condition:
            if event_id in self._event_ids:
                return False
            self._event_ids.add(event_id)
            self._by_report_id[report_id] = receipt
            self._condition.notify_all()
            return True

    def wait_for_report(self, report_id, timeout_seconds):
        with self._condition:
            if report_id not in self._by_report_id:
                self._condition.wait(timeout_seconds)
            return self._by_report_id.get(report_id)


def signature_for(*, secret, path, timestamp, body):
    signed = b"\n".join(
        [b"POST", path.encode("utf-8"), timestamp.encode("utf-8"), body]
    )
    return hmac.new(secret.encode("utf-8"), signed, hashlib.sha256).hexdigest()


class SmokeReceiver(BaseHTTPRequestHandler):
    store = ReceiptStore()
    signing_secret = ""

    def log_message(self, format, *args):  # pragma: no cover - keep smoke logs concise
        return

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            return self._json(HTTPStatus.OK, {"status": "ok"})
        if parsed.path != "/wait":
            return self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

        query = parse_qs(parsed.query)
        report_id = (query.get("reportId") or [""])[0]
        try:
            timeout = min(max(int((query.get("timeout") or ["30"])[0]), 1), 45)
        except ValueError:
            return self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid_timeout"})
        if not report_id:
            return self._json(HTTPStatus.BAD_REQUEST, {"error": "reportId_required"})

        receipt = self.store.wait_for_report(report_id, timeout)
        if receipt is None:
            return self._json(HTTPStatus.NOT_FOUND, {"error": "receipt_not_found"})
        return self._json(HTTPStatus.OK, receipt)

    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/webhooks/report-submitted":
            return self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid_content_length"})
        if content_length <= 0 or content_length > 64 * 1024:
            return self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid_body_size"})
        body = self.rfile.read(content_length)

        timestamp = self.headers.get("X-OHTK-Timestamp", "")
        received_signature = self.headers.get("X-OHTK-Signature", "")
        expected_signature = signature_for(
            secret=self.signing_secret,
            path=parsed.path,
            timestamp=timestamp,
            body=body,
        )
        if not timestamp or not hmac.compare_digest(received_signature, expected_signature):
            return self._json(HTTPStatus.UNAUTHORIZED, {"error": "invalid_signature"})

        try:
            payload = json.loads(body)
            report = payload["report"]
            event_id = payload["eventId"]
            report_id = report["id"]
        except (json.JSONDecodeError, KeyError, TypeError):
            return self._json(HTTPStatus.BAD_REQUEST, {"error": "invalid_payload"})
        if payload.get("eventType") != "report.submitted":
            return self._json(HTTPStatus.BAD_REQUEST, {"error": "unexpected_event_type"})

        receipt = {
            "eventId": event_id,
            "reportId": report_id,
            "eventType": payload["eventType"],
            "tenant": self.headers.get("X-OHTK-Tenant", ""),
            "integration": self.headers.get("X-OHTK-Integration", ""),
            "signatureValid": True,
        }
        created = self.store.record(receipt)
        return self._json(
            HTTPStatus.ACCEPTED if created else HTTPStatus.OK,
            {"status": "accepted" if created else "duplicate", **receipt},
        )

    def _json(self, status, payload):
        encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main():
    secret = os.environ.get("INTEGRATION_SMOKE_WEBHOOK_SECRET", "")
    if not secret:
        raise SystemExit("INTEGRATION_SMOKE_WEBHOOK_SECRET is required")
    port = int(os.environ.get("SMOKE_RECEIVER_PORT", "8080"))
    SmokeReceiver.signing_secret = secret
    server = ThreadingHTTPServer(("0.0.0.0", port), SmokeReceiver)
    server.serve_forever()


if __name__ == "__main__":
    main()
