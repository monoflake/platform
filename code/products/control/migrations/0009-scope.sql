-- A mount under an organization's gateway, RFC oomwh.
CREATE TABLE scope (
	organization INTEGER NOT NULL,
	scope TEXT NOT NULL,
	app INTEGER NOT NULL REFERENCES deployment (app) ON DELETE CASCADE,
	PRIMARY KEY (organization, scope)
);
CREATE INDEX scope_app ON scope (app);
