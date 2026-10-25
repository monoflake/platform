-- Each app id drawn, kept as it is drawn and before its deployment, RFC b8f35.
CREATE TABLE app (id INTEGER PRIMARY KEY);

-- The apps deployed before ids were drawn keep theirs.
INSERT INTO app (id) SELECT app FROM deployment;
