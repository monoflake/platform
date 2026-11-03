open Node

let preload = `import assert from 'node:assert/strict';
import child from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
const scenario = process.env.FAKE_SCENARIO;
const operations = [];
const version = 'ab'.repeat(32);
const described = { runs: { name: 'app', id: 1 }, version, state: { name: 'stopped' } };
const success = data => JSON.stringify({ status: 'success', data });
const refused = reason => JSON.stringify({ status: 'error', failure: 'rejected', reason, message: 'fixture' });
child.spawnSync = (program, args, options) => {
  assert.equal(program, 'ssh');
  assert(args.includes('root@localhost'));
  assert(args.includes('2222'));
  const shell = args.at(-1);
  let output;
  let operation;
  if (options.input) {
    const request = JSON.parse(options.input);
    operation = request.operation;
    assert.equal(request.interface, 'deployments');
    assert.deepEqual(request.input, { runs: { name: 'app', id: 1 } });
    assert.equal(request.capabilities, undefined);
    assert(shell.includes('/deployments/' + operation));
    assert(shell.includes('$(o bindings)'));
    assert(shell.includes('--data-binary @-'));
    output = scenario === 'absent' ? refused('not_found')
      : scenario === operation ? refused('fault')
      : operation === 'delete' ? success({}) : success(described);
  } else {
    assert.fail('retire asks only deployments, not ' + shell);
  }
  operations.push(operation);
  return { status: 0, stdout: output, stderr: 'fixture failure' };
};
syncBuiltinESMExports();
globalThis.fetch = async (url, init) => {
  const request = JSON.parse(init.body);
  assert.equal(scenario, 'control');
  assert.equal(url, 'https://control.example/releases/retire');
  assert.equal(init.headers.authorization, 'Bearer fixture operator');
  assert.deepEqual(request, { interface: 'releases', operation: 'retire', input: { app: 1 } });
  operations.push('retire');
  return new Response(success({ app: 1 }), { status: 200 });
};
process.on('exit', () => {
  const expected = {
    success: ['describe', 'stop', 'delete'],
    absent: ['describe'], dry: ['describe'],
    describe: ['describe'],
    stop: ['describe', 'stop'], delete: ['describe', 'stop', 'delete'],
    control: ['retire'], 'control-dry': []
  };
  assert.deepEqual(operations, expected[scenario]);
});
`

test("retire routes machine and control targets and stops at the first failed phase", () => {
  let directory = Host.makeTemporary(Host.join([Host.temporary(), "retire-cli-"]))
  let check = () => {
    let path = Host.join([directory, "preload.mjs"])
    Host.writeBytes(path, Bytes.utf8(preload))
    [
      "success",
      "absent",
      "dry",
      "describe",
      "stop",
      "delete",
      "control",
      "control-dry",
    ]->Array.forEach(scenario => {
      let control = scenario->String.startsWith("control")
      let dry = scenario == "dry" || scenario == "control-dry"
      let result = spawnSync(
        executable,
        [
          "--import",
          path,
          "src/main.res.mjs",
          control ? "control:https://control.example" : "local",
          "--retire",
          "00000001",
          ...dry ? ["--dry-run"] : [],
        ],
        {
          "env": dict{"FAKE_SCENARIO": scenario, "CONTROL_OPERATOR": "fixture operator"},
          "encoding": "utf8",
        },
      )
      let failed = ["describe", "stop", "delete"]->Array.includes(scenario)
      deepEqual(result.status->Nullable.toOption, Some(failed ? 1 : 0), ~message=result.stderr)
      if failed {
        ok(result.stderr->String.includes("failed after"))
      } else {
        let expected = switch scenario {
        | "absent" => "is not there"
        | "control" => "app 00000001 retired"
        | "control-dry" => "would be stopped, deleted by its driver and removed"
        | "dry" => "would be deleted"
        | _ => "deleted"
        }
        ok(result.stdout->String.includes(expected), ~message=result.stdout)
      }
      ok(!(result.stdout->String.includes("fixture operator")))
      ok(!(result.stderr->String.includes("fixture operator")))
    })
  }
  switch check() {
  | exception JsExn(error) =>
    Host.remove(directory, {recursive: true, force: true})
    throw(JsExn(error))
  | () => Host.remove(directory, {recursive: true, force: true})
  }
})
