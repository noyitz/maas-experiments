package models

import "errors"

var (
	ErrTierNameRequired        = errors.New("tier name is required")
	ErrTierDescriptionRequired = errors.New("tier description is required")
	ErrTierLevelInvalid        = errors.New("tier level must be non-negative")
	ErrTierNotFound            = errors.New("tier not found")
	ErrTierAlreadyExists       = errors.New("tier already exists")
	ErrTierNameImmutable       = errors.New("tier name cannot be changed")
	ErrGroupRequired           = errors.New("group name is required")
	ErrGroupAlreadyExists      = errors.New("group already exists in tier")
	ErrGroupNotFound           = errors.New("group not found in tier")
	ErrInvalidKubernetesName   = errors.New("invalid Kubernetes name format: must be 1-253 characters, start and end with alphanumeric, and contain only lowercase alphanumeric, hyphens, colons, dots, or underscores")
)

