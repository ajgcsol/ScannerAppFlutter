"use strict";

const { CosmosClient } = require("@azure/cosmos");
const { DefaultAzureCredential } = require("@azure/identity");
const { randomUUID } = require("crypto");

const DATABASE = process.env.COSMOS_DATABASE || "insession";

// Container layout mirrors the old Firestore collections one-for-one.
// `scans` is the flat structure the admin portal reads; `lists` is the nested
// per-event structure the mobile app writes. Both are kept, and both are still
// written on every scan, exactly as the Firebase version did.
// Every container the data API can address must appear here, or container()
// throws when resolving the name.
const CONTAINERS = {
  events: { id: "events", partitionKey: "/id" },
  students: { id: "students", partitionKey: "/studentId" },
  scans: { id: "scans", partitionKey: "/listId" },
  lists: { id: "lists", partitionKey: "/eventId" },
  errors: { id: "errors", partitionKey: "/id" },
  deleted_events: { id: "deleted_events", partitionKey: "/id" },
  // Used by the portal's backup/restore and analytics screens, which talk to
  // Cosmos through /data rather than through a dedicated endpoint.
  archives: { id: "archives", partitionKey: "/id" },
  archive_students: { id: "archive_students", partitionKey: "/archiveId" },
  analytics: { id: "analytics", partitionKey: "/id" },
  // One document per SONIS attendance export batch.
  sonis_exports: { id: "sonis_exports", partitionKey: "/eventId" },
  // Access control: who may use the scanner/portal, and the invite-only
  // groups (Student Affairs, Admissions, ...) they belong to.
  authorized_users: { id: "authorized_users", partitionKey: "/id" },
  groups: { id: "groups", partitionKey: "/id" },
};

let client;

function getClient() {
  if (client) return client;

  const connectionString = process.env.COSMOS_CONNECTION_STRING;
  if (connectionString) {
    client = new CosmosClient(connectionString);
  } else if (process.env.COSMOS_ENDPOINT) {
    // Preferred in Azure: managed identity, no secrets in app settings.
    client = new CosmosClient({
      endpoint: process.env.COSMOS_ENDPOINT,
      aadCredentials: new DefaultAzureCredential(),
    });
  } else {
    throw new Error("Set COSMOS_CONNECTION_STRING or COSMOS_ENDPOINT");
  }
  return client;
}

const container = (name) => {
  const spec = CONTAINERS[name];
  if (!spec) {
    // Without this the failure surfaces as a confusing
    // "Cannot read properties of undefined (reading 'id')" 500.
    throw new Error(
      `Unknown container '${name}'. Add it to CONTAINERS in src/lib/cosmos.js.`
    );
  }
  return getClient().database(DATABASE).container(spec.id);
};

// Cosmos decorates every document with _rid/_self/_etag/_attachments/_ts.
// Those must never reach the clients, which parse these payloads strictly.
const SYSTEM_FIELDS = new Set(["_rid", "_self", "_etag", "_attachments", "_ts"]);

function clean(doc) {
  if (!doc) return doc;
  const out = {};
  for (const [k, v] of Object.entries(doc)) {
    if (!SYSTEM_FIELDS.has(k)) out[k] = v;
  }
  return out;
}

async function queryAll(name, query, parameters = []) {
  const { resources } = await container(name)
    .items.query({ query, parameters })
    .fetchAll();
  return resources.map(clean);
}

async function listAll(name) {
  return queryAll(name, "SELECT * FROM c");
}

// Firestore's .doc(id).get() — returns null when absent rather than throwing.
async function getById(name, id, partitionKey) {
  try {
    const { resource } = await container(name)
      .item(id, partitionKey === undefined ? id : partitionKey)
      .read();
    return clean(resource);
  } catch (error) {
    if (error.code === 404) return null;
    throw error;
  }
}

// Firestore's .where(field, "==", value).limit(1)
async function findOneBy(name, field, value) {
  const rows = await queryAll(
    name,
    `SELECT TOP 1 * FROM c WHERE c.${field} = @value`,
    [{ name: "@value", value }]
  );
  return rows[0] || null;
}

async function findBy(name, field, value) {
  return queryAll(name, `SELECT * FROM c WHERE c.${field} = @value`, [
    { name: "@value", value },
  ]);
}

// Firestore's .set() — full replace/insert.
async function upsert(name, doc) {
  const { resource } = await container(name).items.upsert(doc);
  return clean(resource);
}

// Firestore's .add() — server-assigned id.
async function add(name, doc) {
  return upsert(name, { id: randomUUID(), ...doc });
}

// Firestore's .update() — merge into the existing document.
async function patch(name, id, partitionKey, changes) {
  const existing = await getById(name, id, partitionKey);
  if (!existing) return null;
  return upsert(name, { ...existing, ...changes });
}

async function remove(name, id, partitionKey) {
  try {
    await container(name).item(id, partitionKey === undefined ? id : partitionKey).delete();
    return true;
  } catch (error) {
    if (error.code === 404) return false;
    throw error;
  }
}

module.exports = {
  DATABASE,
  CONTAINERS,
  getClient,
  container,
  clean,
  queryAll,
  listAll,
  getById,
  findOneBy,
  findBy,
  upsert,
  add,
  patch,
  remove,
  randomUUID,
};
