"use strict";

const { app } = require("@azure/functions");
const db = require("../lib/cosmos");
const { json, handler, readJson } = require("../lib/http");
const { authenticate } = require("../lib/auth");
const access = require("../lib/access");

const M = "GET, POST, OPTIONS";

// Resolves the caller to a signed-in USER (not the app key): the access
// endpoints are about people, so the shared scanner key is not accepted here.
async function requireUser(request) {
  const auth = await authenticate(request, { skipAllowlist: true });
  if (!auth.ok || auth.principal.kind !== "user") {
    return { fail: json(401, { error: "Sign-in required" }, M) };
  }
  const upn = access.norm(auth.principal.name);
  return { upn, principal: auth.principal };
}

// GET /me — who am I, am I authorized, what groups do I have.
// Deliberately open to ANY signed-in tenant user: an unauthorized user needs
// to learn they're unauthorized (and be able to redeem an invite).
app.http("me", {
  methods: ["GET", "OPTIONS"],
  authLevel: "anonymous",
  route: "me",
  handler: handler({
    methods: M,
    fn: async (request) => {
      const who = await requireUser(request);
      if (who.fail) return who.fail;
      const [authorized, groups] = await Promise.all([
        access.isAuthorized(who.upn),
        access.groupsFor(who.upn),
      ]);
      return json(200, {
        upn: who.upn,
        isAdmin: access.isAdmin(who.upn),
        authorized,
        groups: groups.map((g) => ({
          id: g.id,
          name: g.name,
          memberCount: (g.members || []).length,
          // Invite codes only for admins and the group's owner.
          ...(access.isAdmin(who.upn) || access.norm(g.owner) === who.upn
            ? { inviteCode: g.inviteCode, members: g.members || [] }
            : {}),
        })),
      });
    },
  }),
});

// POST /groups {name} — create an invite-only group; creator becomes owner
// and member. Only authorized users can create groups.
app.http("createGroup", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "groups",
  handler: handler({
    methods: M,
    allow: ["POST"],
    fn: async (request) => {
      const who = await requireUser(request);
      if (who.fail) return who.fail;
      if (!(await access.isAuthorized(who.upn))) {
        return json(403, { error: "Not authorized. Ask an admin for an invite." }, M);
      }
      const { name } = await readJson(request);
      if (!name || !String(name).trim()) {
        return json(400, { error: "Group name is required" }, M);
      }
      const group = await db.upsert("groups", {
        id: db.randomUUID(),
        name: String(name).trim(),
        owner: who.upn,
        members: [who.upn],
        inviteCode: access.newInviteCode(),
        createdAt: new Date().toISOString(),
      });
      access.invalidate();
      return json(201, group, M);
    },
  }),
});

// POST /groups/join {inviteCode} — redeem an invite. Open to any signed-in
// tenant user: redeeming a valid invite IS how someone becomes authorized.
app.http("joinGroup", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "groups/join",
  handler: handler({
    methods: M,
    allow: ["POST"],
    fn: async (request, context) => {
      const who = await requireUser(request);
      if (who.fail) return who.fail;
      const { inviteCode } = await readJson(request);
      if (!inviteCode) return json(400, { error: "inviteCode is required" }, M);

      const matches = await db.queryAll(
        "groups",
        "SELECT * FROM c WHERE c.inviteCode = @code",
        [{ name: "@code", value: String(inviteCode).trim() }]
      );
      if (matches.length === 0) {
        return json(404, { error: "Invalid invite code" }, M);
      }
      const group = matches[0];
      const members = new Set((group.members || []).map(access.norm));
      members.add(who.upn);
      const updated = await db.upsert("groups", { ...group, members: [...members] });
      access.invalidate();
      context.log(`${who.upn} joined group "${group.name}" via invite`);
      return json(200, { id: updated.id, name: updated.name, joined: true }, M);
    },
  }),
});

// POST /groups/manage {groupId, action, upn?} — owner/admin operations:
//   addMember, removeMember, rotateInvite, deleteGroup
app.http("manageGroup", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "groups/manage",
  handler: handler({
    methods: M,
    allow: ["POST"],
    fn: async (request, context) => {
      const who = await requireUser(request);
      if (who.fail) return who.fail;
      const { groupId, action, upn } = await readJson(request);
      if (!groupId || !action) {
        return json(400, { error: "groupId and action are required" }, M);
      }
      const group = await db.getById("groups", groupId);
      if (!group) return json(404, { error: "Group not found" }, M);

      const mayManage = access.isAdmin(who.upn) || access.norm(group.owner) === who.upn;
      if (!mayManage) return json(403, { error: "Only the group owner or an admin can manage this group" }, M);

      if (action === "addMember" || action === "removeMember") {
        if (!upn) return json(400, { error: "upn is required" }, M);
        const members = new Set((group.members || []).map(access.norm));
        if (action === "addMember") members.add(access.norm(upn));
        else members.delete(access.norm(upn));
        await db.upsert("groups", { ...group, members: [...members] });
      } else if (action === "rotateInvite") {
        await db.upsert("groups", { ...group, inviteCode: access.newInviteCode() });
      } else if (action === "deleteGroup") {
        await db.remove("groups", groupId);
      } else {
        return json(400, { error: `Unknown action: ${action}` }, M);
      }
      access.invalidate();
      context.log(`group ${group.name}: ${action} by ${who.upn}`);
      const fresh = action === "deleteGroup" ? null : await db.getById("groups", groupId);
      return json(200, { success: true, group: fresh }, M);
    },
  }),
});
