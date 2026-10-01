/**
 * Request outcome counts over a sliding window, for the host heartbeat (tasks.md T095).
 * `GET /internal/stats` answers only loopback callers: the heartbeat runs it inside the API
 * container (`docker compose exec api ...`), while public traffic arrives from cloudflared or a
 * reverse proxy on another address and gets a 404.
 */
import type { FastifyInstance } from "fastify";

const WINDOW_MS = 5 * 60 * 1000;
const LOOPBACK = new Set(["127.0.0.1", "::1", "::ffff:127.0.0.1"]);

export class RequestStats {
  /** One entry per finished request: [epoch ms, is 5xx]. Pruned on every read and write. */
  private readonly entries: Array<[number, boolean]> = [];

  constructor(private readonly now: () => number = Date.now) {}

  record(statusCode: number): void {
    this.entries.push([this.now(), statusCode >= 500]);
    this.prune();
  }

  snapshot(): { windowSeconds: number; requests: number; errors5xx: number; errorRate: number } {
    this.prune();
    const requests = this.entries.length;
    const errors5xx = this.entries.filter(([, failed]) => failed).length;
    return {
      windowSeconds: WINDOW_MS / 1000,
      requests,
      errors5xx,
      errorRate: requests === 0 ? 0 : errors5xx / requests,
    };
  }

  private prune(): void {
    const cutoff = this.now() - WINDOW_MS;
    let drop = 0;
    while (drop < this.entries.length && this.entries[drop][0] < cutoff) drop++;
    if (drop > 0) this.entries.splice(0, drop);
  }
}

export function registerStats(app: FastifyInstance, stats: RequestStats): void {
  app.addHook("onResponse", async (request, reply) => {
    if (request.url.startsWith("/internal/") || request.url === "/healthz") return;
    stats.record(reply.statusCode);
  });
  app.get("/internal/stats", async (request, reply) => {
    if (!LOOPBACK.has(request.ip)) {
      return reply.status(404).send({ error: { code: "not-found", message: "Not found" } });
    }
    return reply.send(stats.snapshot());
  });
}
