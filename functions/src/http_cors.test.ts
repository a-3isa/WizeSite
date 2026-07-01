import assert from "node:assert/strict";
import test from "node:test";
import {
  applyCorsHeaders,
  defaultCorsAllowedOrigins,
  isAllowedCorsOrigin,
} from "./http_cors";

class FakeResponse {
  readonly headers = new Map<string, string>();
  statusCode = 0;
  body = "";

  set(name: string, value: string): void {
    this.headers.set(name, value);
  }

  status(code: number): this {
    this.statusCode = code;
    return this;
  }

  send(body: string): void {
    this.body = body;
  }
}

test("CORS allows Firebase Hosting origins by default", () => {
  assert.deepEqual(defaultCorsAllowedOrigins(), [
    "https://wize-site.web.app",
    "https://wize-site.firebaseapp.com",
  ]);
  assert.equal(isAllowedCorsOrigin("https://wize-site.web.app"), true);
  assert.equal(isAllowedCorsOrigin("https://wize-site.firebaseapp.com"), true);
});

test("CORS does not reflect arbitrary origins", () => {
  assert.equal(isAllowedCorsOrigin("https://evil.example"), false);

  const response = new FakeResponse();
  const handled = applyCorsHeaders(
    {
      method: "POST",
      header: (name: string) =>
        name.toLowerCase() === "origin" ? "https://evil.example" : undefined,
    },
    response,
  );

  assert.equal(handled, false);
  assert.equal(response.headers.has("Access-Control-Allow-Origin"), false);
});

test("CORS rejects disallowed preflight requests", () => {
  const response = new FakeResponse();
  const handled = applyCorsHeaders(
    {
      method: "OPTIONS",
      header: (name: string) =>
        name.toLowerCase() === "origin" ? "https://evil.example" : undefined,
    },
    response,
  );

  assert.equal(handled, true);
  assert.equal(response.statusCode, 403);
  assert.equal(response.body, "");
  assert.equal(response.headers.has("Access-Control-Allow-Origin"), false);
});

test("CORS reflects configured custom origins", () => {
  const response = new FakeResponse();
  const handled = applyCorsHeaders(
    {
      method: "OPTIONS",
      header: (name: string) =>
        name.toLowerCase() === "origin" ? "https://app.example" : undefined,
    },
    response,
    {allowedOrigins: ["https://app.example"]},
  );

  assert.equal(handled, true);
  assert.equal(response.statusCode, 204);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "https://app.example");
});
