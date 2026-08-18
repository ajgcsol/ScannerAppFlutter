"use strict";

const { DefaultAzureCredential } = require("@azure/identity");

// Sends as the shared noreply mailbox via Microsoft Graph. Auth is the
// Function App's managed identity, which holds the Mail.Send app role —
// no secrets in configuration.
const SENDER = process.env.NOREPLY_SENDER || "noreply@charlestonlaw.edu";

// Kill switch: emails only go out when explicitly enabled, so a misconfigured
// deploy can never spray students.
const ENABLED = process.env.ATTENDANCE_EMAILS_ENABLED === "true";

let credential;
function getCredential() {
  if (!credential) credential = new DefaultAzureCredential();
  return credential;
}

async function graphToken() {
  const token = await getCredential().getToken(
    "https://graph.microsoft.com/.default"
  );
  return token.token;
}

/**
 * Sends the attendance confirmation. Throws on failure so the queue trigger's
 * retry/poison handling applies.
 */
async function sendAttendanceEmail({ to, firstName, eventName, eventDate }) {
  if (!ENABLED) {
    return { skipped: true, reason: "ATTENDANCE_EMAILS_ENABLED is not 'true'" };
  }

  const dateText = eventDate
    ? new Date(eventDate).toLocaleDateString("en-US", {
        weekday: "long",
        year: "numeric",
        month: "long",
        day: "numeric",
        timeZone: "America/New_York",
      })
    : "";

  const body = [
    `Dear ${firstName},`,
    ``,
    `This confirms that you have been marked as attending ${eventName}` +
      (dateText ? ` on ${dateText}` : "") +
      `.`,
    ``,
    `Your event attendance in SONIS will be updated within the next 72 hours ` +
      `to reflect your attendance at this event.`,
    ``,
    `This is an automated message; replies to this address are not monitored. ` +
      `If you believe you received this in error, please contact Student ` +
      `Affairs at StudentAffairs@charlestonlaw.edu.`,
    ``,
    `Charleston School of Law`,
  ].join("\n");

  const message = {
    message: {
      subject: `Attendance recorded: ${eventName}`,
      body: { contentType: "Text", content: body },
      toRecipients: [{ emailAddress: { address: to } }],
    },
    saveToSentItems: false,
  };

  const res = await fetch(
    `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(SENDER)}/sendMail`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await graphToken()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(message),
    }
  );

  // Graph returns 202 on success.
  if (res.status !== 202) {
    const detail = await res.text();
    throw new Error(`Graph sendMail failed ${res.status}: ${detail.slice(0, 300)}`);
  }
  return { sent: true, to };
}

/**
 * Emails an event's scan list to staff (e.g. an Admissions team mailing the
 * day's prospect list to themselves). Independent of the student-facing
 * ATTENDANCE_EMAILS_ENABLED kill switch — this is staff-requested reporting.
 */
async function sendEventReport({ to, eventName, eventDate, csv, count, requestedBy }) {
  const dateText = eventDate
    ? new Date(eventDate).toLocaleDateString("en-US", {
        year: "numeric", month: "long", day: "numeric", timeZone: "America/New_York",
      })
    : "";
  const body = [
    `Attached is the scan list for ${eventName}${dateText ? ` (${dateText})` : ""}.`,
    ``,
    `Total scans: ${count}`,
    `Requested by: ${requestedBy}`,
    ``,
    `Charleston School of Law — inSession`,
  ].join("\n");

  const message = {
    message: {
      subject: `Scan list: ${eventName} (${count} scans)`,
      body: { contentType: "Text", content: body },
      toRecipients: to.map((address) => ({ emailAddress: { address } })),
      attachments: [{
        "@odata.type": "#microsoft.graph.fileAttachment",
        name: `${eventName.replace(/[^A-Za-z0-9 _-]/g, "")}_scans.csv`,
        contentType: "text/csv",
        contentBytes: Buffer.from(csv, "utf8").toString("base64"),
      }],
    },
    saveToSentItems: false,
  };

  const res = await fetch(
    `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(SENDER)}/sendMail`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${await graphToken()}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(message),
    }
  );
  if (res.status !== 202) {
    const detail = await res.text();
    throw new Error(`Graph sendMail failed ${res.status}: ${detail.slice(0, 300)}`);
  }
  return { sent: true, to };
}

module.exports = { sendAttendanceEmail, sendEventReport, SENDER, ENABLED };
