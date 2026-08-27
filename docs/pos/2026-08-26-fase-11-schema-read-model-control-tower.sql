-- DRAFT REVIEW ONLY - DO NOT EXECUTE DIRECTLY IN PRODUCTION.
-- Fase 11: snapshot/read-model untuk laporan dan control tower.

CREATE SCHEMA IF NOT EXISTS inventory;

CREATE TABLE inventory.control_tower_snapshot (
    id BIGSERIAL PRIMARY KEY,
    snapshot_key VARCHAR(120) NOT NULL,
    tenant_key VARCHAR(100) NOT NULL,
    location_key VARCHAR(140),
    period_from TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    period_to TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    status VARCHAR(20) NOT NULL,
    generated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    watermark TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    filter_key VARCHAR(500) NOT NULL,
    CONSTRAINT ck_control_tower_snapshot_status CHECK (status IN ('READY', 'STALE', 'FAILED')),
    CONSTRAINT ck_control_tower_snapshot_period CHECK (period_to >= period_from),
    CONSTRAINT uq_control_tower_snapshot_key UNIQUE (snapshot_key)
);

CREATE INDEX ix_control_tower_snapshot_latest
    ON inventory.control_tower_snapshot
    (tenant_key, location_key, period_from, period_to, status, generated_at DESC);

CREATE TABLE inventory.control_tower_metric (
    id BIGSERIAL PRIMARY KEY,
    snapshot_id BIGINT NOT NULL,
    module_code VARCHAR(80) NOT NULL,
    metric_code VARCHAR(100) NOT NULL,
    metric_label VARCHAR(200) NOT NULL,
    metric_owner VARCHAR(160) NOT NULL,
    source_of_truth VARCHAR(300) NOT NULL,
    drill_down_route VARCHAR(300) NOT NULL,
    reconciliation_query VARCHAR(1000) NOT NULL,
    count_value BIGINT NOT NULL DEFAULT 0,
    amount_value NUMERIC(19,4) NOT NULL DEFAULT 0,
    CONSTRAINT fk_control_tower_metric_snapshot FOREIGN KEY (snapshot_id)
        REFERENCES inventory.control_tower_snapshot(id) ON DELETE CASCADE,
    CONSTRAINT uq_control_tower_metric_code UNIQUE (snapshot_id, metric_code)
);

CREATE INDEX ix_control_tower_metric_module
    ON inventory.control_tower_metric (snapshot_id, module_code, metric_code);

CREATE TABLE inventory.control_tower_alert (
    id BIGSERIAL PRIMARY KEY,
    snapshot_id BIGINT NOT NULL,
    module_code VARCHAR(80) NOT NULL,
    source_reference VARCHAR(180) NOT NULL,
    severity VARCHAR(20) NOT NULL,
    title VARCHAR(240) NOT NULL,
    message VARCHAR(2000) NOT NULL,
    drill_down_route VARCHAR(300) NOT NULL,
    occurred_at TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    CONSTRAINT fk_control_tower_alert_snapshot FOREIGN KEY (snapshot_id)
        REFERENCES inventory.control_tower_snapshot(id) ON DELETE CASCADE,
    CONSTRAINT ck_control_tower_alert_severity CHECK (severity IN ('INFO', 'WARNING', 'CRITICAL'))
);

CREATE INDEX ix_control_tower_alert_page
    ON inventory.control_tower_alert (snapshot_id, severity, occurred_at DESC, id DESC);

-- Rollback draft (execute only after all consumers are disabled):
-- DROP TABLE IF EXISTS inventory.control_tower_alert;
-- DROP TABLE IF EXISTS inventory.control_tower_metric;
-- DROP TABLE IF EXISTS inventory.control_tower_snapshot;

