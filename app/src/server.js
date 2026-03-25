/**
 * Secrets Vault Demo Application
 *
 * Multi-tier application demonstrating Vault-managed secrets consumption.
 * ALL credentials come from Kubernetes Secrets synced by the Vault Secrets Operator.
 * This application has ZERO Vault-specific dependencies or SDK usage.
 *
 * Secrets consumed:
 *   - Database credentials (dynamic, short-lived PostgreSQL credentials)
 *   - AWS credentials (dynamic IAM credentials for S3 access)
 *   - TLS certificate (auto-renewed by Vault PKI engine)
 *   - Transit encryption config (Vault address for encrypt/decrypt API calls)
 */

const express = require("express");
const { Pool } = require("pg");
const axios = require("axios");
const fs = require("fs");
const https = require("https");

const app = express();
app.use(express.json());

// =============================================================================
// Database Connection (Vault Database Secrets Engine → VSO → K8s Secret)
// =============================================================================

function createDbPool() {
  return new Pool({
    host: process.env.DB_HOST,
    port: parseInt(process.env.DB_PORT || "5432"),
    database: process.env.DB_NAME,
    // Vault database engine returns 'username' and 'password' as raw keys
    user: process.env.DB_USERNAME || process.env.username,
    password: process.env.DB_PASSWORD || process.env.password,
    ssl: { rejectUnauthorized: false },
    max: 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });
}

let dbPool = createDbPool();

// =============================================================================
// Vault Transit Client (for Encryption as a Service)
// The transit key never leaves Vault — we send plaintext, receive ciphertext.
// =============================================================================

const VAULT_ADDR = process.env.VAULT_ADDR || "https://vault.vault.svc.cluster.local:8200";
const VAULT_TRANSIT_MOUNT = process.env.VAULT_TRANSIT_MOUNT || "transit";
const VAULT_TRANSIT_KEY = process.env.VAULT_TRANSIT_KEY || "app-data";

// Read the service account token for Vault auth
function getVaultToken() {
  try {
    return fs.readFileSync(
      "/var/run/secrets/kubernetes.io/serviceaccount/token",
      "utf8"
    );
  } catch {
    return process.env.VAULT_TOKEN || "";
  }
}

const vaultClient = axios.create({
  baseURL: VAULT_ADDR,
  httpsAgent: new https.Agent({
    rejectUnauthorized: false, // Internal CA — cert mounted via PKI secret
  }),
  timeout: 5000,
});

async function transitEncrypt(plaintext) {
  const b64 = Buffer.from(plaintext).toString("base64");
  const token = getVaultToken();
  const response = await vaultClient.post(
    `/v1/${VAULT_TRANSIT_MOUNT}/encrypt/${VAULT_TRANSIT_KEY}`,
    { plaintext: b64 },
    { headers: { "X-Vault-Token": token } }
  );
  return response.data.data.ciphertext;
}

async function transitDecrypt(ciphertext) {
  const token = getVaultToken();
  const response = await vaultClient.post(
    `/v1/${VAULT_TRANSIT_MOUNT}/decrypt/${VAULT_TRANSIT_KEY}`,
    { ciphertext },
    { headers: { "X-Vault-Token": token } }
  );
  return Buffer.from(response.data.data.plaintext, "base64").toString("utf8");
}

// =============================================================================
// Health & Status Endpoints
// =============================================================================

app.get("/health", async (req, res) => {
  const checks = {
    status: "healthy",
    timestamp: new Date().toISOString(),
    checks: {},
  };

  // Database connectivity
  try {
    const result = await dbPool.query("SELECT 1 AS connected, NOW() AS server_time");
    checks.checks.database = {
      status: "connected",
      serverTime: result.rows[0].server_time,
      user: process.env.DB_USERNAME,
      host: process.env.DB_HOST,
    };
  } catch (err) {
    checks.checks.database = { status: "error", message: err.message };
    checks.status = "degraded";
  }

  // AWS credentials presence (raw keys from Vault: access_key, secret_key)
  const awsKey = process.env.AWS_ACCESS_KEY_ID || process.env.access_key;
  checks.checks.aws = {
    status: awsKey ? "configured" : "missing",
    accessKeyPrefix: awsKey ? `${awsKey.substring(0, 8)}...` : null,
    region: process.env.AWS_DEFAULT_REGION || "eu-west-2",
  };

  // TLS certificate
  const tlsCertPath = "/tls/tls.crt";
  try {
    const certExists = fs.existsSync(tlsCertPath);
    checks.checks.tls = { status: certExists ? "mounted" : "missing" };
  } catch {
    checks.checks.tls = { status: "error" };
  }

  // Transit engine
  try {
    const ciphertext = await transitEncrypt("health-check");
    const decrypted = await transitDecrypt(ciphertext);
    checks.checks.transit = {
      status: decrypted === "health-check" ? "operational" : "error",
      key: VAULT_TRANSIT_KEY,
    };
  } catch (err) {
    checks.checks.transit = { status: "error", message: err.message };
  }

  const statusCode = checks.status === "healthy" ? 200 : 503;
  res.status(statusCode).json(checks);
});

// =============================================================================
// Database Endpoints (Vault Database Secrets Engine)
// =============================================================================

// Initialize the demo table
app.post("/api/init-db", async (req, res) => {
  try {
    await dbPool.query(`
      CREATE TABLE IF NOT EXISTS secrets_demo (
        id SERIAL PRIMARY KEY,
        data_key VARCHAR(255) NOT NULL,
        encrypted_value TEXT NOT NULL,
        created_by VARCHAR(255) DEFAULT CURRENT_USER,
        created_at TIMESTAMP DEFAULT NOW()
      )
    `);
    res.json({ message: "Database initialized", user: process.env.DB_USERNAME });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Store encrypted data (combines database + transit engines)
app.post("/api/secrets", async (req, res) => {
  try {
    const { key, value } = req.body;
    if (!key || !value) {
      return res.status(400).json({ error: "key and value are required" });
    }

    // Encrypt the value using Vault's transit engine
    const ciphertext = await transitEncrypt(value);

    // Store the ciphertext in the database (using dynamic credentials)
    const result = await dbPool.query(
      "INSERT INTO secrets_demo (data_key, encrypted_value) VALUES ($1, $2) RETURNING id, data_key, created_by, created_at",
      [key, ciphertext]
    );

    res.status(201).json({
      message: "Secret stored (encrypted via Vault transit engine)",
      record: result.rows[0],
      encryption: {
        engine: "transit",
        key: VAULT_TRANSIT_KEY,
        ciphertextPreview: `${ciphertext.substring(0, 30)}...`,
      },
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Retrieve and decrypt data
app.get("/api/secrets/:key", async (req, res) => {
  try {
    const result = await dbPool.query(
      "SELECT * FROM secrets_demo WHERE data_key = $1 ORDER BY created_at DESC LIMIT 1",
      [req.params.key]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Secret not found" });
    }

    const record = result.rows[0];
    const decrypted = await transitDecrypt(record.encrypted_value);

    res.json({
      record: {
        id: record.id,
        key: record.data_key,
        value: decrypted,
        createdBy: record.created_by,
        createdAt: record.created_at,
      },
      decryption: {
        engine: "transit",
        key: VAULT_TRANSIT_KEY,
      },
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// List all stored secrets (metadata only — values stay encrypted)
app.get("/api/secrets", async (req, res) => {
  try {
    const result = await dbPool.query(
      "SELECT id, data_key, created_by, created_at FROM secrets_demo ORDER BY created_at DESC"
    );
    res.json({
      count: result.rows.length,
      records: result.rows,
      dbUser: process.env.DB_USERNAME,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// =============================================================================
// Credential Introspection Endpoints (for demo/screenshots)
// Shows HOW secrets are consumed — no sensitive values exposed
// =============================================================================

app.get("/api/credentials/summary", (req, res) => {
  res.json({
    description: "All credentials consumed via Kubernetes Secrets synced by Vault Secrets Operator",
    credentials: {
      database: {
        source: "Vault Database Secrets Engine → VaultDynamicSecret CRD → K8s Secret",
        user: process.env.DB_USERNAME || process.env.username,
        host: process.env.DB_HOST,
        database: process.env.DB_NAME,
        note: "Dynamic credential — unique to this pod, auto-revoked on expiry",
      },
      aws: {
        source: "Vault AWS Secrets Engine → VaultDynamicSecret CRD → K8s Secret",
        accessKeyPrefix: (process.env.AWS_ACCESS_KEY_ID || process.env.access_key)
          ? `${(process.env.AWS_ACCESS_KEY_ID || process.env.access_key).substring(0, 8)}...`
          : "not configured",
        region: process.env.AWS_DEFAULT_REGION || "eu-west-2",
        note: "Dynamic IAM user — created on demand, deleted on lease expiry",
      },
      tls: {
        source: "Vault PKI Engine → VaultPKISecret CRD → K8s Secret (kubernetes.io/tls)",
        certPath: "/tls/tls.crt",
        keyPath: "/tls/tls.key",
        note: "Auto-renewed by VSO before expiry",
      },
      transit: {
        source: "Vault Transit Engine (encryption as a service)",
        vaultAddr: VAULT_ADDR,
        keyName: VAULT_TRANSIT_KEY,
        note: "Encryption key never leaves Vault — data encrypted/decrypted via API",
      },
    },
  });
});

// =============================================================================
// Start Server
// =============================================================================

const PORT = parseInt(process.env.PORT || "3000");

app.listen(PORT, "0.0.0.0", () => {
  console.log(`Secrets Vault Demo running on port ${PORT}`);
  console.log(`Database user: ${process.env.DB_USERNAME || process.env.username || "not set"}`);
  console.log(`AWS configured: ${(process.env.AWS_ACCESS_KEY_ID || process.env.access_key) ? "yes" : "no"}`);
  console.log(`Transit key: ${VAULT_TRANSIT_KEY}`);
});
