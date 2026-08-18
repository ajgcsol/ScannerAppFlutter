"use strict";

const { app } = require("@azure/functions");
const db = require("../lib/cosmos");
const { json, handler, readJson } = require("../lib/http");
const { enqueueAttendanceEmail } = require("../lib/emailQueue");

// Callers pass either a numeric eventNumber or a real event id, and both the
// portal and the app rely on that leniency. Numeric values are resolved to the
// underlying event id; anything else is passed through untouched.
async function resolveEventId(value, context) {
  if (value === undefined || value === null || value === "") return null;
  if (Number.isNaN(Number(value))) return value;

  const event = await db.findOneBy("events", "eventNumber", Number(value));
  if (!event) {
    context.log(`No event found with eventNumber: ${value}`);
    return null;
  }
  context.log(`Resolved eventNumber ${value} to eventId: ${event.id}`);
  return event.id;
}

// Scan timestamps are stored as epoch milliseconds. Accept the legacy Firestore
// {seconds}/{_seconds} shapes and ISO strings on the way in.
function toMillis(timestamp) {
  if (timestamp === undefined || timestamp === null) return Date.now();
  if (typeof timestamp === "number") return timestamp;
  if (typeof timestamp === "object") {
    const seconds = timestamp.seconds ?? timestamp._seconds;
    if (seconds !== undefined) return seconds * 1000;
    return Date.now();
  }
  const parsed = new Date(timestamp);
  return Number.isNaN(parsed.getTime()) ? Date.now() : parsed.getTime();
}

const sortKey = (scan) => scan.timestamp?.seconds ?? scan.timestamp ?? 0;

app.http("getScanRecords", {
  methods: ["GET", "OPTIONS"],
  authLevel: "anonymous",
  route: "getScanRecords",
  handler: handler({
    requireAuth: true,
    methods: "GET, POST, OPTIONS",
    fn: async (request, context) => {
      const paramValue =
        request.query.get("eventNumber") || request.query.get("eventId");

      if (!paramValue) {
        return json(400, { error: "eventNumber or eventId is required" });
      }

      const isNumeric = !Number.isNaN(Number(paramValue));
      const queryValue = await resolveEventId(paramValue, context);

      if (!queryValue) {
        if (isNumeric) {
          return json(404, {
            error: `No event found with eventNumber: ${paramValue}`,
          });
        }
        return json(400, { error: "eventNumber or eventId is required" });
      }

      // Read both the flat and nested structures, exactly as before: the app
      // writes both, but older records may exist in only one of them.
      const [flat, nested] = await Promise.all([
        db.findBy("scans", "listId", queryValue).catch((e) => {
          context.log("Error querying flat structure:", e.message);
          return [];
        }),
        db.findBy("lists", "eventId", queryValue).catch((e) => {
          context.log("Error querying nested structure:", e.message);
          return [];
        }),
      ]);

      // De-duplicate by id, preferring the flat record when both exist.
      const unique = new Map();
      for (const scan of nested) unique.set(scan.id, scan);
      for (const scan of flat) unique.set(scan.id, scan);

      const scans = Array.from(unique.values()).sort(
        (a, b) => sortKey(b) - sortKey(a)
      );

      context.log(
        `Found ${scans.length} total scans for ${paramValue} (eventId: ${queryValue})`
      );
      return json(200, scans);
    },
  }),
});

app.http("addScanRecord", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "addScanRecord",
  handler: handler({
    requireAuth: true,
    methods: "GET, POST, OPTIONS",
    allow: ["POST"],
    fn: async (request, context) => {
      const scanRecord = await readJson(request);

      if (!scanRecord.id || !scanRecord.eventId) {
        return json(400, { error: "Scan record must have id and eventId" });
      }

      // Fall back to the value as supplied when it can't be resolved, matching
      // the original's behaviour of never dropping a scan on lookup failure.
      const actualEventId =
        (await resolveEventId(scanRecord.eventId, context)) || scanRecord.eventId;

      const studentId = scanRecord.studentId || scanRecord.code;
      let studentData = null;
      if (studentId) {
        studentData = await db.findOneBy("students", "studentId", studentId);
        if (studentData) {
          context.log(`Found student: ${studentData.firstName} ${studentData.lastName}`);
        } else {
          context.log(`No student found with studentId: ${studentId}`);
        }
      }

      // Attendance emails go out only on the student's FIRST scan for an
      // event, so this existence check must run before the upserts below.
      let isFirstScanForEvent = false;
      if (studentData && studentData.email) {
        const prior = await db.queryAll(
          "scans",
          "SELECT TOP 1 c.id FROM c WHERE c.listId = @event AND c.studentId = @student",
          [
            { name: "@event", value: actualEventId },
            { name: "@student", value: studentId },
          ]
        );
        isFirstScanForEvent = prior.length === 0;
      }

      const enrichment = {
        firstName: studentData?.firstName || "",
        lastName: studentData?.lastName || "",
        email: studentData?.email || "",
        fullName: studentData
          ? `${studentData.firstName} ${studentData.lastName}`
          : "",
      };
      const verified = studentData ? true : scanRecord.processed || false;

      // Nested structure (mobile app compatibility).
      const nestedScanData = {
        ...scanRecord,
        id: scanRecord.id,
        eventId: actualEventId,
        symbology: scanRecord.symbology || "QR_CODE",
        studentId,
        deviceId: scanRecord.deviceId || "",
        synced: scanRecord.synced || false,
        processed: verified,
        verified,
        ...enrichment,
        metadata: scanRecord.metadata || {},
      };

      // Flat structure (admin portal compatibility), with student enrichment.
      const flatScanData = {
        id: scanRecord.id,
        code: scanRecord.code,
        timestamp: toMillis(scanRecord.timestamp),
        listId: actualEventId,
        eventId: actualEventId,
        deviceId: scanRecord.deviceId || "",
        verified,
        processed: verified,
        symbology: scanRecord.symbology || "QR_CODE",
        studentId,
        synced: scanRecord.synced || false,
        ...enrichment,
        metadata: scanRecord.metadata || {},
      };

      await Promise.all([
        db.upsert("lists", nestedScanData),
        db.upsert("scans", flatScanData),
      ]);

      context.log(`Scan record stored with listId/eventId: ${actualEventId}`);

      // Queue the attendance confirmation. Strictly fire-and-forget: an email
      // problem must never fail or slow a scan.
      if (isFirstScanForEvent) {
        try {
          const event = await db.getById("events", actualEventId);
          // Group scan lists (e.g. Admissions prospect scanning) are not SONIS
          // attendance — never email anyone for them, even if a scanned code
          // happens to collide with a real student ID.
          if (event?.groupId) {
            context.log("Group scan list; skipping attendance email");
            throw { skip: true };
          }
          await enqueueAttendanceEmail({
            to: studentData.email,
            firstName: studentData.firstName,
            eventName: event?.name || "a Charleston School of Law event",
            eventDate: event?.date || null,
            scanId: scanRecord.id,
            eventId: actualEventId,
            studentId,
          });
          context.log(`Attendance email queued for ${studentId}`);
        } catch (emailError) {
          if (!emailError || emailError.skip !== true) {
            context.error(`Failed to queue attendance email:`, emailError);
          }
        }
      }
      return json(200, {
        success: true,
        id: scanRecord.id,
        listId: actualEventId,
        eventId: actualEventId,
      });
    },
  }),
});

app.http("addErrorRecord", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "addErrorRecord",
  handler: handler({
    requireAuth: true,
    methods: "GET, POST, OPTIONS",
    allow: ["POST"],
    fn: async (request) => {
      const errorRecord = await readJson(request);
      await db.add("errors", {
        ...errorRecord,
        timestamp: new Date().toISOString(),
      });
      return json(200, { success: true });
    },
  }),
});

app.http("deleteScanRecord", {
  methods: ["DELETE", "OPTIONS"],
  authLevel: "anonymous",
  route: "deleteScanRecord",
  handler: handler({
    requireAuth: true,
    methods: "DELETE, OPTIONS",
    allow: ["DELETE"],
    fn: async (request, context) => {
      const { scanId, eventId } = await readJson(request);

      if (!scanId) {
        return json(400, { error: "scanId is required" }, "DELETE, OPTIONS");
      }

      // The flat record is the source of truth for locating the event.
      const existing = eventId
        ? await db.getById("scans", scanId, eventId)
        : (await db.findBy("scans", "id", scanId))[0] || null;

      if (!existing) {
        return json(404, { error: "Scan record not found" }, "DELETE, OPTIONS");
      }

      const actualEventId = eventId || existing.listId || existing.eventId;

      await db.remove("scans", scanId, existing.listId ?? actualEventId);
      if (actualEventId) {
        await db.remove("lists", scanId, actualEventId).catch((e) => {
          context.log(`Could not delete from nested structure: ${e.message}`);
        });
      }

      context.log(`Successfully deleted scan record: ${scanId}`);
      return json(
        200,
        {
          success: true,
          message: "Scan record deleted successfully",
          scanId,
          eventId: actualEventId,
        },
        "DELETE, OPTIONS"
      );
    },
  }),
});

app.http("bulkDeleteScanRecords", {
  methods: ["DELETE", "OPTIONS"],
  authLevel: "anonymous",
  route: "bulkDeleteScanRecords",
  handler: handler({
    requireAuth: true,
    methods: "DELETE, OPTIONS",
    allow: ["DELETE"],
    fn: async (request, context) => {
      const { recordIds, eventId } = await readJson(request);

      if (!recordIds || !Array.isArray(recordIds) || recordIds.length === 0) {
        return json(400, { error: "recordIds array is required" }, "DELETE, OPTIONS");
      }
      if (!eventId) {
        return json(400, { error: "eventId is required" }, "DELETE, OPTIONS");
      }

      let deletedCount = 0;
      const errors = [];

      for (const recordId of recordIds) {
        try {
          await db.remove("scans", recordId, eventId);
          await db.remove("lists", recordId, eventId);
          deletedCount++;
        } catch (error) {
          context.error(`Failed to delete record ${recordId}:`, error);
          errors.push({ recordId, error: error.message });
        }
      }

      context.log(
        `Bulk delete completed: ${deletedCount}/${recordIds.length} records deleted`
      );
      return json(
        200,
        {
          success: true,
          message: `Successfully deleted ${deletedCount} of ${recordIds.length} records`,
          deletedCount,
          totalRequested: recordIds.length,
          errors: errors.length > 0 ? errors : undefined,
        },
        "DELETE, OPTIONS"
      );
    },
  }),
});

app.http("migrateScanRecords", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "migrateScanRecords",
  handler: handler({
    requireAuth: true,
    methods: "GET, POST, OPTIONS",
    allow: ["POST"],
    fn: async (request, context) => {
      const { eventNumber } = await readJson(request);
      if (!eventNumber) return json(400, { error: "eventNumber is required" });

      const event = await db.findOneBy("events", "eventNumber", Number(eventNumber));
      if (!event) {
        return json(404, { error: `No event found with eventNumber: ${eventNumber}` });
      }

      // Re-point scans that were filed under the bare event number.
      const stale = await db.findBy("scans", "listId", eventNumber.toString());
      let updateCount = 0;
      for (const scan of stale) {
        // listId is the partition key, so the record must be recreated rather
        // than updated in place.
        await db.remove("scans", scan.id, scan.listId);
        await db.upsert("scans", { ...scan, listId: event.id, eventId: event.id });
        updateCount++;
      }

      context.log(`Successfully migrated ${updateCount} scan records`);
      return json(200, {
        success: true,
        eventNumber,
        actualEventId: event.id,
        migratedCount: updateCount,
      });
    },
  }),
});

app.http("fixScanRecords", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "fixScanRecords",
  handler: handler({
    requireAuth: true,
    methods: "GET, POST, OPTIONS",
    allow: ["POST"],
    fn: async (request, context) => {
      const { eventNumber } = await readJson(request);
      if (!eventNumber) return json(400, { error: "eventNumber is required" });

      const event = await db.findOneBy("events", "eventNumber", Number(eventNumber));
      if (!event) {
        return json(404, { error: `No event found with eventNumber: ${eventNumber}` });
      }

      const students = await db.listAll("students");
      const studentLookup = new Map(students.map((s) => [s.studentId, s]));
      context.log(`Loaded ${studentLookup.size} students for lookup`);

      const scans = await db.findBy("scans", "listId", event.id);
      let enrichedCount = 0;

      for (const scan of scans) {
        const studentId = scan.studentId || scan.code;
        const student = studentId && studentLookup.get(studentId);
        if (!student) continue;

        await db.upsert("scans", {
          ...scan,
          verified: true,
          processed: true,
          firstName: student.firstName,
          lastName: student.lastName,
          email: student.email,
          fullName: `${student.firstName} ${student.lastName}`,
          studentId,
          listId: event.id,
          eventId: event.id,
        });
        enrichedCount++;
      }

      context.log(`Successfully enriched ${enrichedCount} scan records`);
      return json(200, {
        success: true,
        eventNumber,
        actualEventId: event.id,
        totalScans: scans.length,
        enrichedCount,
      });
    },
  }),
});
