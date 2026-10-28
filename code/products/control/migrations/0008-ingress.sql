ALTER TABLE release ADD COLUMN ingress TEXT;
ALTER TABLE deployment ADD COLUMN ingress TEXT;

CREATE TABLE domain (
	domain TEXT PRIMARY KEY NOT NULL,
	app INTEGER NOT NULL REFERENCES deployment (app) ON DELETE CASCADE
);
CREATE INDEX domain_app ON domain (app);
