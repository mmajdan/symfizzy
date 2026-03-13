package amlrepository

import (
	_ "embed"

	"gorm.io/gorm"
)

//go:embed schema.sql
var schemaSQL string

func ApplySchema(db *gorm.DB) error {
	return db.Exec(schemaSQL).Error
}
