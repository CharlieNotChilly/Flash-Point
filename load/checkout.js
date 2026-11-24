import http from "k6/http";
import { Counter, Trend } from "k6/metrics";

export const options = {
  scenarios: {
    buyers: { executor: "per-vu-iterations", vus: 5000, iterations: 1, maxDuration: "5m" },
  },
  summaryTrendStats: ["min", "max", "p(99)"],
  thresholds: {
    iterations: ["count==5000"],
    created: ["count==1000"],
    sold_out: ["count==4000"],
    unexpected: ["count==0"],
  },
};

if (__ENV.DESIGN && __ENV.DESIGN !== "locked") {
  throw new Error("This benchmark supports DESIGN=locked");
}

const duration = new Trend("checkout_duration", true);
const starts = new Trend("checkout_start_epoch_ms");
const ends = new Trend("checkout_end_epoch_ms");
const created = new Counter("created");
const soldOut = new Counter("sold_out");
const unexpected = new Counter("unexpected");
const payload = JSON.stringify({ sku: "FLASH-1", qty: 1 });
const params = {
  headers: { "Content-Type": "application/json" },
  redirects: 0,
  timeout: "120s",
  responseCallback: http.expectedStatuses(201, 409),
};

export default function () {
  const start = Date.now();
  const response = http.post("http://127.0.0.1:3000/locked/checkout", payload, params);
  const end = Date.now();
  starts.add(start);
  ends.add(end);
  duration.add(end - start);

  let body;
  try {
    body = response.json();
  } catch (_) {
    // Transport failures and non-JSON replies count as unexpected.
  }
  const purchased = response.status === 201 && Number.isInteger(body?.order_id);
  const unavailable = response.status === 409 && body?.error === "SOLD_OUT";
  created.add(purchased ? 1 : 0);
  soldOut.add(unavailable ? 1 : 0);
  unexpected.add(purchased || unavailable ? 0 : 1);
}
