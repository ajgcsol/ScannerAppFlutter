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
    
    console.log(`Querying scans from BOTH structures with eventId: ${queryValue}`);
    
    // Query BOTH structures like the admin portal does
    let allScans: any[] = [];
    
    try {
      console.log("Querying flat structure (scans collection)...");
      const flatScansSnapshot = await db.collection("scans")
        .where("listId", "==", queryValue)
        .get();
      
      const flatScans = flatScansSnapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
        source: "flat"
      }));
      
      console.log(`Found ${flatScans.length} scans in flat structure`);
      allScans.push(...flatScans);
      
    } catch (flatError: any) {
      console.log("Error querying flat structure:", flatError.message);
    }

    try {
      console.log("Querying nested structure (lists collection)...");
      const nestedScansSnapshot = await db.collection("lists")
        .doc(queryValue)
        .collection("scans")
        .get();
      
      const nestedScans = nestedScansSnapshot.docs.map((doc) => ({
        id: doc.id,
        ...doc.data(),
        source: "nested"
      }));
      
      console.log(`Found ${nestedScans.length} scans in nested structure`);
      allScans.push(...nestedScans);
      
    } catch (nestedError: any) {
      console.log("Error querying nested structure:", nestedError.message);
    }

    // Remove duplicates by ID (prefer flat structure data if both exist)
    const uniqueScans = new Map();
    allScans.forEach(scan => {
      const existing = uniqueScans.get(scan.id);
      if (!existing || existing.source === "nested") {
        uniqueScans.set(scan.id, scan);
      }
    });
    
    const scans = Array.from(uniqueScans.values()).map(scan => {
      // Remove the source field from final output
      const { source, ...cleanScan } = scan;
      return cleanScan;
    });
    
    // Sort by timestamp in memory (descending order)
    scans.sort((a, b) => {
      const timeA = a.timestamp?.seconds || a.timestamp || 0;
      const timeB = b.timestamp?.seconds || b.timestamp || 0;
      return timeB - timeA;
    });

    console.log(`Found ${scans.length} total scans for parameter: ${paramValue} (queried eventId: ${queryValue})`);
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

    // Get student data for enrichment
    let studentData: any = null;
    const studentId = scanRecord.studentId || scanRecord.code;
    
    if (studentId) {
      try {
        console.log(`Looking up student data for studentId: ${studentId}`);
        const studentSnapshot = await db.collection("students")
          .where("studentId", "==", studentId)
          .limit(1)
          .get();
        
        if (!studentSnapshot.empty) {
          studentData = studentSnapshot.docs[0].data();
          console.log(`Found student: ${studentData.firstName} ${studentData.lastName}`);
        } else {
          console.log(`No student found with studentId: ${studentId}`);
        }
      } catch (studentLookupError) {
        console.error("Error looking up student:", studentLookupError);
      }
    }

    // Add to nested structure (for Android compatibility)
    const nestedScanData = {
      ...scanRecord,
      eventId: actualEventId,
      symbology: scanRecord.symbology || "QR_CODE",
      studentId: studentId,
      deviceId: scanRecord.deviceId || "",
      synced: scanRecord.synced || false,
      processed: studentData ? true : (scanRecord.processed || false),
      verified: studentData ? true : (scanRecord.processed || false),
      // Add student enrichment data
      firstName: studentData?.firstName || "",
      lastName: studentData?.lastName || "",
      email: studentData?.email || "",
      fullName: studentData ? `${studentData.firstName} ${studentData.lastName}` : "",
      metadata: scanRecord.metadata || {},
    };
    await db.collection("lists")
      .doc(actualEventId)
      .collection("scans")
      .doc(scanRecord.id)
      .set(nestedScanData);

    // Add to flat structure (for admin portal compatibility) - WITH ENRICHMENT
    const flatScanData = {
      code: scanRecord.code,
      timestamp: scanRecord.timestamp.seconds ? 
        scanRecord.timestamp.seconds * 1000 : 
        scanRecord.timestamp,
      listId: actualEventId,
      eventId: actualEventId,
      deviceId: scanRecord.deviceId || "",
      verified: studentData ? true : (scanRecord.processed || false),
      processed: studentData ? true : (scanRecord.processed || false),
      symbology: scanRecord.symbology || "QR_CODE",
      studentId: studentId,
      synced: scanRecord.synced || false,
      // CRITICAL: Add enriched student data for admin portal
      firstName: studentData?.firstName || "",
      lastName: studentData?.lastName || "",
      email: studentData?.email || "",
      fullName: studentData ? `${studentData.firstName} ${studentData.lastName}` : "",
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

// Create Event
export const createEvent = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
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
    const eventData = req.body;
    
    if (!eventData.name || !eventData.eventNumber) {
      res.status(400).json({ error: "Event name and eventNumber are required" });
      return;
    }

    console.log(`Creating new event: ${eventData.name} (${eventData.eventNumber})`);

    // Check if event number already exists
    const existingEventSnapshot = await db.collection("events")
      .where("eventNumber", "==", Number(eventData.eventNumber))
      .limit(1)
      .get();
    
    if (!existingEventSnapshot.empty) {
      res.status(409).json({ 
        error: `Event number ${eventData.eventNumber} already exists`,
        conflictField: "eventNumber"
      });
      return;
    }

    // Create the event document
    const eventDoc = {
      eventNumber: Number(eventData.eventNumber),
      name: eventData.name,
      description: eventData.description || "",
      date: eventData.date ? admin.firestore.Timestamp.fromDate(new Date(eventData.date)) : admin.firestore.FieldValue.serverTimestamp(),
      location: eventData.location || "",
      isActive: eventData.isActive !== undefined ? eventData.isActive : true,
      isCompleted: false,
      completedAt: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: eventData.createdBy || "mobile_app",
      customColumns: eventData.customColumns || [],
      staticValues: eventData.staticValues || {},
      exportFormat: eventData.exportFormat || "TEXT_DELIMITED",
    };

    // Add the event to Firestore
    const docRef = await db.collection("events").add(eventDoc);
    
    console.log(`Event created successfully with ID: ${docRef.id}`);
    
    // Return the created event with its ID
    const createdEvent = {
      id: docRef.id,
      ...eventDoc,
      date: eventData.date || new Date().toISOString(),
      createdAt: new Date().toISOString(),
    };

    res.status(201).json({ 
      success: true, 
      event: createdEvent,
      message: "Event created successfully"
    });
  } catch (error) {
    console.error("Error creating event:", error);
    res.status(500).json({ error: "Failed to create event" });
  }
});

// Fix scan records by enriching them with student data and verification
export const fixScanRecords = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
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

    console.log(`Starting scan record enrichment for eventNumber: ${eventNumber}`);

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

    // Get all students for lookup
    const studentsSnapshot = await db.collection("students").get();
    const studentLookup = new Map();
    studentsSnapshot.docs.forEach((doc) => {
      const student = doc.data();
      studentLookup.set(student.studentId, {
        firstName: student.firstName,
        lastName: student.lastName,
        email: student.email,
        id: doc.id
      });
    });

    console.log(`Loaded ${studentLookup.size} students for lookup`);

    // Find all scan records for this event that need enrichment
    const scansSnapshot = await db.collection("scans")
      .where("listId", "==", actualEventId)
      .get();

    console.log(`Found ${scansSnapshot.docs.length} scans to potentially enrich`);

    const batch = db.batch();
    let enrichedCount = 0;

    scansSnapshot.docs.forEach((doc) => {
      const scanData = doc.data();
      const studentId = scanData.studentId || scanData.code;
      
      if (studentId && studentLookup.has(studentId)) {
        const student = studentLookup.get(studentId);
        
        console.log(`Enriching scan ${doc.id} for student ${studentId}: ${student.firstName} ${student.lastName}`);
        
        // Enrich the scan record with student data and verification
        batch.update(doc.ref, {
          verified: true,
          processed: true,
          firstName: student.firstName,
          lastName: student.lastName,
          email: student.email,
          fullName: `${student.firstName} ${student.lastName}`,
          studentId: studentId,
          listId: actualEventId,
          eventId: actualEventId
        });
        
        enrichedCount++;
      } else {
        console.log(`No student found for scan ${doc.id} with studentId: ${studentId}`);
      }
    });

    // Commit the batch update
    if (enrichedCount > 0) {
      await batch.commit();
      console.log(`Successfully enriched ${enrichedCount} scan records with student data`);
    }

    res.status(200).json({ 
      success: true, 
      eventNumber: eventNumber,
      actualEventId: actualEventId,
      totalScans: scansSnapshot.docs.length,
      enrichedCount: enrichedCount 
    });
  } catch (error) {
    console.error("Error enriching scan records:", error);
    res.status(500).json({ error: "Failed to enrich scan records" });
  }
});

// Delete Scan Record (for admin portal)
export const deleteScanRecord = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "DELETE, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "DELETE") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  try {
    const { scanId, eventId } = req.body;
    
    if (!scanId) {
      res.status(400).json({ error: "scanId is required" });
      return;
    }

    console.log(`Deleting scan record: ${scanId} from event: ${eventId || 'unknown'}`);

    // Delete from flat structure (main scans collection)
    const scanDoc = await db.collection("scans").doc(scanId).get();
    
    if (!scanDoc.exists) {
      res.status(404).json({ error: "Scan record not found" });
      return;
    }

    const scanData = scanDoc.data();
    const actualEventId = eventId || scanData?.listId || scanData?.eventId;

    // Delete from flat structure
    await db.collection("scans").doc(scanId).delete();
    console.log(`Deleted scan ${scanId} from flat structure`);

    // Also delete from nested structure if eventId is available
    if (actualEventId) {
      try {
        await db.collection("lists")
          .doc(actualEventId)
          .collection("scans")
          .doc(scanId)
          .delete();
        console.log(`Deleted scan ${scanId} from nested structure (event ${actualEventId})`);
      } catch (nestedError) {
        console.log(`Could not delete from nested structure: ${nestedError}`);
        // Don't fail the request if nested deletion fails
      }
    }

    console.log(`Successfully deleted scan record: ${scanId}`);
    res.status(200).json({ 
      success: true, 
      message: "Scan record deleted successfully",
      scanId: scanId,
      eventId: actualEventId
    });
  } catch (error) {
    console.error("Error deleting scan record:", error);
    res.status(500).json({ error: "Failed to delete scan record" });
  }
});

// Delete Test Event (temporary function)
export const deleteTestEvent = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, DELETE, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  try {
    // Delete the test event
    await db.collection("events").doc("1756647674290").delete();
    res.status(200).json({ success: true, message: "Test event deleted" });
  } catch (error) {
    console.error("Error deleting test event:", error);
    res.status(500).json({ error: "Failed to delete test event" });
  }
});

// Update Event
export const updateEvent = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "PUT, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "PUT") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  try {
    const {
      id,
      eventNumber,
      name,
      description,
      location,
      date,
      isActive,
      isCompleted,
      completedAt,
      exportFormat
    } = req.body;

    if (!id) {
      res.status(400).json({ error: "Event ID is required" });
      return;
    }

    // Prepare update data
    const updateData: any = {
      eventNumber,
      name,
      description,
      location,
      date,
      isActive,
      isCompleted,
      exportFormat,
      updatedAt: new Date().toISOString(),
    };

    // Only set completedAt if provided (can be null to clear it)
    if (completedAt !== undefined) {
      updateData.completedAt = completedAt;
    }

    // Update the event in Firestore
    await db.collection("events").doc(id).update(updateData);

    // Get the updated event data
    const eventDoc = await db.collection("events").doc(id).get();
    if (!eventDoc.exists) {
      res.status(404).json({ error: "Event not found after update" });
      return;
    }

    const eventData = eventDoc.data();
    const updatedEvent = {
      id: eventDoc.id,
      ...eventData,
    };

    console.log(`Event ${id} updated successfully`);
    res.status(200).json(updatedEvent);
  } catch (error) {
    console.error("Error updating event:", error);
    res.status(500).json({ error: "Failed to update event" });
  }
});

// Bulk Delete Scan Records (for admin portal)
export const bulkDeleteScanRecords = functions.runWith({invoker: 'public'}).https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "DELETE, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "DELETE") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  try {
    const { recordIds, eventId } = req.body;

    if (!recordIds || !Array.isArray(recordIds) || recordIds.length === 0) {
      res.status(400).json({ error: "recordIds array is required" });
      return;
    }

    if (!eventId) {
      res.status(400).json({ error: "eventId is required" });
      return;
    }

    console.log(`Bulk deleting ${recordIds.length} scan records for event ${eventId}`);

    let deletedCount = 0;
    const errors = [];

    // Delete each record
    for (const recordId of recordIds) {
      try {
        // Delete from flat structure (scans collection)
        await db.collection("scans").doc(recordId).delete();
        
        // Delete from nested structure (lists collection)
        await db.collection("lists").doc(eventId).collection("scans").doc(recordId).delete();
        
        deletedCount++;
        console.log(`Deleted scan record: ${recordId}`);
      } catch (error) {
        console.error(`Failed to delete record ${recordId}:`, error);
        errors.push({ recordId, error: error.message });
      }
    }

    const response = {
      success: true,
      message: `Successfully deleted ${deletedCount} of ${recordIds.length} records`,
      deletedCount,
      totalRequested: recordIds.length,
      errors: errors.length > 0 ? errors : undefined,
    };

    console.log(`Bulk delete completed: ${deletedCount}/${recordIds.length} records deleted`);
    res.status(200).json(response);
  } catch (error) {
    console.error("Error in bulk delete operation:", error);
    res.status(500).json({ error: "Failed to delete scan records" });
  }
});

