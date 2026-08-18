"use strict";

const { app } = require("@azure/functions");
const db = require("../lib/cosmos");
const { json, handler, readJson } = require("../lib/http");
const { authenticate } = require("../lib/auth");

const METHODS = "GET, POST, PUT, PATCH, DELETE, OPTIONS";

// The admin portal addresses data by Firestore-style collection paths. Only
// these paths are served, so an arbitrary path can't reach an unmapped
// container. `pk` is the field Cosmos partitions that container on.
const COLLECTIONS = {
  events: { container: "events", pk: "id" },
  students: { container: "students", pk: "studentId" },
  scans: { container: "scans", pk: "listId" },
  lists: { container: "lists", pk: "eventId" },
  errors: { container: "errors", pk: "id" },
  deleted_events: { container: "deleted_events", pk: "id" },
  archives: { container: "archives", pk: "id" },
  analytics: { container: "analytics", pk: "id" },
  // Firestore subcollection archives/{archiveId}/students.
  "archives/*/students": { container: "archive_students", pk: "archiveId", parent: "archiveId" },
  // Firestore subcollection lists/{eventId}/scans — the nested scan structure
  // the mobile app writes and the portal's scan views read.
  "lists/*/scans": { container: "lists", pk: "eventId", parent: "eventId" },
  // Ledger of SONIS attendance exports, one batch per export action; used to
  // compute "already exported" so delta exports can't double-post attendance.
  sonis_exports: { container: "sonis_exports", pk: "eventId" },
};

/**
 * Turns a path like ["archives","abc","students","xyz"] into a collection
 * descriptor plus the document id, or null when the path isn't served.
 */
function resolve(segments) {
  if (segments.length === 0) return null;

  const isDoc = segments.length % 2 === 0;
  const collectionSegments = isDoc ? segments.slice(0, -1) : segments;
  const id = isDoc ? segments[segments.length - 1] : null;

  // Replace intermediate document ids with * to match the pattern table.
  const pattern = collectionSegments
    .map((segment, i) => (i % 2 === 1 ? "*" : segment))
    .join("/");

  const spec = COLLECTIONS[pattern];
  if (!spec) return null;

  const parentId = collectionSegments.length > 1 ? collectionSegments[1] : null;
  return { spec, id, parentId, pattern };
}

const partitionValueFor = (spec, doc, parentId) =>
  spec.parent ? parentId : doc?.[spec.pk];

// Materialises the parent link so subcollection docs carry their partition key.
function withParent(spec, doc, parentId) {
  if (!spec.parent) return doc;
  return { ...doc, [spec.parent]: parentId };
}

function buildQuery(request, spec, parentId) {
  const clauses = [];
  const parameters = [];

  if (spec.parent) {
    clauses.push(`c.${spec.parent} = @parent`);
    parameters.push({ name: "@parent", value: parentId });
  }

  // where=field:op:value, repeatable. Only equality and simple comparisons are
  // needed by the portal.
  const OPS = { eq: "=", ne: "!=", gt: ">", gte: ">=", lt: "<", lte: "<=" };
  request.query.getAll("where").forEach((raw, i) => {
    const [field, op, ...rest] = raw.split(":");
    const value = rest.join(":");
    if (!field || !OPS[op] || !/^[A-Za-z0-9_]+$/.test(field)) return;
    const param = `@w${i}`;
    // Preserve numeric and boolean types through the query string.
    let typed = value;
    if (value === "true") typed = true;
    else if (value === "false") typed = false;
    else if (value !== "" && !Number.isNaN(Number(value))) typed = Number(value);
    clauses.push(`c.${field} ${OPS[op]} ${param}`);
    parameters.push({ name: param, value: typed });
  });

  let sql = "SELECT * FROM c";
  if (clauses.length) sql += ` WHERE ${clauses.join(" AND ")}`;

  const orderBy = request.query.get("orderBy");
  if (orderBy) {
    const fields = orderBy
      .split(",")
      .map((f) => f.trim())
      .filter((f) => /^[A-Za-z0-9_]+(\s+(asc|desc))?$/i.test(f));
    if (fields.length) {
      sql += ` ORDER BY ${fields.map((f) => {
        const [name, dir] = f.split(/\s+/);
        return `c.${name}${dir ? ` ${dir.toUpperCase()}` : ""}`;
      }).join(", ")}`;
    }
  }

  const limit = Number(request.query.get("limit"));
  if (limit > 0) sql = sql.replace("SELECT *", `SELECT TOP ${Math.floor(limit)} *`);

  return { sql, parameters };
}

app.http("data", {
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  authLevel: "anonymous",
  route: "data/{*path}",
  handler: handler({
    methods: METHODS,
    fn: async (request, context) => {
      // This endpoint exposes student records in bulk, so it always requires a
      // verified caller — unlike the legacy scanner endpoints.
      const auth = await authenticate(request);
      if (!auth.ok) {
        return json(401, { error: "Unauthorized", detail: auth.reason }, METHODS);
      }

      const raw = request.params.path || "";
      const segments = raw.split("/").filter(Boolean).map(decodeURIComponent);
      const target = resolve(segments);

      if (!target) {
        return json(404, { error: `Unsupported collection path: ${raw}` }, METHODS);
      }

      const { spec, id, parentId } = target;
      const name = spec.container;

      switch (request.method) {
        case "GET": {
          if (id) {
            const pkValue = spec.parent ? parentId : id;
            const doc = await db.getById(name, id, pkValue);
            if (!doc) return json(404, { error: "Not found", exists: false }, METHODS);
            return json(200, doc, METHODS);
          }
          const { sql, parameters } = buildQuery(request, spec, parentId);
          return json(200, await db.queryAll(name, sql, parameters), METHODS);
        }

        case "POST": {
          // Firestore .add() — server-assigned id.
          const body = await readJson(request);
          const doc = withParent(spec, { id: db.randomUUID(), ...body }, parentId);
          return json(201, await db.upsert(name, doc), METHODS);
        }

        case "PUT": {
          // Firestore .set() — full replace at a known id.
          if (!id) return json(400, { error: "Document id required for set" }, METHODS);
          const body = await readJson(request);

          // set(..., {merge: true}) keeps fields the caller didn't send.
          let base = {};
          if (request.query.get("merge") === "true") {
            base = (await db.getById(name, id, spec.parent ? parentId : id)) || {};
          }

          const doc = withParent(spec, { ...base, ...body, id }, parentId);
          if (partitionValueFor(spec, doc, parentId) === undefined) {
            return json(400, { error: `Field '${spec.pk}' is required` }, METHODS);
          }
          return json(200, await db.upsert(name, doc), METHODS);
        }

        case "PATCH": {
          // Firestore .update() — merge into an existing document.
          if (!id) return json(400, { error: "Document id required for update" }, METHODS);
          const body = await readJson(request);
          const pkValue = spec.parent ? parentId : id;
          const existing = await db.getById(name, id, pkValue);
          if (!existing) return json(404, { error: "Not found" }, METHODS);
          return json(200, await db.upsert(name, { ...existing, ...body, id }), METHODS);
        }

        case "DELETE": {
          if (!id) return json(400, { error: "Document id required for delete" }, METHODS);
          let pkValue = spec.parent ? parentId : id;
          if (!spec.parent && spec.pk !== "id") {
            // Partition key lives in a field, so the document must be read to
            // find it before it can be addressed for deletion.
            const found = (await db.findBy(name, "id", id))[0];
            if (!found) return json(404, { error: "Not found" }, METHODS);
            pkValue = found[spec.pk];
          }
          const removed = await db.remove(name, id, pkValue);
          if (!removed) return json(404, { error: "Not found" }, METHODS);
          return json(200, { success: true, id }, METHODS);
        }

        default:
          return json(405, { error: "Method not allowed" }, METHODS);
      }
    },
  }),
});

// Firestore batch writes, applied as a best-effort sequence. Cosmos has no
// cross-partition transaction, so partial failures are reported per operation
// rather than rolled back.
app.http("batch", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "batch",
  handler: handler({
    methods: "POST, OPTIONS",
    allow: ["POST"],
    fn: async (request, context) => {
      const auth = await authenticate(request);
      if (!auth.ok) {
        return json(401, { error: "Unauthorized", detail: auth.reason }, "POST, OPTIONS");
      }

      const { operations } = await readJson(request);
      if (!Array.isArray(operations) || operations.length === 0) {
        return json(400, { error: "operations array is required" }, "POST, OPTIONS");
      }

      const results = [];
      for (const [index, op] of operations.entries()) {
        try {
          const segments = String(op.path || "").split("/").filter(Boolean);
          const target = resolve(segments);
          if (!target || !target.id) {
            throw new Error(`Unsupported document path: ${op.path}`);
          }
          const { spec, id, parentId } = target;
          const nameC = spec.container;

          if (op.type === "delete") {
            let pkValue = spec.parent ? parentId : id;
            if (!spec.parent && spec.pk !== "id") {
              const found = (await db.findBy(nameC, "id", id))[0];
              pkValue = found ? found[spec.pk] : id;
            }
            await db.remove(nameC, id, pkValue);
          } else if (op.type === "update") {
            const pkValue = spec.parent ? parentId : id;
            const existing = await db.getById(nameC, id, pkValue);
            if (!existing) throw new Error("Not found");
            await db.upsert(nameC, { ...existing, ...op.data, id });
          } else if (op.type === "merge") {
            // set(..., {merge: true}): merge over an existing document, or
            // create it when absent.
            const pkValue = spec.parent ? parentId : id;
            const existing = await db.getById(nameC, id, pkValue);
            await db.upsert(
              nameC,
              withParent(spec, { ...(existing || {}), ...op.data, id }, parentId)
            );
          } else {
            await db.upsert(nameC, withParent(spec, { ...op.data, id }, parentId));
          }
          results.push({ index, path: op.path, success: true });
        } catch (error) {
          context.error(`Batch op ${index} failed:`, error);
          results.push({ index, path: op.path, success: false, error: error.message });
        }
      }

      const failed = results.filter((r) => !r.success);
      return json(
        failed.length ? 207 : 200,
        {
          success: failed.length === 0,
          applied: results.length - failed.length,
          total: results.length,
          results,
        },
        "POST, OPTIONS"
      );
    },
  }),
});
