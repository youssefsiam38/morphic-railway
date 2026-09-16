// Create the Morphic owner account before the app listens.
//
// Morphic has no first-run step: whoever signs up first simply has an account, and the signup gate
// (gate.sql) refuses everyone who is not allowed. The owner is created here, through Supabase Auth's
// admin API over the private network, carrying the one-time nonce the gate admits.
//
// The claim is "an account with OWNER_EMAIL exists", not "any account exists", so an allowlisted
// account can never stop the owner from being created. Once it exists this exits without touching it,
// so a redeploy never undoes a password change. RECOVERY: a new OWNER_PASSWORD with
// MORPHIC_RESET_OWNER_PASSWORD=true.
//
// Secrets come from the environment and are never printed; the e-mail is masked.

const BASE = (process.env.SUPABASE_INTERNAL_URL ?? "").replace(/\/+$/, "");
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
const EMAIL = (process.env.OWNER_EMAIL ?? "").trim().toLowerCase();
const PASSWORD = process.env.OWNER_PASSWORD ?? "";
const NONCE = process.env.MORPHIC_BOOTSTRAP_NONCE ?? "";

const log = (m) => process.stdout.write(`[morphic-bootstrap] ${m}\n`);
const warn = (m) => process.stderr.write(`[morphic-bootstrap] WARNING: ${m}\n`);
const die = (m) => {
  process.stderr.write(`[morphic-bootstrap] FATAL: ${m}\n`);
  process.exit(1);
};
const masked = EMAIL.replace(/^(.).*(@.*)$/, "$1***$2");

if (!BASE || !SERVICE) die("SUPABASE_INTERNAL_URL and SUPABASE_SERVICE_ROLE_KEY are required");
if (!EMAIL || !PASSWORD) die("OWNER_EMAIL and OWNER_PASSWORD are required");
if (!/^[0-9a-f]{64}$/.test(NONCE)) die("MORPHIC_BOOTSTRAP_NONCE is missing; the entrypoint registers it");

async function call(method, path, body) {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { apikey: SERVICE, Authorization: `Bearer ${SERVICE}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  if (!res.ok) {
    const code = json && (json.code || json.error_code || json.error) ? ` (${json.code || json.error_code || json.error})` : "";
    throw new Error(`${method} ${path.split("?")[0]} -> HTTP ${res.status}${code}`);
  }
  return json;
}

async function findUserByEmail(email) {
  for (let page = 1; page <= 50; page++) {
    const data = await call("GET", `/auth/v1/admin/users?page=${page}&per_page=200`);
    const users = (data && data.users) || [];
    const hit = users.find((u) => (u.email ?? "").toLowerCase() === email);
    if (hit) return hit;
    if (users.length < 200) return null;
  }
  return null;
}

try {
  const existing = await findUserByEmail(EMAIL);
  if (existing) {
    if ((process.env.MORPHIC_RESET_OWNER_PASSWORD ?? "").trim() === "true") {
      await call("PUT", `/auth/v1/admin/users/${existing.id}`, { password: PASSWORD });
      warn("owner password reset from OWNER_PASSWORD. Remove MORPHIC_RESET_OWNER_PASSWORD now, or every redeploy will reset it again.");
    } else {
      log("owner account exists from an earlier start; leaving it alone");
    }
    process.exit(0);
  }
  const user = await call("POST", "/auth/v1/admin/users", {
    email: EMAIL,
    password: PASSWORD,
    email_confirm: true,
    user_metadata: { morphic_railway_bootstrap_nonce: NONCE },
  });
  if (!user || !user.id) die("Supabase Auth did not return the new owner");
  log(`owner account created for ${masked}`);
} catch (err) {
  die(err.message);
}
