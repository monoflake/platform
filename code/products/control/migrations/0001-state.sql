-- The control's state, src/parts/state.resi; an applied migration is never edited.
CREATE TABLE organization (id INTEGER PRIMARY KEY, label TEXT NOT NULL UNIQUE);

-- The secret in hex, sent to the host's driver as its token on every call, RFC 3d3nt.
CREATE TABLE binding (
	id INTEGER PRIMARY KEY,
	organization INTEGER NOT NULL REFERENCES organization (id),
	secret TEXT NOT NULL,
	tunnel TEXT,
	address TEXT
);

CREATE TABLE release (hash TEXT PRIMARY KEY, form TEXT NOT NULL, size INTEGER NOT NULL);

CREATE TABLE deployment (
	app INTEGER PRIMARY KEY,
	binding INTEGER NOT NULL REFERENCES binding (id),
	release TEXT NOT NULL REFERENCES release (hash),
	capacity INTEGER NOT NULL
);
