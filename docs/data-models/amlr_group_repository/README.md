# AMLR Group Repository Data Model

This directory contains a standalone SQLite schema and matching GORM models
for a group-wide AML/CFT information sharing repository aligned with the
requirements described in CARD-6.

Files:
- `schema.sql`: SQLite DDL with foreign keys, indexes, and basic integrity checks.
- `schema_loader.go`: embeds and applies the canonical SQLite schema through GORM.
- `models.go`: GORM model definitions aligned with the SQLite schema.
- `go.mod`: standalone Go module definition for the GORM package.
- `models_test.go`: smoke tests proving the model set migrates cleanly on SQLite and enforces core constraints.
- `schema_test.go`: smoke test proving `schema.sql` executes cleanly on SQLite.

Design assumptions:
- Primary keys use `INTEGER PRIMARY KEY AUTOINCREMENT` to keep the schema simple
  and portable for SQLite-backed prototypes.
- Date fields are stored as SQLite-compatible `date` values and guarded with
  `CHECK` constraints so malformed values are rejected at the database layer.
- LEI is optional, but when present it must be a 20-character identifier.
- Fields that may carry multiple values in regulation-driven workflows, such as
  citizenships or nationalities, are stored as text. The recommended encoding is
  a JSON array serialized to a string.
- `T_PEP_INFO` allows either a direct customer PEP record or a beneficial-owner
  PEP record, enforced with a `CHECK` constraint requiring exactly one parent.
- `T_BUSINESS_RELATIONSHIP` uses a uniqueness constraint on
  `(br_customer_id, br_entity_id)` so one customer has at most one repository
  row per group entity.
- `schema.sql` is the authoritative SQLite definition. Use `ApplySchema` when
  exact foreign-key actions matter; the GORM models are provided for repository
  mapping and smoke-tested `AutoMigrate`, but SQLite DDL fidelity is enforced
  through the embedded schema.
