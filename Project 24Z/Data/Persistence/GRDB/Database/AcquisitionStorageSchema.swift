import GRDB

/// Acquisition Session Storeの追記式v2物理schemaを定義します。
enum AcquisitionStorageSchema {
    /// Vehicle Identity Store v1へ追記するMigration識別子です。
    nonisolated static let v2MigrationIdentifier = "v2_create_acquisition_storage"

    /// Session、Stream、Epoch、Gap、Chunk目録、保全Findingを作るSQLです。
    nonisolated static let v2SQL = """
    CREATE TABLE acquisition_sessions (
      user_scope_id TEXT NOT NULL CHECK(length(user_scope_id) = 36),
      session_id TEXT NOT NULL CHECK(length(session_id) = 36),
      vehicle_id TEXT CHECK(vehicle_id IS NULL OR length(vehicle_id) = 36),
      vehicle_binding_state TEXT NOT NULL CHECK(vehicle_binding_state IN ('registered_confirmed','unassigned_unidentified','unassigned_conflict')),
      capture_state TEXT NOT NULL CHECK(capture_state IN ('recording','stop_requested','ended_cleanly','recovery_required')),
      disposition_state TEXT NOT NULL CHECK(disposition_state IN ('pending_decision','saved','discard_pending','discarded','delete_pending','deleted')),
      integrity_state TEXT NOT NULL CHECK(integrity_state IN ('unchecked','verified','attention_required','unavailable')),
      end_reason_code TEXT CHECK(end_reason_code IS NULL OR end_reason_code IN ('user_stop','storage_critical','application_termination','process_termination','device_restart','write_pipeline_failure','unknown')),
      started_at_utc TEXT NOT NULL,
      ended_at_utc TEXT,
      reviewed_at_utc TEXT,
      disposition_requested_at_utc TEXT,
      disposition_completed_at_utc TEXT,
      created_by_device_id TEXT NOT NULL CHECK(length(created_by_device_id) = 36),
      record_revision INTEGER NOT NULL CHECK(record_revision >= 1),
      updated_at_utc TEXT NOT NULL,
      updated_by_device_id TEXT NOT NULL CHECK(length(updated_by_device_id) = 36),
      PRIMARY KEY(user_scope_id, session_id),
      UNIQUE(user_scope_id, vehicle_id, session_id),
      FOREIGN KEY(user_scope_id, vehicle_id) REFERENCES vehicles(user_scope_id, vehicle_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
      CHECK((vehicle_binding_state = 'registered_confirmed') = (vehicle_id IS NOT NULL)),
      CHECK((capture_state IN ('recording','stop_requested') AND ended_at_utc IS NULL AND end_reason_code IS NULL) OR (capture_state IN ('ended_cleanly','recovery_required') AND ended_at_utc IS NOT NULL AND end_reason_code IS NOT NULL)),
      CHECK(capture_state <> 'ended_cleanly' OR end_reason_code = 'user_stop'),
      CHECK(disposition_state = 'pending_decision' OR capture_state IN ('ended_cleanly','recovery_required')),
      CHECK(disposition_state <> 'saved' OR integrity_state = 'verified'),
      CHECK(updated_at_utc >= started_at_utc)
    ) STRICT;

    CREATE UNIQUE INDEX acquisition_sessions_one_in_progress_per_scope_uidx ON acquisition_sessions(user_scope_id) WHERE capture_state IN ('recording','stop_requested');
    CREATE INDEX acquisition_sessions_recovery_idx ON acquisition_sessions(user_scope_id,capture_state,updated_at_utc);

    CREATE TABLE acquisition_streams (
      user_scope_id TEXT NOT NULL,
      stream_id TEXT NOT NULL CHECK(length(stream_id) = 36),
      session_id TEXT NOT NULL CHECK(length(session_id) = 36),
      stream_kind TEXT NOT NULL CHECK(stream_kind IN ('obd_pid','raw_can')),
      adapter_role TEXT NOT NULL CHECK(adapter_role IN ('primary','secondary')),
      adapter_reference_id TEXT NOT NULL CHECK(length(adapter_reference_id) BETWEEN 1 AND 128),
      connection_instance_id TEXT NOT NULL CHECK(length(connection_instance_id) = 36),
      stream_state TEXT NOT NULL CHECK(stream_state IN ('active','pause_requested','paused','reconnecting','stop_requested','stopped','interrupted')),
      started_at_utc TEXT NOT NULL,
      ended_at_utc TEXT,
      next_record_sequence INTEGER NOT NULL CHECK(next_record_sequence >= 0),
      next_chunk_sequence INTEGER NOT NULL CHECK(next_chunk_sequence >= 0),
      record_revision INTEGER NOT NULL CHECK(record_revision >= 1),
      updated_at_utc TEXT NOT NULL,
      PRIMARY KEY(user_scope_id, stream_id),
      UNIQUE(user_scope_id, session_id, stream_kind),
      UNIQUE(user_scope_id, session_id, stream_id),
      UNIQUE(user_scope_id, session_id, adapter_reference_id),
      UNIQUE(user_scope_id, connection_instance_id),
      FOREIGN KEY(user_scope_id, session_id) REFERENCES acquisition_sessions(user_scope_id, session_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
      CHECK((stream_kind = 'obd_pid' AND adapter_role = 'primary') OR (stream_kind = 'raw_can' AND adapter_role = 'secondary')),
      CHECK((stream_state IN ('stopped','interrupted')) = (ended_at_utc IS NOT NULL))
    ) STRICT;

    CREATE TABLE clock_epochs (
      user_scope_id TEXT NOT NULL,
      clock_epoch_id TEXT NOT NULL CHECK(length(clock_epoch_id) = 36),
      session_id TEXT NOT NULL CHECK(length(session_id) = 36),
      process_instance_id TEXT NOT NULL CHECK(length(process_instance_id) = 36),
      device_id TEXT NOT NULL CHECK(length(device_id) = 36),
      monotonic_clock_kind TEXT NOT NULL CHECK(monotonic_clock_kind = 'continuous_host_time'),
      wall_clock_anchor_utc TEXT NOT NULL,
      anchor_uncertainty_ns INTEGER NOT NULL CHECK(anchor_uncertainty_ns >= 0),
      started_at_utc TEXT NOT NULL,
      ended_at_utc TEXT,
      revision INTEGER NOT NULL CHECK(revision IN (1,2)),
      PRIMARY KEY(user_scope_id, clock_epoch_id),
      UNIQUE(user_scope_id, session_id, clock_epoch_id),
      UNIQUE(user_scope_id, process_instance_id, session_id),
      FOREIGN KEY(user_scope_id, session_id) REFERENCES acquisition_sessions(user_scope_id, session_id) ON DELETE RESTRICT ON UPDATE RESTRICT
    ) STRICT;

    CREATE TABLE acquisition_gaps (
      user_scope_id TEXT NOT NULL,
      gap_id TEXT NOT NULL CHECK(length(gap_id) = 36),
      session_id TEXT NOT NULL CHECK(length(session_id) = 36),
      stream_id TEXT NOT NULL CHECK(length(stream_id) = 36),
      reason_code TEXT NOT NULL CHECK(reason_code IN ('adapter_disconnected','transport_interrupted','ios_background_or_application_termination','macos_sleep_or_process_termination','reconnection_in_progress','buffer_overflow_or_processing_drop','storage_capacity_critical','write_encryption_or_integrity_failure','user_paused','unknown')),
      detection_method TEXT NOT NULL CHECK(detection_method IN ('transport_event','lifecycle_event','sequence_audit','buffer_accounting','storage_monitor','write_verification','startup_recovery','user_action','unknown')),
      start_boundary_certainty TEXT NOT NULL CHECK(start_boundary_certainty IN ('confirmed','estimated')),
      start_clock_epoch_id TEXT NOT NULL,
      start_monotonic_ns INTEGER CHECK(start_monotonic_ns IS NULL OR start_monotonic_ns >= 0),
      start_utc TEXT NOT NULL,
      end_clock_epoch_id TEXT,
      end_monotonic_ns INTEGER CHECK(end_monotonic_ns IS NULL OR end_monotonic_ns >= 0),
      end_utc TEXT,
      end_boundary_certainty TEXT CHECK(end_boundary_certainty IS NULL OR end_boundary_certainty IN ('confirmed','estimated')),
      first_missing_sequence INTEGER CHECK(first_missing_sequence IS NULL OR first_missing_sequence >= 0),
      missing_record_count INTEGER CHECK(missing_record_count IS NULL OR missing_record_count >= 0),
      revision INTEGER NOT NULL CHECK(revision IN (1,2)),
      created_at_utc TEXT NOT NULL,
      PRIMARY KEY(user_scope_id, gap_id),
      UNIQUE(user_scope_id, stream_id, gap_id),
      FOREIGN KEY(user_scope_id, session_id, stream_id) REFERENCES acquisition_streams(user_scope_id, session_id, stream_id) ON DELETE RESTRICT,
      FOREIGN KEY(user_scope_id, session_id, start_clock_epoch_id) REFERENCES clock_epochs(user_scope_id, session_id, clock_epoch_id) ON DELETE RESTRICT,
      FOREIGN KEY(user_scope_id, session_id, end_clock_epoch_id) REFERENCES clock_epochs(user_scope_id, session_id, clock_epoch_id) ON DELETE RESTRICT,
      CHECK((revision = 1 AND end_utc IS NULL AND end_clock_epoch_id IS NULL AND end_monotonic_ns IS NULL AND end_boundary_certainty IS NULL) OR (revision = 2 AND end_utc IS NOT NULL AND end_clock_epoch_id IS NOT NULL AND end_boundary_certainty IS NOT NULL))
    ) STRICT;

    CREATE INDEX acquisition_gaps_open_idx ON acquisition_gaps(user_scope_id,session_id,stream_id) WHERE end_utc IS NULL;

    CREATE TABLE log_chunks (
      user_scope_id TEXT NOT NULL,
      chunk_id TEXT NOT NULL CHECK(length(chunk_id) = 36),
      session_id TEXT NOT NULL CHECK(length(session_id) = 36),
      stream_id TEXT NOT NULL CHECK(length(stream_id) = 36),
      chunk_sequence INTEGER NOT NULL CHECK(chunk_sequence >= 0),
      clock_epoch_id TEXT NOT NULL CHECK(length(clock_epoch_id) = 36),
      first_record_sequence INTEGER NOT NULL CHECK(first_record_sequence >= 0),
      last_record_sequence INTEGER NOT NULL CHECK(last_record_sequence >= first_record_sequence),
      first_monotonic_ns INTEGER NOT NULL CHECK(first_monotonic_ns >= 0),
      last_monotonic_ns INTEGER NOT NULL CHECK(last_monotonic_ns >= first_monotonic_ns),
      record_count INTEGER NOT NULL CHECK(record_count > 0 AND record_count = last_record_sequence - first_record_sequence + 1),
      plaintext_size INTEGER NOT NULL CHECK(plaintext_size >= 0),
      compressed_size INTEGER NOT NULL CHECK(compressed_size >= 0),
      ciphertext_size INTEGER NOT NULL CHECK(ciphertext_size > 0),
      record_format_version INTEGER NOT NULL CHECK(record_format_version > 0),
      compression_format_version INTEGER NOT NULL CHECK(compression_format_version > 0),
      encryption_format_version INTEGER NOT NULL CHECK(encryption_format_version > 0),
      key_version INTEGER NOT NULL CHECK(key_version > 0),
      ciphertext_digest BLOB NOT NULL CHECK(length(ciphertext_digest) = 32),
      catalog_digest BLOB NOT NULL CHECK(length(catalog_digest) = 32),
      relative_path TEXT NOT NULL CHECK(length(relative_path) > 0),
      storage_state TEXT NOT NULL CHECK(storage_state IN ('available','quarantined','missing','delete_pending','deleted')),
      revision INTEGER NOT NULL CHECK(revision >= 1),
      created_at_utc TEXT NOT NULL,
      updated_at_utc TEXT NOT NULL,
      PRIMARY KEY(user_scope_id, chunk_id),
      UNIQUE(user_scope_id, session_id, chunk_id),
      UNIQUE(user_scope_id, stream_id, chunk_sequence),
      UNIQUE(user_scope_id, stream_id, first_record_sequence),
      UNIQUE(user_scope_id, relative_path),
      FOREIGN KEY(user_scope_id, session_id, stream_id) REFERENCES acquisition_streams(user_scope_id, session_id, stream_id) ON DELETE RESTRICT,
      FOREIGN KEY(user_scope_id, session_id, clock_epoch_id) REFERENCES clock_epochs(user_scope_id, session_id, clock_epoch_id) ON DELETE RESTRICT,
      CHECK(updated_at_utc >= created_at_utc)
    ) STRICT;

    CREATE INDEX log_chunks_session_idx ON log_chunks(user_scope_id,session_id,stream_id,chunk_sequence);
    CREATE INDEX log_chunks_state_idx ON log_chunks(user_scope_id,storage_state,updated_at_utc);

    CREATE TABLE storage_integrity_findings (
      user_scope_id TEXT NOT NULL,
      finding_id TEXT NOT NULL CHECK(length(finding_id) = 36),
      session_id TEXT,
      catalog_chunk_id TEXT,
      observed_session_id TEXT CHECK(observed_session_id IS NULL OR length(observed_session_id) = 36),
      observed_chunk_id TEXT CHECK(observed_chunk_id IS NULL OR length(observed_chunk_id) = 36),
      finding_kind TEXT NOT NULL CHECK(finding_kind IN ('orphan_file','missing_file','chunk_sequence_gap','record_sequence_gap','authentication_failed','digest_mismatch','truncated_file','header_catalog_mismatch','unexpected_temporary_file')),
      resolution_state TEXT NOT NULL CHECK(resolution_state IN ('detected','quarantined','retryable','resolved','acknowledged_unrecoverable')),
      observed_relative_path TEXT,
      quarantine_relative_path TEXT,
      diagnostic_id TEXT NOT NULL CHECK(length(diagnostic_id) = 36),
      detected_at_utc TEXT NOT NULL,
      resolved_at_utc TEXT,
      revision INTEGER NOT NULL CHECK(revision >= 1),
      PRIMARY KEY(user_scope_id, finding_id),
      FOREIGN KEY(user_scope_id, session_id) REFERENCES acquisition_sessions(user_scope_id, session_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
      FOREIGN KEY(user_scope_id, session_id, catalog_chunk_id) REFERENCES log_chunks(user_scope_id, session_id, chunk_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
      CHECK(catalog_chunk_id IS NULL OR session_id IS NOT NULL),
      CHECK((resolution_state IN ('resolved','acknowledged_unrecoverable')) = (resolved_at_utc IS NOT NULL))
    ) STRICT;

    CREATE INDEX storage_findings_open_idx ON storage_integrity_findings(user_scope_id,resolution_state,detected_at_utc);

    CREATE TRIGGER acquisition_sessions_scope_insert BEFORE INSERT ON acquisition_sessions WHEN NEW.user_scope_id <> (SELECT user_scope_id FROM database_scope WHERE scope_row_id=1) BEGIN SELECT RAISE(ABORT,'scope mismatch'); END;
    CREATE TRIGGER acquisition_sessions_no_delete BEFORE DELETE ON acquisition_sessions BEGIN SELECT RAISE(ABORT,'sessions cannot be deleted'); END;
    CREATE TRIGGER acquisition_sessions_guard_update BEFORE UPDATE ON acquisition_sessions BEGIN
      SELECT CASE WHEN NEW.user_scope_id <> OLD.user_scope_id OR NEW.session_id <> OLD.session_id OR NEW.started_at_utc <> OLD.started_at_utc OR NEW.created_by_device_id <> OLD.created_by_device_id THEN RAISE(ABORT,'immutable session columns') END;
      SELECT CASE WHEN OLD.vehicle_id IS NOT NULL AND NEW.vehicle_id IS NOT OLD.vehicle_id THEN RAISE(ABORT,'vehicle binding is immutable') END;
      SELECT CASE WHEN OLD.vehicle_id IS NULL AND NEW.vehicle_id IS NOT NULL AND (OLD.vehicle_binding_state NOT IN ('unassigned_unidentified','unassigned_conflict') OR NEW.vehicle_binding_state <> 'registered_confirmed' OR OLD.disposition_state <> 'pending_decision') THEN RAISE(ABORT,'invalid vehicle binding') END;
      SELECT CASE WHEN NEW.record_revision <> OLD.record_revision + 1 OR NEW.updated_at_utc <= OLD.updated_at_utc THEN RAISE(ABORT,'invalid session revision') END;
      SELECT CASE WHEN OLD.capture_state IN ('ended_cleanly','recovery_required') AND NEW.capture_state <> OLD.capture_state THEN RAISE(ABORT,'capture state is terminal') END;
    END;

    CREATE TRIGGER acquisition_streams_scope_insert BEFORE INSERT ON acquisition_streams WHEN NEW.user_scope_id <> (SELECT user_scope_id FROM database_scope WHERE scope_row_id=1) BEGIN SELECT RAISE(ABORT,'scope mismatch'); END;
    CREATE TRIGGER acquisition_streams_no_delete BEFORE DELETE ON acquisition_streams BEGIN SELECT RAISE(ABORT,'streams cannot be deleted'); END;
    CREATE TRIGGER acquisition_streams_guard_update BEFORE UPDATE ON acquisition_streams BEGIN
      SELECT CASE WHEN NEW.user_scope_id <> OLD.user_scope_id OR NEW.stream_id <> OLD.stream_id OR NEW.session_id <> OLD.session_id OR NEW.stream_kind <> OLD.stream_kind OR NEW.adapter_role <> OLD.adapter_role OR NEW.adapter_reference_id <> OLD.adapter_reference_id OR NEW.connection_instance_id <> OLD.connection_instance_id OR NEW.started_at_utc <> OLD.started_at_utc THEN RAISE(ABORT,'immutable stream columns') END;
      SELECT CASE WHEN NEW.record_revision <> OLD.record_revision + 1 OR NEW.updated_at_utc <= OLD.updated_at_utc THEN RAISE(ABORT,'invalid stream revision') END;
    END;

    CREATE TRIGGER clock_epochs_no_delete BEFORE DELETE ON clock_epochs BEGIN SELECT RAISE(ABORT,'epochs cannot be deleted'); END;
    CREATE TRIGGER acquisition_gaps_no_delete BEFORE DELETE ON acquisition_gaps BEGIN SELECT RAISE(ABORT,'gaps cannot be deleted'); END;
    CREATE TRIGGER log_chunks_no_delete BEFORE DELETE ON log_chunks BEGIN SELECT RAISE(ABORT,'chunks cannot be deleted'); END;
    CREATE TRIGGER log_chunks_guard_update BEFORE UPDATE ON log_chunks BEGIN
      SELECT CASE WHEN NEW.user_scope_id <> OLD.user_scope_id OR NEW.chunk_id <> OLD.chunk_id OR NEW.session_id <> OLD.session_id OR NEW.stream_id <> OLD.stream_id OR NEW.chunk_sequence <> OLD.chunk_sequence OR NEW.clock_epoch_id <> OLD.clock_epoch_id OR NEW.first_record_sequence <> OLD.first_record_sequence OR NEW.last_record_sequence <> OLD.last_record_sequence OR NEW.first_monotonic_ns <> OLD.first_monotonic_ns OR NEW.last_monotonic_ns <> OLD.last_monotonic_ns OR NEW.record_count <> OLD.record_count OR NEW.plaintext_size <> OLD.plaintext_size OR NEW.compressed_size <> OLD.compressed_size OR NEW.ciphertext_size <> OLD.ciphertext_size OR NEW.record_format_version <> OLD.record_format_version OR NEW.compression_format_version <> OLD.compression_format_version OR NEW.encryption_format_version <> OLD.encryption_format_version OR NEW.key_version <> OLD.key_version OR NEW.ciphertext_digest <> OLD.ciphertext_digest OR NEW.catalog_digest <> OLD.catalog_digest OR NEW.relative_path <> OLD.relative_path OR NEW.created_at_utc <> OLD.created_at_utc THEN RAISE(ABORT,'immutable chunk columns') END;
      SELECT CASE WHEN NEW.revision <> OLD.revision + 1 OR NEW.updated_at_utc <= OLD.updated_at_utc THEN RAISE(ABORT,'invalid chunk revision') END;
      SELECT CASE WHEN NOT ((OLD.storage_state='available' AND NEW.storage_state IN ('quarantined','missing','delete_pending')) OR (OLD.storage_state='quarantined' AND NEW.storage_state IN ('available','missing','delete_pending')) OR (OLD.storage_state='missing' AND NEW.storage_state IN ('available','quarantined','delete_pending')) OR (OLD.storage_state='delete_pending' AND NEW.storage_state='deleted')) THEN RAISE(ABORT,'invalid chunk state transition') END;
    END;
    """
}
