import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();

// CORS headers are set individually in each function

// Get Events
export const getEvents = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  try {
    const eventsSnapshot = await db.collection("events").get();
    const events = eventsSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));
    
    res.status(200).json(events);
  } catch (error) {
    console.error("Error getting events:", error);
    res.status(500).json({ error: "Failed to get events" });
  }
});

// Get Students
export const getStudents = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  try {
    const studentsSnapshot = await db.collection("students").get();
    const students = studentsSnapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));
    
    res.status(200).json(students);
  } catch (error) {
    console.error("Error getting students:", error);
    res.status(500).json({ error: "Failed to get students" });
  }
});

// Get Student by ID
export const getStudentById = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
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
    res.status(200).json({
      id: studentSnapshot.docs[0].id,
      ...student,
    });
  } catch (error) {
    console.error("Error getting student:", error);
    res.status(500).json({ error: "Failed to get student" });
  }
});

// Get Scan Records for Event
export const getScanRecords = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
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
    
    let queryValue: any = paramValue;
    
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
        } else {
          console.log(`No event found with eventNumber: ${paramValue}`);
          res.status(404).json({ error: `No event found with eventNumber: ${paramValue}` });
          return;
        }
      } catch (lookupError) {
        console.error("Error looking up event:", lookupError);
        res.status(500).json({ error: "Failed to lookup event" });
        return;
      }
    }
    
    console.log(`Querying scans with listId: ${queryValue}`);
    
    // For backwards compatibility, also try querying with the original eventNumber
    const alternativeQueryValue = paramValue; // Original eventNumber/eventId parameter
    console.log(`Alternative query value: ${alternativeQueryValue}`);
    
    // First try with orderBy, if it fails due to missing index, get without ordering
    let scans: any[] = [];
    
    try {
      const scansSnapshot = await db.collection("scans")
        .where("listId", "==", queryValue)
        .orderBy("timestamp", "desc")
        .get();
      
      scans = scansSnapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      }));
    } catch (indexError: any) {
      console.log("Index error, trying without orderBy:", indexError.message);
      // Fallback: get without orderBy and sort in memory
      const scansSnapshot = await db.collection("scans")
        .where("listId", "==", queryValue)
        .get();
      
      scans = scansSnapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
      }));
      
      // Sort by timestamp in memory
      scans.sort((a, b) => {
        const timeA = a.timestamp?.seconds || a.timestamp || 0;
        const timeB = b.timestamp?.seconds || b.timestamp || 0;
        return timeB - timeA; // Descending order
      });
    }

    // If no scans found and queryValue is different from alternativeQueryValue, try the alternative
    if (scans.length === 0 && queryValue !== alternativeQueryValue) {
      console.log(`No scans found with listId: ${queryValue}, trying alternative: ${alternativeQueryValue}`);
      
      try {
        const alternativeSnapshot = await db.collection("scans")
          .where("listId", "==", alternativeQueryValue)
          .orderBy("timestamp", "desc")
          .get();
        
        scans = alternativeSnapshot.docs.map((doc) => ({
          id: doc.id,
          ...doc.data(),
        }));
        
        console.log(`Found ${scans.length} scans with alternative listId: ${alternativeQueryValue}`);
      } catch (altIndexError: any) {
        console.log("Alternative query index error, trying without orderBy");
        const alternativeSnapshot = await db.collection("scans")
          .where("listId", "==", alternativeQueryValue)
          .get();
        
        scans = alternativeSnapshot.docs.map((doc) => ({
          id: doc.id,
          ...doc.data(),
        }));
        
        // Sort by timestamp in memory
        scans.sort((a, b) => {
          const timeA = a.timestamp?.seconds || a.timestamp || 0;
          const timeB = b.timestamp?.seconds || b.timestamp || 0;
          return timeB - timeA; // Descending order
        });
        
        console.log(`Found ${scans.length} scans with alternative listId (no orderBy): ${alternativeQueryValue}`);
      }
    }

    console.log(`Found ${scans.length} scans for parameter: ${paramValue} (queried with listId: ${queryValue})`);
    res.status(200).json(scans);
  } catch (error) {
    console.error("Error getting scan records:", error);
    res.status(500).json({ error: "Failed to get scan records" });
  }
});

// Add Scan Record
export const addScanRecord = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
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

    console.log(`Adding scan record with eventId: ${scanRecord.eventId}`);
    console.log(`Original scanRecord:`, JSON.stringify(scanRecord, null, 2));
    
    // Determine the actual Firebase eventId to use for storage
    let actualEventId = scanRecord.eventId;
    
    // If eventId looks like an eventNumber (numeric), convert to actual eventId by looking up the event
    if (scanRecord.eventId && !isNaN(Number(scanRecord.eventId))) {
      console.log(`EventId appears to be eventNumber: ${scanRecord.eventId}, looking up corresponding eventId...`);
      
      try {
        const eventsSnapshot = await db.collection("events")
          .where("eventNumber", "==", Number(scanRecord.eventId))
          .limit(1)
          .get();
        
        if (!eventsSnapshot.empty) {
          actualEventId = eventsSnapshot.docs[0].id;
          console.log(`Successfully converted eventNumber ${scanRecord.eventId} to eventId: ${actualEventId}`);
        } else {
          console.log(`WARNING: No event found with eventNumber: ${scanRecord.eventId}, keeping original value`);
          actualEventId = scanRecord.eventId; // Keep original if no match found
        }
      } catch (lookupError) {
        console.error("Error looking up event:", lookupError);
        console.log(`FALLBACK: Using original eventId due to lookup error: ${scanRecord.eventId}`);
        actualEventId = scanRecord.eventId; // Keep original if lookup fails
      }
    }
    
    console.log(`Final actualEventId for storage: ${actualEventId} (original: ${scanRecord.eventId})`)

    // Add to nested structure (for Android compatibility)
    const nestedScanData = {
      ...scanRecord,
      eventId: actualEventId,
      symbology: scanRecord.symbology || "QR_CODE", // Ensure symbology is not undefined
      studentId: scanRecord.studentId || scanRecord.code,
      deviceId: scanRecord.deviceId || "",
      synced: scanRecord.synced || false,
      processed: scanRecord.processed || false,
      metadata: scanRecord.metadata || {},
    };
    await db.collection("lists")
      .doc(actualEventId)
      .collection("scans")
      .doc(scanRecord.id)
      .set(nestedScanData);

    // Add to flat structure (for admin portal compatibility)
    const flatScanData = {
      code: scanRecord.code,
      timestamp: scanRecord.timestamp.seconds ? 
        scanRecord.timestamp.seconds * 1000 : 
        scanRecord.timestamp,
      listId: actualEventId, // Use actual Firebase eventId to match existing working scans
      eventId: actualEventId, // Use actual Firebase eventId 
      deviceId: scanRecord.deviceId || "",
      verified: scanRecord.processed || false,
      symbology: scanRecord.symbology || "QR_CODE", // Default to QR_CODE if undefined
      studentId: scanRecord.studentId || scanRecord.code,
      synced: scanRecord.synced || false,
      metadata: scanRecord.metadata || {},
    };

    await db.collection("scans").doc(scanRecord.id).set(flatScanData);

    console.log(`Scan record stored with listId/eventId: ${actualEventId}`);
    console.log(`Flat scan data stored:`, JSON.stringify(flatScanData, null, 2));
    res.status(200).json({ success: true, id: scanRecord.id, listId: actualEventId, eventId: actualEventId });
  } catch (error) {
    console.error("Error adding scan record:", error);
    res.status(500).json({ error: "Failed to add scan record" });
  }
});

// Add Error Record
export const addErrorRecord = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
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
    
    await db.collection("errors").add({
      ...errorRecord,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.status(200).json({ success: true });
  } catch (error) {
    console.error("Error adding error record:", error);
    res.status(500).json({ error: "Failed to add error record" });
  }
});

// Migration Function - Fix existing scan records for admin portal visibility
export const migrateScanRecords = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
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
    const { eventNumber } = req.body;
    
    if (!eventNumber) {
      res.status(400).json({ error: "eventNumber is required" });
      return;
    }

    console.log(`Starting migration for eventNumber: ${eventNumber}`);

    // First, find the actual eventId for this eventNumber
    const eventsSnapshot = await db.collection("events")
      .where("eventNumber", "==", Number(eventNumber))
      .limit(1)
      .get();
    
    if (eventsSnapshot.empty) {
      res.status(404).json({ error: `No event found with eventNumber: ${eventNumber}` });
      return;
    }

    const actualEventId = eventsSnapshot.docs[0].id;
    console.log(`Found eventId: ${actualEventId} for eventNumber: ${eventNumber}`);

    // Find all scans that need migration (where listId doesn't match the actual eventId)
    const scansSnapshot = await db.collection("scans")
      .where("listId", "==", eventNumber.toString())
      .get();

    console.log(`Found ${scansSnapshot.docs.length} scans to migrate`);

    // Update each scan record
    const batch = db.batch();
    let updateCount = 0;

    scansSnapshot.docs.forEach((doc) => {
      const scanData = doc.data();
      console.log(`Migrating scan ${doc.id}: listId from "${scanData.listId}" to "${actualEventId}"`);
      
      batch.update(doc.ref, {
        listId: actualEventId,
        eventId: actualEventId,
      });
      updateCount++;
    });

    // Commit the batch update
    if (updateCount > 0) {
      await batch.commit();
      console.log(`Successfully migrated ${updateCount} scan records`);
    }

    res.status(200).json({ 
      success: true, 
      eventNumber: eventNumber,
      actualEventId: actualEventId,
      migratedCount: updateCount 
    });
  } catch (error) {
    console.error("Error migrating scan records:", error);
    res.status(500).json({ error: "Failed to migrate scan records" });
  }
});

