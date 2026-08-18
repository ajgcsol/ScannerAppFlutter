"use strict";

const { app } = require("@azure/functions");
const db = require("../lib/cosmos");
const { json, handler } = require("../lib/http");
const { authenticate } = require("../lib/auth");

// Minimal RFC-4180 parser: handles quoted fields, escaped quotes ("") and
// embedded commas/newlines, which SIS exports routinely contain.
function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = "";
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const char = text[i];

    if (inQuotes) {
      if (char === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += char;
      }
      continue;
    }

    if (char === '"') {
      inQuotes = true;
    } else if (char === ",") {
      row.push(field);
      field = "";
    } else if (char === "\n" || char === "\r") {
      if (char === "\r" && text[i + 1] === "\n") i++;
      row.push(field);
      if (row.some((c) => c.trim() !== "")) rows.push(row);
      row = [];
      field = "";
    } else {
      field += char;
    }
  }

  row.push(field);
  if (row.some((c) => c.trim() !== "")) rows.push(row);
  return rows;
}

const normalize = (header) => header.toLowerCase().replace(/[^a-z0-9]/g, "");

// Accepts the many spellings a SIS export might use for each column.
function pick(record, ...aliases) {
  for (const alias of aliases) {
    const value = record[normalize(alias)];
    if (value !== undefined && value !== "") return value;
  }
  return undefined;
}

function toRecords(text) {
  const rows = parseCsv(text);
  if (rows.length < 2) return [];
  const headers = rows[0].map((h) => normalize(h.trim()));
  return rows.slice(1).map((row) => {
    const record = {};
    headers.forEach((header, i) => {
      record[header] = (row[i] ?? "").trim();
    });
    return record;
  });
}

// Body may be raw CSV or a JSON array of already-shaped objects.
async function readPayload(request) {
  const text = await request.text();
  if (!text) return { rows: [], raw: "" };

  const trimmed = text.trim();
  if (trimmed.startsWith("[") || trimmed.startsWith("{")) {
    const parsed = JSON.parse(trimmed);
    const array = Array.isArray(parsed) ? parsed : parsed.rows || parsed.students || parsed.events;
    if (Array.isArray(array)) {
      return {
        rows: array.map((item) => {
          const record = {};
          for (const [k, v] of Object.entries(item)) {
            record[normalize(k)] = typeof v === "string" ? v.trim() : v;
          }
          return record;
        }),
        raw: trimmed,
      };
    }
  }
  return { rows: toRecords(text), raw: text };
}

const truthy = (value, fallback = true) => {
  if (value === undefined || value === "") return fallback;
  return !["false", "0", "no", "n", "inactive"].includes(String(value).toLowerCase());
};

app.http("importStudents", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "importStudents",
  handler: handler({
    methods: "POST, OPTIONS",
    allow: ["POST"],
    fn: async (request, context) => {
      // Imports overwrite roster and event data, so a verified caller is
      // required just as it is for the /data endpoints.
      const auth = await authenticate(request);
      if (!auth.ok) {
        return json(401, { error: "Unauthorized", detail: auth.reason }, "POST, OPTIONS");
      }

      const { rows } = await readPayload(request);
      if (rows.length === 0) {
        return json(400, { error: "No rows found. Send CSV with a header row, or a JSON array." }, "POST, OPTIONS");
      }

      // Preserve existing records so a roster refresh doesn't wipe photo state.
      const existing = new Map(
        (await db.listAll("students")).map((s) => [s.studentId, s])
      );

      let imported = 0;
      let updated = 0;
      const errors = [];

      for (const [index, record] of rows.entries()) {
        const studentId = pick(record, "studentId", "student id", "id", "studentnumber", "sid");
        if (!studentId) {
          errors.push({ row: index + 2, error: "Missing studentId" });
          continue;
        }

        const prior = existing.get(studentId);
        const student = {
          ...(prior || {}),
          id: prior?.id || db.randomUUID(),
          studentId: String(studentId),
          firstName: pick(record, "firstName", "first name", "first", "givenname") || prior?.firstName || "",
          lastName: pick(record, "lastName", "last name", "last", "surname", "familyname") || prior?.lastName || "",
          email: pick(record, "email", "emailaddress", "e-mail") || prior?.email || "",
          program: pick(record, "program", "major", "degree") || prior?.program || "",
          year: pick(record, "year", "classyear", "cohort") || prior?.year || "",
          active: truthy(pick(record, "active", "status", "enrolled")),
          hasPhoto: prior?.hasPhoto ?? false,
          updatedAt: new Date().toISOString(),
        };

        try {
          await db.upsert("students", student);
          if (prior) updated++;
          else imported++;
        } catch (error) {
          errors.push({ row: index + 2, studentId, error: error.message });
        }
      }

      context.log(`Student import: ${imported} new, ${updated} updated, ${errors.length} errors`);
      return json(
        200,
        {
          success: true,
          imported,
          updated,
          totalRows: rows.length,
          errors: errors.length > 0 ? errors : undefined,
        },
        "POST, OPTIONS"
      );
    },
  }),
});

app.http("importEvents", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "importEvents",
  handler: handler({
    methods: "POST, OPTIONS",
    allow: ["POST"],
    fn: async (request, context) => {
      // Imports overwrite roster and event data, so a verified caller is
      // required just as it is for the /data endpoints.
      const auth = await authenticate(request);
      if (!auth.ok) {
        return json(401, { error: "Unauthorized", detail: auth.reason }, "POST, OPTIONS");
      }

      const { rows } = await readPayload(request);
      if (rows.length === 0) {
        return json(400, { error: "No rows found. Send CSV with a header row, or a JSON array." }, "POST, OPTIONS");
      }

      const existing = new Map(
        (await db.listAll("events")).map((e) => [Number(e.eventNumber), e])
      );

      let imported = 0;
      let updated = 0;
      const errors = [];

      for (const [index, record] of rows.entries()) {
        const eventNumber = Number(pick(record, "eventNumber", "event number", "number", "eventno"));
        const name = pick(record, "name", "event name", "title", "eventtitle");

        if (!eventNumber || Number.isNaN(eventNumber) || !name) {
          errors.push({ row: index + 2, error: "Missing eventNumber or name" });
          continue;
        }

        const prior = existing.get(eventNumber);
        const rawDate = pick(record, "date", "eventdate", "startdate");
        const parsedDate = rawDate ? new Date(rawDate) : null;

        const event = {
          ...(prior || {}),
          id: prior?.id || db.randomUUID(),
          eventNumber,
          name,
          description: pick(record, "description", "desc", "notes") || prior?.description || "",
          location: pick(record, "location", "room", "venue") || prior?.location || "",
          date:
            parsedDate && !Number.isNaN(parsedDate.getTime())
              ? parsedDate.toISOString()
              : prior?.date || new Date().toISOString(),
          isActive: truthy(pick(record, "isActive", "active", "status")),
          isCompleted: prior?.isCompleted ?? false,
          completedAt: prior?.completedAt ?? null,
          createdAt: prior?.createdAt || new Date().toISOString(),
          createdBy: prior?.createdBy || "csv_import",
          customColumns: prior?.customColumns || [],
          staticValues: prior?.staticValues || {},
          exportFormat: pick(record, "exportFormat") || prior?.exportFormat || "TEXT_DELIMITED",
          // Dual-purpose events carry a second SIS id for the CC file;
          // eventNumber doubles as the PS id.
          isCCC: truthy(pick(record, "isCCC", "ccc"), prior?.isCCC ?? false),
          cccEventId: (() => {
            const v = Number(pick(record, "cccEventId", "ccc event id", "cccid"));
            return Number.isFinite(v) && v > 0 ? v : prior?.cccEventId ?? null;
          })(),
        };

        try {
          await db.upsert("events", event);
          if (prior) updated++;
          else imported++;
        } catch (error) {
          errors.push({ row: index + 2, eventNumber, error: error.message });
        }
      }

      context.log(`Event import: ${imported} new, ${updated} updated, ${errors.length} errors`);
      return json(
        200,
        {
          success: true,
          imported,
          updated,
          totalRows: rows.length,
          errors: errors.length > 0 ? errors : undefined,
        },
        "POST, OPTIONS"
      );
    },
  }),
});
