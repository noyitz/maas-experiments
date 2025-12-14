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
	"strings"
	"testing"
)

func TestValidateKubernetesName(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		wantErr bool
	}{
		// Valid names
		{"valid single char", "a", false},
		{"valid simple name", "mygroup", false},
		{"valid with hyphen", "my-group", false},
		{"valid with colon", "system:authenticated", false},
		{"valid with dot", "group.name", false},
		{"valid with underscore", "group_name", false},
		{"valid complex", "system:authenticated:users", false},
		{"valid with numbers", "group123", false},
		{"valid long name", "a" + strings.Repeat("b", 250) + "z", false}, // 252 chars

		// Invalid names
		{"empty string", "", true},
		{"starts with hyphen", "-invalid", true},
		{"ends with hyphen", "invalid-", true},
		{"starts with colon", ":invalid", true},
		{"ends with colon", "invalid:", true},
		{"starts with dot", ".invalid", true},
		{"ends with dot", "invalid.", true},
		{"starts with underscore", "_invalid", true},
		{"ends with underscore", "invalid_", true},
		{"has uppercase", "Invalid", true},
		{"has uppercase in middle", "invalidName", true},
		{"too long", "a" + strings.Repeat("b", 253) + "z", true}, // 255 chars
		{"only special chars", "---", true},
		{"only colons", ":::", true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := ValidateKubernetesName(tt.input)
			if (err != nil) != tt.wantErr {
				t.Errorf("ValidateKubernetesName(%q) error = %v, wantErr %v", tt.input, err, tt.wantErr)
			}
		})
	}
}

