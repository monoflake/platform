open Node

let preload = `import assert from 'node:assert/strict';
import child from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { syncBuiltinESMExports } from 'node:module';
let reads = 0;
let describes = 0;
let builds = 0;
process.env = new Proxy(process.env, {
  get(target, name) {
    if (name === 'SALT_MASTER') reads++;
    return Reflect.get(target, name);
  }
});
const success = data => JSON.stringify({ status: 'success', data });
child.spawnSync = (program, args, options) => {
  let stdout;
  if (program.endsWith('/wrangler')) {
    builds++;
    assert.equal(options.env.SALT_MASTER, undefined);
    const out = args[args.indexOf('--outdir') + 1];
    fs.mkdirSync(out, { recursive: true });
    fs.writeFileSync(path.join(out, 'index.js'), 'export default {}');
    stdout = '';
  } else {
    assert.equal(program, 'ssh');
    if (!options.input) {
      stdout = 'directory=/d\\nbinding=1\\ntunnel=\\n';
    } else {
      const request = JSON.parse(options.input);
      assert.equal(request.operation, 'describe');
      if (request.interface === 'management') {
        stdout = success({ generation: 0, policy: 0, grace: 0, items: [] });
      } else {
        describes++;
        assert.equal(request.interface, 'deployments');
        assert.deepEqual(request.input, { runs: { name: 'component', component: 'compute', id: 1 } });
        stdout = JSON.stringify({ status: 'error', failure: 'rejected', reason: 'not_found', message: 'fixture' });
      }
    }
  }
  return { status: 0, stdout, stderr: '' };
};
syncBuiltinESMExports();
process.on('exit', () => {
  assert.equal(reads, 0);
  assert.equal(builds, 1);
  assert.equal(describes, 1);
});
`

test("a compute dry run reads no salt master and hands no salt", () => {
  let directory = Host.makeTemporary(Host.join([Host.temporary(), "component-cli-"]))
  let check = () => {
    let path = Host.join([directory, "preload.mjs"])
    Host.writeBytes(path, Bytes.utf8(preload))
    mkdir(Host.join([directory, "node_modules", ".bin"]), {"recursive": true})
    Host.writeBytes(Host.join([directory, "node_modules", ".bin", "wrangler"]), Bytes.utf8(""))
    Host.writeBytes(
      Host.join([directory, "wrangler.json"]),
      Bytes.utf8(`{"main":"index.js","compatibility_date":"2026-10-21"}`),
    )
    [dict{}, dict{"SALT_MASTER": "malformed"}]->Array.forEach(env => {
      let result = spawnSync(
        executable,
        [
          "--import",
          path,
          "src/main.res.mjs",
          directory,
          "local",
          "--component",
          "compute",
          "--organization",
          "0000000a",
          "--app",
          "00000001",
          "--dry-run",
        ],
        {"env": env, "encoding": "utf8"},
      )
      deepEqual(result.status->Nullable.toOption, Some(0), ~message=result.stderr)
      ok(result.stdout->String.includes("would be deployed"), ~message=result.stdout)
      ok(!(result.stdout->String.includes("salt handed")), ~message=result.stdout)
    })
  }
  switch check() {
  | exception JsExn(error) =>
    Host.remove(directory, {recursive: true, force: true})
    throw(JsExn(error))
  | () => Host.remove(directory, {recursive: true, force: true})
  }
})
