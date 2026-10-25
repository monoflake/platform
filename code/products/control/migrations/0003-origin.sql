-- The origin a binding's driver is served at, kept once its call back proved it, RFC 8j7b0.
ALTER TABLE binding ADD COLUMN origin TEXT;
