"use strict";

// The Firebase originals set permissive CORS on every endpoint and answered
// preflight with 204. The admin portal and the Flutter app both rely on that,
// so the behaviour is preserved exactly.
const baseHeaders = (methods) => ({
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": methods,
  // The portal sends Authorization; the scanner sends x-api-key; photo uploads
  // send x-photo-path. All three must be allowed or the browser blocks them.
  "Access-Control-Allow-Headers": "Content-Type, Authorization, x-api-key, x-photo-path",
  "Content-Type": "application/json",
});

function json(status, body, methods = "GET, POST, OPTIONS") {
  return { status, headers: baseHeaders(methods), jsonBody: body };
}

// A 204 must carry neither a body nor Content-Type, so the CORS headers are
// emitted on their own. Sending an empty body here makes the host return 500.
function preflight(methods) {
  return {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": methods,
      "Access-Control-Allow-Headers": "Content-Type, Authorization, x-api-key, x-photo-path",
      "Access-Control-Max-Age": "3600",
    },
  };
}

// Wraps a handler with the CORS + OPTIONS + method-guard preamble that every
// original function repeated inline. `requireAuth` additionally demands a
// verified caller — used by every endpoint that reads or writes student data.
function handler({ methods, allow, fn, requireAuth = false }) {
  return async (request, context) => {
    if (request.method === "OPTIONS") return preflight(methods);

    if (allow && !allow.includes(request.method)) {
      return json(405, { error: "Method not allowed" }, methods);
    }

    if (requireAuth) {
      // Required lazily so modules without auth needs don't pull in the JWKS
      // client, and so tests can stub it.
      const { authenticate } = require("./auth");
      const auth = await authenticate(request);
      if (!auth.ok) {
        return json(401, { error: "Unauthorized", detail: auth.reason }, methods);
      }
      context.principal = auth.principal;
    }

    try {
      return await fn(request, context);
    } catch (error) {
      context.error(`Unhandled error in ${context.functionName}:`, error);
      return json(500, { error: error.message || "Internal error" }, methods);
    }
  };
}

// req.body was already parsed by Firebase; Azure hands us a stream.
async function readJson(request) {
  const text = await request.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
}

module.exports = { json, preflight, handler, readJson };
