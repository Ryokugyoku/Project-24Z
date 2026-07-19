/// 端末別Adapter既定候補と確認済みIdentity bindingのv5物理schemaです。
enum ConnectionSettingsSchema {
    /// 追記式Migrationの不変識別子です。
    nonisolated static let v5MigrationIdentifier = "v5_create_connection_settings"

    /// 候補履歴、Active一意制約、Identity監査を作成するSQLです。
    nonisolated static let v5SQL = """
    CREATE TABLE default_adapter_candidates (
      user_scope_id TEXT NOT NULL CHECK (length(user_scope_id) = 36),
      local_device_scope_id TEXT NOT NULL CHECK (length(local_device_scope_id) = 36),
      platform TEXT NOT NULL CHECK (platform IN ('iOS', 'macOS')),
      candidate_id TEXT NOT NULL CHECK (length(candidate_id) = 36),
      role TEXT NOT NULL CHECK (role IN ('primary_obd', 'secondary_raw_can')),
      endpoint_digest BLOB NOT NULL CHECK (length(endpoint_digest) = 32),
      display_name TEXT NOT NULL CHECK (length(display_name) BETWEEN 1 AND 128),
      transport_kind TEXT NOT NULL CHECK (transport_kind IN ('usb_serial', 'bluetooth_le', 'bluetooth_classic', 'tcp')),
      is_active INTEGER NOT NULL CHECK (is_active IN (0, 1)),
      revision INTEGER NOT NULL CHECK (revision >= 1),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (user_scope_id, local_device_scope_id, candidate_id),
      CHECK (updated_at >= created_at)
    ) STRICT;

    CREATE UNIQUE INDEX default_adapter_one_active_role_uidx
      ON default_adapter_candidates(user_scope_id, local_device_scope_id, role)
      WHERE is_active = 1;
    CREATE UNIQUE INDEX default_adapter_distinct_active_endpoint_uidx
      ON default_adapter_candidates(user_scope_id, local_device_scope_id, endpoint_digest)
      WHERE is_active = 1;
    CREATE INDEX default_adapter_history_idx
      ON default_adapter_candidates(user_scope_id, local_device_scope_id, role, updated_at DESC, candidate_id);

    CREATE TABLE verified_adapter_bindings (
      user_scope_id TEXT NOT NULL CHECK (length(user_scope_id) = 36),
      local_device_scope_id TEXT NOT NULL CHECK (length(local_device_scope_id) = 36),
      binding_id TEXT NOT NULL CHECK (length(binding_id) = 36),
      candidate_id TEXT NOT NULL CHECK (length(candidate_id) = 36),
      adapter_reference_digest BLOB NOT NULL CHECK (length(adapter_reference_digest) = 32),
      verification_version TEXT NOT NULL CHECK (length(verification_version) BETWEEN 1 AND 64),
      verified_at TEXT NOT NULL,
      PRIMARY KEY (user_scope_id, local_device_scope_id, binding_id),
      UNIQUE (user_scope_id, local_device_scope_id, candidate_id),
      FOREIGN KEY (user_scope_id, local_device_scope_id, candidate_id)
        REFERENCES default_adapter_candidates(user_scope_id, local_device_scope_id, candidate_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
    ) STRICT;
    CREATE INDEX verified_binding_reference_history_idx
      ON verified_adapter_bindings(user_scope_id, local_device_scope_id, adapter_reference_digest, verified_at DESC);

    CREATE TRIGGER default_adapter_scope_insert
      BEFORE INSERT ON default_adapter_candidates
      WHEN NEW.user_scope_id <> (SELECT user_scope_id FROM database_scope WHERE scope_row_id = 1)
      BEGIN SELECT RAISE(ABORT, 'scope mismatch'); END;
    CREATE TRIGGER default_adapter_no_delete
      BEFORE DELETE ON default_adapter_candidates
      BEGIN SELECT RAISE(ABORT, 'adapter candidate history cannot be deleted'); END;
    CREATE TRIGGER default_adapter_guard_update
      BEFORE UPDATE ON default_adapter_candidates
      BEGIN
        SELECT CASE WHEN NEW.user_scope_id <> OLD.user_scope_id
          OR NEW.local_device_scope_id <> OLD.local_device_scope_id
          OR NEW.platform <> OLD.platform
          OR NEW.candidate_id <> OLD.candidate_id
          OR NEW.role <> OLD.role
          OR NEW.endpoint_digest <> OLD.endpoint_digest
          OR NEW.display_name <> OLD.display_name
          OR NEW.transport_kind <> OLD.transport_kind
          OR OLD.is_active <> 1 OR NEW.is_active <> 0
          OR NEW.revision <> OLD.revision + 1
          OR NEW.created_at <> OLD.created_at
          OR NEW.updated_at = OLD.updated_at
          THEN RAISE(ABORT, 'only explicit candidate deactivation is allowed') END;
      END;

    CREATE TRIGGER verified_binding_scope_insert
      BEFORE INSERT ON verified_adapter_bindings
      WHEN NEW.user_scope_id <> (SELECT user_scope_id FROM database_scope WHERE scope_row_id = 1)
      BEGIN SELECT RAISE(ABORT, 'scope mismatch'); END;
    CREATE TRIGGER verified_binding_candidate_scope_insert
      BEFORE INSERT ON verified_adapter_bindings
      WHEN NOT EXISTS (
        SELECT 1 FROM default_adapter_candidates c
        WHERE c.user_scope_id = NEW.user_scope_id
          AND c.local_device_scope_id = NEW.local_device_scope_id
          AND c.candidate_id = NEW.candidate_id
      )
      BEGIN SELECT RAISE(ABORT, 'candidate scope mismatch'); END;
    CREATE TRIGGER verified_binding_active_candidate_insert
      BEFORE INSERT ON verified_adapter_bindings
      WHEN NOT EXISTS (
        SELECT 1 FROM default_adapter_candidates c
        WHERE c.user_scope_id = NEW.user_scope_id
          AND c.local_device_scope_id = NEW.local_device_scope_id
          AND c.candidate_id = NEW.candidate_id
          AND c.is_active = 1
      )
      BEGIN SELECT RAISE(ABORT, 'binding requires active candidate'); END;
    CREATE TRIGGER verified_binding_distinct_active_reference_insert
      BEFORE INSERT ON verified_adapter_bindings
      WHEN EXISTS (
        SELECT 1
        FROM verified_adapter_bindings b
        JOIN default_adapter_candidates c
          ON c.user_scope_id = b.user_scope_id
         AND c.local_device_scope_id = b.local_device_scope_id
         AND c.candidate_id = b.candidate_id
        WHERE b.user_scope_id = NEW.user_scope_id
          AND b.local_device_scope_id = NEW.local_device_scope_id
          AND b.adapter_reference_digest = NEW.adapter_reference_digest
          AND c.is_active = 1
      )
      BEGIN SELECT RAISE(ABORT, 'active roles require distinct physical adapters'); END;
    CREATE TRIGGER verified_binding_no_update
      BEFORE UPDATE ON verified_adapter_bindings
      BEGIN SELECT RAISE(ABORT, 'verified binding is immutable'); END;
    CREATE TRIGGER verified_binding_no_delete
      BEFORE DELETE ON verified_adapter_bindings
      BEGIN SELECT RAISE(ABORT, 'verified binding history cannot be deleted'); END;
    """
}
