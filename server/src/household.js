// Household meta helpers for the live DB.
//   node src/household.js active-from              print current (or default) date
//   node src/household.js active-from YYYY-MM-DD   set explicitly
// ROOST_DB picks the database (default /var/lib/roost/roost.db). Run as the roost user, never as root:
// root-owned roost.db-wal / -shm would stall the service.
import { openDb, getMeta, setMeta } from "./db.js";
import { chicagoDateString, DEFAULT_ACTIVE_FROM, parseActiveFrom } from "./rules.js";

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

const [command, dateArg] = process.argv.slice(2);
const dbPath = process.env.ROOST_DB || "/var/lib/roost/roost.db";

if (command !== "active-from") {
  console.error("usage: household active-from [YYYY-MM-DD]");
  process.exit(2);
}

if (dateArg != null && !DATE_RE.test(dateArg)) {
  console.error("active-from date must be YYYY-MM-DD (Chicago calendar)");
  process.exit(2);
}

const db = openDb(dbPath);

if (dateArg) {
  // Validate it parses as a real Chicago calendar day, then store the string as given.
  parseActiveFrom(dateArg);
  setMeta(db, "activeFrom", dateArg);
  console.log(`activeFrom set to ${dateArg}`);
} else {
  const meta = getMeta(db, "activeFrom");
  const value = meta ?? chicagoDateString(DEFAULT_ACTIVE_FROM);
  const source = meta ? "meta" : "default";
  console.log(`activeFrom: ${value} (${source})`);
}

db.close();
