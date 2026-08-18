"use strict";

const jwt = require("jsonwebtoken");
const { JwksClient } = require("jwks-rsa");

const TENANT_ID = process.env.ENTRA_TENANT_ID;
const CLIENT_ID = process.env.ENTRA_CLIENT_ID;

// The scanner app has no interactive sign-in, so it authenticates with a shared
// key instead of a user token.
const APP_API_KEY = process.env.APP_API_KEY;

let jwks;
function getJwks() {
  if (!jwks) {
    jwks = new JwksClient({
      jwksUri: `https://login.microsoftonline.com/${TENANT_ID}/discovery/v2.0/keys`,
      cache: true,
      cacheMaxAge: 12 * 60 * 60 * 1000,
      rateLimit: true,
      jwksRequestsPerMinute: 10,
    });
  }
  return jwks;
}

const getKey = (header, callback) => {
  getJwks()
    .getSigningKey(header.kid)
    .then((key) => callback(null, key.getPublicKey()))
    .catch(callback);
};

// Entra issues v1.0 and v2.0 tokens with different issuer strings; both are
// legitimate for this tenant.
const allowedIssuers = () => [
  `https://login.microsoftonline.com/${TENANT_ID}/v2.0`,
  `https://sts.windows.net/${TENANT_ID}/`,
];

// Accepts either an access token minted for this API's exposed scope, or the
// ID token the portal already receives. Both prove the caller signed in to this
// tenant through this app registration.
const allowedAudiences = () =>
  [CLIENT_ID, `api://${CLIENT_ID}`].filter(Boolean);

function verifyToken(token) {
  return new Promise((resolve, reject) => {
    jwt.verify(
      token,
      getKey,
      {
        audience: allowedAudiences(),
        issuer: allowedIssuers(),
        algorithms: ["RS256"],
      },
      (err, decoded) => (err ? reject(err) : resolve(decoded))
    );
  });
}

function bearer(request) {
  const header = request.headers.get("authorization") || "";
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match ? match[1] : null;
}

/**
 * Resolves the caller's identity, or returns a reason for rejection.
 * Fails closed: if no auth mechanism is configured, nothing is authorized.
 *
 * Signed-in users must additionally be on the allowlist (an admin, an
 * explicitly authorized user, or a member of any group) — being in the
 * tenant is not enough. opts.skipAllowlist exempts the two bootstrap
 * endpoints (/me and /groups/join) that unauthorized users legitimately
 * need to reach. Never applies to the scanner's shared-key path.
 */
async function authenticate(request, opts = {}) {
  if (APP_API_KEY) {
    const provided = request.headers.get("x-api-key");
    if (provided && provided === APP_API_KEY) {
      return { ok: true, principal: { kind: "app", name: "scanner-app" } };
    }
  }

  const token = bearer(request);
  if (token) {
    if (!TENANT_ID || !CLIENT_ID) {
      return { ok: false, reason: "Token auth not configured on the server" };
    }
    try {
      const claims = await verifyToken(token);
      const name = claims.preferred_username || claims.upn || claims.oid;
      if (!opts.skipAllowlist) {
        const { isAuthorized } = require("./access");
        if (!(await isAuthorized(name))) {
          return {
            ok: false,
            reason: "Signed in, but not authorized for this system. Ask an admin for a group invite.",
          };
        }
      }
      return {
        ok: true,
        principal: { kind: "user", name, oid: claims.oid, claims },
      };
    } catch (error) {
      return { ok: false, reason: `Invalid token: ${error.message}` };
    }
  }

  return { ok: false, reason: "Missing Authorization bearer token or x-api-key" };
}

module.exports = { authenticate, verifyToken, APP_API_KEY, TENANT_ID, CLIENT_ID };
