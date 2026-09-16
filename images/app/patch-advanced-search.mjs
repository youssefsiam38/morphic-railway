// Build-time patch: close Morphic's /api/advanced-search to the outside.
//
// Upstream's search tool reaches its SearXNG crawler through an HTTP route on the app itself,
// POST /api/advanced-search, and that route checks nothing: anyone on the internet can make the
// instance run searches and crawl pages on their behalf. Only the app's own search tool needs it.
//
// Two edits, each of which must match exactly once or the build fails:
//   1. the search tool sends a per-process token, MORPHIC_RAILWAY_INTERNAL_TOKEN, with its call
//   2. the route answers 404 unless the request carries that token (compared in constant time)
//
// The entrypoint generates the token at start-up; it is never a template variable and never logged.
import { readFileSync, writeFileSync } from "node:fs";

const [, , root] = process.argv;
const die = (m) => {
  process.stderr.write(`patch-advanced-search: ${m}\n`);
  process.exit(1);
};

function patch(rel, pattern, replacement, what) {
  const file = `${root}/${rel}`;
  const src = readFileSync(file, "utf8");
  const found = src.match(new RegExp(pattern.source, "g")) ?? [];
  if (found.length !== 1) die(`expected exactly one ${what} in ${rel}, found ${found.length}`);
  writeFileSync(file, src.replace(pattern, replacement));
}

patch(
  "lib/tools/search.ts",
  /fetch\(`\$\{baseUrl\}\/api\/advanced-search`, \{\s*method: 'POST',\s*headers: \{ 'Content-Type': 'application\/json' \},/,
  "fetch(`${baseUrl}/api/advanced-search`, {\n            method: 'POST',\n            headers: {\n              'Content-Type': 'application/json',\n              'x-morphic-railway-internal': process.env.MORPHIC_RAILWAY_INTERNAL_TOKEN ?? ''\n            },",
  "advanced-search call",
);

patch(
  "app/api/advanced-search/route.ts",
  /export async function POST\(request: Request\) \{\n/,
  `export async function POST(request: Request) {
  {
    const expected = Buffer.from(process.env.MORPHIC_RAILWAY_INTERNAL_TOKEN ?? '')
    const given = Buffer.from(request.headers.get('x-morphic-railway-internal') ?? '')
    const { timingSafeEqual } = await import('node:crypto')
    if (expected.length < 32 || given.length !== expected.length || !timingSafeEqual(given, expected)) {
      return new Response('Not Found', { status: 404 })
    }
  }
`,
  "POST handler",
);

process.stdout.write("patch-advanced-search: /api/advanced-search accepts only the app's own search tool\n");
