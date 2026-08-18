"use strict";

const {
  BlobServiceClient,
  StorageSharedKeyCredential,
  generateBlobSASQueryParameters,
  BlobSASPermissions,
  SASProtocol,
} = require("@azure/storage-blob");

const CONTAINER = process.env.PHOTOS_CONTAINER || "student-photos";

// Firebase signed URLs were issued with an absurd expiry (03-09-2491) so the
// admin portal could cache them indefinitely. SAS tokens can't run that long
// safely, so photo URLs are minted with a bounded lifetime and refreshed by
// checkStudentPhotos. Default: 7 days.
const SAS_TTL_DAYS = Number(process.env.PHOTO_SAS_TTL_DAYS || 7);

let service;
let sharedKey;

function getService() {
  if (service) return service;

  const connectionString = process.env.STORAGE_CONNECTION_STRING;
  if (!connectionString) {
    throw new Error("Set STORAGE_CONNECTION_STRING");
  }
  service = BlobServiceClient.fromConnectionString(connectionString);

  // Pull the account key out of the connection string so we can sign SAS URLs.
  const account = /AccountName=([^;]+)/.exec(connectionString);
  const key = /AccountKey=([^;]+)/.exec(connectionString);
  if (account && key) {
    sharedKey = new StorageSharedKeyCredential(account[1], key[1]);
  }
  return service;
}

const containerClient = () => getService().getContainerClient(CONTAINER);

async function photoExists(fileName) {
  return containerClient().getBlockBlobClient(fileName).exists();
}

// The ID-card system exports a mix of .jpg and .png, so a photo can't be
// located by assuming one extension. Order matters only for the unlikely case
// of a student having more than one.
const PHOTO_EXTENSIONS = ["jpg", "png", "jpeg", "webp"];

/**
 * Finds a student's photo regardless of stored extension.
 * Returns the blob name, or null when the student has no photo.
 */
async function findPhoto(studentId) {
  for (const ext of PHOTO_EXTENSIONS) {
    const name = `${studentId}-photo.${ext}`;
    if (await photoExists(name)) return name;
  }
  return null;
}

// Equivalent of file.getSignedUrl({action: "read"}).
function photoUrl(fileName) {
  const blob = containerClient().getBlockBlobClient(fileName);
  if (!sharedKey) return blob.url;

  const expiresOn = new Date(Date.now() + SAS_TTL_DAYS * 86400 * 1000);
  const sas = generateBlobSASQueryParameters(
    {
      containerName: CONTAINER,
      blobName: fileName,
      permissions: BlobSASPermissions.parse("r"),
      protocol: SASProtocol.Https,
      startsOn: new Date(Date.now() - 5 * 60 * 1000),
      expiresOn,
    },
    sharedKey
  ).toString();

  return `${blob.url}?${sas}`;
}

async function ensureContainer() {
  await containerClient().createIfNotExists();
}

async function uploadPhoto(fileName, buffer, contentType = "image/jpeg") {
  await ensureContainer();
  const blob = containerClient().getBlockBlobClient(fileName);
  await blob.uploadData(buffer, {
    blobHTTPHeaders: { blobContentType: contentType },
  });
  return photoUrl(fileName);
}

module.exports = {
  CONTAINER,
  PHOTO_EXTENSIONS,
  photoExists,
  findPhoto,
  photoUrl,
  ensureContainer,
  uploadPhoto,
  containerClient,
};
