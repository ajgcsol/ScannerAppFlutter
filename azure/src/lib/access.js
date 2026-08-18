"use strict";

const db = require("./cosmos");

// Admins see every group, can add members, and bypass the allowlist.
const admins = () =>
  (process.env.ADMIN_UPNS || "")
    .toLowerCase()
    .split(",")
    .map((u) => u.trim())
    .filter(Boolean);

const norm = (upn) => String(upn || "").toLowerCase().trim();

// The allowlist is consulted on every request, so it is cached briefly.
let cache = { at: 0, users: new Set(), groups: [] };
const TTL_MS = 60 * 1000;

async function load() {
  if (Date.now() - cache.at < TTL_MS) return cache;
  const [users, groups] = await Promise.all([
    db.listAll("authorized_users"),
    db.listAll("groups"),
  ]);
  cache = {
    at: Date.now(),
    users: new Set(users.map((u) => norm(u.id))),
    groups,
  };
  return cache;
}

function invalidate() {
  cache.at = 0;
}

const isAdmin = (upn) => admins().includes(norm(upn));

/**
 * A signed-in tenant user is authorized when they are an admin, on the
 * explicit allowlist, or a member of any group (joining a group via invite
 * IS the act of being authorized).
 *
 * Bootstrapping: while both the allowlist and groups are empty, every
 * tenant user passes — so enabling this can never lock everyone out.
 */
async function isAuthorized(upn) {
  const u = norm(upn);
  if (!u) return false;
  if (isAdmin(u)) return true;
  const { users, groups } = await load();
  if (users.size === 0 && groups.length === 0) return true; // bootstrap
  if (users.has(u)) return true;
  return groups.some((g) => (g.members || []).map(norm).includes(u));
}

async function groupsFor(upn) {
  const u = norm(upn);
  const { groups } = await load();
  if (isAdmin(u)) return groups;
  return groups.filter((g) => (g.members || []).map(norm).includes(u));
}

function newInviteCode() {
  // Short enough to share, long enough to be unguessable.
  return db.randomUUID().replace(/-/g, "").slice(0, 20);
}

module.exports = { isAuthorized, isAdmin, groupsFor, newInviteCode, invalidate, norm, load };
