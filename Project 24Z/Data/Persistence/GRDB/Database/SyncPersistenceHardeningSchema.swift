import GRDB

/// 旧v3同期台帳を非破壊で強化する追記式v4 Migrationです。
enum SyncPersistenceHardeningSchema {
    /// 旧v3とは別に適用するMigration識別子です。
    nonisolated static let v4MigrationIdentifier = "v4_harden_sync_state_machines"

    /// 遷移来歴列、初期INSERT制約、Materialization不変制約を追記するSQLです。
    nonisolated static let v4SQL = """
    ALTER TABLE session_transfers ADD COLUMN transition_step INTEGER NOT NULL DEFAULT 0 CHECK(transition_step>=0);
    ALTER TABLE chunk_transfers ADD COLUMN transition_step INTEGER NOT NULL DEFAULT 0 CHECK(transition_step>=0);
    ALTER TABLE chunk_transfer_segments ADD COLUMN transition_step INTEGER NOT NULL DEFAULT 0 CHECK(transition_step>=0);
    ALTER TABLE wrapped_key_receipts ADD COLUMN transition_step INTEGER NOT NULL DEFAULT 0 CHECK(transition_step>=0);

    CREATE TRIGGER session_transfer_initial_state_guard BEFORE INSERT ON session_transfers
    WHEN NEW.transfer_state<>'manifest_pending' OR NEW.transition_step<>0
    BEGIN SELECT RAISE(ABORT,'session transfer must start manifest_pending'); END;
    CREATE TRIGGER chunk_transfer_initial_state_guard BEFORE INSERT ON chunk_transfers
    WHEN NEW.transfer_state<>'pending' OR NEW.transition_step<>0
    BEGIN SELECT RAISE(ABORT,'chunk transfer must start pending'); END;
    CREATE TRIGGER chunk_segment_initial_state_guard BEFORE INSERT ON chunk_transfer_segments
    WHEN NEW.segment_state<>'expected' OR NEW.transition_step<>0
    BEGIN SELECT RAISE(ABORT,'chunk segment must start expected'); END;
    CREATE TRIGGER wrapped_key_initial_state_guard BEFORE INSERT ON wrapped_key_receipts
    WHEN NEW.receipt_state<>'received' OR NEW.transition_step<>0
    BEGIN SELECT RAISE(ABORT,'wrapped key must start received'); END;

    CREATE TRIGGER session_transfer_transition_step_guard BEFORE UPDATE OF transfer_state ON session_transfers
    WHEN NEW.transfer_state<>OLD.transfer_state AND NEW.transition_step<>OLD.transition_step+1
    BEGIN SELECT RAISE(ABORT,'session transition step mismatch'); END;
    CREATE TRIGGER session_transfer_step_immutable BEFORE UPDATE OF transition_step ON session_transfers
    WHEN NEW.transition_step<>OLD.transition_step AND (NEW.transfer_state=OLD.transfer_state OR NEW.transition_step<>OLD.transition_step+1)
    BEGIN SELECT RAISE(ABORT,'session transition step is guarded'); END;
    CREATE TRIGGER chunk_transfer_transition_step_guard BEFORE UPDATE OF transfer_state ON chunk_transfers
    WHEN NEW.transfer_state<>OLD.transfer_state AND NEW.transition_step<>OLD.transition_step+1
    BEGIN SELECT RAISE(ABORT,'chunk transition step mismatch'); END;
    CREATE TRIGGER chunk_transfer_step_immutable BEFORE UPDATE OF transition_step ON chunk_transfers
    WHEN NEW.transition_step<>OLD.transition_step AND (NEW.transfer_state=OLD.transfer_state OR NEW.transition_step<>OLD.transition_step+1)
    BEGIN SELECT RAISE(ABORT,'chunk transition step is guarded'); END;
    CREATE TRIGGER chunk_segment_transition_step_guard BEFORE UPDATE OF segment_state ON chunk_transfer_segments
    WHEN NEW.segment_state<>OLD.segment_state AND NEW.transition_step<>OLD.transition_step+1
    BEGIN SELECT RAISE(ABORT,'segment transition step mismatch'); END;
    CREATE TRIGGER chunk_segment_step_immutable BEFORE UPDATE OF transition_step ON chunk_transfer_segments
    WHEN NEW.transition_step<>OLD.transition_step AND (NEW.segment_state=OLD.segment_state OR NEW.transition_step<>OLD.transition_step+1)
    BEGIN SELECT RAISE(ABORT,'segment transition step is guarded'); END;
    CREATE TRIGGER wrapped_key_transition_step_guard BEFORE UPDATE OF receipt_state ON wrapped_key_receipts
    WHEN NEW.receipt_state<>OLD.receipt_state AND NEW.transition_step<>OLD.transition_step+1
    BEGIN SELECT RAISE(ABORT,'wrapped key transition step mismatch'); END;
    CREATE TRIGGER wrapped_key_step_immutable BEFORE UPDATE OF transition_step ON wrapped_key_receipts
    WHEN NEW.transition_step<>OLD.transition_step AND (NEW.receipt_state=OLD.receipt_state OR NEW.transition_step<>OLD.transition_step+1)
    BEGIN SELECT RAISE(ABORT,'wrapped key transition step is guarded'); END;

    CREATE TRIGGER wrapped_key_transition_guard BEFORE UPDATE OF receipt_state ON wrapped_key_receipts
    WHEN NOT((OLD.receipt_state='received' AND NEW.receipt_state IN ('verified','quarantined')) OR (OLD.receipt_state='verified' AND NEW.receipt_state IN ('applied','quarantined')))
    BEGIN SELECT RAISE(ABORT,'invalid wrapped key transition'); END;

    DROP TRIGGER segments_complete_guard;
    CREATE TRIGGER segments_complete_guard BEFORE UPDATE OF transfer_state ON chunk_transfers WHEN NEW.transfer_state='segments_complete' AND (OLD.transition_step<1 OR NOT EXISTS(SELECT 1 FROM chunk_transfer_segments s WHERE s.user_scope_id=OLD.user_scope_id AND s.chunk_transfer_id=OLD.chunk_transfer_id) OR EXISTS(SELECT 1 FROM chunk_transfer_segments s WHERE s.user_scope_id=OLD.user_scope_id AND s.chunk_transfer_id=OLD.chunk_transfer_id AND (s.segment_state<>'verified' OR s.transition_step<2)) OR (SELECT MIN(byte_offset) FROM chunk_transfer_segments s WHERE s.user_scope_id=OLD.user_scope_id AND s.chunk_transfer_id=OLD.chunk_transfer_id)<>0 OR (SELECT SUM(byte_length) FROM chunk_transfer_segments s WHERE s.user_scope_id=OLD.user_scope_id AND s.chunk_transfer_id=OLD.chunk_transfer_id)<>OLD.ciphertext_size OR EXISTS(SELECT 1 FROM chunk_transfer_segments s WHERE s.user_scope_id=OLD.user_scope_id AND s.chunk_transfer_id=OLD.chunk_transfer_id AND s.segment_index>0 AND NOT EXISTS(SELECT 1 FROM chunk_transfer_segments p WHERE p.user_scope_id=s.user_scope_id AND p.chunk_transfer_id=s.chunk_transfer_id AND p.segment_index=s.segment_index-1 AND p.byte_offset+p.byte_length=s.byte_offset))) BEGIN SELECT RAISE(ABORT,'segments not durable'); END;

    DROP TRIGGER session_durable_guard;
    CREATE TRIGGER session_durable_guard BEFORE UPDATE OF transfer_state ON session_transfers WHEN NEW.transfer_state='durable' AND (OLD.transition_step<2 OR (SELECT COUNT(*) FROM chunk_transfers c WHERE c.user_scope_id=OLD.user_scope_id AND c.session_transfer_id=OLD.session_transfer_id AND c.transfer_state='cataloged' AND c.transition_step>=5)<>OLD.expected_chunk_count OR COALESCE((SELECT SUM(ciphertext_size) FROM chunk_transfers c WHERE c.user_scope_id=OLD.user_scope_id AND c.session_transfer_id=OLD.session_transfer_id AND c.transfer_state='cataloged' AND c.transition_step>=5),0)<>OLD.expected_ciphertext_bytes OR EXISTS(SELECT 1 FROM chunk_transfers c WHERE c.user_scope_id=OLD.user_scope_id AND c.session_transfer_id=OLD.session_transfer_id AND NOT EXISTS(SELECT 1 FROM wrapped_key_receipts k JOIN sync_batches b ON b.user_scope_id=OLD.user_scope_id AND b.batch_id=OLD.batch_id WHERE k.user_scope_id=OLD.user_scope_id AND k.sender_identity_id=b.peer_identity_id AND k.key_purpose='session_chunk' AND k.wrapped_key_version=c.key_version AND k.bound_session_id=OLD.session_id AND k.bound_chunk_id=c.chunk_id AND k.receipt_state='applied' AND k.transition_step>=2))) BEGIN SELECT RAISE(ABORT,'durable ack conditions not met'); END;

    CREATE TRIGGER materialization_initial_state_guard BEFORE INSERT ON origin_entity_materializations
    WHEN NEW.materialization_state<>'projected'
    BEGIN SELECT RAISE(ABORT,'materialization must start projected'); END;
    CREATE TRIGGER materialization_transition_guard BEFORE UPDATE OF materialization_state ON origin_entity_materializations
    WHEN NEW.materialization_state<>OLD.materialization_state AND NOT((OLD.materialization_state='projected' AND NEW.materialization_state IN ('applied','conflicted','quarantined')) OR (OLD.materialization_state='applied' AND NEW.materialization_state='superseded_projection'))
    BEGIN SELECT RAISE(ABORT,'invalid materialization transition'); END;
    CREATE TRIGGER materialization_graph_immutable BEFORE UPDATE ON origin_entity_materializations WHEN
      NEW.user_scope_id IS NOT OLD.user_scope_id OR NEW.materialization_id IS NOT OLD.materialization_id OR
      NEW.logical_change_id IS NOT OLD.logical_change_id OR NEW.origin_device_identity_id IS NOT OLD.origin_device_identity_id OR NEW.origin_change_id IS NOT OLD.origin_change_id OR
      NEW.entity_kind IS NOT OLD.entity_kind OR NEW.origin_entity_id IS NOT OLD.origin_entity_id OR NEW.origin_vehicle_id IS NOT OLD.origin_vehicle_id OR
      NEW.origin_parent_entity_kind IS NOT OLD.origin_parent_entity_kind OR NEW.origin_parent_entity_id IS NOT OLD.origin_parent_entity_id OR
      NEW.origin_entity_version IS NOT OLD.origin_entity_version OR NEW.origin_content_digest IS NOT OLD.origin_content_digest OR NEW.origin_envelope_storage IS NOT OLD.origin_envelope_storage OR
      NEW.vehicle_alias_id IS NOT OLD.vehicle_alias_id OR NEW.graph_generation IS NOT OLD.graph_generation OR NEW.projection_version IS NOT OLD.projection_version OR NEW.canonical_vehicle_id IS NOT OLD.canonical_vehicle_id OR
      NEW.parent_materialization_id IS NOT OLD.parent_materialization_id OR NEW.materialized_parent_entity_id IS NOT OLD.materialized_parent_entity_id OR
      NEW.origin_secondary_parent_entity_kind IS NOT OLD.origin_secondary_parent_entity_kind OR NEW.origin_secondary_parent_entity_id IS NOT OLD.origin_secondary_parent_entity_id OR NEW.secondary_parent_materialization_id IS NOT OLD.secondary_parent_materialization_id OR NEW.materialized_secondary_parent_entity_id IS NOT OLD.materialized_secondary_parent_entity_id OR
      NEW.origin_tertiary_parent_entity_kind IS NOT OLD.origin_tertiary_parent_entity_kind OR NEW.origin_tertiary_parent_entity_id IS NOT OLD.origin_tertiary_parent_entity_id OR NEW.tertiary_parent_materialization_id IS NOT OLD.tertiary_parent_materialization_id OR NEW.materialized_tertiary_parent_entity_id IS NOT OLD.materialized_tertiary_parent_entity_id OR
      NEW.materialization_result_kind IS NOT OLD.materialization_result_kind OR NEW.materialized_identifier_kind IS NOT OLD.materialized_identifier_kind OR NEW.materialized_identifier_digest_key_version IS NOT OLD.materialized_identifier_digest_key_version OR NEW.materialized_identifier_lookup_digest IS NOT OLD.materialized_identifier_lookup_digest OR
      NEW.materialized_content_digest IS NOT OLD.materialized_content_digest OR NEW.materialized_entity_id IS NOT OLD.materialized_entity_id OR NEW.relay_eligibility IS NOT OLD.relay_eligibility OR
      NEW.received_at IS NOT OLD.received_at OR NEW.created_at IS NOT OLD.created_at OR NEW.created_by_device_id IS NOT OLD.created_by_device_id
    BEGIN SELECT RAISE(ABORT,'materialization graph is immutable'); END;
    """
}
