-- One row per sync code (only a hash of the code), and one per theme in its list.
CREATE TABLE IF NOT EXISTS lists (
  id TEXT PRIMARY KEY,
  created INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS themes (
  list_id TEXT NOT NULL,
  key TEXT NOT NULL,            -- the name in lower case (names are the same whatever the case)
  name TEXT NOT NULL,
  fg TEXT NOT NULL,
  bg TEXT NOT NULL,
  PRIMARY KEY (list_id, key)
);
