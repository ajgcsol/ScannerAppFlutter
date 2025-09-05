"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.addErrorRecord = exports.addScanRecord = exports.getScanRecords = exports.getStudentById = exports.getStudents = exports.getEvents = void 0;
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();
const db = admin.firestore();
// CORS headers are set individually in each function
// Get Events
exports.getEvents = functions.runWith({ invoker: 'public' }).https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    try {
        const eventsSnapshot = await db.collection("events").get();
        const events = eventsSnapshot.docs.map((doc) => (Object.assign({ id: doc.id }, doc.data())));
        res.status(200).json(events);
    }
    catch (error) {
        console.error("Error getting events:", error);
        res.status(500).json({ error: "Failed to get events" });
    }
});
// Get Students
exports.getStudents = functions.runWith({ invoker: 'public' }).https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    try {
        const studentsSnapshot = await db.collection("students").get();
        const students = studentsSnapshot.docs.map((doc) => (Object.assign({ id: doc.id }, doc.data())));
        res.status(200).json(students);
    }
    catch (error) {
        console.error("Error getting students:", error);
        res.status(500).json({ error: "Failed to get students" });
    }
});
// Get Student by ID
exports.getStudentById = functions.runWith({ invoker: 'public' }).https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    try {
        const { studentId } = req.query;
        if (!studentId) {
            res.status(400).json({ error: "studentId is required" });
            return;
        }
        const studentSnapshot = await db.collection("students")
            .where("studentId", "==", studentId)
            .get();
        if (studentSnapshot.empty) {
            res.status(404).json({ error: "Student not found" });
            return;
        }
        const student = studentSnapshot.docs[0].data();
        res.status(200).json(Object.assign({ id: studentSnapshot.docs[0].id }, student));
    }
    catch (error) {
        console.error("Error getting student:", error);
        res.status(500).json({ error: "Failed to get student" });
    }
});
// Get Scan Records for Event
exports.getScanRecords = functions.runWith({ invoker: 'public' }).https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    try {
        // Accept both eventNumber and eventId for backward compatibility
        const { eventNumber, eventId } = req.query;
        const paramValue = eventNumber || eventId;
        if (!paramValue) {
            res.status(400).json({ error: "eventNumber or eventId is required" });
            return;
        }
        console.log(`Getting scans for parameter: ${paramValue}`);
        let queryValue = paramValue;
        // If paramValue looks like an eventNumber (numeric), convert to eventId by looking up the event
        if (!isNaN(Number(paramValue))) {
            console.log(`Parameter appears to be eventNumber: ${paramValue}, looking up corresponding eventId...`);
            try {
                const eventsSnapshot = await db.collection("events")
                    .where("eventNumber", "==", Number(paramValue))
                    .limit(1)
                    .get();
                if (!eventsSnapshot.empty) {
                    queryValue = eventsSnapshot.docs[0].id;
                    console.log(`Found eventId: ${queryValue} for eventNumber: ${paramValue}`);
                }
                else {
                    console.log(`No event found with eventNumber: ${paramValue}`);
                    res.status(404).json({ error: `No event found with eventNumber: ${paramValue}` });
                    return;
                }
            }
            catch (lookupError) {
                console.error("Error looking up event:", lookupError);
                res.status(500).json({ error: "Failed to lookup event" });
                return;
            }
        }
        console.log(`Querying scans with listId: ${queryValue}`);
        // First try with orderBy, if it fails due to missing index, get without ordering
        let scans = [];
        try {
            const scansSnapshot = await db.collection("scans")
                .where("listId", "==", queryValue)
                .orderBy("timestamp", "desc")
                .get();
            scans = scansSnapshot.docs.map((doc) => (Object.assign({ id: doc.id }, doc.data())));
        }
        catch (indexError) {
            console.log("Index error, trying without orderBy:", indexError.message);
            // Fallback: get without orderBy and sort in memory
            const scansSnapshot = await db.collection("scans")
                .where("listId", "==", queryValue)
                .get();
            scans = scansSnapshot.docs.map((doc) => (Object.assign({ id: doc.id }, doc.data())));
            // Sort by timestamp in memory
            scans.sort((a, b) => {
                var _a, _b;
                const timeA = ((_a = a.timestamp) === null || _a === void 0 ? void 0 : _a.seconds) || a.timestamp || 0;
                const timeB = ((_b = b.timestamp) === null || _b === void 0 ? void 0 : _b.seconds) || b.timestamp || 0;
                return timeB - timeA; // Descending order
            });
        }
        console.log(`Found ${scans.length} scans for parameter: ${paramValue} (queried with listId: ${queryValue})`);
        res.status(200).json(scans);
    }
    catch (error) {
        console.error("Error getting scan records:", error);
        res.status(500).json({ error: "Failed to get scan records" });
    }
});
// Add Scan Record
exports.addScanRecord = functions.runWith({ invoker: 'public' }).https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method not allowed" });
        return;
    }
    try {
        const scanRecord = req.body;
        if (!scanRecord.id || !scanRecord.eventId) {
            res.status(400).json({ error: "Scan record must have id and eventId" });
            return;
        }
        // Add to nested structure (for Android compatibility)
        await db.collection("lists")
            .doc(scanRecord.eventId)
            .collection("scans")
            .doc(scanRecord.id)
            .set(scanRecord);
        // Add to flat structure (for admin portal compatibility)
        const flatScanData = {
            code: scanRecord.code,
            timestamp: scanRecord.timestamp.seconds ?
                scanRecord.timestamp.seconds * 1000 :
                scanRecord.timestamp,
            listId: scanRecord.eventId,
            eventId: scanRecord.eventId,
            deviceId: scanRecord.deviceId || "",
            verified: scanRecord.processed || false,
            symbology: scanRecord.symbology,
            studentId: scanRecord.studentId,
            synced: scanRecord.synced || false,
            metadata: scanRecord.metadata || {},
        };
        await db.collection("scans").doc(scanRecord.id).set(flatScanData);
        res.status(200).json({ success: true, id: scanRecord.id });
    }
    catch (error) {
        console.error("Error adding scan record:", error);
        res.status(500).json({ error: "Failed to add scan record" });
    }
});
// Add Error Record
exports.addErrorRecord = functions.runWith({ invoker: 'public' }).https.onRequest(async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method not allowed" });
        return;
    }
    try {
        const errorRecord = req.body;
        await db.collection("errors").add(Object.assign(Object.assign({}, errorRecord), { timestamp: admin.firestore.FieldValue.serverTimestamp() }));
        res.status(200).json({ success: true });
    }
    catch (error) {
        console.error("Error adding error record:", error);
        res.status(500).json({ error: "Failed to add error record" });
    }
});
//# sourceMappingURL=index.js.map