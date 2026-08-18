# inSession backend on Azure

Replaces the retired Firebase project `scannerappfb` (Firestore was deleted;
its Cloud Functions returned 503). Nothing here depends on Google.

## What runs where

| Piece | Azure resource | Notes |
|---|---|---|
| API (19 HTTP endpoints) | Function App `insession-api-fc` | Flex Consumption, Node 24 |
| Database | Cosmos DB `insession-cosmos-csol`, database `insession` | Serverless (pay per request) |
| Student photos | Storage `insessionapicsol`, container `student-photos` | Private; no public blob access |
| Admin portal | Static Web App `insession-portal` | Free tier |
| Everything | Resource group `insession-rg`, `eastus` | |

URLs:
- API — https://insession-api-fc.azurewebsites.net
- Portal — https://mango-flower-0fc5da20f.7.azurestaticapps.net

> A second Function App, `insession-api-csol` (Y1 Linux Consumption), was
> created first and never served traffic — every request returned 503 despite
> correct configuration and three successful deployments. It holds no data and
> can be deleted.

## Route compatibility

`host.json` sets `extensions.http.routePrefix` to `""`, so paths match the old
Cloud Functions exactly (`/getEvents`, not `/api/getEvents`). Moving off
Firebase was therefore a hostname change in the clients, not a route rewrite.

## Data model

Cosmos containers mirror the old Firestore collections. Partition keys:

| Container | Partition key | Purpose |
|---|---|---|
| `events` | `/id` | |
| `students` | `/studentId` | |
| `scans` | `/listId` | Flat structure the admin portal reads |
| `lists` | `/eventId` | Nested per-event structure the mobile app writes |
| `errors` | `/id` | |
| `deleted_events` | `/id` | Tombstones so mobile clients detect deletions |
| `archives` | `/id` | Portal backup/restore |
| `archive_students` | `/archiveId` | Firestore subcollection `archives/{id}/students` |
| `analytics` | `/id` | |

Both scan structures are still written on every scan and merged (de-duplicated,
preferring the flat record) on read — matching the original behaviour, because
older records may exist in only one of them.

Dates are ISO-8601 strings; scan timestamps are epoch milliseconds. This is not
cosmetic: the Flutter client calls a bare `DateTime.parse` on `date` and
`createdAt` in the `createEvent`/`updateEvent` responses.

## Authentication

The old setup had no Firestore rules and the portal queried Firestore straight
from the browser with a public API key, so student records were readable by
anyone holding that key. MSAL only gated the UI. That is closed here.

- **Portal** — sends its Entra ID token as `Authorization: Bearer`. Validated
  against tenant `40acb9f6-…` via JWKS, audience `cd8d142c-…`.
- **Scanner app** — has no interactive login, so it sends `x-api-key` matching
  the `APP_API_KEY` app setting. Compiled in at build time via
  `--dart-define=INSESSION_API_KEY=…`, never committed.
- Auth **fails closed**: with neither mechanism configured, nothing authorizes.

Every endpoint that reads or writes student data requires a verified caller.

> A key embedded in a shipped binary is extractable by a determined user. It is
> a large improvement over an open database, not a substitute for per-user auth.
> Proper fix: expose an API scope on the Entra app and have the app sign in.

## App settings

`COSMOS_CONNECTION_STRING`, `STORAGE_CONNECTION_STRING`, `COSMOS_DATABASE`,
`PHOTOS_CONTAINER`, `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, `APP_API_KEY`,
`PHOTO_SAS_TTL_DAYS`.

## Deploying

```bash
# API — remote build is required, or node_modules never lands on the host
npx azure-functions-core-tools@4 azure functionapp publish insession-api-fc --javascript --build remote

# Portal
TOKEN=$(az staticwebapp secrets list -n insession-portal -g insession-rg --query "properties.apiKey" -o tsv)
npx @azure/static-web-apps-cli deploy ./public --deployment-token "$TOKEN" --env production
```

Note: `az functionapp deployment source config-zip` and `az webapp deploy` both
failed against these apps (400 / 503 from Kudu). The Core Tools path works.

Run `npm test` for the offline suite (CSV parsing, auth rejection, preflight).

## Photos

Blobs are named `{studentId}-photo.jpg`. Firebase issued effectively permanent
signed URLs; SAS tokens expire, so `checkStudentPhotos` re-mints them (default
7-day TTL) and always refreshes the stored URL. Uploads go through
`/uploadPhoto` so the storage account stays private and no SAS reaches the
browser.

## Re-seeding data

Firestore was deleted, so there is nothing to migrate. `POST /importStudents`
and `POST /importEvents` accept raw CSV (header row required) or a JSON array,
tolerate common column-name spellings, and update existing records in place
rather than duplicating them — a roster refresh preserves photo state.

```bash
curl -X POST https://insession-api-fc.azurewebsites.net/importStudents \
  -H "x-api-key: $APP_API_KEY" -H "Content-Type: text/csv" \
  --data-binary @roster.csv
```

## The portal's compatibility shim

`public/admin-portal.js` makes ~76 direct `firebase.firestore()` calls,
including `archives` and `analytics` work that no Cloud Function ever covered.
Rather than rewrite 3,257 lines, `public/azure-db.js` re-implements the subset
of that API in use and installs itself as `window.firebase`, so those call sites
are untouched. It relies on there being no `onSnapshot` listeners — there are
none. Load order matters: `azure-db.js` must precede `admin-portal.js`, and the
Firebase CDN bundles must not be loaded at all.

Generic collection access is served by `/data/{path}` and `/batch`. Only mapped
collection paths are served, so an arbitrary path cannot reach an unmapped
container. Cosmos has no cross-partition transaction, so `/batch` applies
operations sequentially and reports per-operation failures instead of rolling
back — a partial batch failure surfaces as an error in the portal.
