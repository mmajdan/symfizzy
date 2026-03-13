package amlrepository

import "time"

type GroupEntity struct {
	GeEntityID    uint                   `gorm:"column:ge_entity_id;primaryKey;autoIncrement"`
	GeEntityName  string                 `gorm:"column:ge_entity_name;type:text;not null"`
	GeEntityType  string                 `gorm:"column:ge_entity_type;type:text;not null"`
	GeCountryCode string                 `gorm:"column:ge_country_code;type:text;not null;check:ck_group_entity_country_code,length(ge_country_code) BETWEEN 2 AND 3"`
	Relationships []BusinessRelationship `gorm:"foreignKey:BrEntityID"`
	Reports       []SuspiciousReport     `gorm:"foreignKey:SrEntityID"`
	Screenings    []SanctionScreening    `gorm:"foreignKey:SsEntityID"`
}

func (GroupEntity) TableName() string {
	return "t_group_entity"
}

type Customer struct {
	CuCustomerID                 uint                   `gorm:"column:cu_customer_id;primaryKey;autoIncrement"`
	CuCustomerType               string                 `gorm:"column:cu_customer_type;type:text;not null;index:idx_customer_type;check:ck_customer_type,cu_customer_type IN ('natural_person', 'legal_person', 'legal_arrangement')"`
	CuFirstNameOrRegName         string                 `gorm:"column:cu_first_name_or_reg_name;type:text;not null"`
	CuLastNameOrTradeName        *string                `gorm:"column:cu_last_name_or_trade_name;type:text"`
	CuDateOfBirthOrIncorporation time.Time              `gorm:"column:cu_date_of_birth_or_incorporation;type:date;not null;check:ck_customer_date,date(cu_date_of_birth_or_incorporation) IS NOT NULL"`
	CuNationalityOrCountry       string                 `gorm:"column:cu_nationality_or_country;type:text;not null"`
	CuAddress                    string                 `gorm:"column:cu_address;type:text;not null"`
	CuTaxID                      *string                `gorm:"column:cu_tax_id;type:text"`
	CuLEI                        *string                `gorm:"column:cu_lei;type:text;check:ck_customer_lei,cu_lei IS NULL OR length(cu_lei) = 20"`
	CuRiskProfile                string                 `gorm:"column:cu_risk_profile;type:text;not null;index:idx_customer_risk_profile;check:ck_customer_risk_profile,cu_risk_profile IN ('low', 'medium', 'significant', 'high')"`
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
	BrCustomerID       uint        `gorm:"column:br_customer_id;not null;index:idx_business_relationship_customer;uniqueIndex:uq_business_relationship_customer_entity"`
	BrEntityID         uint        `gorm:"column:br_entity_id;not null;index:idx_business_relationship_entity;uniqueIndex:uq_business_relationship_customer_entity"`
	BrPurposeAndNature string      `gorm:"column:br_purpose_and_nature;type:text;not null"`
	BrSourceOfFunds    *string     `gorm:"column:br_source_of_funds;type:text"`
	BrStatus           string      `gorm:"column:br_status;type:text;not null;check:ck_business_relationship_status,br_status IN ('active', 'terminated', 'declined')"`
	Customer           Customer    `gorm:"foreignKey:BrCustomerID;references:CuCustomerID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
	Entity             GroupEntity `gorm:"foreignKey:BrEntityID;references:GeEntityID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
}

func (BusinessRelationship) TableName() string {
	return "t_business_relationship"
}

type BeneficialOwner struct {
	BoUboID                     uint      `gorm:"column:bo_ubo_id;primaryKey;autoIncrement"`
	BoCustomerID                uint      `gorm:"column:bo_customer_id;not null;index:idx_beneficial_owner_customer"`
	BoFirstName                 string    `gorm:"column:bo_first_name;type:text;not null"`
	BoLastName                  string    `gorm:"column:bo_last_name;type:text;not null"`
	BoDateOfBirth               time.Time `gorm:"column:bo_date_of_birth;type:date;not null;check:ck_beneficial_owner_date,date(bo_date_of_birth) IS NOT NULL"`
	BoNationality               string    `gorm:"column:bo_nationality;type:text;not null"`
	BoNatureAndExtentOfInterest string    `gorm:"column:bo_nature_and_extent_of_interest;type:text;not null"`
	BoIsSeniorManagingOfficial  bool      `gorm:"column:bo_is_senior_managing_official;not null;default:false"`
	Customer                    Customer  `gorm:"foreignKey:BoCustomerID;references:CuCustomerID;constraint:OnUpdate:CASCADE,OnDelete:CASCADE"`
	PepInfos                    []PepInfo `gorm:"foreignKey:PiUboID"`
}

func (BeneficialOwner) TableName() string {
	return "t_beneficial_owner"
}

type PepInfo struct {
	PiPepID          uint             `gorm:"column:pi_pep_id;primaryKey;autoIncrement"`
	PiCustomerID     *uint            `gorm:"column:pi_customer_id;index:idx_pep_info_customer;check:ck_pep_info_parent,((pi_customer_id IS NOT NULL AND pi_ubo_id IS NULL) OR (pi_customer_id IS NULL AND pi_ubo_id IS NOT NULL))"`
	PiUboID          *uint            `gorm:"column:pi_ubo_id;index:idx_pep_info_ubo"`
	PiPepCategory    string           `gorm:"column:pi_pep_category;type:text;not null;check:ck_pep_info_category,pi_pep_category IN ('pep', 'family_member', 'close_associate')"`
	PiPublicFunction string           `gorm:"column:pi_public_function;type:text;not null"`
	Customer         *Customer        `gorm:"foreignKey:PiCustomerID;references:CuCustomerID;constraint:OnUpdate:CASCADE,OnDelete:CASCADE"`
	BeneficialOwner  *BeneficialOwner `gorm:"foreignKey:PiUboID;references:BoUboID;constraint:OnUpdate:CASCADE,OnDelete:CASCADE"`
}

func (PepInfo) TableName() string {
	return "t_pep_info"
}

type SuspiciousReport struct {
	SrReportID            uint        `gorm:"column:sr_report_id;primaryKey;autoIncrement"`
	SrCustomerID          uint        `gorm:"column:sr_customer_id;not null;index:idx_suspicious_report_customer"`
	SrEntityID            uint        `gorm:"column:sr_entity_id;not null;index:idx_suspicious_report_entity"`
	SrFiuNotificationDate time.Time   `gorm:"column:sr_fiu_notification_date;type:date;not null;index:idx_suspicious_report_notification_date;check:ck_suspicious_report_date,date(sr_fiu_notification_date) IS NOT NULL"`
	SrUnderlyingAnalysis  string      `gorm:"column:sr_underlying_analysis;type:text;not null"`
	Customer              Customer    `gorm:"foreignKey:SrCustomerID;references:CuCustomerID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
	Entity                GroupEntity `gorm:"foreignKey:SrEntityID;references:GeEntityID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
}

func (SuspiciousReport) TableName() string {
	return "t_suspicious_report"
}

type SanctionScreening struct {
	SsScreeningID   uint        `gorm:"column:ss_screening_id;primaryKey;autoIncrement"`
	SsCustomerID    uint        `gorm:"column:ss_customer_id;not null;index:idx_sanction_screening_customer"`
	SsEntityID      uint        `gorm:"column:ss_entity_id;not null;index:idx_sanction_screening_entity"`
	SsScreeningDate time.Time   `gorm:"column:ss_screening_date;type:date;not null;index:idx_sanction_screening_date;check:ck_sanction_screening_date,date(ss_screening_date) IS NOT NULL"`
	SsHitStatus     string      `gorm:"column:ss_hit_status;type:text;not null;check:ck_sanction_screening_hit_status,ss_hit_status IN ('no_hit', 'potential_hit', 'true_positive')"`
	Customer        Customer    `gorm:"foreignKey:SsCustomerID;references:CuCustomerID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
	Entity          GroupEntity `gorm:"foreignKey:SsEntityID;references:GeEntityID;constraint:OnUpdate:CASCADE,OnDelete:RESTRICT"`
}

func (SanctionScreening) TableName() string {
	return "t_sanction_screening"
}

func RepositoryModels() []any {
	return []any{
		&GroupEntity{},
		&Customer{},
		&BusinessRelationship{},
		&BeneficialOwner{},
		&PepInfo{},
		&SuspiciousReport{},
		&SanctionScreening{},
	}
}
