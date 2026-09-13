// Mint a device token and add it to the tokens file.
//   node src/mktoken.js <anne|wes> "<device label>" [tokensPath]
// Prints the token once. It is not stored anywhere else; the server only ever sees its hash in the DB.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { randomBytes } from "node:crypto";

const [person, label, pathArg] = process.argv.slice(2);
const tokensPath = pathArg || process.env.ROOST_TOKENS || "/etc/roost/tokens.json";

if (!["anne", "wes"].includes(person) || !label) {
  console.error('usage: mktoken <anne|wes> "<device label>" [tokensPath]');
  process.exit(2);
}

const current = existsSync(tokensPath) ? JSON.parse(readFileSync(tokensPath, "utf8")) : {};
const token = randomBytes(32).toString("base64url");
current[token] = { person, device: label };
writeFileSync(tokensPath, JSON.stringify(current, null, 2) + "\n", { mode: 0o640 });

console.log(`added ${person} / ${label} to ${tokensPath}`);
console.log(`token (shown once): ${token}`);
