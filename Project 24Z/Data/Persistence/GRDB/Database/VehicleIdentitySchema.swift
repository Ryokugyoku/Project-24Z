import GRDB

/// Vehicle Identity Storeのv1物理schemaだけを定義します。
enum VehicleIdentitySchema {
    /// リリース後に変更しない初回Migration識別子です。
    nonisolated static let v1MigrationIdentifier = "v1_create_vehicle_identity_store"

    /// v1の全テーブル、Index、保全Triggerを作成するSQLです。
    nonisolated static let v1SQL = """
    CREATE TABLE database_scope (
      scope_row_id INTEGER PRIMARY KEY CHECK (scope_row_id = 1),
      user_scope_id TEXT NOT NULL UNIQUE CHECK (length(user_scope_id) = 36),
      active_digest_key_version INTEGER NOT NULL CHECK (active_digest_key_version >= 1),
      created_at TEXT NOT NULL
    ) STRICT;

    CREATE TABLE vehicles (
      user_scope_id TEXT NOT NULL CHECK (length(user_scope_id) = 36),
      vehicle_id TEXT NOT NULL CHECK (length(vehicle_id) = 36),
      display_name_ciphertext BLOB,
      display_name_key_version INTEGER,
      lifecycle_state TEXT NOT NULL CHECK (lifecycle_state IN ('active', 'archived')),
      record_revision INTEGER NOT NULL CHECK (record_revision >= 1),
      display_name_revision INTEGER NOT NULL CHECK (display_name_revision >= 0),
      display_name_updated_at TEXT,
      display_name_updated_by_device_id TEXT CHECK (display_name_updated_by_device_id IS NULL OR length(display_name_updated_by_device_id) = 36),
      lifecycle_revision INTEGER NOT NULL CHECK (lifecycle_revision >= 1),
      lifecycle_updated_at TEXT NOT NULL,
      lifecycle_updated_by_device_id TEXT NOT NULL CHECK (length(lifecycle_updated_by_device_id) = 36),
      archived_at TEXT,
      created_at TEXT NOT NULL,
      created_by_device_id TEXT NOT NULL CHECK (length(created_by_device_id) = 36),
      updated_at TEXT NOT NULL,
      updated_by_device_id TEXT NOT NULL CHECK (length(updated_by_device_id) = 36),
      PRIMARY KEY (user_scope_id, vehicle_id),
      CHECK ((display_name_ciphertext IS NULL AND display_name_key_version IS NULL) OR (display_name_ciphertext IS NOT NULL AND display_name_key_version IS NOT NULL AND length(display_name_ciphertext) >= 29 AND display_name_key_version >= 1)),
      CHECK ((lifecycle_state = 'active' AND archived_at IS NULL) OR (lifecycle_state = 'archived' AND archived_at IS NOT NULL)),
      CHECK ((display_name_revision = 0 AND display_name_ciphertext IS NULL AND display_name_key_version IS NULL AND display_name_updated_at IS NULL AND display_name_updated_by_device_id IS NULL) OR (display_name_revision > 0 AND display_name_updated_at IS NOT NULL AND display_name_updated_by_device_id IS NOT NULL)),
      CHECK (updated_at >= created_at),
      CHECK (display_name_updated_at IS NULL OR display_name_updated_at >= created_at),
      CHECK (lifecycle_updated_at >= created_at)
    ) STRICT;

    CREATE TABLE vehicle_identification_scans (
      user_scope_id TEXT NOT NULL CHECK (length(user_scope_id) = 36),
      scan_id TEXT NOT NULL CHECK (length(scan_id) = 36),
      vehicle_id TEXT CHECK (vehicle_id IS NULL OR length(vehicle_id) = 36),
      obd_connection_id TEXT NOT NULL CHECK (length(obd_connection_id) = 36),
      transport_kind TEXT NOT NULL CHECK (length(transport_kind) BETWEEN 1 AND 64),
      diagnostic_protocol_kind TEXT NOT NULL CHECK (length(diagnostic_protocol_kind) BETWEEN 1 AND 64),
      adapter_reference_id TEXT NOT NULL CHECK (length(adapter_reference_id) BETWEEN 1 AND 128),
      decoder_version TEXT NOT NULL CHECK (length(decoder_version) BETWEEN 1 AND 64),
      normalization_version TEXT NOT NULL CHECK (length(normalization_version) BETWEEN 1 AND 64),
      scan_status TEXT NOT NULL CHECK (scan_status IN ('completed', 'incomplete', 'failed')),
      decode_state TEXT NOT NULL CHECK (decode_state IN ('decoded', 'partially_decoded', 'undecodable')),
      identity_validation_state TEXT NOT NULL CHECK (identity_validation_state IN ('valid', 'invalid', 'unavailable')),
      termination_reason_code TEXT,
      started_at TEXT NOT NULL,
      finished_at TEXT NOT NULL,
      revision INTEGER NOT NULL CHECK (revision = 1),
      created_at TEXT NOT NULL,
      created_by_device_id TEXT NOT NULL CHECK (length(created_by_device_id) = 36),
      updated_at TEXT NOT NULL,
      updated_by_device_id TEXT NOT NULL CHECK (length(updated_by_device_id) = 36),
      PRIMARY KEY (user_scope_id, scan_id),
      UNIQUE (user_scope_id, vehicle_id, scan_id),
      UNIQUE (user_scope_id, obd_connection_id),
      FOREIGN KEY (user_scope_id, vehicle_id) REFERENCES vehicles(user_scope_id, vehicle_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
      CHECK (identity_validation_state <> 'valid' OR vehicle_id IS NOT NULL),
      CHECK (finished_at >= started_at),
      CHECK ((scan_status = 'completed' AND termination_reason_code IS NULL) OR (scan_status IN ('incomplete', 'failed') AND termination_reason_code IS NOT NULL AND length(termination_reason_code) BETWEEN 1 AND 64)),
      CHECK (updated_at = created_at),
      CHECK (updated_by_device_id = created_by_device_id)
    ) STRICT;

    CREATE TABLE vehicle_identifiers (
      user_scope_id TEXT NOT NULL CHECK (length(user_scope_id) = 36),
      identifier_id TEXT NOT NULL CHECK (length(identifier_id) = 36),
      vehicle_id TEXT NOT NULL CHECK (length(vehicle_id) = 36),
      identifier_kind TEXT NOT NULL CHECK (identifier_kind IN ('vin', 'domestic_chassis_number')),
      normalized_value_ciphertext BLOB NOT NULL CHECK (length(normalized_value_ciphertext) >= 29),
      encryption_key_version INTEGER NOT NULL CHECK (encryption_key_version >= 1),
      lookup_digest BLOB NOT NULL CHECK (length(lookup_digest) = 32),
      digest_key_version INTEGER NOT NULL CHECK (digest_key_version >= 1),
      source_scan_id TEXT NOT NULL CHECK (length(source_scan_id) = 36),
      revision INTEGER NOT NULL CHECK (revision = 1),
      created_at TEXT NOT NULL,
      created_by_device_id TEXT NOT NULL CHECK (length(created_by_device_id) = 36),
      updated_at TEXT NOT NULL,
      updated_by_device_id TEXT NOT NULL CHECK (length(updated_by_device_id) = 36),
      PRIMARY KEY (user_scope_id, identifier_id),
      UNIQUE (user_scope_id, identifier_kind, lookup_digest),
      UNIQUE (user_scope_id, vehicle_id, identifier_kind),
      FOREIGN KEY (user_scope_id, vehicle_id) REFERENCES vehicles(user_scope_id, vehicle_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
      FOREIGN KEY (user_scope_id, vehicle_id, source_scan_id) REFERENCES vehicle_identification_scans(user_scope_id, vehicle_id, scan_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
      CHECK (updated_at = created_at),
      CHECK (updated_by_device_id = created_by_device_id)
    ) STRICT;

    CREATE TABLE ecu_observations (
      user_scope_id TEXT NOT NULL CHECK (length(user_scope_id) = 36),
      ecu_observation_id TEXT NOT NULL CHECK (length(ecu_observation_id) = 36),
      scan_id TEXT NOT NULL CHECK (length(scan_id) = 36),
      observation_ordinal INTEGER NOT NULL CHECK (observation_ordinal >= 0),
      responder_address_format TEXT NOT NULL CHECK (responder_address_format IN ('can_11_bit', 'can_29_bit', 'iso9141', 'iso14230', 'unknown')),
      responder_address BLOB NOT NULL CHECK (length(responder_address) > 0),
      revision INTEGER NOT NULL CHECK (revision = 1),
      created_at TEXT NOT NULL,
      created_by_device_id TEXT NOT NULL CHECK (length(created_by_device_id) = 36),
      updated_at TEXT NOT NULL,
      updated_by_device_id TEXT NOT NULL CHECK (length(updated_by_device_id) = 36),
      PRIMARY KEY (user_scope_id, ecu_observation_id),
      UNIQUE (user_scope_id, scan_id, observation_ordinal),
      UNIQUE (user_scope_id, scan_id, responder_address_format, responder_address),
      FOREIGN KEY (user_scope_id, scan_id) REFERENCES vehicle_identification_scans(user_scope_id, scan_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
      CHECK (updated_at = created_at),
      CHECK (updated_by_device_id = created_by_device_id)
    ) STRICT;

    CREATE TABLE ecu_identification_values (
      user_scope_id TEXT NOT NULL CHECK (length(user_scope_id) = 36),
      identification_value_id TEXT NOT NULL CHECK (length(identification_value_id) = 36),
      ecu_observation_id TEXT NOT NULL CHECK (length(ecu_observation_id) = 36),
      info_type_code INTEGER NOT NULL CHECK (info_type_code BETWEEN 0 AND 255),
      occurrence_ordinal INTEGER NOT NULL CHECK (occurrence_ordinal >= 0),
      value_kind TEXT NOT NULL CHECK (value_kind IN ('vin', 'domestic_chassis_number', 'ecu_name', 'calibration_id', 'cvn', 'engine_serial_number', 'engine_family', 'other_known_identification', 'unknown_standard_info_type')),
      decode_state TEXT NOT NULL CHECK (decode_state IN ('decoded', 'not_decodable', 'unsupported')),
      validation_state TEXT NOT NULL CHECK (validation_state IN ('valid', 'invalid', 'not_applicable', 'not_evaluated')),
      decoded_value_ciphertext BLOB,
      decoded_value_key_version INTEGER,
      raw_response_ciphertext BLOB NOT NULL CHECK (length(raw_response_ciphertext) >= 29),
      raw_response_key_version INTEGER NOT NULL CHECK (raw_response_key_version >= 1),
      revision INTEGER NOT NULL CHECK (revision = 1),
      created_at TEXT NOT NULL,
      created_by_device_id TEXT NOT NULL CHECK (length(created_by_device_id) = 36),
      updated_at TEXT NOT NULL,
      updated_by_device_id TEXT NOT NULL CHECK (length(updated_by_device_id) = 36),
      PRIMARY KEY (user_scope_id, identification_value_id),
      UNIQUE (user_scope_id, ecu_observation_id, info_type_code, occurrence_ordinal),
      FOREIGN KEY (user_scope_id, ecu_observation_id) REFERENCES ecu_observations(user_scope_id, ecu_observation_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
      CHECK ((decode_state = 'decoded' AND decoded_value_ciphertext IS NOT NULL AND decoded_value_key_version IS NOT NULL AND length(decoded_value_ciphertext) >= 29 AND decoded_value_key_version >= 1) OR (decode_state <> 'decoded' AND decoded_value_ciphertext IS NULL AND decoded_value_key_version IS NULL)),
      CHECK (updated_at = created_at),
      CHECK (updated_by_device_id = created_by_device_id)
    ) STRICT;

    CREATE INDEX vehicles_active_order_idx ON vehicles(user_scope_id, lifecycle_state, updated_at DESC, vehicle_id);
    CREATE INDEX vehicle_scans_latest_valid_idx ON vehicle_identification_scans(user_scope_id, vehicle_id, finished_at DESC, scan_id DESC) WHERE vehicle_id IS NOT NULL AND scan_status = 'completed' AND identity_validation_state = 'valid';
    CREATE INDEX vehicle_scans_history_idx ON vehicle_identification_scans(user_scope_id, vehicle_id, started_at DESC, scan_id DESC) WHERE vehicle_id IS NOT NULL;
    CREATE INDEX unassigned_scans_history_idx ON vehicle_identification_scans(user_scope_id, started_at DESC, scan_id DESC) WHERE vehicle_id IS NULL;
    CREATE INDEX ecu_values_kind_idx ON ecu_identification_values(user_scope_id, ecu_observation_id, value_kind, info_type_code, occurrence_ordinal);

    CREATE TRIGGER database_scope_no_delete BEFORE DELETE ON database_scope BEGIN SELECT RAISE(ABORT, 'database_scope is immutable'); END;
    CREATE TRIGGER database_scope_no_update BEFORE UPDATE ON database_scope BEGIN SELECT RAISE(ABORT, 'database_scope requires dedicated maintenance'); END;

    CREATE TRIGGER vehicles_scope_insert BEFORE INSERT ON vehicles WHEN NEW.user_scope_id <> (SELECT user_scope_id FROM database_scope WHERE scope_row_id = 1) BEGIN SELECT RAISE(ABORT, 'scope mismatch'); END;
    CREATE TRIGGER vehicles_scope_update BEFORE UPDATE ON vehicles WHEN NEW.user_scope_id <> (SELECT user_scope_id FROM database_scope WHERE scope_row_id = 1) BEGIN SELECT RAISE(ABORT, 'scope mismatch'); END;
    CREATE TRIGGER vehicles_no_delete BEFORE DELETE ON vehicles BEGIN SELECT RAISE(ABORT, 'vehicles cannot be deleted'); END;
    CREATE TRIGGER vehicles_guard_update BEFORE UPDATE ON vehicles BEGIN
      SELECT CASE WHEN NEW.user_scope_id <> OLD.user_scope_id OR NEW.vehicle_id <> OLD.vehicle_id OR NEW.created_at <> OLD.created_at OR NEW.created_by_device_id <> OLD.created_by_device_id THEN RAISE(ABORT, 'immutable vehicle columns') END;
      SELECT CASE WHEN (NEW.display_name_ciphertext IS NOT OLD.display_name_ciphertext OR NEW.display_name_key_version IS NOT OLD.display_name_key_version) AND NEW.lifecycle_state <> OLD.lifecycle_state THEN RAISE(ABORT, 'separate field updates required') END;
      SELECT CASE WHEN NEW.display_name_ciphertext IS NOT OLD.display_name_ciphertext OR NEW.display_name_key_version IS NOT OLD.display_name_key_version THEN CASE WHEN NEW.display_name_revision <> OLD.display_name_revision + 1 OR NEW.record_revision <> OLD.record_revision + 1 OR NEW.display_name_updated_at IS OLD.display_name_updated_at OR NEW.lifecycle_revision <> OLD.lifecycle_revision OR NEW.lifecycle_updated_at <> OLD.lifecycle_updated_at OR NEW.lifecycle_updated_by_device_id <> OLD.lifecycle_updated_by_device_id OR NEW.archived_at IS NOT OLD.archived_at THEN RAISE(ABORT, 'invalid display name revision') END END;
      SELECT CASE WHEN NEW.lifecycle_state <> OLD.lifecycle_state THEN CASE WHEN NEW.lifecycle_revision <> OLD.lifecycle_revision + 1 OR NEW.record_revision <> OLD.record_revision + 1 OR NEW.lifecycle_updated_at = OLD.lifecycle_updated_at OR NEW.display_name_revision <> OLD.display_name_revision OR NEW.display_name_ciphertext IS NOT OLD.display_name_ciphertext OR NEW.display_name_key_version IS NOT OLD.display_name_key_version OR NEW.display_name_updated_at IS NOT OLD.display_name_updated_at OR NEW.display_name_updated_by_device_id IS NOT OLD.display_name_updated_by_device_id THEN RAISE(ABORT, 'invalid lifecycle revision') END END;
      SELECT CASE WHEN NEW.display_name_ciphertext IS OLD.display_name_ciphertext AND NEW.display_name_key_version IS OLD.display_name_key_version AND NEW.lifecycle_state = OLD.lifecycle_state THEN RAISE(ABORT, 'no supported vehicle change') END;
      SELECT CASE WHEN NEW.updated_at = OLD.updated_at THEN RAISE(ABORT, 'missing row update metadata') END;
    END;

    CREATE TRIGGER scans_scope_insert BEFORE INSERT ON vehicle_identification_scans WHEN NEW.user_scope_id <> (SELECT user_scope_id FROM database_scope WHERE scope_row_id = 1) BEGIN SELECT RAISE(ABORT, 'scope mismatch'); END;
    CREATE TRIGGER scans_no_update BEFORE UPDATE ON vehicle_identification_scans BEGIN SELECT RAISE(ABORT, 'scans are immutable'); END;
    CREATE TRIGGER scans_no_delete BEFORE DELETE ON vehicle_identification_scans BEGIN SELECT RAISE(ABORT, 'scans cannot be deleted'); END;

    CREATE TRIGGER identifiers_scope_insert BEFORE INSERT ON vehicle_identifiers WHEN NEW.user_scope_id <> (SELECT user_scope_id FROM database_scope WHERE scope_row_id = 1) BEGIN SELECT RAISE(ABORT, 'scope mismatch'); END;
    CREATE TRIGGER identifiers_validate_insert BEFORE INSERT ON vehicle_identifiers WHEN NOT EXISTS (SELECT 1 FROM vehicle_identification_scans s WHERE s.user_scope_id = NEW.user_scope_id AND s.vehicle_id = NEW.vehicle_id AND s.scan_id = NEW.source_scan_id AND s.scan_status = 'completed' AND s.identity_validation_state = 'valid') OR NEW.digest_key_version <> (SELECT active_digest_key_version FROM database_scope WHERE scope_row_id = 1) BEGIN SELECT RAISE(ABORT, 'invalid identifier evidence'); END;
    CREATE TRIGGER identifiers_no_update BEFORE UPDATE ON vehicle_identifiers BEGIN SELECT RAISE(ABORT, 'identifiers are immutable'); END;
    CREATE TRIGGER identifiers_no_delete BEFORE DELETE ON vehicle_identifiers BEGIN SELECT RAISE(ABORT, 'identifiers cannot be deleted'); END;

    CREATE TRIGGER observations_scope_insert BEFORE INSERT ON ecu_observations WHEN NEW.user_scope_id <> (SELECT user_scope_id FROM database_scope WHERE scope_row_id = 1) BEGIN SELECT RAISE(ABORT, 'scope mismatch'); END;
    CREATE TRIGGER observations_no_update BEFORE UPDATE ON ecu_observations BEGIN SELECT RAISE(ABORT, 'observations are immutable'); END;
    CREATE TRIGGER observations_no_delete BEFORE DELETE ON ecu_observations BEGIN SELECT RAISE(ABORT, 'observations cannot be deleted'); END;

    CREATE TRIGGER values_scope_insert BEFORE INSERT ON ecu_identification_values WHEN NEW.user_scope_id <> (SELECT user_scope_id FROM database_scope WHERE scope_row_id = 1) BEGIN SELECT RAISE(ABORT, 'scope mismatch'); END;
    CREATE TRIGGER values_no_update BEFORE UPDATE ON ecu_identification_values BEGIN SELECT RAISE(ABORT, 'identification values are immutable'); END;
    CREATE TRIGGER values_no_delete BEFORE DELETE ON ecu_identification_values BEGIN SELECT RAISE(ABORT, 'identification values cannot be deleted'); END;
    """
}
