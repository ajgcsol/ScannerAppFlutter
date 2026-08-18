"use strict";

const { test } = require("node:test");
const assert = require("node:assert");
const { execSync } = require("node:child_process");

process.env.COSMOS_CONNECTION_STRING =
  "AccountEndpoint=https://stub.documents.azure.com:443/;AccountKey=c3R1Yg==;";

const { CONTAINERS } = require("../src/lib/cosmos");

// dataApi.js registers Azure handlers at require time, so its collection map is
// read from source rather than by importing the module.
function dataApiCollections() {
  const source = require("node:fs").readFileSync(
    require("node:path").join(__dirname, "../src/functions/dataApi.js"),
    "utf8"
  );
  const block = source.match(/const COLLECTIONS = \{([\s\S]*?)\n\};/);
  assert.ok(block, "COLLECTIONS block not found in dataApi.js");
  return [...block[1].matchAll(/container:\s*"([^"]+)"/g)].map((m) => m[1]);
}

test("every collection the data API maps is a known Cosmos container", () => {
  const missing = dataApiCollections().filter((name) => !CONTAINERS[name]);
  assert.deepStrictEqual(
    missing,
    [],
    `these containers are addressed by /data but absent from CONTAINERS: ${missing.join(", ")}`
  );
});

test("every declared container names itself and has a partition key", () => {
  for (const [name, spec] of Object.entries(CONTAINERS)) {
    assert.strictEqual(spec.id, name, `${name}: id must match its key`);
    assert.match(spec.partitionKey, /^\/[A-Za-z]+$/, `${name}: bad partition key`);
  }
});

test("unknown containers fail with an actionable message", () => {
  const { container } = require("../src/lib/cosmos");
  assert.throws(() => container("does_not_exist"), /Unknown container 'does_not_exist'/);
});
