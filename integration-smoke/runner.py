#!/usr/bin/env python3
"""One-shot OAuth/API half of the LAHIS integration smoke."""

import json
import os
import sys
from datetime import date, timedelta
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def required(name):
    value = os.environ.get(name, "")
    if not value:
        raise SystemExit(f"{name} is required")
    return value


API_BASE_URL = required("SMOKE_API_BASE_URL").rstrip("/")
TENANT_HOST = required("SMOKE_TENANT_HOST")
RECEIVER_URL = required("SMOKE_RECEIVER_URL").rstrip("/")
CLIENT_ID = required("SMOKE_CLIENT_ID")
CLIENT_SECRET = required("SMOKE_CLIENT_SECRET")
REPORT_ID = required("SMOKE_REPORT_ID")
VILLAGE_ID = required("SMOKE_VILLAGE_ID")
RUN_ID = required("SMOKE_RUN_ID")


def request_json(path, *, method="GET", payload=None, token=None, headers=None, timeout=15):
    final_headers = {"Host": TENANT_HOST, "Accept": "application/json"}
    if token:
        final_headers["Authorization"] = f"Bearer {token}"
    if headers:
        final_headers.update(headers)
    data = None
    if payload is not None:
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        final_headers["Content-Type"] = "application/json"
    request = Request(
        f"{API_BASE_URL}{path}", data=data, headers=final_headers, method=method
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"raw": raw}
        return exc.code, payload
    except URLError as exc:
        raise RuntimeError(f"request to {path} failed: {exc.reason}") from exc


def expect(status, payload, expected, label):
    if status != expected:
        raise RuntimeError(f"{label}: expected HTTP {expected}, got {status}: {payload}")
    print(f"PASS {label}")


def get_token():
    encoded = urlencode(
        {
            "grant_type": "client_credentials",
            "client_id": CLIENT_ID,
            "client_secret": CLIENT_SECRET,
        }
    ).encode("utf-8")
    request = Request(
        f"{API_BASE_URL}/o/token/",
        data=encoded,
        headers={
            "Host": TENANT_HOST,
            "Accept": "application/json",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        method="POST",
    )
    with urlopen(request, timeout=15) as response:
        payload = json.loads(response.read().decode("utf-8"))
    token = payload.get("access_token")
    if not token:
        raise RuntimeError("token response did not contain access_token")
    print("PASS OAuth client-credentials token")
    return token


def receiver_request(path):
    request = Request(f"{RECEIVER_URL}{path}", headers={"Accept": "application/json"})
    with urlopen(request, timeout=40) as response:
        return response.status, json.loads(response.read().decode("utf-8"))


def main():
    # A single bounded wait avoids polling Celery/receiver state.
    status, receipt = receiver_request(
        f"/wait?{urlencode({'reportId': REPORT_ID, 'timeout': 35})}"
    )
    expect(status, receipt, 200, "signed report.submitted webhook")
    if (
        receipt.get("reportId") != REPORT_ID
        or receipt.get("eventType") != "report.submitted"
        or not receipt.get("signatureValid")
    ):
        raise RuntimeError(f"webhook receipt did not match smoke report: {receipt}")

    token = get_token()
    status, incident = request_json(
        f"/api/integrations/v1/incidents/{REPORT_ID}", token=token
    )
    expect(status, incident, 200, "incident read")

    status, _ = request_json(
        "/api/integrations/v1/census/snapshots?"
        + urlencode({"villageId": VILLAGE_ID, "kind": "ANIMAL", "limit": 1}),
        token=token,
    )
    expect(status, _, 200, "census read")

    headers = {"Idempotency-Key": f"{RUN_ID}:comment"}
    comment = {
        "externalActionId": f"{RUN_ID}:comment",
        "body": "Integration smoke: signed delivery and OAuth read/write verified.",
        "visibility": "staff",
        "metadata": {"smokeRunId": RUN_ID},
        "recommendation": {"type": "integration_smoke"},
    }
    status, _ = request_json(
        f"/api/integrations/v1/reports/{REPORT_ID}/comments",
        method="POST",
        payload=comment,
        token=token,
        headers=headers,
    )
    expect(status, _, 202, "AI comment write")
    status, replay = request_json(
        f"/api/integrations/v1/reports/{REPORT_ID}/comments",
        method="POST",
        payload=comment,
        token=token,
        headers=headers,
    )
    expect(status, replay, 202, "AI comment idempotency replay")

    risk = {
        "externalAssessmentId": f"{RUN_ID}:risk",
        "level": "LOW",
        "score": 0.01,
        "factors": [{"key": "smoke", "label": "Integration smoke", "weight": 1}],
        "evaluatorVersion": "integration-smoke-v1",
        "source": "external_risk_evaluator",
    }
    status, _ = request_json(
        f"/api/integrations/v1/reports/{REPORT_ID}/risk-assessments",
        method="POST",
        payload=risk,
        token=token,
        headers={"Idempotency-Key": f"{RUN_ID}:risk"},
    )
    expect(status, _, 202, "risk assessment write")

    today = date.today()
    cluster = {
        "externalClusterId": f"{RUN_ID}:cluster",
        "algorithmVersion": "integration-smoke-v1",
        "window": {
            "from": (today - timedelta(days=1)).isoformat(),
            "to": today.isoformat(),
        },
        "incidentIds": [REPORT_ID],
        "authorityIds": incident["incident"].get("relevantAuthorityIds", []),
        "villageIds": [int(VILLAGE_ID)],
        "score": 0.01,
        "riskLevel": "LOW",
        "explanation": "Synthetic integration smoke result.",
        "metadata": {"smokeRunId": RUN_ID},
    }
    status, cluster_response = request_json(
        "/api/integrations/v1/clusters",
        method="POST",
        payload=cluster,
        token=token,
        headers={"Idempotency-Key": f"{RUN_ID}:cluster"},
    )
    expect(status, cluster_response, 202, "cluster write")
    cluster_id = cluster_response["cluster"]["id"]
    status, _ = request_json(
        f"/api/integrations/v1/clusters/{cluster_id}", token=token
    )
    expect(status, _, 200, "cluster read")
    status, replay = request_json(
        "/api/integrations/v1/clusters",
        method="POST",
        payload=cluster,
        token=token,
        headers={"Idempotency-Key": f"{RUN_ID}:cluster"},
    )
    expect(status, replay, 202, "cluster idempotency replay")

    print(f"PASS integration smoke run {RUN_ID}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"FAIL integration smoke: {exc}", file=sys.stderr)
        raise SystemExit(1)
