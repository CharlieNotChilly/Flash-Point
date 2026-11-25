import http from "k6/http";
import { Counter, Trend } from "k6/metrics";

const smoke = __ENV.CI_SMOKE === "1";
const buyers = smoke ? 200 : 5000;

export const options = {
  scenarios: {
    buyers: { executor: "per-vu-iterations", vus: buyers, iterations: 1, maxDuration: "5m" },
  },
  summaryTrendStats: ["min", "max", "p(99)"],
  thresholds: {
    iterations: [`count==${buyers}`],
    created: [smoke ? "count==200" : "count==1000"],
    sold_out: [smoke ? "count==0" : "count==4000"],
    unexpected: ["count==0"],
  },
};

const design = __ENV.DESIGN || "locked";
if (!["locked", "flashpoint"].includes(design)) throw new Error("Unsupported checkout design");
const port = __ENV.BENCH_PORT || "3000";
if (!/^\d+$/.test(port)) throw new Error("BENCH_PORT must be a local port number");
const base = `http://127.0.0.1:${port}`;

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

function json(response) {
  try {
    return response.json();
  } catch (_) {
    return null;
  }
}

export default function () {
  const flashpoint = design === "flashpoint";
  const headers = { ...params.headers, "Idempotency-Key": `${__ENV.RUN_ID || "local"}-${__VU}` };
  const request = flashpoint ? { ...params, headers } : params;
  const path = flashpoint ? "/reserve" : "/locked/checkout";
  if (__ENV.CHAOS && __VU === 1) console.log("buyers-started");
  const start = Date.now();
  const first = http.post(base + path, payload, request);
  let end = Date.now();
  const body = json(first);
  const unavailable = first.status === 409 && body?.error === "SOLD_OUT";
  let purchased = first.status === 201 && Number.isInteger(body?.order_id) && !flashpoint;
  if (flashpoint && first.status === 201 && typeof body?.hold_id === "string") {
    const confirm = http.post(base + "/confirm", JSON.stringify({ hold_id: body.hold_id }), {
      ...request, responseCallback: http.expectedStatuses(202),
    });
    end = Date.now();
    purchased = confirm.status === 202 && json(confirm)?.status === "pending";
  }

  if (__ENV.CHAOS && purchased) console.log(headers["Idempotency-Key"]);
  starts.add(start);
  ends.add(end);
  duration.add(end - start);
  created.add(purchased ? 1 : 0);
  soldOut.add(unavailable ? 1 : 0);
  unexpected.add(purchased || unavailable ? 0 : 1);
}
