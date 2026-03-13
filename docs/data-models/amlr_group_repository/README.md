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

Table mapping:

## `t_group_entity`

Stores AML-regulated entities that belong to the group and participate in
intra-group information sharing.

| Column | Meaning |
| --- | --- |
| `ge_entity_id` | Surrogate primary key. |
| `ge_entity_name` | Legal name of the group entity. |
| `ge_entity_type` | Institution type, for example bank or life insurer. |
| `ge_country_code` | Registration country, constrained to 2- or 3-character country codes. |

## `t_customer`

Stores the core CDD identity profile for natural persons, legal persons, and
legal arrangements.

| Column | Meaning |
| --- | --- |
| `cu_customer_id` | Surrogate primary key. |
| `cu_customer_type` | `natural_person`, `legal_person`, or `legal_arrangement`. |
| `cu_first_name_or_reg_name` | Given names for a person or registered name for an entity. |
| `cu_last_name_or_trade_name` | Surname for a person or trade name for an entity, optional because not all customer types require it. |
| `cu_date_of_birth_or_incorporation` | Full date of birth or incorporation date. |
| `cu_nationality_or_country` | Citizenship or country of incorporation. Recommended encoding for multiple values is a JSON array serialized to text. |
| `cu_address` | Residential or registered office address. |
| `cu_tax_id` | Optional tax identifier used in risk assessments. |
| `cu_lei` | Optional Legal Entity Identifier. When present it must be 20 characters long. |
| `cu_risk_profile` | `low`, `medium`, `significant`, or `high`. |

## `t_business_relationship`

Captures the nature and purpose of the business relationship between a customer
and a group entity.

| Column | Meaning |
| --- | --- |
| `br_relationship_id` | Surrogate primary key. |
| `br_customer_id` | Foreign key to `t_customer`. |
| `br_entity_id` | Foreign key to `t_group_entity`. |
| `br_purpose_and_nature` | Free-text summary of the intended relationship. |
| `br_source_of_funds` | Optional source-of-funds information, especially for EDD scenarios. |
| `br_status` | `active`, `terminated`, or `declined`. |

The schema enforces one row per `(customer, entity)` pair so the repository has
one canonical relationship record per group entity.

## `t_beneficial_owner`

Stores ultimate beneficial owner data for institutional customers.

| Column | Meaning |
| --- | --- |
| `bo_ubo_id` | Surrogate primary key. |
| `bo_customer_id` | Foreign key to the institutional customer in `t_customer`. |
| `bo_first_name` | UBO given name. |
| `bo_last_name` | UBO surname. |
| `bo_date_of_birth` | Full date of birth. |
| `bo_nationality` | Citizenship or citizenships, recommended as serialized JSON text when multiple values are needed. |
| `bo_nature_and_extent_of_interest` | Ownership percentage or another control description. |
| `bo_is_senior_managing_official` | Boolean flag used when no factual owner can be identified and the fallback senior managing official rule is applied. |

## `t_pep_info`

Represents politically exposed person screening results for either a direct
customer or a beneficial owner.

| Column | Meaning |
| --- | --- |
| `pi_pep_id` | Surrogate primary key. |
| `pi_customer_id` | Optional foreign key to `t_customer`. |
| `pi_ubo_id` | Optional foreign key to `t_beneficial_owner`. |
| `pi_pep_category` | `pep`, `family_member`, or `close_associate`. |
| `pi_public_function` | The relevant public function or the basis for the PEP association. |

Exactly one parent reference must be present, which prevents orphaned PEP rows
and ambiguous dual linkage.

## `t_suspicious_report`

Stores STR/SAR notifications shared within the group.

| Column | Meaning |
| --- | --- |
| `sr_report_id` | Surrogate primary key. |
| `sr_customer_id` | Foreign key to `t_customer`. |
| `sr_entity_id` | Foreign key to the reporting entity in `t_group_entity`. |
| `sr_fiu_notification_date` | Date the FIU report was filed. |
| `sr_underlying_analysis` | Short narrative of the analysis and circumstances behind the suspicion. |

## `t_sanction_screening`

Stores sanctions/TFS screening outcomes performed by group entities for
customers.

| Column | Meaning |
| --- | --- |
| `ss_screening_id` | Surrogate primary key. |
| `ss_customer_id` | Foreign key to `t_customer`. |
| `ss_entity_id` | Foreign key to `t_group_entity`. |
| `ss_screening_date` | Date of the sanctions screening run. |
| `ss_hit_status` | `no_hit`, `potential_hit`, or `true_positive`. |
