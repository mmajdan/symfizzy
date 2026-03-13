package amlrepository

import (
	"strings"
	"testing"
	"time"
)

func TestRepositoryModelsAutoMigrate(t *testing.T) {
	db := openSQLiteTestDB(t)

	if err := db.AutoMigrate(RepositoryModels()...); err != nil {
		t.Fatalf("auto migrate repository models: %v", err)
	}

	for _, model := range RepositoryModels() {
		if !db.Migrator().HasTable(model) {
			t.Fatalf("expected table for %T to exist", model)
		}
	}
}

func TestRepositoryModelsEnforceKeyConstraints(t *testing.T) {
	db := openSQLiteTestDB(t)

	if err := db.Exec("PRAGMA foreign_keys = ON").Error; err != nil {
		t.Fatalf("enable foreign keys: %v", err)
	}

	if err := db.AutoMigrate(RepositoryModels()...); err != nil {
		t.Fatalf("auto migrate repository models: %v", err)
	}

	entity := GroupEntity{
		GeEntityName:  "Fizzy Bank",
		GeEntityType:  "bank",
		GeCountryCode: "PL",
	}
	if err := db.Create(&entity).Error; err != nil {
		t.Fatalf("create entity: %v", err)
	}

	customer := Customer{
		CuCustomerType:               "legal_person",
		CuFirstNameOrRegName:         "Acme Sp. z o.o.",
		CuDateOfBirthOrIncorporation: time.Date(2020, time.January, 2, 0, 0, 0, 0, time.UTC),
		CuNationalityOrCountry:       "PL",
		CuAddress:                    "ul. Testowa 1, Warszawa",
		CuRiskProfile:                "medium",
	}
	if err := db.Create(&customer).Error; err != nil {
		t.Fatalf("create customer: %v", err)
	}

	relationship := BusinessRelationship{
		BrCustomerID:       customer.CuCustomerID,
		BrEntityID:         entity.GeEntityID,
		BrPurposeAndNature: "Current account and cash management",
		BrStatus:           "active",
	}
	if err := db.Create(&relationship).Error; err != nil {
		t.Fatalf("create relationship: %v", err)
	}

	duplicateRelationship := BusinessRelationship{
		BrCustomerID:       customer.CuCustomerID,
		BrEntityID:         entity.GeEntityID,
		BrPurposeAndNature: "Duplicate relationship",
		BrStatus:           "active",
	}
	if err := db.Create(&duplicateRelationship).Error; err == nil || !strings.Contains(err.Error(), "UNIQUE") {
		t.Fatalf("expected unique constraint error for duplicate relationship, got: %v", err)
	}

	invalidPepInfo := PepInfo{
		PiPepCategory:    "pep",
		PiPublicFunction: "Minister of Finance",
	}
	if err := db.Create(&invalidPepInfo).Error; err == nil || !strings.Contains(err.Error(), "CHECK constraint failed") {
		t.Fatalf("expected pep parent check constraint error, got: %v", err)
	}

	invalidCustomer := Customer{
		CuCustomerType:               "legal_person",
		CuFirstNameOrRegName:         "Broken Corp",
		CuDateOfBirthOrIncorporation: time.Date(2021, time.February, 3, 0, 0, 0, 0, time.UTC),
		CuNationalityOrCountry:       "PL",
		CuAddress:                    "ul. Wadliwa 2, Krakow",
		CuRiskProfile:                "critical",
	}
	if err := db.Create(&invalidCustomer).Error; err == nil || !strings.Contains(err.Error(), "CHECK constraint failed") {
		t.Fatalf("expected customer risk profile check constraint error, got: %v", err)
	}
}
