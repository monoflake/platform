/** The control's SQL costs, held by its state tests as docs/code.md describes. */
type quantity = [#constant | #bindings | #deployments | #held_ids]

type budget = {
  name: string,
  template: string,
  quantity: quantity,
  perRow: int,
  fixed: int,
}

let rule = {
  "name": "control-sql-rows-read",
  "says": "Every state statement has a measured rows read bound and a growth quantity",
  "doc": "docs/code.md#sql-cost",
  "heldBy": "model/tests/sql_cost_test.res",
}

let fixtureSizes = [0, 16, 384]

let tables = dict{
  "constant": [],
  "bindings": ["binding"],
  "deployments": ["deployment"],
  "held_ids": ["binding", "app", "deployment"],
}

let fragments = [
  "WITH RECURSIVE n(v) AS (SELECT COALESCE(MAX(id), 0) + 1 FROM ${table} UNION ALL SELECT v + 1 FROM n WHERE EXISTS (SELECT 1 FROM app WHERE id = v) OR EXISTS (SELECT 1 FROM deployment WHERE app = v) OR EXISTS (SELECT 1 FROM binding WHERE id = v))",
  "WITH RECURSIVE n(v) AS (SELECT 1 UNION ALL SELECT v + 1 FROM n WHERE v < ${Int.toString(Addresses.count)} AND '10.200.' || (v / 256) || '.' || (v % 256) IN (SELECT address FROM binding WHERE address IS NOT NULL)), a(address) AS MATERIALIZED (SELECT '10.200.' || (v / 256) || '.' || (v % 256) FROM n WHERE '10.200.' || (v / 256) || '.' || (v % 256) NOT IN (SELECT address FROM binding WHERE address IS NOT NULL))",
  "(EXISTS (SELECT 1 FROM app WHERE id = ${app}) OR EXISTS (SELECT 1 FROM deployment WHERE app = ${app} AND ${ranRow}))",
  "(SELECT COALESCE(MAX(bound), 0) + 1 FROM binding)",
]

let budgets: array<budget> = [
  {
    name: "reseal",
    template: "UPDATE ${kind} SET secret = ? WHERE id = ? AND secret = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "organization",
    template: "SELECT id, secret FROM organization WHERE id = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "open_organization",
    template: "${following(\"organization\")} INSERT INTO organization (id, label) SELECT MAX(v), ? FROM n WHERE true ON CONFLICT (label) DO NOTHING",
    quantity: #held_ids,
    perRow: 3,
    fixed: 16,
  },
  {
    name: "organization_label",
    template: "SELECT id, secret FROM organization WHERE label = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "seal_organization",
    template: "UPDATE organization SET secret = ? WHERE id = ? AND secret IS NULL",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "has_organization",
    template: "SELECT id FROM organization WHERE id = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "seal_binding",
    template: "UPDATE binding SET secret = ? WHERE id = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "open_binding",
    template: "INSERT INTO binding (id, organization, secret, relayed) SELECT ?1, ?2, '', ?3 WHERE NOT EXISTS (SELECT 1 FROM app WHERE id = ?1) AND NOT EXISTS (SELECT 1 FROM organization WHERE id = ?1) AND NOT EXISTS (SELECT 1 FROM deployment WHERE app = ?1) ON CONFLICT (id) DO NOTHING RETURNING id",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "delete_binding",
    template: "DELETE FROM binding WHERE id = ?",
    quantity: #deployments,
    perRow: 2,
    fixed: 8,
  },
  {
    name: "binding",
    template: "SELECT ${bindingColumns} FROM binding WHERE id = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "storage",
    template: "SELECT ${bindingColumns} FROM binding WHERE organization = ? AND relayed = 0 AND bound IS NOT NULL AND origin IS NULL ORDER BY bound LIMIT 1",
    quantity: #bindings,
    perRow: 2,
    fixed: 8,
  },
  {
    name: "addressed_at",
    template: "SELECT ${bindingColumns} FROM binding WHERE address = ?",
    quantity: #bindings,
    perRow: 2,
    fixed: 8,
  },
  {
    name: "tunneled",
    template: "UPDATE binding SET tunnel = ? WHERE id = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "given_address",
    template: "UPDATE binding SET address = ? WHERE id = ? AND address IS NULL AND origin IS NULL RETURNING address",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "allocate_address",
    template: "${unaddressed} UPDATE binding SET address = (SELECT address FROM a) WHERE id = ? AND address IS NULL AND origin IS NULL AND EXISTS (SELECT 1 FROM a) RETURNING address",
    quantity: #bindings,
    perRow: 6,
    fixed: 32,
  },
  {
    name: "address",
    template: "SELECT address FROM binding WHERE id = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "unaddressed",
    template: "UPDATE binding SET address = NULL WHERE id = ? AND address = ? AND bound IS NULL",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "routed",
    template: "UPDATE binding SET bound = ${followingBound} WHERE id = ? AND address IS NOT NULL AND bound IS NULL AND origin IS NULL",
    quantity: #bindings,
    perRow: 2,
    fixed: 8,
  },
  {
    name: "originated",
    template: "UPDATE binding SET origin = ? WHERE id = ? AND origin IS NULL AND bound IS NULL RETURNING id",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "put_release",
    template: "INSERT INTO release (hash, form, size, kinds) VALUES (?, ?, ?, ?) ON CONFLICT (hash) DO NOTHING",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "release",
    template: "SELECT hash, form, size, kinds FROM release WHERE hash = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "deploy",
    template: "INSERT INTO deployment (app, binding, release, capacity, kind) SELECT ?1, ?2, ?3, ?4, ?5 WHERE ${appHeld(\"?1\")} ON CONFLICT (app) DO UPDATE SET binding = excluded.binding, release = excluded.release, capacity = excluded.capacity, kind = excluded.kind",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "deployment",
    template: "SELECT app, binding, release, capacity, kind FROM deployment WHERE app = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "draw_app",
    template: "INSERT INTO app (id) SELECT ?1 WHERE NOT EXISTS (SELECT 1 FROM binding WHERE id = ?1) AND NOT EXISTS (SELECT 1 FROM organization WHERE id = ?1) AND NOT EXISTS (SELECT 1 FROM deployment WHERE app = ?1) ON CONFLICT (id) DO NOTHING RETURNING id",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "forget_deployment",
    template: "DELETE FROM deployment WHERE app = ? AND NOT ${ranRow} RETURNING app",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "forget_app",
    template: "DELETE FROM app WHERE id = ?1 AND NOT EXISTS (SELECT 1 FROM deployment WHERE app = ?1) RETURNING id",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "app_held",
    template: "SELECT 1 AS id WHERE ${appHeld(\"?1\")}",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "has_app",
    template: "SELECT id FROM app WHERE id = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "retire_app",
    template: "DELETE FROM app WHERE id = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
  {
    name: "retire_deployment",
    template: "DELETE FROM deployment WHERE app = ?",
    quantity: #constant,
    perRow: 0,
    fixed: 8,
  },
]
