open Node

let write = (directory, name, content) =>
  Host.writeBytes(Host.join([directory, name]), Bytes.utf8(content))

let builder = `#!/usr/bin/env node
import { mkdirSync, writeFileSync } from 'node:fs';
import assert from 'node:assert/strict';
assert(!('CONTROL_PRODUCTION_DEPLOY' in process.env));
assert(!('CONTROL_OPERATOR' in process.env));
assert(!('APP_SECRET' in process.env));
assert.equal(process.argv[2], 'deploy');
assert.equal(process.argv[3], '--dry-run');
const out = process.argv.at(-1);
mkdirSync(out, { recursive: true });
writeFileSync(out + '/index.js', 'export default {};');
`

let preload = `import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
const bearer = process.env.CONTROL_PRODUCTION_DEPLOY;
const scenario = process.env.FAKE_SCENARIO;
process.env = new Proxy(process.env, {
  get(target, name) {
    if (name === 'CONTROL_OPERATOR') throw new Error('operator must not be read');
    return Reflect.get(target, name);
  },
  ownKeys() { throw new Error('environment must not be copied'); }
});
const operations = [];
let digest;
let candidate;
globalThis.fetch = async (url, init) => {
  assert(init.headers.authorization === 'Bearer ' + bearer);
  assert.equal(init.redirect, 'error');
  const request = JSON.parse(init.body);
  assert.equal(request.interface, 'deployment_grants');
  assert.equal(url, 'https://control.example/deployment_grants/' + request.operation);
  operations.push(request.operation);
  const input = request.input;
  let data;
  switch (request.operation) {
    case 'upload': {
      assert.deepEqual(Object.keys(input).sort(), ['artifact', 'digest']);
      const artifact = Buffer.from(input.artifact, 'base64url');
      digest = createHash('sha256').update(artifact).digest('hex');
      assert.equal(input.digest, digest);
      assert(artifact.includes(Buffer.from('main_module')));
      assert(!artifact.includes(Buffer.from('APP_SECRET')));
      if (scenario === 'upload') return new Response(bearer, { status: 403 });
      data = { digest, expires: 12345 };
      break;
    }
    case 'deploy':
      assert.deepEqual(Object.keys(input).sort(), ['candidate', 'digest', 'expected']);
      assert.equal(input.expected, 7);
      assert.equal(input.digest, digest);
      candidate = input.candidate;
      assert.deepEqual(candidate, {
        platform: 'a'.repeat(40), cloud: 'b'.repeat(40),
        driver: 'c'.repeat(40), machine: 'd'.repeat(40)
      });
      if (scenario === 'stale') return Response.json({
        status: 'error', failure: 'rejected', reason: 'stale', message: bearer
      });
      data = { app: 1, digest, version: 8, candidate };
      break;
    case 'status':
      assert.deepEqual(input, {});
      data = { app: 1, digest, version: 8, candidate };
      if (scenario === 'digest') data.digest = '00'.repeat(32);
      if (scenario === 'candidate') data.candidate = { ...candidate, cloud: 'e'.repeat(40) };
      break;
    default: throw new Error('unexpected call');
  }
  return Response.json({ status: 'success', data });
};
process.on('exit', () => {
  const expected = scenario === 'upload' ? ['upload']
    : scenario === 'stale' ? ['upload', 'deploy'] : ['upload', 'deploy', 'status'];
  try { assert.deepEqual(operations, expected); }
  catch { process.exitCode = 99; }
});
`

test("grant CLI bundles locally and uses only scoped calls with masked failures", () => {
  let directory = Host.makeTemporary(Host.join([Host.temporary(), "grant-cli-"]))
  let check = () => {
    mkdir(Host.join([directory, "node_modules", ".bin"]), {"recursive": true})
    write(directory, "node_modules/.bin/wrangler", builder)
    chmod(Host.join([directory, "node_modules/.bin/wrangler"]), 0o755)
    write(directory, "preload.mjs", preload)
    write(directory, "wrangler.json", `{"main":"index.js","compatibility_date":"2026-10-21"}`)
    ["success", "digest", "candidate", "stale", "upload"]->Array.forEach(scenario => {
      let environment = dict{
        "CONTROL_PRODUCTION_DEPLOY": "fake deployment proof",
        "APP_SECRET": "must stay local",
        "FAKE_SCENARIO": scenario,
      }
      env->Dict.get("PATH")->Option.forEach(value => environment->Dict.set("PATH", value))
      let result = spawnSync(
        "node",
        [
          "--import",
          Host.join([directory, "preload.mjs"]),
          "src/main.res.mjs",
          directory,
          "control:https://control.example",
          "--expected-version",
          "7",
          "--platform",
          String.repeat("a", 40),
          "--cloud",
          String.repeat("b", 40),
          "--driver",
          String.repeat("c", 40),
          "--machine",
          String.repeat("d", 40),
        ],
        {"env": environment, "encoding": "utf8"},
      )
      deepEqual(
        result.status->Nullable.toOption,
        Some(scenario == "success" ? 0 : 1),
        ~message=scenario,
      )
      let expected = switch scenario {
      | "success" => "grant deployment digest version and candidate confirmed"
      | "upload" => "grant upload refused"
      | "stale" => "grant deploy refused or malformed"
      | _ => "grant status does not match the deployed digest version and candidate"
      }
      ok((scenario == "success" ? result.stdout : result.stderr)->String.includes(expected))
      ok(!(result.stdout->String.includes("fake deployment proof")))
      ok(!(result.stderr->String.includes("fake deployment proof")))
      ok(!(result.stdout->String.includes("must stay local")))
      ok(!(result.stderr->String.includes("must stay local")))
    })
  }
  switch check() {
  | exception JsExn(e) =>
    Host.remove(directory, {recursive: true, force: true})
    throw(JsExn(e))
  | () => Host.remove(directory, {recursive: true, force: true})
  }
})
