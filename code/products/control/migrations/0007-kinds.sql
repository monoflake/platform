-- The kinds a release declares, their names joined by commas in its order, none NULL, RFC emgxf.
ALTER TABLE release ADD COLUMN kinds TEXT;

-- The kind a deployment was declared to run as, none for one drawn and not yet declared or
-- declared before kinds were kept.
ALTER TABLE deployment ADD COLUMN kind TEXT;
