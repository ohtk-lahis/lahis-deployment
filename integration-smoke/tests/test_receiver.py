import importlib.util
import json
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


RECEIVER_PATH = Path(__file__).parents[1] / "receiver.py"
SPEC = importlib.util.spec_from_file_location("integration_smoke_receiver", RECEIVER_PATH)
receiver = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(receiver)


class ReceiverTests(unittest.TestCase):
    def setUp(self):
        receiver.SmokeReceiver.store = receiver.ReceiptStore()
        receiver.SmokeReceiver.signing_secret = "test-secret"
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), receiver.SmokeReceiver)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def test_accepts_valid_signature_and_exposes_receipt(self):
        body = json.dumps(
            {
                "eventType": "report.submitted",
                "eventId": "event-1",
                "report": {"id": "report-1"},
            },
            separators=(",", ":"),
        ).encode("utf-8")
        timestamp = "2026-07-21T00:00:00+00:00"
        signature = receiver.signature_for(
            secret="test-secret",
            path="/webhooks/report-submitted",
            timestamp=timestamp,
            body=body,
        )
        request = Request(
            f"{self.base_url}/webhooks/report-submitted",
            data=body,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "X-OHTK-Timestamp": timestamp,
                "X-OHTK-Signature": signature,
                "X-OHTK-Tenant": "demo",
                "X-OHTK-Integration": "smoke",
            },
        )
        with urlopen(request, timeout=2) as response:
            self.assertEqual(202, response.status)

        with urlopen(f"{self.base_url}/wait?reportId=report-1&timeout=1", timeout=2) as response:
            receipt = json.loads(response.read())
        self.assertEqual("event-1", receipt["eventId"])
        self.assertTrue(receipt["signatureValid"])
        self.assertEqual("demo", receipt["tenant"])

    def test_rejects_invalid_signature(self):
        body = b'{"eventType":"report.submitted","eventId":"event-1","report":{"id":"report-1"}}'
        request = Request(
            f"{self.base_url}/webhooks/report-submitted",
            data=body,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "X-OHTK-Timestamp": "2026-07-21T00:00:00+00:00",
                "X-OHTK-Signature": "not-a-valid-signature",
            },
        )
        with self.assertRaises(HTTPError) as raised:
            urlopen(request, timeout=2)
        self.assertEqual(401, raised.exception.code)


if __name__ == "__main__":
    unittest.main()
