"use strict";

const { app } = require("@azure/functions");
const db = require("../lib/cosmos");
const blob = require("../lib/blob");
const { json, handler } = require("../lib/http");
const { authenticate } = require("../lib/auth");

app.http("checkStudentPhotos", {
  methods: ["GET", "POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "checkStudentPhotos",
  handler: handler({
    methods: "GET, POST, OPTIONS",
    fn: async (request, context) => {
      context.log("Starting student photo check...");
      await blob.ensureContainer();

      const students = await db.listAll("students");
      context.log(`Found ${students.length} students to check`);

      let photosFound = 0;
      let photosNotFound = 0;
      let photosUpdated = 0;
      const results = [];

      for (const student of students) {
        const studentId = student.studentId;
        if (!studentId) {
          context.log(`Student ${student.id} has no studentId, skipping`);
          continue;
        }

        // Photos follow the convention {Student ID}-photo.{ext}. The ID-card
        // system exports both .jpg and .png, so the extension is discovered
        // rather than assumed.
        const name = `${student.firstName} ${student.lastName}`;
        let photoFileName = `${studentId}-photo.jpg`;

        try {
          const found = await blob.findPhoto(studentId);
          const exists = Boolean(found);
          if (found) photoFileName = found;

          if (exists) {
            const url = blob.photoUrl(photoFileName);
            // SAS URLs carry an expiry, so the stored URL is always refreshed
            // rather than compared for equality as the Firebase version did.
            await db.upsert("students", {
              ...student,
              photoUrl: url,
              hasPhoto: true,
              photoFileName,
              photoUpdatedAt: new Date().toISOString(),
            });
            photosUpdated++;
            photosFound++;
            results.push({ studentId, name, hasPhoto: true, photoUrl: url, photoFileName });
          } else {
            if (student.hasPhoto !== false) {
              const { photoUrl, photoFileName: _drop, ...rest } = student;
              await db.upsert("students", {
                ...rest,
                hasPhoto: false,
                photoUpdatedAt: new Date().toISOString(),
              });
              photosUpdated++;
            }
            photosNotFound++;
            results.push({ studentId, name, hasPhoto: false, expectedFileName: photoFileName });
          }
        } catch (error) {
          context.error(`Error checking photo for ${studentId}:`, error);
          photosNotFound++;
          results.push({
            studentId,
            name,
            hasPhoto: false,
            error: error.message,
            expectedFileName: photoFileName,
          });
        }
      }

      const summary = {
        totalStudents: students.length,
        photosFound,
        photosNotFound,
        recordsUpdated: photosUpdated,
        timestamp: new Date().toISOString(),
      };
      context.log("Photo check summary:", summary);

      return json(200, {
        success: true,
        summary,
        results: request.query.get("includeDetails") === "true" ? results : undefined,
      });
    },
  }),
});

// The portal's storage shim posts raw image bytes here. Uploading through the
// API keeps the storage account private: no public blob access, and no SAS
// token is ever exposed to the browser.
app.http("uploadPhoto", {
  methods: ["POST", "OPTIONS"],
  authLevel: "anonymous",
  route: "uploadPhoto",
  handler: handler({
    methods: "POST, OPTIONS",
    allow: ["POST"],
    fn: async (request, context) => {
      const auth = await authenticate(request);
      if (!auth.ok) {
        return json(401, { error: "Unauthorized", detail: auth.reason }, "POST, OPTIONS");
      }

      const path = request.headers.get("x-photo-path");
      if (!path) {
        return json(400, { error: "x-photo-path header is required" }, "POST, OPTIONS");
      }
      // Reject traversal and absolute paths before they reach the container.
      if (path.includes("..") || path.startsWith("/")) {
        return json(400, { error: "Invalid photo path" }, "POST, OPTIONS");
      }

      const body = Buffer.from(await request.arrayBuffer());
      if (body.length === 0) {
        return json(400, { error: "Empty upload" }, "POST, OPTIONS");
      }

      const contentType = request.headers.get("content-type") || "image/jpeg";
      const url = await blob.uploadPhoto(path, body, contentType);

      context.log(`Uploaded ${path} (${body.length} bytes) as ${auth.principal.name}`);
      return json(200, { success: true, path, url }, "POST, OPTIONS");
    },
  }),
});

app.http("photoUrl", {
  methods: ["GET", "OPTIONS"],
  authLevel: "anonymous",
  route: "photoUrl",
  handler: handler({
    methods: "GET, OPTIONS",
    fn: async (request) => {
      const auth = await authenticate(request);
      if (!auth.ok) {
        return json(401, { error: "Unauthorized", detail: auth.reason }, "GET, OPTIONS");
      }

      const path = request.query.get("path");
      if (!path) return json(400, { error: "path is required" }, "GET, OPTIONS");
      if (path.includes("..") || path.startsWith("/")) {
        return json(400, { error: "Invalid photo path" }, "GET, OPTIONS");
      }

      if (!(await blob.photoExists(path))) {
        return json(404, { error: "Photo not found", path }, "GET, OPTIONS");
      }
      return json(200, { url: blob.photoUrl(path), path }, "GET, OPTIONS");
    },
  }),
});
