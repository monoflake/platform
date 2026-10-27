/*** What workerd gives a Worker, stood in for where node gives nothing alike. */

/** A binding as workerd gives one, every name read on it a function, `fetch` answering. */
let everyName: unit => Stores.env = %raw(`() => ({
  HOSTS: new Proxy({}, {
    get: (_, name) => name === "fetch" ? async () => new Response("through") : () => undefined,
  }),
})`)

// The Worker is bundled through its own Wrangler configuration before its exports are read.
let bundled: unit => promise<Worker.worker> = %raw(`async () => {
  const {execFileSync} = await import("node:child_process")
  const {mkdtempSync, readdirSync, rmSync} = await import("node:fs")
  const {tmpdir} = await import("node:os")
  const {join} = await import("node:path")
  const {fileURLToPath, pathToFileURL} = await import("node:url")
  const block = fileURLToPath(new URL("../../", import.meta.url))
  const scratch = mkdtempSync(join(tmpdir(), "worker-bundle-"))
  try {
    execFileSync(process.execPath, [
      join(block, "node_modules/wrangler/bin/wrangler.js"),
      "deploy", "--dry-run", "--config", join(block, "wrangler.json"), "--outdir", scratch,
    ], {
      cwd: block,
      timeout: 30000,
      env: {...process.env, CI: "1", WRANGLER_SEND_METRICS: "false",
        WRANGLER_SEND_ERROR_REPORTS: "false", WRANGLER_HIDE_BANNER: "true",
        WRANGLER_LOG_PATH: join(scratch, "wrangler.log")},
      stdio: ["ignore", "pipe", "pipe"],
    })
    const files = readdirSync(scratch).filter(name => name.endsWith(".js"))
    if (files.length !== 1) throw new Error("expected one bundled Worker")
    const loaded = await import(pathToFileURL(join(scratch, files[0])).href)
    if (typeof loaded.default?.fetch !== "function") throw new Error("Worker has no fetch handler")
    for (const [name, value] of Object.entries(loaded)) {
      if (value == null) throw new Error("Worker exports an undefined entrypoint " + name)
    }
    return loaded.default
  } finally {
    rmSync(scratch, {recursive: true, force: true})
  }
}`)
