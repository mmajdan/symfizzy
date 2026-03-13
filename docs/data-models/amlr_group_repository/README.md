# AMLR Group Repository Data Model

This directory contains a standalone SQLite schema and matching GORM models
for a group-wide AML/CFT information sharing repository aligned with the
requirements described in CARD-6.

Files:
- `schema.sql`: SQLite DDL with foreign keys, indexes, and basic integrity checks.
- `models.go`: GORM model definitions aligned with the SQLite schema.

Design assumptions:
- Primary keys use `INTEGER PRIMARY KEY AUTOINCREMENT` to keep the schema simple
  and portable for SQLite-backed prototypes.
- Fields that may carry multiple values in regulation-driven workflows, such as
  citizenships or nationalities, are stored as text. The recommended encoding is
  a JSON array serialized to a string.
- `T_PEP_INFO` allows either a direct customer PEP record or a beneficial-owner
  PEP record, enforced with a `CHECK` constraint requiring exactly one parent.
- `T_BUSINESS_RELATIONSHIP` uses a uniqueness constraint on
  `(br_customer_id, br_entity_id)` so one customer has at most one active
  repository row per group entity.
