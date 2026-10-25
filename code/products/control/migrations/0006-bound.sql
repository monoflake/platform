-- The order a binding was given its address in, its organization's storage the first so given.
ALTER TABLE binding ADD COLUMN bound INTEGER;

-- Bindings given an address before keep the order their ids gave them.
UPDATE binding SET bound = id WHERE address IS NOT NULL;
