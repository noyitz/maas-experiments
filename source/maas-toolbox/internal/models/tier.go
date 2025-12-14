package models

// Tier represents a single tier configuration
// @Description Tier configuration that maps Kubernetes groups to a subscription tier
type Tier struct {
	Name        string   `json:"name" yaml:"name" example:"free"`                    // Tier name (immutable after creation)
	Description string   `json:"description" yaml:"description" example:"Free tier for basic users"` // Tier description
	Level       int      `json:"level" yaml:"level" example:"1"`                // Tier level (non-negative integer)
	Groups      []string `json:"groups" yaml:"groups" example:"system:authenticated"`                     // List of Kubernetes groups
}

// TierConfig represents the complete tier configuration
// This matches the structure of the ConfigMap data field
type TierConfig struct {
	Tiers []Tier `json:"tiers" yaml:"tiers"`
}

// Validate validates a Tier struct
func (t *Tier) Validate() error {
	if t.Name == "" {
		return ErrTierNameRequired
	}
	if t.Description == "" {
		return ErrTierDescriptionRequired
	}
	if t.Level < 0 {
		return ErrTierLevelInvalid
	}
	// Validate all groups conform to Kubernetes naming conventions
	for _, group := range t.Groups {
		if err := ValidateGroupName(group); err != nil {
			return err
		}
	}
	return nil
}

// IsValid returns true if the tier is valid
func (t *Tier) IsValid() bool {
	return t.Validate() == nil
}

