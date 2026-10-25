-- A binding whose tunnel was made before its address was kept keeps the one its id gave, RFC b8f35.
UPDATE binding SET address = '10.200.' || (id / 256) || '.' || (id % 256)
WHERE address IS NULL AND origin IS NULL AND tunnel IS NOT NULL AND id BETWEEN 1 AND 65535
AND '10.200.' || (id / 256) || '.' || (id % 256)
NOT IN (SELECT address FROM binding WHERE address IS NOT NULL);
