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

package service

import (
	"fmt"
	"maas-toolbox/internal/models"
	"maas-toolbox/internal/storage"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

// LLMInferenceServiceService provides business logic for LLMInferenceService operations
type LLMInferenceServiceService struct {
	tierService *TierService
}

// NewLLMInferenceServiceService creates a new LLMInferenceServiceService instance
func NewLLMInferenceServiceService(tierService *TierService) *LLMInferenceServiceService {
	return &LLMInferenceServiceService{
		tierService: tierService,
	}
}

// GetLLMInferenceServicesByTier returns all LLMInferenceService instances that have the specified tier
func (s *LLMInferenceServiceService) GetLLMInferenceServicesByTier(tierName string) ([]models.LLMInferenceService, error) {
	// Get unstructured objects from storage
	unstructuredServices, err := storage.GetLLMInferenceServicesByTier(tierName)
	if err != nil {
		return nil, fmt.Errorf("failed to get LLMInferenceServices by tier: %w", err)
	}

	// Convert to model objects
	services := make([]models.LLMInferenceService, 0, len(unstructuredServices))
	for _, us := range unstructuredServices {
		service, err := convertUnstructuredToLLMInferenceService(us)
		if err != nil {
			// Log error but continue processing other services
			continue
		}
		services = append(services, *service)
	}

	return services, nil
}

// GetLLMInferenceServicesByGroup returns all LLMInferenceService instances associated with the specified group
func (s *LLMInferenceServiceService) GetLLMInferenceServicesByGroup(groupName string) ([]models.LLMInferenceService, error) {
	// Get tiers for the group
	tiers, err := s.tierService.GetTiersByGroup(groupName)
	if err != nil {
		return nil, fmt.Errorf("failed to get tiers by group: %w", err)
	}

	// Collect all services from all tiers
	serviceMap := make(map[string]models.LLMInferenceService) // Use map to deduplicate by name+namespace

	for _, tier := range tiers {
		services, err := s.GetLLMInferenceServicesByTier(tier.Name)
		if err != nil {
			// Log error but continue with other tiers
			continue
		}

		// Add services to map (deduplication by key: namespace/name)
		for _, service := range services {
			key := fmt.Sprintf("%s/%s", service.Namespace, service.Name)
			serviceMap[key] = service
		}
	}

	// Convert map to slice
	services := make([]models.LLMInferenceService, 0, len(serviceMap))
	for _, service := range serviceMap {
		services = append(services, service)
	}

	return services, nil
}

// convertUnstructuredToLLMInferenceService converts an unstructured object to LLMInferenceService model
func convertUnstructuredToLLMInferenceService(obj *unstructured.Unstructured) (*models.LLMInferenceService, error) {
	// Extract metadata
	name, found, err := unstructured.NestedString(obj.Object, "metadata", "name")
	if err != nil || !found {
		return nil, fmt.Errorf("failed to extract name: %w", err)
	}

	namespace, found, err := unstructured.NestedString(obj.Object, "metadata", "namespace")
	if err != nil || !found {
		return nil, fmt.Errorf("failed to extract namespace: %w", err)
	}

	// Extract tiers from annotation
	var tiers []string
	annotations, found, err := unstructured.NestedStringMap(obj.Object, "metadata", "annotations")
	if err == nil && found && annotations != nil {
		if tiersAnnotation, exists := annotations[models.TierAnnotationKey]; exists && tiersAnnotation != "" {
			parsedTiers, err := models.ParseTiersFromAnnotation(tiersAnnotation)
			if err == nil {
				tiers = parsedTiers
			}
		}
	}

	// Extract spec
	spec, found, err := unstructured.NestedMap(obj.Object, "spec")
	if err != nil {
		return nil, fmt.Errorf("failed to extract spec: %w", err)
	}
	if !found {
		spec = make(map[string]interface{})
	}

	return &models.LLMInferenceService{
		Name:      name,
		Namespace: namespace,
		Tiers:     tiers,
		Spec:      spec,
	}, nil
}

// AnnotateLLMInferenceServiceWithTier annotates an LLMInferenceService with a tier
func (s *LLMInferenceServiceService) AnnotateLLMInferenceServiceWithTier(namespace, name, tierName string) error {
	// Validate input parameters
	if namespace == "" {
		return models.ErrNamespaceRequired
	}
	if name == "" {
		return models.ErrNameRequired
	}
	if tierName == "" {
		return models.ErrTierNameRequired
	}

	// Check that the tier exists
	_, err := s.tierService.GetTier(tierName)
	if err != nil {
		return err // Will be ErrTierNotFound if tier doesn't exist
	}

	// Update the annotation via storage layer
	if err := storage.UpdateLLMInferenceServiceAnnotation(namespace, name, tierName); err != nil {
		return fmt.Errorf("failed to update LLMInferenceService annotation: %w", err)
	}

	return nil
}

// RemoveTierFromLLMInferenceService removes a tier annotation from an LLMInferenceService
func (s *LLMInferenceServiceService) RemoveTierFromLLMInferenceService(namespace, name, tierName string) error {
	// Validate input parameters
	if namespace == "" {
		return models.ErrNamespaceRequired
	}
	if name == "" {
		return models.ErrNameRequired
	}
	if tierName == "" {
		return models.ErrTierNameRequired
	}

	// Note: We don't check if tier exists in tier config
	// We just remove it from the annotation if present
	// This allows cleanup of orphaned tier references

	// Remove the annotation via storage layer
	if err := storage.RemoveLLMInferenceServiceAnnotation(namespace, name, tierName); err != nil {
		return fmt.Errorf("failed to remove tier from LLMInferenceService annotation: %w", err)
	}

	return nil
}
