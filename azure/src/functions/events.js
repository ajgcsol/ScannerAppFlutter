"use strict";

const { app } = require("@azure/functions");
const db = require("../lib/cosmos");
const { json, handler, readJson } = require("../lib/http");

const nowIso = () => new Date().toISOString();

// Dates are stored as ISO-8601 strings throughout. The Flutter client parses
// event date/createdAt/completedAt with a bare DateTime.parse on the
// createEvent and updateEvent responses, so these must be strings, not the
// {_seconds, _nanoseconds} maps Firestore used to emit.
const toIso = (value) => {
  if (!value) return null;
  if (typeof value === "number") return new Date(value).toISOString();
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
};

app.http("getEvents", {
  methods: ["GET", "OPTIONS"],
  authLevel: "anonymous",
  route: "getEvents",
  handler: handler({
    requireAuth: true,
    methods: "GET, POST, OPTIONS",
    fn: async () => json(200, await db.listAll("events")),
  }),
});

app.http("createEvent", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "createEvent",
  handler: handler({
    requireAuth: true,
    methods: "GET, POST, OPTIONS",
    allow: ["POST"],
    fn: async (request, context) => {
      const eventData = await readJson(request);

      if (!eventData.name || !eventData.eventNumber) {
        return json(400, { error: "Event name and eventNumber are required" });
      }

      const existing = await db.findOneBy(
        "events",
        "eventNumber",
        Number(eventData.eventNumber)
      );
      if (existing) {
        return json(409, {
          error: `Event number ${eventData.eventNumber} already exists`,
          conflictField: "eventNumber",
        });
      }

      const createdAt = nowIso();
      const eventDoc = {
        id: db.randomUUID(),
        eventNumber: Number(eventData.eventNumber),
        name: eventData.name,
        description: eventData.description || "",
        date: toIso(eventData.date) || createdAt,
        location: eventData.location || "",
        isActive: eventData.isActive !== undefined ? eventData.isActive : true,
        isCompleted: false,
        completedAt: null,
        createdAt,
        createdBy: eventData.createdBy || "mobile_app",
        customColumns: eventData.customColumns || [],
        staticValues: eventData.staticValues || {},
        exportFormat: eventData.exportFormat || "TEXT_DELIMITED",
        // Cross-Cultural Competency events: eventNumber doubles as the SIS
        // Professionalism Series id; cccEventId is the second SIS id.
        isCCC: eventData.isCCC === true,
        cccEventId: eventData.cccEventId ? Number(eventData.cccEventId) : null,
        // Which group owns this scan list; null = school-wide.
        groupId: eventData.groupId || null,
      };

      const created = await db.upsert("events", eventDoc);
      context.log(`Event created successfully with ID: ${created.id}`);

      return json(201, {
        success: true,
        event: created,
        message: "Event created successfully",
      });
    },
  }),
});

app.http("updateEvent", {
  methods: ["PUT", "OPTIONS"],
  authLevel: "anonymous",
  route: "updateEvent",
  handler: handler({
    requireAuth: true,
    methods: "PUT, OPTIONS",
    allow: ["PUT"],
    fn: async (request, context) => {
      const body = await readJson(request);
      const { id } = body;

      if (!id) return json(400, { error: "Event ID is required" }, "PUT, OPTIONS");

      const existing = await db.getById("events", id);
      if (!existing) {
        return json(404, { error: "Event not found" }, "PUT, OPTIONS");
      }

      // Only overwrite fields the caller actually sent, so a partial update
      // can't blank out the rest of the event.
      const changes = { updatedAt: nowIso() };
      for (const field of [
        "eventNumber",
        "name",
        "description",
        "location",
        "isActive",
        "isCompleted",
        "exportFormat",
        "isCCC",
        "cccEventId",
        "groupId",
      ]) {
        if (body[field] !== undefined) changes[field] = body[field];
      }
      if (body.eventNumber !== undefined) {
        changes.eventNumber = Number(body.eventNumber);
      }
      if (body.date !== undefined) changes.date = toIso(body.date);
      if (body.completedAt !== undefined) {
        changes.completedAt = body.completedAt ? toIso(body.completedAt) : null;
      }

      const updated = await db.upsert("events", { ...existing, ...changes });
      context.log(`Event ${id} updated successfully`);
      return json(200, updated, "PUT, OPTIONS");
    },
  }),
});

app.http("deleteEvent", {
  methods: ["DELETE", "OPTIONS"],
  authLevel: "anonymous",
  route: "deleteEvent",
  handler: handler({
    requireAuth: true,
    methods: "DELETE, OPTIONS",
    allow: ["DELETE"],
    fn: async (request, context) => {
      const { eventId } = await readJson(request);

      if (!eventId) {
        return json(400, { error: "eventId is required" }, "DELETE, OPTIONS");
      }

      const event = await db.getById("events", eventId);
      if (!event) {
        return json(404, { error: "Event not found" }, "DELETE, OPTIONS");
      }

      const eventName = event.name || "Unknown Event";

      // Tombstone the event first so mobile clients polling getDeletedEvents
      // learn about the deletion even if the cleanup below partly fails.
      await db.upsert("deleted_events", {
        id: eventId,
        originalEventId: eventId,
        eventName,
        eventNumber: event.eventNumber,
        deletedAt: nowIso(),
        deletedBy: "admin_portal",
        action: "delete_event",
      });

      const flatScans = await db.findBy("scans", "listId", eventId);
      const nestedScans = await db.findBy("lists", "eventId", eventId);

      await Promise.all([
        ...flatScans.map((s) => db.remove("scans", s.id, s.listId)),
        ...nestedScans.map((s) => db.remove("lists", s.id, s.eventId)),
      ]);

      await db.remove("events", eventId);

      context.log(
        `Successfully deleted event ${eventId} (${eventName}) and all associated data`
      );

      return json(
        200,
        {
          success: true,
          message: `Event "${eventName}" and all associated data deleted successfully`,
          eventId,
          eventName,
          deletedScansCount: flatScans.length + nestedScans.length,
        },
        "DELETE, OPTIONS"
      );
    },
  }),
});

app.http("getDeletedEvents", {
  methods: ["GET", "OPTIONS"],
  authLevel: "anonymous",
  route: "getDeletedEvents",
  handler: handler({
    requireAuth: true,
    methods: "GET, OPTIONS",
    fn: async (request, context) => {
      const cutoff = new Date(Date.now() - 30 * 86400 * 1000).toISOString();
      // ISO-8601 strings sort lexicographically in chronological order, so the
      // range filter and ordering work directly on the stored value.
      const deletedEvents = await db.queryAll(
        "deleted_events",
        "SELECT * FROM c WHERE c.deletedAt >= @cutoff ORDER BY c.deletedAt DESC",
        [{ name: "@cutoff", value: cutoff }]
      );
      context.log(
        `Found ${deletedEvents.length} deleted events from the last 30 days`
      );
      return json(200, deletedEvents, "GET, OPTIONS");
    },
  }),
});

app.http("deleteTestEvent", {
  methods: ["GET", "DELETE", "OPTIONS"],
  authLevel: "anonymous",
  route: "deleteTestEvent",
  handler: handler({
    requireAuth: true,
    methods: "GET, DELETE, OPTIONS",
    fn: async () => {
      await db.remove("events", "1756647674290");
      return json(
        200,
        { success: true, message: "Test event deleted" },
        "GET, DELETE, OPTIONS"
      );
    },
  }),
});
