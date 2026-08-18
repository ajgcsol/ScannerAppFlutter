"use strict";

const { test } = require("node:test");
const assert = require("node:assert");
const Module = require("module");

// The function modules call app.http() at require time, so stub the SDK and
// capture the registered handlers instead of standing up a real host.
const registered = new Map();
const originalResolve = Module._resolveFilename;
Module._resolveFilename = function (request, ...args) {
  if (request === "@azure/functions") return "STUB_AZURE_FUNCTIONS";
  return originalResolve.call(this, request, ...args);
};
require.cache["STUB_AZURE_FUNCTIONS"] = {
  id: "STUB_AZURE_FUNCTIONS",
  filename: "STUB_AZURE_FUNCTIONS",
  loaded: true,
  exports: {
    app: { http: (name, opts) => registered.set(name, opts.handler) },
  },
};

process.env.APP_API_KEY = "test-key";
process.env.COSMOS_CONNECTION_STRING =
  "AccountEndpoint=https://stub.documents.azure.com:443/;AccountKey=c3R1Yg==;";

require("../src/functions/import");

const makeRequest = (body, method = "POST", headers = { "x-api-key": "test-key" }) => ({
  method,
  query: new Map(),
  headers: {
    get: (name) => headers[name.toLowerCase()] ?? headers[name] ?? null,
  },
  text: async () => body,
});

test("CSV parser handles quoted fields, embedded commas and escaped quotes", async () => {
  // Exercise the parser through the import handler by stubbing the data layer.
  const db = require("../src/lib/cosmos");
  const upserted = [];
  db.listAll = async () => [];
  db.upsert = async (_c, doc) => {
    upserted.push(doc);
    return doc;
  };

  const csv = [
    'Student ID,First Name,Last Name,Email,Program',
    '"12345","Ann, Marie","O""Brien",ann@example.edu,JD',
    '67890,Bob,Smith,bob@example.edu,LLM',
  ].join("\n");

  const res = await registered.get("importStudents")(makeRequest(csv), {
    log: () => {},
    error: () => {},
  });

  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.jsonBody.imported, 2);
  assert.strictEqual(upserted[0].firstName, "Ann, Marie");
  assert.strictEqual(upserted[0].lastName, 'O"Brien');
  assert.strictEqual(upserted[0].studentId, "12345");
  assert.strictEqual(upserted[1].email, "bob@example.edu");
});

test("import accepts a JSON array as well as CSV", async () => {
  const db = require("../src/lib/cosmos");
  const upserted = [];
  db.listAll = async () => [];
  db.upsert = async (_c, doc) => {
    upserted.push(doc);
    return doc;
  };

  const res = await registered.get("importStudents")(
    makeRequest(JSON.stringify([{ studentId: "999", firstName: "Cy", lastName: "Lee" }])),
    { log: () => {}, error: () => {} }
  );

  assert.strictEqual(res.status, 200);
  assert.strictEqual(upserted[0].studentId, "999");
  assert.strictEqual(upserted[0].firstName, "Cy");
});

test("re-importing an existing student updates rather than duplicates, keeping photo state", async () => {
  const db = require("../src/lib/cosmos");
  const upserted = [];
  db.listAll = async () => [
    { id: "stable-id", studentId: "12345", firstName: "Old", lastName: "Name", hasPhoto: true },
  ];
  db.upsert = async (_c, doc) => {
    upserted.push(doc);
    return doc;
  };

  const res = await registered.get("importStudents")(
    makeRequest("Student ID,First Name,Last Name\n12345,New,Name"),
    { log: () => {}, error: () => {} }
  );

  assert.strictEqual(res.jsonBody.imported, 0);
  assert.strictEqual(res.jsonBody.updated, 1);
  assert.strictEqual(upserted[0].id, "stable-id", "must reuse the existing document id");
  assert.strictEqual(upserted[0].firstName, "New");
  assert.strictEqual(upserted[0].hasPhoto, true, "photo state must survive a roster refresh");
});

test("rows missing a student id are reported, not silently dropped", async () => {
  const db = require("../src/lib/cosmos");
  db.listAll = async () => [];
  db.upsert = async (_c, doc) => doc;

  const res = await registered.get("importStudents")(
    makeRequest("Student ID,First Name\n,Nobody\n555,Real"),
    { log: () => {}, error: () => {} }
  );

  assert.strictEqual(res.jsonBody.imported, 1);
  assert.strictEqual(res.jsonBody.errors.length, 1);
  assert.strictEqual(res.jsonBody.errors[0].row, 2);
});

test("OPTIONS preflight returns 204 with CORS headers", async () => {
  const res = await registered.get("importStudents")(makeRequest("", "OPTIONS"), {
    log: () => {},
    error: () => {},
  });
  assert.strictEqual(res.status, 204);
  assert.strictEqual(res.headers["Access-Control-Allow-Origin"], "*");
});

test("import rejects unauthenticated callers", async () => {
  const res = await registered.get("importStudents")(
    makeRequest("Student ID,First Name\n123,Nope", "POST", {}),
    { log: () => {}, error: () => {} }
  );
  assert.strictEqual(res.status, 401);
});

test("preflight carries the headers the clients actually send", async () => {
  const res = await registered.get("importStudents")(makeRequest("", "OPTIONS"), {
    log: () => {},
    error: () => {},
  });
  assert.strictEqual(res.status, 204);
  // A 204 must not carry a body or Content-Type, or the host returns 500.
  assert.ok(!("body" in res), "204 must have no body");
  assert.ok(!res.headers["Content-Type"], "204 must not set Content-Type");
  assert.match(res.headers["Access-Control-Allow-Headers"], /Authorization/);
  assert.match(res.headers["Access-Control-Allow-Headers"], /x-api-key/);
});
