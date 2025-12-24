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

import (
	"encoding/json"
	"fmt"
)

// TierAnnotationKey is the annotation key used to store tier information
const TierAnnotationKey = "alpha.maas.opendatahub.io/tiers"

// LLMInferenceService represents an LLMInferenceService custom resource
// @Description LLMInferenceService custom resource from KServe
type LLMInferenceService struct {
	Name      string                 `json:"name" example:"acme-dev-model"`                            // Name of the LLMInferenceService
	Namespace string                 `json:"namespace" example:"acme-inc-models"`                      // Namespace where the service is deployed
	Tiers     []string               `json:"tiers" example:"acme-dev-users-tier,acme-prod-users-tier"` // List of tiers associated with this service
	Spec      map[string]interface{} `json:"spec"`                                                     // Full spec of the LLMInferenceService
}

// ParseTiersFromAnnotation parses the tiers annotation value (JSON array string) into a slice of tier names
func ParseTiersFromAnnotation(annotationValue string) ([]string, error) {
	if annotationValue == "" {
		return []string{}, nil
	}

	var tiers []string
	if err := json.Unmarshal([]byte(annotationValue), &tiers); err != nil {
		return nil, fmt.Errorf("failed to parse tiers annotation: %w", err)
	}

	return tiers, nil
}

// HasTier checks if the service has the specified tier in its tiers list
func (l *LLMInferenceService) HasTier(tierName string) bool {
	for _, tier := range l.Tiers {
		if tier == tierName {
			return true
		}
	}
	return false
}

// AnnotateRequest represents the request body for annotating an LLMInferenceService with a tier
// @Description Request body for annotating an LLMInferenceService with a tier
type AnnotateRequest struct {
	Namespace string `json:"namespace" binding:"required" example:"acme-inc-models"` // Namespace where the LLMInferenceService is deployed
	Name      string `json:"name" binding:"required" example:"acme-dev-model"`       // Name of the LLMInferenceService
	Tier      string `json:"tier" binding:"required" example:"free"`                 // Tier name to add to the service
}

// Validate validates an AnnotateRequest
func (a *AnnotateRequest) Validate() error {
	if a.Namespace == "" {
		return ErrNamespaceRequired
	}
	if a.Name == "" {
		return ErrNameRequired
	}
	if a.Tier == "" {
		return ErrTierNameRequired
	}
	return nil
}

// AddTierToList adds a tier to a list of tiers, avoiding duplicates
func AddTierToList(tiers []string, tierName string) []string {
	// Check if tier already exists
	for _, tier := range tiers {
		if tier == tierName {
			return tiers // Already exists, return unchanged
		}
	}
	// Add the new tier
	return append(tiers, tierName)
}

// FormatTiersAnnotation converts a slice of tier names to JSON string for annotation
func FormatTiersAnnotation(tiers []string) (string, error) {
	if len(tiers) == 0 {
		return "[]", nil
	}
	data, err := json.Marshal(tiers)
	if err != nil {
		return "", fmt.Errorf("failed to marshal tiers: %w", err)
	}
	return string(data), nil
}

// RemoveTierFromList removes a tier from a list of tiers
// Returns the updated list and a boolean indicating if the tier was found
func RemoveTierFromList(tiers []string, tierName string) ([]string, bool) {
	for i, tier := range tiers {
		if tier == tierName {
			// Found it - remove by creating new slice without this element
			return append(tiers[:i], tiers[i+1:]...), true
		}
	}
	// Not found
	return tiers, false
}

// RemoveTierRequest represents the request body for removing a tier annotation
// @Description Request body for removing a tier from an LLMInferenceService
type RemoveTierRequest struct {
	Namespace string `json:"namespace" binding:"required" example:"acme-inc-models"` // Namespace where the LLMInferenceService is deployed
	Name      string `json:"name" binding:"required" example:"acme-dev-model"`       // Name of the LLMInferenceService
	Tier      string `json:"tier" binding:"required" example:"free"`                 // Tier name to remove from the service
}

// Validate validates a RemoveTierRequest
func (r *RemoveTierRequest) Validate() error {
	if r.Namespace == "" {
		return ErrNamespaceRequired
	}
	if r.Name == "" {
		return ErrNameRequired
	}
	if r.Tier == "" {
		return ErrTierNameRequired
	}
	return nil
}
