'use strict';

/**
 * upload.js — Custom Multer storage engine that streams directly to MinIO.
 *
 * Why a custom engine?
 *   - Standard multer `diskStorage` would write the file to the API container's
 *     local disk first, then we'd need a second pass to upload to MinIO.
 *     For a 1 GB video, this requires 2 GB of scratch space and doubles latency.
 *   - Our custom engine pipes the incoming HTTP stream directly to MinIO via
 *     a PassThrough, so the video never fully lands on disk.
 *
 * Usage:
 *   const { uploadMiddleware } = require('./upload');
 *   router.post('/upload', uploadMiddleware.single('video'), handler);
 *
 *   In the handler, req.file will contain:
 *   { bucket, key, size, mimetype, originalname }
 */

const multer      = require('multer');
const { PassThrough } = require('stream');
const { v4: uuidv4 }  = require('uuid');
const Minio       = require('minio');
const config      = require('../config');
const logger      = require('../logger');

// ── MinIO client (scoped to this module) ────────────────────────────────────
const minioClient = new Minio.Client({
  endPoint:  config.minio.endpoint,
  port:      config.minio.port,
  useSSL:    config.minio.useSSL,
  accessKey: config.minio.accessKey,
  secretKey: config.minio.secretKey,
});

// ── Allowed MIME types ───────────────────────────────────────────────────────
const ALLOWED_MIMES = new Set(['video/mp4', 'video/quicktime', 'video/x-mkvideo',
  'video/x-matroska', 'video/avi', 'video/x-msvideo']);

// ── Custom Multer Storage Engine ─────────────────────────────────────────────
const minioStorage = {
  /**
   * Called by Multer for each file in the upload.
   * We set req._uploadVideoId early so route handlers can reference
   * the video UUID before the upload completes.
   */
  _handleFile(req, file, cb) {
    // Validate MIME before doing anything
    if (!ALLOWED_MIMES.has(file.mimetype)) {
      return cb(new Error(`Unsupported file type: ${file.mimetype}. Only video files are accepted.`));
    }

    const videoId    = req._uploadVideoId ?? (req._uploadVideoId = uuidv4());
    const bucket     = config.minio.buckets.rawUploads;
    const objectKey  = `${videoId}/source.mp4`;

    // PassThrough pipe: HTTP body → MinIO putObject
    const passThrough = new PassThrough();
    let uploadedBytes = 0;

    passThrough.on('data', (chunk) => { uploadedBytes += chunk.length; });

    // MinIO putObject returns an ETag on success
    minioClient.putObject(
      bucket,
      objectKey,
      passThrough,
      { 'Content-Type': 'video/mp4', 'x-amz-meta-originalname': file.originalname }
    ).then((objInfo) => {
      logger.info({ videoId, bucket, objectKey, bytes: uploadedBytes }, 'Upload complete');
      cb(null, {
        bucket,
        key:          objectKey,
        videoId,
        size:         uploadedBytes,
        etag:         objInfo.etag,
        mimetype:     file.mimetype,
        originalname: file.originalname,
      });
    }).catch(cb);

    // Pipe the incoming file stream into MinIO
    file.stream.pipe(passThrough);
  },

  /**
   * Called by Multer if the request fails AFTER the file was partially stored.
   * Clean up the incomplete object from MinIO.
   */
  _removeFile(req, file, cb) {
    minioClient.removeObject(file.bucket, file.key)
      .then(() => cb())
      .catch(cb);
  },
};

// ── Multer instance ───────────────────────────────────────────────────────────
const uploadMiddleware = multer({
  storage: minioStorage,
  limits: {
    fileSize: config.maxUploadBytes,
    files:    1,  // one video per request
  },
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_MIMES.has(file.mimetype)) {
      return cb(new multer.MulterError('LIMIT_UNEXPECTED_FILE', file.fieldname));
    }
    cb(null, true);
  },
});

module.exports = { uploadMiddleware };
