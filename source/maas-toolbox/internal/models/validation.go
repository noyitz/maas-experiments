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
	"regexp"
	"unicode"
)

var (
	// kubernetesNameRegex validates Kubernetes resource names (DNS subdomain format)
	// Allows: lowercase alphanumeric, hyphens, colons (for groups like system:authenticated), dots, underscores
	// Must start and end with alphanumeric (single character names are allowed)
	// Pattern: starts with alphanumeric, optionally followed by middle chars ending with alphanumeric
	// The regex handles single char (a-z0-9) and multi-char (a-z0-9 followed by optional middle ending with a-z0-9)
	kubernetesNameRegex = regexp.MustCompile(`^[a-z0-9]([a-z0-9\-:._]*[a-z0-9])?$`)
)

// ValidateKubernetesName validates that a name conforms to Kubernetes naming conventions
// Kubernetes names must:
// - Be between 1 and 253 characters
// - Start and end with an alphanumeric character
// - Contain only lowercase alphanumeric characters, hyphens (-), colons (:), dots (.), and underscores (_)
// - Not be empty
func ValidateKubernetesName(name string) error {
	if name == "" {
		return ErrGroupRequired
	}

	// Check length (Kubernetes DNS subdomain max length is 253)
	if len(name) > 253 {
		return ErrInvalidKubernetesName
	}

	// Check if it's all lowercase
	for _, r := range name {
		if unicode.IsUpper(r) {
			return ErrInvalidKubernetesName
		}
	}

	// Check format with regex
	if !kubernetesNameRegex.MatchString(name) {
		return ErrInvalidKubernetesName
	}

	return nil
}

// ValidateGroupName validates a Kubernetes group name
// This is an alias for ValidateKubernetesName for clarity
func ValidateGroupName(groupName string) error {
	return ValidateKubernetesName(groupName)
}

