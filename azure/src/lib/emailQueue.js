"use strict";

const { QueueClient } = require("@azure/storage-queue");

const QUEUE_NAME = "attendance-emails";

let client;
function getQueue() {
  if (!client) {
    client = new QueueClient(
      process.env.STORAGE_CONNECTION_STRING,
      QUEUE_NAME
    );
  }
  return client;
}

/**
 * Enqueues an attendance email. Fire-and-forget from the scan path: any
 * failure here is logged by the caller and never affects the scan itself.
 * The Functions queue trigger expects base64-encoded message bodies.
 */
async function enqueueAttendanceEmail(payload) {
  const queue = getQueue();
  await queue.createIfNotExists();
  await queue.sendMessage(
    Buffer.from(JSON.stringify(payload)).toString("base64")
  );
}

module.exports = { enqueueAttendanceEmail, QUEUE_NAME };
