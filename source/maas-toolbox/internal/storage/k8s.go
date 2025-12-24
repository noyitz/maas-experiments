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

package storage

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"maas-toolbox/internal/models"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

// SystemAuthenticatedGroup is the special built-in Kubernetes group that
// always exists but is not returned by the API, so it requires special handling.
const SystemAuthenticatedGroup = "system:authenticated"

// K8sTierStorage implements TierStorage using Kubernetes ConfigMap
type K8sTierStorage struct {
	Client    kubernetes.Interface
	Namespace string
	ConfigMap string
}

// NewK8sTierStorage creates a new K8sTierStorage instance
func NewK8sTierStorage(client kubernetes.Interface, namespace, configMap string) *K8sTierStorage {
	return &K8sTierStorage{
		Client:    client,
		Namespace: namespace,
		ConfigMap: configMap,
	}
}

// ValidateNamespace checks if the configured namespace exists
func (k *K8sTierStorage) ValidateNamespace() error {
	exists, err := NamespaceExists(k.Namespace)
	if err != nil {
		return fmt.Errorf("failed to check namespace %s: %w", k.Namespace, err)
	}
	if !exists {
		return fmt.Errorf("namespace %s not found - ensure it exists before starting the application", k.Namespace)
	}
	log.Printf("Validated that namespace %s exists", k.Namespace)
	return nil
}

// Load retrieves the tier configuration from Kubernetes ConfigMap
func (k *K8sTierStorage) Load() (*models.TierConfig, error) {
	ctx := context.Background()
	log.Printf("Loading ConfigMap: namespace=%s, name=%s", k.Namespace, k.ConfigMap)

	// Check if namespace exists first
	nsExists, err := NamespaceExists(k.Namespace)
	if err != nil {
		return nil, fmt.Errorf("failed to verify namespace %s: %w", k.Namespace, err)
	}
	if !nsExists {
		log.Printf("Namespace %s not found", k.Namespace)
		return nil, models.ErrNamespaceNotFound
	}

	// Get ConfigMap from Kubernetes API
	cm, err := k.Client.CoreV1().ConfigMaps(k.Namespace).Get(ctx, k.ConfigMap, metav1.GetOptions{})
	if err != nil {
		// If ConfigMap doesn't exist, return empty config
		if errors.IsNotFound(err) {
			log.Printf("ConfigMap %s/%s not found, returning empty config", k.Namespace, k.ConfigMap)
			return &models.TierConfig{Tiers: []models.Tier{}}, nil
		}
		log.Printf("Error getting ConfigMap %s/%s: %v", k.Namespace, k.ConfigMap, err)
		return nil, fmt.Errorf("failed to get ConfigMap %s/%s: %w", k.Namespace, k.ConfigMap, err)
	}

	log.Printf("ConfigMap retrieved successfully")

	// Extract the "tiers" field from data
	tiersYAML, exists := cm.Data["tiers"]
	if !exists {
		log.Printf("ConfigMap %s/%s does not have 'tiers' key. Available keys: %v", k.Namespace, k.ConfigMap, getMapKeys(cm.Data))
		return &models.TierConfig{Tiers: []models.Tier{}}, nil
	}
	if tiersYAML == "" || tiersYAML == "[]" {
		log.Printf("ConfigMap %s/%s has empty 'tiers' field", k.Namespace, k.ConfigMap)
		return &models.TierConfig{Tiers: []models.Tier{}}, nil
	}

	log.Printf("Parsing tiers YAML (length: %d chars)", len(tiersYAML))

	// Parse the tiers YAML string
	var tiers []models.Tier
	if err := yaml.Unmarshal([]byte(tiersYAML), &tiers); err != nil {
		log.Printf("Failed to parse tiers YAML: %v", err)
		return nil, fmt.Errorf("failed to parse tiers YAML: %w", err)
	}

	log.Printf("Successfully loaded %d tiers from ConfigMap", len(tiers))
	return &models.TierConfig{Tiers: tiers}, nil
}

// Helper function to get keys from a map for logging
func getMapKeys(m map[string]string) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

// Save persists the tier configuration to Kubernetes ConfigMap
func (k *K8sTierStorage) Save(config *models.TierConfig) error {
	ctx := context.Background()

	// Check if namespace exists first
	nsExists, err := NamespaceExists(k.Namespace)
	if err != nil {
		return fmt.Errorf("failed to verify namespace %s: %w", k.Namespace, err)
	}
	if !nsExists {
		log.Printf("Namespace %s not found", k.Namespace)
		return models.ErrNamespaceNotFound
	}

	// Marshal tiers to YAML string with 2-space indentation
	var tiersBuffer bytes.Buffer
	tiersEncoder := yaml.NewEncoder(&tiersBuffer)
	tiersEncoder.SetIndent(2)
	if err := tiersEncoder.Encode(config.Tiers); err != nil {
		return fmt.Errorf("failed to marshal tiers: %w", err)
	}
	tiersEncoder.Close()

	// Remove document separator and trailing newline if present
	tiersYAML := tiersBuffer.String()
	tiersYAML = strings.TrimPrefix(tiersYAML, "---\n")
	tiersYAML = strings.TrimSuffix(tiersYAML, "\n")

	// Try to get existing ConfigMap
	cm, err := k.Client.CoreV1().ConfigMaps(k.Namespace).Get(ctx, k.ConfigMap, metav1.GetOptions{})
	if err != nil {
		if errors.IsNotFound(err) {
			// ConfigMap doesn't exist, create it
			newCM := &corev1.ConfigMap{
				ObjectMeta: metav1.ObjectMeta{
					Name:      k.ConfigMap,
					Namespace: k.Namespace,
					Labels: map[string]string{
						"app": "tier-to-group-admin",
					},
				},
				Data: map[string]string{
					"tiers": tiersYAML,
				},
			}

			_, err := k.Client.CoreV1().ConfigMaps(k.Namespace).Create(ctx, newCM, metav1.CreateOptions{})
			if err != nil {
				return fmt.Errorf("failed to create ConfigMap: %w", err)
			}
			return nil
		}
		return fmt.Errorf("failed to get ConfigMap: %w", err)
	}

	// Update existing ConfigMap
	cm.Data["tiers"] = tiersYAML
	_, err = k.Client.CoreV1().ConfigMaps(k.Namespace).Update(ctx, cm, metav1.UpdateOptions{})
	if err != nil {
		return fmt.Errorf("failed to update ConfigMap: %w", err)
	}

	return nil
}

// getRESTConfig creates a REST config for accessing OpenShift resources
// This uses the same logic as NewKubernetesClient to get the config
func getRESTConfig() (*rest.Config, error) {
	// Try in-cluster config first (when running in pod)
	config, err := rest.InClusterConfig()
	if err != nil {
		// Fall back to kubeconfig file (for local development)
		kubeconfig := os.Getenv("KUBECONFIG")
		if kubeconfig == "" {
			kubeconfig = os.Getenv("HOME") + "/.kube/config"
		}

		config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
		if err != nil {
			return nil, fmt.Errorf("failed to create Kubernetes config: %w", err)
		}
	}
	return config, nil
}

// GroupExists checks if a Group exists in the OpenShift cluster.
// Groups are cluster-scoped resources in the user.openshift.io/v1 API group.
// Note: system:authenticated is a special built-in Kubernetes group that
// always exists but is not returned by the API, so it's handled as a special case.
func (k *K8sTierStorage) GroupExists(groupName string) (bool, error) {
	if groupName == SystemAuthenticatedGroup {
		return true, nil
	}

	ctx := context.Background()

	// Get REST config
	config, err := getRESTConfig()
	if err != nil {
		return false, fmt.Errorf("failed to get REST config: %w", err)
	}

	// Create dynamic client for OpenShift resources
	dynamicClient, err := dynamic.NewForConfig(config)
	if err != nil {
		return false, fmt.Errorf("failed to create dynamic client: %w", err)
	}

	// Define Group resource
	groupResource := schema.GroupVersionResource{
		Group:    "user.openshift.io",
		Version:  "v1",
		Resource: "groups",
	}

	// Try to get the group
	_, err = dynamicClient.Resource(groupResource).Get(ctx, groupName, metav1.GetOptions{})
	if err != nil {
		if errors.IsNotFound(err) {
			log.Printf("Group %s not found in cluster", groupName)
			return false, nil
		}
		// For other errors (permission denied, etc.), return the error
		log.Printf("Error checking if group %s exists: %v", groupName, err)
		return false, fmt.Errorf("failed to check if group exists: %w", err)
	}

	log.Printf("Group %s exists in cluster", groupName)
	return true, nil
}

// ListLLMInferenceServices lists all LLMInferenceService resources across all namespaces
func ListLLMInferenceServices() ([]*unstructured.Unstructured, error) {
	ctx := context.Background()

	// Get REST config
	config, err := getRESTConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to get REST config: %w", err)
	}

	// Create dynamic client
	dynamicClient, err := dynamic.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create dynamic client: %w", err)
	}

	// Define LLMInferenceService resource
	llmResource := schema.GroupVersionResource{
		Group:    "serving.kserve.io",
		Version:  "v1alpha1",
		Resource: "llminferenceservices",
	}

	// List all LLMInferenceServices across all namespaces
	list, err := dynamicClient.Resource(llmResource).List(ctx, metav1.ListOptions{})
	if err != nil {
		log.Printf("Error listing LLMInferenceServices: %v", err)
		return nil, fmt.Errorf("failed to list LLMInferenceServices: %w", err)
	}

	log.Printf("Found %d LLMInferenceService resources", len(list.Items))

	// Convert items to slice of pointers
	items := make([]*unstructured.Unstructured, len(list.Items))
	for i := range list.Items {
		items[i] = &list.Items[i]
	}

	return items, nil
}

// GetLLMInferenceServicesByTier filters LLMInferenceServices by tier annotation
func GetLLMInferenceServicesByTier(tierName string) ([]*unstructured.Unstructured, error) {
	// List all LLMInferenceServices
	allServices, err := ListLLMInferenceServices()
	if err != nil {
		return nil, err
	}

	var matchingServices []*unstructured.Unstructured

	for _, service := range allServices {
		// Extract annotations
		annotations, found, err := unstructured.NestedStringMap(service.Object, "metadata", "annotations")
		if err != nil {
			log.Printf("Error extracting annotations from LLMInferenceService %s/%s: %v",
				getNamespace(service), getName(service), err)
			continue
		}

		if !found || annotations == nil {
			// No annotations, skip
			continue
		}

		// Get tiers annotation
		tiersAnnotation, exists := annotations[models.TierAnnotationKey]
		if !exists || tiersAnnotation == "" {
			// No tiers annotation, skip
			continue
		}

		// Parse tiers from annotation
		tiers, err := models.ParseTiersFromAnnotation(tiersAnnotation)
		if err != nil {
			log.Printf("Error parsing tiers annotation for LLMInferenceService %s/%s: %v",
				getNamespace(service), getName(service), err)
			continue
		}

		// Check if tier is in the list
		for _, tier := range tiers {
			if tier == tierName {
				matchingServices = append(matchingServices, service)
				break
			}
		}
	}

	log.Printf("Found %d LLMInferenceService resources with tier %s", len(matchingServices), tierName)
	return matchingServices, nil
}

// Helper functions to extract name and namespace from unstructured object
func getName(obj *unstructured.Unstructured) string {
	name, _, _ := unstructured.NestedString(obj.Object, "metadata", "name")
	return name
}

func getNamespace(obj *unstructured.Unstructured) string {
	namespace, _, _ := unstructured.NestedString(obj.Object, "metadata", "namespace")
	return namespace
}

// NamespaceExists checks if a namespace exists in the cluster
func NamespaceExists(namespace string) (bool, error) {
	ctx := context.Background()

	// Get REST config
	config, err := getRESTConfig()
	if err != nil {
		return false, fmt.Errorf("failed to get REST config: %w", err)
	}

	// Create clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return false, fmt.Errorf("failed to create clientset: %w", err)
	}

	// Try to get the namespace
	_, err = clientset.CoreV1().Namespaces().Get(ctx, namespace, metav1.GetOptions{})
	if err != nil {
		if errors.IsNotFound(err) {
			return false, nil
		}
		return false, fmt.Errorf("failed to check namespace: %w", err)
	}

	return true, nil
}

// GetLLMInferenceService retrieves a specific LLMInferenceService by namespace and name
func GetLLMInferenceService(namespace, name string) (*unstructured.Unstructured, error) {
	ctx := context.Background()

	// First check if namespace exists
	nsExists, err := NamespaceExists(namespace)
	if err != nil {
		return nil, fmt.Errorf("failed to verify namespace: %w", err)
	}
	if !nsExists {
		log.Printf("Namespace %s not found", namespace)
		return nil, models.ErrNamespaceNotFound
	}

	// Get REST config
	config, err := getRESTConfig()
	if err != nil {
		return nil, fmt.Errorf("failed to get REST config: %w", err)
	}

	// Create dynamic client
	dynamicClient, err := dynamic.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create dynamic client: %w", err)
	}

	// Define LLMInferenceService resource
	llmResource := schema.GroupVersionResource{
		Group:    "serving.kserve.io",
		Version:  "v1alpha1",
		Resource: "llminferenceservices",
	}

	// Get the specific LLMInferenceService
	service, err := dynamicClient.Resource(llmResource).Namespace(namespace).Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		if errors.IsNotFound(err) {
			log.Printf("LLMInferenceService %s/%s not found", namespace, name)
			return nil, models.ErrLLMInferenceServiceNotFound
		}
		log.Printf("Error getting LLMInferenceService %s/%s: %v", namespace, name, err)
		return nil, fmt.Errorf("failed to get LLMInferenceService: %w", err)
	}

	log.Printf("Found LLMInferenceService %s/%s", namespace, name)
	return service, nil
}

// UpdateLLMInferenceServiceAnnotation updates the tier annotation on an LLMInferenceService
func UpdateLLMInferenceServiceAnnotation(namespace, name, tierName string) error {
	ctx := context.Background()

	// First check if namespace exists
	nsExists, err := NamespaceExists(namespace)
	if err != nil {
		return fmt.Errorf("failed to verify namespace: %w", err)
	}
	if !nsExists {
		log.Printf("Namespace %s not found", namespace)
		return models.ErrNamespaceNotFound
	}

	// Get REST config
	config, err := getRESTConfig()
	if err != nil {
		return fmt.Errorf("failed to get REST config: %w", err)
	}

	// Create dynamic client
	dynamicClient, err := dynamic.NewForConfig(config)
	if err != nil {
		return fmt.Errorf("failed to create dynamic client: %w", err)
	}

	// Define LLMInferenceService resource
	llmResource := schema.GroupVersionResource{
		Group:    "serving.kserve.io",
		Version:  "v1alpha1",
		Resource: "llminferenceservices",
	}

	// Get the service
	service, err := dynamicClient.Resource(llmResource).Namespace(namespace).Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		if errors.IsNotFound(err) {
			return models.ErrLLMInferenceServiceNotFound
		}
		return fmt.Errorf("failed to get LLMInferenceService: %w", err)
	}

	// Extract existing annotations
	annotations, found, err := unstructured.NestedStringMap(service.Object, "metadata", "annotations")
	if err != nil {
		return fmt.Errorf("failed to extract annotations: %w", err)
	}
	if !found || annotations == nil {
		annotations = make(map[string]string)
	}

	// Parse existing tiers
	var existingTiers []string
	if tiersAnnotation, exists := annotations[models.TierAnnotationKey]; exists && tiersAnnotation != "" {
		existingTiers, err = models.ParseTiersFromAnnotation(tiersAnnotation)
		if err != nil {
			log.Printf("Warning: failed to parse existing tiers annotation, starting fresh: %v", err)
			existingTiers = []string{}
		}
	}

	// Add the new tier (avoiding duplicates)
	updatedTiers := models.AddTierToList(existingTiers, tierName)

	// Format tiers as JSON
	tiersJSON, err := models.FormatTiersAnnotation(updatedTiers)
	if err != nil {
		return fmt.Errorf("failed to format tiers annotation: %w", err)
	}

	// Update the annotation
	annotations[models.TierAnnotationKey] = tiersJSON
	if err := unstructured.SetNestedStringMap(service.Object, annotations, "metadata", "annotations"); err != nil {
		return fmt.Errorf("failed to set annotations: %w", err)
	}

	// Update the resource
	_, err = dynamicClient.Resource(llmResource).Namespace(namespace).Update(ctx, service, metav1.UpdateOptions{})
	if err != nil {
		return fmt.Errorf("failed to update LLMInferenceService: %w", err)
	}

	log.Printf("Successfully updated LLMInferenceService %s/%s with tier %s", namespace, name, tierName)
	return nil
}

// RemoveLLMInferenceServiceAnnotation removes a tier annotation from an LLMInferenceService
func RemoveLLMInferenceServiceAnnotation(namespace, name, tierName string) error {
	ctx := context.Background()

	// First check if namespace exists
	nsExists, err := NamespaceExists(namespace)
	if err != nil {
		return fmt.Errorf("failed to verify namespace: %w", err)
	}
	if !nsExists {
		log.Printf("Namespace %s not found", namespace)
		return models.ErrNamespaceNotFound
	}

	// Get REST config
	config, err := getRESTConfig()
	if err != nil {
		return fmt.Errorf("failed to get REST config: %w", err)
	}

	// Create dynamic client
	dynamicClient, err := dynamic.NewForConfig(config)
	if err != nil {
		return fmt.Errorf("failed to create dynamic client: %w", err)
	}

	// Define LLMInferenceService resource
	llmResource := schema.GroupVersionResource{
		Group:    "serving.kserve.io",
		Version:  "v1alpha1",
		Resource: "llminferenceservices",
	}

	// Get the service
	service, err := dynamicClient.Resource(llmResource).Namespace(namespace).Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		if errors.IsNotFound(err) {
			return models.ErrLLMInferenceServiceNotFound
		}
		return fmt.Errorf("failed to get LLMInferenceService: %w", err)
	}

	// Extract existing annotations
	annotations, found, err := unstructured.NestedStringMap(service.Object, "metadata", "annotations")
	if err != nil {
		return fmt.Errorf("failed to extract annotations: %w", err)
	}
	if !found || annotations == nil {
		// No annotations at all - tier can't exist
		return models.ErrTierNotFoundInAnnotation
	}

	// Parse existing tiers
	tiersAnnotation, exists := annotations[models.TierAnnotationKey]
	if !exists || tiersAnnotation == "" {
		// No tiers annotation - tier can't exist
		return models.ErrTierNotFoundInAnnotation
	}

	existingTiers, err := models.ParseTiersFromAnnotation(tiersAnnotation)
	if err != nil {
		return fmt.Errorf("failed to parse tiers annotation: %w", err)
	}

	// Remove the tier
	updatedTiers, found := models.RemoveTierFromList(existingTiers, tierName)
	if !found {
		return models.ErrTierNotFoundInAnnotation
	}

	// Format tiers as JSON
	tiersJSON, err := models.FormatTiersAnnotation(updatedTiers)
	if err != nil {
		return fmt.Errorf("failed to format tiers annotation: %w", err)
	}

	// Update the annotation
	annotations[models.TierAnnotationKey] = tiersJSON
	if err := unstructured.SetNestedStringMap(service.Object, annotations, "metadata", "annotations"); err != nil {
		return fmt.Errorf("failed to set annotations: %w", err)
	}

	// Update the resource
	_, err = dynamicClient.Resource(llmResource).Namespace(namespace).Update(ctx, service, metav1.UpdateOptions{})
	if err != nil {
		return fmt.Errorf("failed to update LLMInferenceService: %w", err)
	}

	log.Printf("Successfully removed tier %s from LLMInferenceService %s/%s", tierName, namespace, name)
	return nil
}
