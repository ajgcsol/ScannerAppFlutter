"use strict";

const { app } = require("@azure/functions");
const db = require("../lib/cosmos");
const { json, handler, readJson } = require("../lib/http");
const { authenticate } = require("../lib/auth");
const { sendEventReport } = require("../lib/email");
const access = require("../lib/access");

// POST /emailEventReport { eventId, groupId? }
// Emails the event's full scan list as a CSV attachment — to the group's
// members when groupId is given (Admissions mailing the day's prospect list
// to the team), otherwise to the requesting user.
app.http("emailEventReport", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "emailEventReport",
  handler: handler({
    methods: "POST, OPTIONS",
    allow: ["POST"],
    fn: async (request, context) => {
      const auth = await authenticate(request);
      if (!auth.ok) {
        return json(401, { error: "Unauthorized", detail: auth.reason }, "POST, OPTIONS");
      }

      const { eventId, groupId } = await readJson(request);
      if (!eventId) return json(400, { error: "eventId is required" }, "POST, OPTIONS");

      const event = await db.getById("events", eventId);
      if (!event) return json(404, { error: "Event not found" }, "POST, OPTIONS");

      // Recipients: the group's members, or the requesting user.
      let to = [];
      if (groupId) {
        const group = await db.getById("groups", groupId);
        if (!group) return json(404, { error: "Group not found" }, "POST, OPTIONS");
        to = (group.members || []).map(access.norm);
      } else if (auth.principal.kind === "user") {
        to = [access.norm(auth.principal.name)];
      }
      if (to.length === 0) {
        return json(400, { error: "No recipients: pass groupId or call as a signed-in user" }, "POST, OPTIONS");
      }

      // Same dual-structure gather + dedup as getScanRecords.
      const [flat, nested] = await Promise.all([
        db.findBy("scans", "listId", eventId).catch(() => []),
        db.findBy("lists", "eventId", eventId).catch(() => []),
      ]);
      const unique = new Map();
      for (const scan of nested) unique.set(scan.id, scan);
      for (const scan of flat) unique.set(scan.id, scan);
      const scans = [...unique.values()].sort(
        (a, b) => (a.timestamp || 0) - (b.timestamp || 0)
      );

      const esc = (v) => {
        const s = String(v ?? "");
        return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
      };
      const csv = [
        "code,studentId,firstName,lastName,email,verified,scannedAt",
        ...scans.map((s) =>
          [
            s.code, s.studentId, s.firstName, s.lastName, s.email,
            s.verified === true ? "yes" : "no",
            s.timestamp ? new Date(s.timestamp).toISOString() : "",
          ].map(esc).join(",")
        ),
      ].join("\r\n") + "\r\n";

      const requestedBy =
        auth.principal.kind === "user" ? access.norm(auth.principal.name) : "scanner app";

      await sendEventReport({
        to,
        eventName: event.name,
        eventDate: event.date,
        csv,
        count: scans.length,
        requestedBy,
      });

      context.log(`Event report for "${event.name}" (${scans.length} scans) sent to ${to.join(", ")}`);
      return json(200, { success: true, recipients: to, scanCount: scans.length }, "POST, OPTIONS");
    },
  }),
});
