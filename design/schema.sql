-- Proposed project database v1. One database per project, per device.
-- Apply the connection pragmas when opening each writer. Times are UTC epoch ms.
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = FULL;
BEGIN;
CREATE TABLE devices (id TEXT PRIMARY KEY NOT NULL, label TEXT NOT NULL);
CREATE TABLE project (singleton INTEGER PRIMARY KEY CHECK(singleton=1), uuid TEXT UNIQUE NOT NULL, name TEXT NOT NULL);
-- Each editable aggregate has one identity. Subtype and change rows are written
-- together by Drift. The core checks subtype matches kind on every import.
CREATE TABLE records (
  id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('road','waypoint','route','junction')),
  created_ms INTEGER NOT NULL, updated_ms INTEGER NOT NULL, deleted_ms INTEGER,
  origin_device TEXT NOT NULL REFERENCES devices, writer_device TEXT NOT NULL REFERENCES devices,
  version_vector TEXT NOT NULL CHECK(json_valid(version_vector))
);
CREATE TABLE roads (
  id TEXT PRIMARY KEY NOT NULL REFERENCES records, name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('trail','dirt_road','4x4_track','footpath')),
  surface TEXT, difficulty INTEGER CHECK(difficulty BETWEEN 1 AND 5), seasonal_notes TEXT,
  source TEXT NOT NULL, source_feature_id TEXT, attribution TEXT,
  direction TEXT NOT NULL DEFAULT 'both' CHECK(direction IN ('both','forward','reverse')),
  access_json TEXT NOT NULL DEFAULT '{}' CHECK(json_valid(access_json))
);
-- A shared junction UUID encodes connectivity, including for imported ways.
CREATE TABLE junctions (id TEXT PRIMARY KEY NOT NULL REFERENCES records);
CREATE TABLE road_points (
  id TEXT PRIMARY KEY NOT NULL, road_id TEXT NOT NULL REFERENCES roads,
  part INTEGER NOT NULL CHECK(part>=0), ordinal INTEGER NOT NULL CHECK(ordinal>=0),
  lat REAL NOT NULL CHECK(lat BETWEEN -90 AND 90), lon REAL NOT NULL CHECK(lon BETWEEN -180 AND 180),
  elevation_m REAL, junction_id TEXT REFERENCES junctions, captured_ms INTEGER,
  created_ms INTEGER NOT NULL, updated_ms INTEGER NOT NULL, writer_device TEXT NOT NULL REFERENCES devices,
  UNIQUE(road_id,part,ordinal)
);
CREATE INDEX road_points_junction ON road_points(junction_id) WHERE junction_id IS NOT NULL;
CREATE TABLE waypoints (
  id TEXT PRIMARY KEY NOT NULL REFERENCES records, name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('camp','water','hazard','fuel','viewpoint','river_crossing','custom')),
  icon TEXT NOT NULL, color INTEGER NOT NULL, notes TEXT, observed_ms INTEGER NOT NULL,
  lat REAL NOT NULL CHECK(lat BETWEEN -90 AND 90), lon REAL NOT NULL CHECK(lon BETWEEN -180 AND 180), elevation_m REAL
);
-- Immutable local photo bytes live at a path derived from their SHA-256.
CREATE TABLE blobs (sha256 TEXT PRIMARY KEY NOT NULL, bytes INTEGER NOT NULL CHECK(bytes>=0), mime TEXT NOT NULL);
CREATE TABLE photos (id TEXT PRIMARY KEY NOT NULL, owner_id TEXT NOT NULL REFERENCES records,
  sha256 TEXT NOT NULL REFERENCES blobs, caption TEXT, created_ms INTEGER NOT NULL, updated_ms INTEGER NOT NULL,
  writer_device TEXT NOT NULL REFERENCES devices);
CREATE INDEX photos_owner ON photos(owner_id);
-- A route is a saved snapshot, so editing its source roads cannot erase it.
CREATE TABLE routes (id TEXT PRIMARY KEY NOT NULL REFERENCES records, name TEXT NOT NULL,
  profile TEXT NOT NULL, destination_id TEXT REFERENCES waypoints, graph_revision INTEGER,
  distance_m REAL NOT NULL CHECK(distance_m>=0), eta_s REAL CHECK(eta_s>=0));
CREATE TABLE route_points (route_id TEXT NOT NULL REFERENCES routes, ordinal INTEGER NOT NULL,
  lat REAL NOT NULL CHECK(lat BETWEEN -90 AND 90), lon REAL NOT NULL CHECK(lon BETWEEN -180 AND 180),
  elevation_m REAL, cumulative_m REAL NOT NULL CHECK(cumulative_m>=0), instruction TEXT, source_road_id TEXT REFERENCES roads,
  PRIMARY KEY(route_id,ordinal));
-- Device-local raw observation journal. Pause, loss of fix and process death
-- open a new part. Stop materializes roads/points atomically and is retryable.
CREATE TABLE recordings (id TEXT PRIMARY KEY NOT NULL, device_id TEXT NOT NULL REFERENCES devices,
  state TEXT NOT NULL CHECK(state IN ('active','paused','interrupted','finished')),
  started_ms INTEGER NOT NULL, updated_ms INTEGER NOT NULL, current_part INTEGER NOT NULL DEFAULT 0,
  road_id TEXT UNIQUE REFERENCES roads);
CREATE UNIQUE INDEX one_open_recording ON recordings(device_id) WHERE state<>'finished';
CREATE TABLE fixes (recording_id TEXT NOT NULL REFERENCES recordings, seq INTEGER NOT NULL, part INTEGER NOT NULL,
  fix_id TEXT NOT NULL UNIQUE, captured_ms INTEGER NOT NULL, lat REAL NOT NULL CHECK(lat BETWEEN -90 AND 90),
  lon REAL NOT NULL CHECK(lon BETWEEN -180 AND 180), elevation_m REAL, accuracy_m REAL CHECK(accuracy_m>=0),
  speed_mps REAL, course_deg REAL, PRIMARY KEY(recording_id,seq));
-- Device-local inventory. A west bound greater than east crosses the date line.
CREATE TABLE regions (id TEXT PRIMARY KEY NOT NULL, label TEXT NOT NULL, source TEXT NOT NULL, attribution TEXT NOT NULL,
  west REAL NOT NULL CHECK(west BETWEEN -180 AND 180), east REAL NOT NULL CHECK(east BETWEEN -180 AND 180),
  south REAL NOT NULL CHECK(south BETWEEN -90 AND 90), north REAL NOT NULL CHECK(north BETWEEN south AND 90),
  min_zoom INTEGER NOT NULL CHECK(min_zoom>=0), max_zoom INTEGER NOT NULL CHECK(max_zoom>=min_zoom),
  style TEXT NOT NULL, format TEXT NOT NULL, relative_path TEXT NOT NULL UNIQUE,
  state TEXT NOT NULL CHECK(state IN ('staging','ready','failed','deleting')), expected_tiles INTEGER,
  estimated_bytes INTEGER, actual_bytes INTEGER, checksum TEXT, created_ms INTEGER NOT NULL, updated_ms INTEGER NOT NULL);
-- Disposable spatial lookup. Entries address waypoints and road *segments*,
-- including segments whose two vertices both lie outside the search window.
-- Segments that cross the date line get two boxes; queries deduplicate hits.
CREATE TABLE spatial_parts (key INTEGER PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES records,
  start_point_id TEXT REFERENCES road_points ON DELETE CASCADE, end_point_id TEXT REFERENCES road_points ON DELETE CASCADE);
CREATE INDEX spatial_owner ON spatial_parts(owner_id);
CREATE INDEX spatial_start ON spatial_parts(start_point_id);
CREATE INDEX spatial_end ON spatial_parts(end_point_id);
CREATE VIRTUAL TABLE spatial_bounds USING rtree(key,min_lon,max_lon,min_lat,max_lat);
CREATE TRIGGER spatial_cleanup AFTER DELETE ON spatial_parts BEGIN DELETE FROM spatial_bounds WHERE key=OLD.key; END;
-- Rebuildable routing cache, published with its revision in one transaction.
CREATE TABLE graph_state (singleton INTEGER PRIMARY KEY CHECK(singleton=1), source_revision INTEGER NOT NULL, built_revision INTEGER);
CREATE TABLE graph_nodes (id INTEGER PRIMARY KEY, lat REAL NOT NULL, lon REAL NOT NULL);
CREATE TABLE graph_edges (id INTEGER PRIMARY KEY, src INTEGER NOT NULL REFERENCES graph_nodes,
  dst INTEGER NOT NULL REFERENCES graph_nodes, road_id TEXT NOT NULL REFERENCES roads,
  first_point TEXT NOT NULL REFERENCES road_points ON DELETE CASCADE, last_point TEXT NOT NULL REFERENCES road_points ON DELETE CASCADE,
  distance_m REAL NOT NULL CHECK(distance_m>=0), access_json TEXT NOT NULL CHECK(json_valid(access_json)));
CREATE INDEX graph_outgoing ON graph_edges(src);
-- Operation groups preserve multi-road split/merge and junction edits across peers.
-- Payloads include stable vertex IDs and attachment hashes. A group carries its
-- full member list and is only applied/acknowledged as a unit.
CREATE TABLE changes (id TEXT PRIMARY KEY NOT NULL, group_id TEXT NOT NULL, member INTEGER NOT NULL, group_size INTEGER NOT NULL,
  device_id TEXT NOT NULL REFERENCES devices, counter INTEGER NOT NULL CHECK(counter>0), record_id TEXT NOT NULL REFERENCES records,
  op TEXT NOT NULL CHECK(op IN ('create','update','delete','resolve')), base_vector TEXT NOT NULL CHECK(json_valid(base_vector)),
  result_vector TEXT NOT NULL CHECK(json_valid(result_vector)), payload TEXT NOT NULL CHECK(json_valid(payload)), at_ms INTEGER NOT NULL,
  CHECK(member>=0 AND member<group_size), UNIQUE(group_id,member), UNIQUE(device_id,counter));
CREATE INDEX changes_record ON changes(record_id);
CREATE TABLE peer_cursors (peer_id TEXT NOT NULL REFERENCES devices, origin_id TEXT NOT NULL REFERENCES devices,
  contiguous_counter INTEGER NOT NULL, PRIMARY KEY(peer_id,origin_id));
-- Staging accepts foreign UUIDs before live records exist. Keep divergent
-- groups and their blobs until the user resolves them with a new revision.
CREATE TABLE incoming_groups (group_id TEXT PRIMARY KEY NOT NULL, manifest TEXT NOT NULL CHECK(json_valid(manifest)),
  status TEXT NOT NULL CHECK(status IN ('staged','conflict')), received_ms INTEGER NOT NULL);
CREATE TABLE edit_history (seq INTEGER PRIMARY KEY, group_id TEXT NOT NULL UNIQUE, forward_json TEXT NOT NULL CHECK(json_valid(forward_json)),
  inverse_json TEXT NOT NULL CHECK(json_valid(inverse_json)), expected_versions TEXT NOT NULL CHECK(json_valid(expected_versions)),
  undone INTEGER NOT NULL DEFAULT 0 CHECK(undone IN (0,1)));
CREATE TABLE settings (key TEXT PRIMARY KEY NOT NULL, value_json TEXT NOT NULL CHECK(json_valid(value_json)));
PRAGMA user_version=1;
COMMIT;
