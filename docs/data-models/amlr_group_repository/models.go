package amlrepository

import "time"

type GroupEntity struct {
	GeEntityID    uint                   `gorm:"column:ge_entity_id;primaryKey;autoIncrement"`
	GeEntityName  string                 `gorm:"column:ge_entity_name;not null"`
	GeEntityType  string                 `gorm:"column:ge_entity_type;not null"`
	GeCountryCode string                 `gorm:"column:ge_country_code;not null"`
	Relationships []BusinessRelationship `gorm:"foreignKey:BrEntityID"`
	Reports       []SuspiciousReport     `gorm:"foreignKey:SrEntityID"`
	Screenings    []SanctionScreening    `gorm:"foreignKey:SsEntityID"`
}

func (GroupEntity) TableName() string {
	return "t_group_entity"
}

type Customer struct {
	CuCustomerID                 uint                   `gorm:"column:cu_customer_id;primaryKey;autoIncrement"`
	CuCustomerType               string                 `gorm:"column:cu_customer_type;not null"`
	CuFirstNameOrRegName         string                 `gorm:"column:cu_first_name_or_reg_name;not null"`
	CuLastNameOrTradeName        *string                `gorm:"column:cu_last_name_or_trade_name"`
	CuDateOfBirthOrIncorporation time.Time              `gorm:"column:cu_date_of_birth_or_incorporation;type:date;not null"`
	CuNationalityOrCountry       string                 `gorm:"column:cu_nationality_or_country;not null"`
	CuAddress                    string                 `gorm:"column:cu_address;not null"`
	CuTaxID                      *string                `gorm:"column:cu_tax_id"`
	CuLEI                        *string                `gorm:"column:cu_lei"`
	CuRiskProfile                string                 `gorm:"column:cu_risk_profile;not null"`
	BusinessRelationships        []BusinessRelationship `gorm:"foreignKey:BrCustomerID"`
	BeneficialOwners             []BeneficialOwner      `gorm:"foreignKey:BoCustomerID"`
	PepInfos                     []PepInfo              `gorm:"foreignKey:PiCustomerID"`
	SuspiciousReports            []SuspiciousReport     `gorm:"foreignKey:SrCustomerID"`
	SanctionScreenings           []SanctionScreening    `gorm:"foreignKey:SsCustomerID"`
}

func (Customer) TableName() string {
	return "t_customer"
}

type BusinessRelationship struct {
	BrRelationshipID   uint        `gorm:"column:br_relationship_id;primaryKey;autoIncrement"`
	BrCustomerID       uint        `gorm:"column:br_customer_id;not null;uniqueIndex:uq_br_customer_entity"`
	BrEntityID         uint        `gorm:"column:br_entity_id;not null;uniqueIndex:uq_br_customer_entity"`
	BrPurposeAndNature string      `gorm:"column:br_purpose_and_nature;not null"`
	BrSourceOfFunds    *string     `gorm:"column:br_source_of_funds"`
	BrStatus           string      `gorm:"column:br_status;not null"`
	Customer           Customer    `gorm:"foreignKey:BrCustomerID;references:CuCustomerID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
	Entity             GroupEntity `gorm:"foreignKey:BrEntityID;references:GeEntityID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
}

func (BusinessRelationship) TableName() string {
	return "t_business_relationship"
}

type BeneficialOwner struct {
	BoUboID                     uint      `gorm:"column:bo_ubo_id;primaryKey;autoIncrement"`
	BoCustomerID                uint      `gorm:"column:bo_customer_id;not null"`
	BoFirstName                 string    `gorm:"column:bo_first_name;not null"`
	BoLastName                  string    `gorm:"column:bo_last_name;not null"`
	BoDateOfBirth               time.Time `gorm:"column:bo_date_of_birth;type:date;not null"`
	BoNationality               string    `gorm:"column:bo_nationality;not null"`
	BoNatureAndExtentOfInterest string    `gorm:"column:bo_nature_and_extent_of_interest;not null"`
	BoIsSeniorManagingOfficial  bool      `gorm:"column:bo_is_senior_managing_official;not null;default:false"`
	Customer                    Customer  `gorm:"foreignKey:BoCustomerID;references:CuCustomerID;constraint:OnUpdate:CASCADE,OnDelete:CASCADE"`
	PepInfos                    []PepInfo `gorm:"foreignKey:PiUboID"`
}

func (BeneficialOwner) TableName() string {
	return "t_beneficial_owner"
}

type PepInfo struct {
	PiPepID          uint             `gorm:"column:pi_pep_id;primaryKey;autoIncrement"`
	PiCustomerID     *uint            `gorm:"column:pi_customer_id"`
	PiUboID          *uint            `gorm:"column:pi_ubo_id"`
	PiPepCategory    string           `gorm:"column:pi_pep_category;not null"`
	PiPublicFunction string           `gorm:"column:pi_public_function;not null"`
	Customer         *Customer        `gorm:"foreignKey:PiCustomerID;references:CuCustomerID;constraint:OnUpdate:CASCADE,OnDelete:CASCADE"`
	BeneficialOwner  *BeneficialOwner `gorm:"foreignKey:PiUboID;references:BoUboID;constraint:OnUpdate:CASCADE,OnDelete:CASCADE"`
}

func (PepInfo) TableName() string {
	return "t_pep_info"
}

type SuspiciousReport struct {
	SrReportID            uint        `gorm:"column:sr_report_id;primaryKey;autoIncrement"`
	SrCustomerID          uint        `gorm:"column:sr_customer_id;not null"`
	SrEntityID            uint        `gorm:"column:sr_entity_id;not null"`
	SrFiuNotificationDate time.Time   `gorm:"column:sr_fiu_notification_date;type:date;not null"`
	SrUnderlyingAnalysis  string      `gorm:"column:sr_underlying_analysis;not null"`
	Customer              Customer    `gorm:"foreignKey:SrCustomerID;references:CuCustomerID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
	Entity                GroupEntity `gorm:"foreignKey:SrEntityID;references:GeEntityID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
}

func (SuspiciousReport) TableName() string {
	return "t_suspicious_report"
}

type SanctionScreening struct {
	SsScreeningID   uint        `gorm:"column:ss_screening_id;primaryKey;autoIncrement"`
	SsCustomerID    uint        `gorm:"column:ss_customer_id;not null"`
	SsEntityID      uint        `gorm:"column:ss_entity_id;not null"`
	SsScreeningDate time.Time   `gorm:"column:ss_screening_date;type:date;not null"`
	SsHitStatus     string      `gorm:"column:ss_hit_status;not null"`
	Customer        Customer    `gorm:"foreignKey:SsCustomerID;references:CuCustomerID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
	Entity          GroupEntity `gorm:"foreignKey:SsEntityID;references:GeEntityID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
}

func (SanctionScreening) TableName() string {
	return "t_sanction_screening"
}
