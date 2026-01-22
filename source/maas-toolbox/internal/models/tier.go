// Copyright 2025 Bryon Baker
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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

// UserTier represents a tier with user-specific information
// @Description Tier information for a specific user, including which groups grant access
type UserTier struct {
	Name        string   `json:"name" example:"premium"`                               // Tier name
	Description string   `json:"description" example:"Premium tier with high priority"` // Tier description
	Level       int      `json:"level" example:"10"`                                   // Tier priority level (higher = higher priority)
	Groups      []string `json:"groups" example:"cluster-admins,premium-users"`        // User's groups that grant access to this tier
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

