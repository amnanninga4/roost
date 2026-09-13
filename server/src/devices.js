// What can authenticate, and how to cut one off from the shell. Both sources in one list: tokens
// hand-minted into the tokens file (mktoken.js) and tokens minted by POST /pair (the paired_tokens
// table). A lost phone is revoked here without editing a file or restarting the API.
//   node src/devices.js list
//   node src/devices.js revoke <hashPrefix>      paired tokens only
// ROOST_DB picks the database, ROOST_TOKENS the tokens file. Run as the roost user, never as root:
// root-owned roost.db-wal / -shm would stall the service.
import { existsSync, readFileSync } from "node:fs";
import { openDb } from "./db.js";
import { parseTokens } from "./auth.js";
import { listPairedTokens, revokePairedToken } from "./pairing.js";

const PREFIX_MIN = 4; // shorter than this is not a device, it is a wildcard
const PREFIX_SHOWN = 8;

const [command, prefixArg] = process.argv.slice(2);
const dbPath = process.env.ROOST_DB || "/var/lib/roost/roost.db";
const tokensPath = process.env.ROOST_TOKENS || "/etc/roost/tokens.json";

if (!["list", "revoke"].includes(command) || (command === "revoke" && !prefixArg)) {
  console.error("usage: devices list | devices revoke <hashPrefix>");
  process.exit(2);
}

const db = openDb(dbPath);
const lastSeenOf = (tokenHash) =>
  db.prepare("SELECT lastSeen FROM devices WHERE tokenHash = ?").get(tokenHash)?.lastSeen ?? null;

/** File tokens as { tokenHash, person, label }. An unreadable file is reported, not fatal. */
function fileDevices() {
  if (!existsSync(tokensPath)) return [];
  try {
    return [...parseTokens(readFileSync(tokensPath, "utf8"))].map(([tokenHash, info]) => ({ tokenHash, ...info }));
  } catch (err) {
    console.error(`tokens file ${tokensPath} not readable as tokens: ${err.message}`);
    return [];
  }
}

/** One list, newest paired first, then the file entries. `source` is what can revoke it. */
function everyDevice() {
  const paired = listPairedTokens(db).map((r) => ({
    source: r.revokedAt ? "revoked" : "paired",
    tokenHash: r.tokenHash,
    person: r.person,
    label: r.label,
    lastSeen: r.lastSeen ?? null,
  }));
  const file = fileDevices().map((d) => ({
    source: "file",
    tokenHash: d.tokenHash,
    person: d.person,
    label: d.label,
    lastSeen: lastSeenOf(d.tokenHash),
  }));
  return [...paired, ...file];
}

if (command === "list") {
  const rows = everyDevice();
  if (rows.length === 0) {
    console.log("no devices: nothing in the tokens file and nothing paired");
  } else {
    const pad = (s, n) => String(s).padEnd(n);
    const labelWidth = Math.max(5, ...rows.map((r) => r.label.length));
    console.log(`${pad("source", 8)}${pad("hash", PREFIX_SHOWN + 2)}${pad("person", 7)}${pad("label", labelWidth + 2)}lastSeen`);
    for (const r of rows) {
      console.log(
        `${pad(r.source, 8)}${pad(r.tokenHash.slice(0, PREFIX_SHOWN), PREFIX_SHOWN + 2)}${pad(r.person, 7)}` +
          `${pad(r.label, labelWidth + 2)}${r.lastSeen ?? "never"}`
      );
    }
    console.log(`\nrevoke a paired device: devices revoke <hashPrefix>`);
    console.log(`a file device is revoked by deleting its line from ${tokensPath}`);
  }
  db.close();
  process.exit(0);
}

const prefix = prefixArg.trim().toLowerCase();
if (prefix.length < PREFIX_MIN || !/^[0-9a-f]+$/.test(prefix)) {
  console.error(`hash prefix must be at least ${PREFIX_MIN} hex characters`);
  db.close();
  process.exit(2);
}

const matches = everyDevice().filter((d) => d.tokenHash.startsWith(prefix));
if (matches.length === 0) {
  console.error(`no device whose token hash starts with ${prefix}`);
  db.close();
  process.exit(1);
}
if (matches.length > 1) {
  console.error(`${matches.length} devices start with ${prefix}; use a longer prefix`);
  db.close();
  process.exit(1);
}

const [device] = matches;
if (device.source === "file") {
  console.error(`${device.person} / ${device.label} was set up by hand; remove its line from ${tokensPath}`);
  db.close();
  process.exit(1);
}

const revoked = revokePairedToken(db, device.tokenHash, new Date().toISOString());
db.close();
console.log(
  revoked
    ? `revoked ${device.person} / ${device.label}; its next request is a 401`
    : `${device.person} / ${device.label} was already revoked`
);
