package amlrepository

import (
	"strings"
	"testing"

	"gorm.io/gorm"
)

func TestSchemaSQLExecutesOnSQLite(t *testing.T) {
	db := openSQLiteTestDB(t)

	if err := ApplySchema(db); err != nil {
		t.Fatalf("execute schema.sql: %v", err)
	}

	for _, model := range RepositoryModels() {
		if !db.Migrator().HasTable(model) {
			t.Fatalf("expected table for %T to exist after schema.sql execution", model)
		}
	}
}

func TestSchemaSQLEnforcesKeyConstraints(t *testing.T) {
	db := openSQLiteTestDB(t)

	if err := ApplySchema(db); err != nil {
		t.Fatalf("execute schema.sql: %v", err)
	}

	if err := db.Exec(`
		INSERT INTO t_group_entity (ge_entity_name, ge_entity_type, ge_country_code)
		VALUES ('Fizzy Bank', 'bank', 'PL')
	`).Error; err != nil {
		t.Fatalf("insert entity: %v", err)
	}

	if err := db.Exec(`
		INSERT INTO t_customer (
			cu_customer_type,
			cu_first_name_or_reg_name,
			cu_date_of_birth_or_incorporation,
			cu_nationality_or_country,
			cu_address,
			cu_risk_profile
		) VALUES (
			'legal_person',
			'Acme Sp. z o.o.',
			'2020-01-02',
			'PL',
			'ul. Testowa 1, Warszawa',
			'medium'
		)
	`).Error; err != nil {
		t.Fatalf("insert customer: %v", err)
	}

	if err := db.Exec(`
		INSERT INTO t_business_relationship (
			br_customer_id,
			br_entity_id,
			br_purpose_and_nature,
			br_status
		) VALUES (
			1,
			1,
			'Current account and cash management',
			'active'
		)
	`).Error; err != nil {
		t.Fatalf("insert business relationship: %v", err)
	}

	if err := db.Exec(`
		INSERT INTO t_business_relationship (
			br_customer_id,
			br_entity_id,
			br_purpose_and_nature,
			br_status
		) VALUES (
			1,
			1,
			'Duplicate relationship',
			'active'
		)
	`).Error; err == nil || !strings.Contains(err.Error(), "UNIQUE constraint failed") {
		t.Fatalf("expected unique constraint error for duplicate relationship, got: %v", err)
	}

	if err := db.Exec(`
		INSERT INTO t_pep_info (pi_pep_category, pi_public_function)
		VALUES ('pep', 'Minister of Finance')
	`).Error; err == nil || !strings.Contains(err.Error(), "CHECK constraint failed") {
		t.Fatalf("expected pep parent check constraint error, got: %v", err)
	}

	if err := db.Exec(`
		INSERT INTO t_customer (
			cu_customer_type,
			cu_first_name_or_reg_name,
			cu_date_of_birth_or_incorporation,
			cu_nationality_or_country,
			cu_address,
			cu_risk_profile
		) VALUES (
			'legal_person',
			'Broken Corp',
			'2021-02-03',
			'PL',
			'ul. Wadliwa 2, Krakow',
			'critical'
		)
	`).Error; err == nil || !strings.Contains(err.Error(), "CHECK constraint failed") {
		t.Fatalf("expected customer risk profile check constraint error, got: %v", err)
	}

	if err := db.Exec(`
		INSERT INTO t_suspicious_report (
			sr_customer_id,
			sr_entity_id,
			sr_fiu_notification_date,
			sr_underlying_analysis
		) VALUES (
			999,
			1,
			'2026-03-13',
			'Unmatched customer should fail'
		)
	`).Error; err == nil || !strings.Contains(err.Error(), "FOREIGN KEY constraint failed") {
		t.Fatalf("expected foreign key constraint error for missing customer, got: %v", err)
	}
}

func TestSchemaSQLAppliesForeignKeyActions(t *testing.T) {
	db := openSQLiteTestDB(t)

	if err := ApplySchema(db); err != nil {
		t.Fatalf("execute schema.sql: %v", err)
	}

	assertForeignKeyRule(t, db, "t_business_relationship", foreignKeyRule{
		From:     "br_customer_id",
		Table:    "t_customer",
		To:       "cu_customer_id",
		OnUpdate: "CASCADE",
		OnDelete: "RESTRICT",
	})
	assertForeignKeyRule(t, db, "t_business_relationship", foreignKeyRule{
		From:     "br_entity_id",
		Table:    "t_group_entity",
		To:       "ge_entity_id",
		OnUpdate: "CASCADE",
		OnDelete: "RESTRICT",
	})
	assertForeignKeyRule(t, db, "t_beneficial_owner", foreignKeyRule{
		From:     "bo_customer_id",
		Table:    "t_customer",
		To:       "cu_customer_id",
		OnUpdate: "CASCADE",
		OnDelete: "CASCADE",
	})
	assertForeignKeyRule(t, db, "t_pep_info", foreignKeyRule{
		From:     "pi_customer_id",
		Table:    "t_customer",
		To:       "cu_customer_id",
		OnUpdate: "CASCADE",
		OnDelete: "CASCADE",
	})
	assertForeignKeyRule(t, db, "t_pep_info", foreignKeyRule{
		From:     "pi_ubo_id",
		Table:    "t_beneficial_owner",
		To:       "bo_ubo_id",
		OnUpdate: "CASCADE",
		OnDelete: "CASCADE",
	})
	assertForeignKeyRule(t, db, "t_suspicious_report", foreignKeyRule{
		From:     "sr_customer_id",
		Table:    "t_customer",
		To:       "cu_customer_id",
		OnUpdate: "CASCADE",
		OnDelete: "RESTRICT",
	})
	assertForeignKeyRule(t, db, "t_suspicious_report", foreignKeyRule{
		From:     "sr_entity_id",
		Table:    "t_group_entity",
		To:       "ge_entity_id",
		OnUpdate: "CASCADE",
		OnDelete: "RESTRICT",
	})
	assertForeignKeyRule(t, db, "t_sanction_screening", foreignKeyRule{
		From:     "ss_customer_id",
		Table:    "t_customer",
		To:       "cu_customer_id",
		OnUpdate: "CASCADE",
		OnDelete: "RESTRICT",
	})
	assertForeignKeyRule(t, db, "t_sanction_screening", foreignKeyRule{
		From:     "ss_entity_id",
		Table:    "t_group_entity",
		To:       "ge_entity_id",
		OnUpdate: "CASCADE",
		OnDelete: "RESTRICT",
	})
}

type foreignKeyRule struct {
	From     string
	Table    string
	To       string
	OnUpdate string
	OnDelete string
}

func assertForeignKeyRule(t *testing.T, db *gorm.DB, table string, expected foreignKeyRule) {
	t.Helper()

	var rules []foreignKeyRule
	if err := db.Raw("PRAGMA foreign_key_list(" + "'" + table + "'" + ")").Scan(&rules).Error; err != nil {
		t.Fatalf("load foreign keys for %s: %v", table, err)
	}

	for _, rule := range rules {
		if rule == expected {
			return
		}
	}

	t.Fatalf("expected foreign key %#v on %s, got %#v", expected, table, rules)
}
