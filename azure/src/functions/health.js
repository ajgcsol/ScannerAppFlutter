"use strict";

const { app } = require("@azure/functions");

// Anonymous liveness probe: no auth, no data — exists so the keep-warm timer
// (and any monitor) can touch the app cheaply.
app.http("healthz", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "healthz",
  handler: async () => ({ status: 200, jsonBody: { ok: true } }),
});

// Pings the app's own public endpoint every 4 minutes so the platform keeps
// an instance warm. Without this, the first request after idle pays a ~5s
// cold start — which staff feel as a slow sign-in or slow first scan.
app.timer("keepWarm", {
  schedule: "0 */4 * * * *",
  handler: async (timer, context) => {
    try {
      const res = await fetch(
        "https://insession-api-fc.azurewebsites.net/healthz",
        { signal: AbortSignal.timeout(20000) }
      );
      context.log(`keepWarm: ${res.status}`);
    } catch (e) {
      context.log(`keepWarm failed: ${e.message}`);
    }
  },
});
