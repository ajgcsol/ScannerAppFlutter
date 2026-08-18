"use strict";

const { app } = require("@azure/functions");
const db = require("../lib/cosmos");
const { json, handler } = require("../lib/http");

app.http("getStudents", {
  methods: ["GET", "OPTIONS"],
  authLevel: "anonymous",
  route: "getStudents",
  handler: handler({
    requireAuth: true,
    methods: "GET, POST, OPTIONS",
    fn: async () => json(200, await db.listAll("students")),
  }),
});

app.http("getStudentById", {
  methods: ["GET", "OPTIONS"],
  authLevel: "anonymous",
  route: "getStudentById",
  handler: handler({
    requireAuth: true,
    methods: "GET, POST, OPTIONS",
    fn: async (request) => {
      const studentId = request.query.get("studentId");
      if (!studentId) return json(400, { error: "studentId is required" });

      const student = await db.findOneBy("students", "studentId", studentId);
      if (!student) return json(404, { error: "Student not found" });

      return json(200, student);
    },
  }),
});

app.http("getStudentsWithPhotos", {
  methods: ["GET", "OPTIONS"],
  authLevel: "anonymous",
  route: "getStudentsWithPhotos",
  handler: handler({
    requireAuth: true,
    methods: "GET, OPTIONS",
    fn: async (request, context) => {
      const hasPhoto = request.query.get("hasPhoto");
      const includePhotos = request.query.get("includePhotos");

      const clauses = ["c.active = true"];
      const parameters = [];
      if (hasPhoto === "true") {
        clauses.push("c.hasPhoto = true");
      } else if (hasPhoto === "false") {
        // Firestore required hasPhoto to exist and be false; treat a missing
        // flag as "no photo" here so newly imported students aren't invisible.
        clauses.push("(NOT IS_DEFINED(c.hasPhoto) OR c.hasPhoto = false)");
      }

      const rows = await db.queryAll(
        "students",
        `SELECT * FROM c WHERE ${clauses.join(" AND ")} ORDER BY c.lastName, c.firstName`,
        parameters
      );

      const students = rows.map((data) => {
        const student = {
          id: data.id,
          studentId: data.studentId,
          firstName: data.firstName,
          lastName: data.lastName,
          email: data.email,
          program: data.program,
          year: data.year,
          hasPhoto: data.hasPhoto || false,
        };
        if (includePhotos === "true" && data.photoUrl) {
          student.photoUrl = data.photoUrl;
          student.photoFileName = data.photoFileName;
        }
        return student;
      });

      context.log(
        `Retrieved ${students.length} students (hasPhoto filter: ${hasPhoto || "none"})`
      );

      return json(
        200,
        {
          students,
          total: students.length,
          filter: {
            hasPhoto: hasPhoto || null,
            includePhotos: includePhotos === "true",
          },
        },
        "GET, OPTIONS"
      );
    },
  }),
});
