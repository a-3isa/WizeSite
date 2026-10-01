/** GET /internal/stats for the heartbeat (tasks.md T095): 5-minute window, loopback only. */
import assert from "node:assert/strict";
import { test } from "node:test";

import Fastify from "fastify";

import { RequestStats, registerStats } from "../../src/stats";

test("counts requests and 5xx answers inside the 5-minute window", () => {
  let now = 1_000_000;
  const stats = new RequestStats(() => now);
  stats.record(200);
  stats.record(503);
  now += 4 * 60 * 1000;
  stats.record(500);
  assert.deepEqual(stats.snapshot(), { windowSeconds: 300, requests: 3, errors5xx: 2, errorRate: 2 / 3 });
  now += 2 * 60 * 1000; // the first two are now older than 5 minutes
  assert.deepEqual(stats.snapshot(), { windowSeconds: 300, requests: 1, errors5xx: 1, errorRate: 1 });
});

test("serves loopback callers only and does not count itself or /healthz", async () => {
  const app = Fastify();
  const stats = new RequestStats();
  registerStats(app, stats);
  app.get("/healthz", async () => ({ status: "ok" }));
  app.get("/boom", async (_request, reply) => reply.status(500).send({}));
  await app.ready();

  await app.inject({ method: "GET", url: "/boom" });
  await app.inject({ method: "GET", url: "/healthz" });
  const local = await app.inject({ method: "GET", url: "/internal/stats", remoteAddress: "127.0.0.1" });
  assert.equal(local.statusCode, 200);
  assert.equal(local.json().requests, 1);
  assert.equal(local.json().errors5xx, 1);

  const remote = await app.inject({ method: "GET", url: "/internal/stats", remoteAddress: "172.18.0.5" });
  assert.equal(remote.statusCode, 404);
  await app.close();
});
