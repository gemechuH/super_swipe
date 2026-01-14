import admin from "firebase-admin";

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
    throw new Error(`Invalid JSON in env var ${name}: ${e?.message || e}`);
  }
}

async function main() {
  const projectId = requireEnv("FIREBASE_PROJECT_ID");
  const serviceAccount = parseJsonEnv("SERVICE_ACCOUNT_JSON");

  const dryRun =
    String(process.env.DRY_RUN || "false").toLowerCase() === "true";
  const pageSize = Math.min(
    Math.max(parseInt(process.env.PAGE_SIZE || "200", 10) || 200, 1),
    500
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
