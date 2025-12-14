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
	"fmt"
	"os"

	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

// NewKubernetesClient creates a Kubernetes client using client-go's automatic
// service account token management. When running in-cluster, it automatically
// reads and refreshes the service account token from the mounted secret volume.
//
// Priority order:
// 1. In-cluster config (automatic service account token management)
// 2. Kubeconfig file (for local development)
func NewKubernetesClient() (kubernetes.Interface, error) {
	var config *rest.Config
	var err error

	// Try in-cluster config first (when running in pod)
	// rest.InClusterConfig() automatically:
	// - Reads service account token from /var/run/secrets/kubernetes.io/serviceaccount/token
	// - Handles token refresh for projected service account tokens
	// - Reads CA certificate from /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
	// - Uses the service account's namespace
	config, err = rest.InClusterConfig()
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

	// Create the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create Kubernetes client: %w", err)
	}

	return clientset, nil
}
