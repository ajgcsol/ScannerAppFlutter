"use strict";

const { app } = require("@azure/functions");
const { sendAttendanceEmail } = require("../lib/email");
const { QUEUE_NAME } = require("../lib/emailQueue");

// Drains the attendance-email queue. The Functions runtime retries failed
// messages (dequeueCount) and shelves persistent failures onto the poison
// queue, so a Graph outage delays notifications rather than losing them.
app.storageQueue("attendanceEmail", {
  queueName: QUEUE_NAME,
  connection: "STORAGE_CONNECTION_STRING",
  handler: async (message, context) => {
    const { to, firstName, eventName, eventDate, scanId } = message || {};

    if (!to || !eventName) {
      // Malformed message — log and swallow; retrying can never fix it.
      context.error(`attendanceEmail: malformed message, dropping`, message);
      return;
    }

    const result = await sendAttendanceEmail({ to, firstName, eventName, eventDate });
    if (result.skipped) {
      context.log(`attendanceEmail: skipped for scan ${scanId}: ${result.reason}`);
    } else {
      context.log(`attendanceEmail: sent to ${to} for "${eventName}" (scan ${scanId})`);
    }
  },
});
