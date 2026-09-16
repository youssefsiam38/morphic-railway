// Database steps for the Morphic app wrapper, run with node. They use the `postgres` client Morphic
// itself depends on, from the app's node_modules.
//
//   wait <url-var>                    exit 0 once the database in that variable answers
//   ensure-database                   create DATABASE_URL's database if it does not exist yet
//   apply <file.sql>                  run a SQL file in the Supabase database (SUPABASE_DB_URL)
//   nonce-set <sha256> | nonce-clear  the bootstrap nonce's hash for the signup gate
//   signup-policy                     write MORPHIC_SIGNUP_MODE and MORPHIC_ALLOWED_SIGNUPS
//
// Nothing here prints a connection string or a secret.
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";

const require = createRequire("/app/package.json");
const pgModule = require("postgres");
const postgres = pgModule.default ?? pgModule;

const [cmd, arg] = process.argv.slice(2);
const connect = (url) => postgres(url, { max: 1, connect_timeout: 5, onnotice: () => {}, ssl: false });
const fail = (m) => {
  process.stderr.write(`[morphic-app] FATAL: ${m}\n`);
  process.exit(1);
};

let sql;
try {
  switch (cmd) {
    case "wait":
      sql = connect(process.env[arg]);
      await sql`select 1`;
      break;
    case "ensure-database": {
      const name = decodeURIComponent(new URL(process.env.DATABASE_URL).pathname.replace(/^\//, ""));
      if (!/^[a-z_][a-z0-9_]{0,62}$/.test(name)) fail("DATABASE_URL must name a database made of lower-case letters, digits and underscores");
      sql = connect(process.env.SUPABASE_DB_URL);
      const [{ exists }] = await sql`select exists (select 1 from pg_database where datname = ${name}) as exists`;
      if (!exists) {
        await sql.unsafe(`create database "${name}"`);
        process.stdout.write(`[morphic-app] created the ${name} database\n`);
      }
      break;
    }
    case "apply":
      sql = connect(process.env.SUPABASE_DB_URL);
      await sql.unsafe(readFileSync(arg, "utf8"));
      break;
    case "nonce-set":
      sql = connect(process.env.SUPABASE_DB_URL);
      await sql`insert into morphic_railway.settings (key, value) values ('bootstrap_nonce_sha256', ${arg})
                on conflict (key) do update set value = excluded.value, updated_at = now()`;
      break;
    case "nonce-clear":
      sql = connect(process.env.SUPABASE_DB_URL);
      await sql`delete from morphic_railway.settings where key = 'bootstrap_nonce_sha256'`;
      break;
    case "signup-policy": {
      const mode = process.env.MORPHIC_SIGNUP_MODE ?? "closed";
      if (!["closed", "open"].includes(mode)) fail("MORPHIC_SIGNUP_MODE must be closed or open");
      const entries = [...new Set(
        (process.env.MORPHIC_ALLOWED_SIGNUPS ?? "").split(/[\s,]+/).map((e) => e.trim().toLowerCase()).filter(Boolean),
      )];
      for (const e of entries) {
        if (!/^[^@\s]*@[^@\s]+$/.test(e)) fail(`MORPHIC_ALLOWED_SIGNUPS: "${e}" is neither an e-mail address nor @domain`);
      }
      sql = connect(process.env.SUPABASE_DB_URL);
      await sql.begin(async (tx) => {
        await tx`insert into morphic_railway.settings (key, value) values ('signup_mode', ${mode})
                 on conflict (key) do update set value = excluded.value, updated_at = now()`;
        await tx`delete from morphic_railway.signup_allowlist`;
        for (const e of entries) await tx`insert into morphic_railway.signup_allowlist (entry) values (${e})`;
      });
      process.stdout.write(`[morphic-app] signup: ${mode}, ${entries.length} allowlist entr${entries.length === 1 ? "y" : "ies"}\n`);
      break;
    }
    default:
      fail(`unknown command: ${cmd}`);
  }
} catch (err) {
  if (cmd !== "wait") process.stderr.write(`[morphic-app] database step "${cmd}" failed: ${err.code ?? ""} ${err.message}\n`);
  process.exitCode = 1;
} finally {
  if (sql) await sql.end({ timeout: 5 });
}
