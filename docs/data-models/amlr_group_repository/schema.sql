PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS t_group_entity (
  ge_entity_id INTEGER PRIMARY KEY AUTOINCREMENT,
  ge_entity_name TEXT NOT NULL,
  ge_entity_type TEXT NOT NULL,
  ge_country_code TEXT NOT NULL CHECK (length(ge_country_code) BETWEEN 2 AND 3)
);

CREATE TABLE IF NOT EXISTS t_customer (
  cu_customer_id INTEGER PRIMARY KEY AUTOINCREMENT,
  cu_customer_type TEXT NOT NULL CHECK (
    cu_customer_type IN ('natural_person', 'legal_person', 'legal_arrangement')
  ),
  cu_first_name_or_reg_name TEXT NOT NULL,
  cu_last_name_or_trade_name TEXT,
  cu_date_of_birth_or_incorporation TEXT NOT NULL CHECK (
    date(cu_date_of_birth_or_incorporation) IS NOT NULL
  ),
  cu_nationality_or_country TEXT NOT NULL,
  cu_address TEXT NOT NULL,
  cu_tax_id TEXT,
  cu_lei TEXT CHECK (
    cu_lei IS NULL OR length(cu_lei) = 20
  ),
  cu_risk_profile TEXT NOT NULL CHECK (
    cu_risk_profile IN ('low', 'medium', 'significant', 'high')
  )
);

CREATE TABLE IF NOT EXISTS t_business_relationship (
  br_relationship_id INTEGER PRIMARY KEY AUTOINCREMENT,
  br_customer_id INTEGER NOT NULL,
  br_entity_id INTEGER NOT NULL,
  br_purpose_and_nature TEXT NOT NULL,
  br_source_of_funds TEXT,
  br_status TEXT NOT NULL CHECK (
    br_status IN ('active', 'terminated', 'declined')
  ),
  CONSTRAINT fk_business_relationship_customer
    FOREIGN KEY (br_customer_id) REFERENCES t_customer(cu_customer_id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_business_relationship_entity
    FOREIGN KEY (br_entity_id) REFERENCES t_group_entity(ge_entity_id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT uq_business_relationship_customer_entity
    UNIQUE (br_customer_id, br_entity_id)
);

CREATE TABLE IF NOT EXISTS t_beneficial_owner (
  bo_ubo_id INTEGER PRIMARY KEY AUTOINCREMENT,
  bo_customer_id INTEGER NOT NULL,
  bo_first_name TEXT NOT NULL,
  bo_last_name TEXT NOT NULL,
  bo_date_of_birth TEXT NOT NULL CHECK (
    date(bo_date_of_birth) IS NOT NULL
  ),
  bo_nationality TEXT NOT NULL,
  bo_nature_and_extent_of_interest TEXT NOT NULL,
  bo_is_senior_managing_official INTEGER NOT NULL DEFAULT 0 CHECK (
    bo_is_senior_managing_official IN (0, 1)
  ),
  CONSTRAINT fk_beneficial_owner_customer
    FOREIGN KEY (bo_customer_id) REFERENCES t_customer(cu_customer_id)
    ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS t_pep_info (
  pi_pep_id INTEGER PRIMARY KEY AUTOINCREMENT,
  pi_customer_id INTEGER,
  pi_ubo_id INTEGER,
  pi_pep_category TEXT NOT NULL CHECK (
    pi_pep_category IN ('pep', 'family_member', 'close_associate')
  ),
  pi_public_function TEXT NOT NULL,
  CONSTRAINT fk_pep_info_customer
    FOREIGN KEY (pi_customer_id) REFERENCES t_customer(cu_customer_id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT fk_pep_info_ubo
    FOREIGN KEY (pi_ubo_id) REFERENCES t_beneficial_owner(bo_ubo_id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT ck_pep_info_parent
    CHECK (
      (pi_customer_id IS NOT NULL AND pi_ubo_id IS NULL) OR
      (pi_customer_id IS NULL AND pi_ubo_id IS NOT NULL)
    )
);

CREATE TABLE IF NOT EXISTS t_suspicious_report (
  sr_report_id INTEGER PRIMARY KEY AUTOINCREMENT,
  sr_customer_id INTEGER NOT NULL,
  sr_entity_id INTEGER NOT NULL,
  sr_fiu_notification_date TEXT NOT NULL CHECK (
    date(sr_fiu_notification_date) IS NOT NULL
  ),
  sr_underlying_analysis TEXT NOT NULL,
  CONSTRAINT fk_suspicious_report_customer
    FOREIGN KEY (sr_customer_id) REFERENCES t_customer(cu_customer_id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_suspicious_report_entity
    FOREIGN KEY (sr_entity_id) REFERENCES t_group_entity(ge_entity_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS t_sanction_screening (
  ss_screening_id INTEGER PRIMARY KEY AUTOINCREMENT,
  ss_customer_id INTEGER NOT NULL,
  ss_entity_id INTEGER NOT NULL,
  ss_screening_date TEXT NOT NULL CHECK (
    date(ss_screening_date) IS NOT NULL
  ),
  ss_hit_status TEXT NOT NULL CHECK (
    ss_hit_status IN ('no_hit', 'potential_hit', 'true_positive')
  ),
  CONSTRAINT fk_sanction_screening_customer
    FOREIGN KEY (ss_customer_id) REFERENCES t_customer(cu_customer_id)
    ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_sanction_screening_entity
    FOREIGN KEY (ss_entity_id) REFERENCES t_group_entity(ge_entity_id)
    ON UPDATE CASCADE ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_customer_type
  ON t_customer (cu_customer_type);

CREATE INDEX IF NOT EXISTS idx_customer_risk_profile
  ON t_customer (cu_risk_profile);

CREATE INDEX IF NOT EXISTS idx_business_relationship_customer
  ON t_business_relationship (br_customer_id);

CREATE INDEX IF NOT EXISTS idx_business_relationship_entity
  ON t_business_relationship (br_entity_id);

CREATE INDEX IF NOT EXISTS idx_beneficial_owner_customer
  ON t_beneficial_owner (bo_customer_id);

CREATE INDEX IF NOT EXISTS idx_pep_info_customer
  ON t_pep_info (pi_customer_id);

CREATE INDEX IF NOT EXISTS idx_pep_info_ubo
  ON t_pep_info (pi_ubo_id);

CREATE INDEX IF NOT EXISTS idx_suspicious_report_customer
  ON t_suspicious_report (sr_customer_id);

CREATE INDEX IF NOT EXISTS idx_suspicious_report_entity
  ON t_suspicious_report (sr_entity_id);

CREATE INDEX IF NOT EXISTS idx_suspicious_report_notification_date
  ON t_suspicious_report (sr_fiu_notification_date);

CREATE INDEX IF NOT EXISTS idx_sanction_screening_customer
  ON t_sanction_screening (ss_customer_id);

CREATE INDEX IF NOT EXISTS idx_sanction_screening_entity
  ON t_sanction_screening (ss_entity_id);

CREATE INDEX IF NOT EXISTS idx_sanction_screening_date
  ON t_sanction_screening (ss_screening_date);
