// THROWAWAY: loopback-only static demo server; owns and closes its socket.
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve, extname } from "node:path";

const root = dirname(fileURLToPath(import.meta.url));
export async function start(port = 0) {
  const server = createServer(async (req, res) => {
    try {
      const pathname = new URL(req.url, "http://localhost").pathname;
      const file = resolve(root, `.${decodeURIComponent(pathname === "/" ? "/index.html" : pathname)}`);
      if (!file.startsWith(root + "/")) { res.writeHead(403).end(); return; }
      res.setHeader("Content-Type", extname(file) === ".mjs" ? "text/javascript" : "text/html");
      res.end(await readFile(file));
    } catch { res.writeHead(404).end(); }
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "127.0.0.1", resolve);
  });
  return server;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = await start(Number(process.env.PORT || 5175));
  console.log(`Timetravel experiment: http://127.0.0.1:${server.address().port}`);
  for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => server.close());
}
