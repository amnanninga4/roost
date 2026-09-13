// Mint a short-lived pairing code and print it. The phone types the code into the app, which POSTs it to
// /pair and gets a real bearer token back; the token stays the long-lived credential, the code does not.
//   node src/mkcode.js <anne|wes> "<device label>" [--minutes 15]
// ROOST_DB picks the database (default /var/lib/roost/roost.db). src/mktoken.js is the fallback for
// handing over a token directly.
import { openDb, PEOPLE } from "./db.js";
import { createPairingCode, DEFAULT_MINUTES } from "./pairing.js";

const MINUTES = "--minutes";
const args = process.argv.slice(2);
const positional = [];
let minutes = DEFAULT_MINUTES;

for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === MINUTES) minutes = Number(args[++i]);
  else if (a.startsWith(`${MINUTES}=`)) minutes = Number(a.slice(MINUTES.length + 1));
  else positional.push(a);
}

const [person, label] = positional;
if (!PEOPLE.includes(person) || !label || !Number.isInteger(minutes) || minutes < 1) {
  console.error(`usage: mkcode <${PEOPLE.join("|")}> "<device label>" [${MINUTES} ${DEFAULT_MINUTES}]`);
  process.exit(2);
}

const db = openDb(process.env.ROOST_DB || "/var/lib/roost/roost.db");
const row = createPairingCode(db, { person, deviceLabel: label, minutes }, new Date().toISOString());
db.close();

console.log(`pairing code for ${person} / ${label}: ${row.code}`);
console.log(`expires ${row.expiresAt} (${minutes} min); it works once`);
