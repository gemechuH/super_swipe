import admin from "firebase-admin";

function looksLikeBase64(value) {
  // Very small heuristic: base64 payloads are typically long and only contain base64 chars.
  // This avoids breaking normal JSON.
  return (
    typeof value === "string" &&
    value.length > 200 &&
    /^[A-Za-z0-9+/=\r\n]+$/.test(value) &&
    !value.trim().startsWith("{")
  );
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

function parseJsonEnv(name) {
  const raw = requireEnv(name);
  try {
    return JSON.parse(raw);
  } catch (e) {
    // Some users prefer storing the service account JSON as base64 to avoid formatting issues.
    // If JSON parsing fails and it looks like base64, try decode+parse.
    if (looksLikeBase64(raw)) {
      try {
        const decoded = Buffer.from(raw, "base64").toString("utf8");
        return JSON.parse(decoded);
      } catch (e2) {
        throw new Error(
          `Invalid JSON in env var ${name} (base64 decode attempted): ${e2?.message || e2}`
        );
      }
    }

    throw new Error(`Invalid JSON in env var ${name}: ${e?.message || e}`);
  }
}

function normalizeServiceAccount(sa) {
  if (!sa || typeof sa !== "object") return sa;

  // If the private key ended up with literal "\\n" sequences, normalize it.
  if (typeof sa.private_key === "string" && sa.private_key.includes("\\n")) {
    sa.private_key = sa.private_key.replace(/\\n/g, "\n");
  }

  return sa;
}

async function main() {
  const projectId = requireEnv("FIREBASE_PROJECT_ID");
  const serviceAccount = normalizeServiceAccount(
    parseJsonEnv("SERVICE_ACCOUNT_JSON")
  );

  const dryRun =
    String(process.env.DRY_RUN || "false").toLowerCase() === "true";
  const pageSize = Math.min(
    Math.max(parseInt(process.env.PAGE_SIZE || "200", 10) || 200, 1),
    500
  );

  // Safe diagnostics (no secrets printed)
  console.log(
    `Config: projectId=${projectId} dryRun=${dryRun} pageSize=${pageSize}`
  );
  console.log(
    `ServiceAccount: type=${serviceAccount?.type || "?"} project_id=${
      serviceAccount?.project_id || "?"
    } has_private_key=${Boolean(serviceAccount?.private_key)}`
  );

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId,
  });

  const db = admin.firestore();

  let scannedUsers = 0;
  let eligibleUsers = 0;
  let updatedUsers = 0;
  let lastDoc = null;

  console.log(
    `Weekly carrot reset starting. dryRun=${dryRun} pageSize=${pageSize}`
  );

  // Paginate by documentId for stable full-table scan.
  while (true) {
    let query = db
      .collection("users")
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(pageSize);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snap = await query.get();
    if (snap.empty) break;

    scannedUsers += snap.size;

    // 2 writes per eligible user: user update + tx log.
    let batch = db.batch();
    let opsInBatch = 0;

    for (const doc of snap.docs) {
      lastDoc = doc;

      const data = doc.data() || {};
      const subscriptionStatus = String(
        data.subscriptionStatus || "free"
      ).toLowerCase();
      const isPremium = subscriptionStatus === "premium";
      if (isPremium) continue;

      const carrots =
        data.carrots && typeof data.carrots === "object" ? data.carrots : {};
      const max = Number.isFinite(carrots.max) ? Math.trunc(carrots.max) : 5;

      eligibleUsers += 1;

      if (dryRun) continue;

      const userRef = doc.ref;
      const txRef = userRef.collection("transactions").doc();

      batch.update(userRef, {
        "carrots.current": max,
        "carrots.lastResetAt": admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      batch.set(txRef, {
        type: "reset",
        amount: max,
        balanceAfter: max,
        description: "Weekly carrot refresh",
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });

      opsInBatch += 2;
      updatedUsers += 1;

      // Firestore batches are limited to 500 operations.
      if (opsInBatch >= 450) {
        await batch.commit();
        batch = db.batch();
        opsInBatch = 0;
      }
    }

    if (!dryRun && opsInBatch > 0) {
      await batch.commit();
    }

    console.log(
      `Progress: scanned=${scannedUsers} eligible=${eligibleUsers} updated=${updatedUsers}`
    );
  }

  console.log(
    `Done. scanned=${scannedUsers} eligible=${eligibleUsers} updated=${updatedUsers} dryRun=${dryRun}`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
