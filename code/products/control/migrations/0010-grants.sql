CREATE TABLE deployment_grant (
	grant TEXT PRIMARY KEY NOT NULL,
	verifier TEXT NOT NULL,
	expires INTEGER NOT NULL,
	revoked INTEGER NOT NULL DEFAULT 0,
	policy TEXT NOT NULL,
	app INTEGER
);

CREATE INDEX deployment_grant_app ON deployment_grant (app);

CREATE TABLE grant_staging (
	grant TEXT NOT NULL REFERENCES deployment_grant (grant),
	digest TEXT NOT NULL,
	size INTEGER NOT NULL,
	expires INTEGER NOT NULL,
	token TEXT NOT NULL,
	PRIMARY KEY (grant, digest)
);

CREATE INDEX grant_staging_expires ON grant_staging (expires);

CREATE TABLE grant_head (
	app INTEGER PRIMARY KEY REFERENCES deployment (app) ON DELETE CASCADE,
	digest TEXT NOT NULL,
	version INTEGER NOT NULL DEFAULT 0,
	candidate TEXT NOT NULL,
	grant TEXT,
	locked TEXT NOT NULL DEFAULT ''
);

CREATE INDEX grant_head_open ON grant_head (app) WHERE locked != '';

CREATE TABLE grant_audit (
	app INTEGER NOT NULL,
	version INTEGER NOT NULL,
	previous INTEGER NOT NULL,
	grant TEXT NOT NULL,
	digest TEXT NOT NULL,
	candidate TEXT NOT NULL,
	PRIMARY KEY (app, version)
);

CREATE TRIGGER grant_committed AFTER UPDATE OF version ON grant_head
WHEN NEW.version = OLD.version + 1 AND NEW.grant IS NOT NULL
BEGIN
	INSERT INTO grant_audit (app, version, previous, grant, digest, candidate)
	VALUES (NEW.app, NEW.version, OLD.version, NEW.grant, NEW.digest, NEW.candidate);
	UPDATE deployment SET release = NEW.digest WHERE app = NEW.app;
END;

CREATE TRIGGER grant_retired AFTER DELETE ON deployment
BEGIN
	UPDATE deployment_grant SET revoked = 1
	WHERE app = OLD.app;
END;
