// Entry point. Binds to loopback by default; the Cloudflare Tunnel on the host is the only public path.
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "./app.js";

const here = dirname(fileURLToPath(import.meta.url));
const env = process.env;

const config = {
  host: env.ROOST_HOST || "127.0.0.1",
  port: Number(env.ROOST_PORT || 8790),
  dbPath: env.ROOST_DB || "/var/lib/roost/roost.db",
  choresPath: env.ROOST_CHORES || resolve(here, "../../data/chores.json"),
  tokensPath: env.ROOST_TOKENS || "/etc/roost/tokens.json",
};

const { server, tokens, seeded } = createApp(config);

server.listen(config.port, config.host, () => {
  console.log(
    `${new Date().toISOString()} roost listening on http://${config.host}:${config.port} ` +
      `db=${config.dbPath} chores=${seeded} devices=${tokens.size()}`
  );
});

for (const sig of ["SIGINT", "SIGTERM"]) {
  process.on(sig, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 2000).unref();
  });
}
