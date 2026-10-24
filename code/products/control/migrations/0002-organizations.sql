-- An organization's secret, its own control's token, and a binding that control binds, RFC rxmd9.
ALTER TABLE organization ADD COLUMN secret TEXT;

-- A relayed binding's host is bound to an organization's own control, reached through this one.
ALTER TABLE binding ADD COLUMN relayed INTEGER NOT NULL DEFAULT 0;
