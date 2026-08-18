"use strict";

// Azure Functions v4 discovers handlers by loading this entry point, which
// registers every endpoint. host.json clears the route prefix, so the paths
// match the old Cloud Functions URLs exactly (/getEvents, /addScanRecord, ...)
// and only the host name changes for the clients.
require("./functions/events");
require("./functions/students");
require("./functions/scans");
require("./functions/photos");
require("./functions/import");
require("./functions/dataApi");
require("./functions/attendanceEmail");
require("./functions/access");
require("./functions/reports");
require("./functions/health");
