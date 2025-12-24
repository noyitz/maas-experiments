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

package api

import (
	"errors"
	"log"
	"maas-toolbox/internal/models"
	"maas-toolbox/internal/service"
	"net/http"

	"github.com/gin-gonic/gin"
)

// TierHandler handles HTTP requests for tier management
type TierHandler struct {
	service           *service.TierService
	llmServiceService *service.LLMInferenceServiceService
}

// NewTierHandler creates a new TierHandler instance
func NewTierHandler(service *service.TierService, llmServiceService *service.LLMInferenceServiceService) *TierHandler {
	return &TierHandler{
		service:           service,
		llmServiceService: llmServiceService,
	}
}

// ErrorResponse represents an error response
type ErrorResponse struct {
	Error string `json:"error"`
}

// CreateTier handles POST /api/v1/tiers
// @Summary      Create a new tier
// @Description  Create a new tier with name, description, level, and groups. The tier name must be unique and cannot be changed after creation.
// @Tags         tiers
// @Accept       json
// @Produce      json
// @Param        tier  body      models.Tier  true  "Tier object"
// @Success      201   {object}  models.Tier  "Tier created successfully"
// @Failure      400   {object}  ErrorResponse  "Bad request - validation error"
// @Failure      409   {object}  ErrorResponse  "Conflict - tier already exists"
// @Failure      500   {object}  ErrorResponse  "Internal server error"
// @Router       /tiers [post]
func (h *TierHandler) CreateTier(c *gin.Context) {
	var tier models.Tier
	if err := c.ShouldBindJSON(&tier); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	// Initialize groups to empty list if not provided
	if tier.Groups == nil {
		tier.Groups = []string{}
	}

	// Validate required fields for creation
	if tier.Name == "" {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: models.ErrTierNameRequired.Error()})
		return
	}
	if tier.Description == "" {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: models.ErrTierDescriptionRequired.Error()})
		return
	}

	if err := h.service.CreateTier(&tier); err != nil {
		// Use errors.Is() to properly check wrapped errors
		if errors.Is(err, models.ErrTierAlreadyExists) {
			c.JSON(http.StatusConflict, ErrorResponse{Error: "tier already exists"})
		} else if errors.Is(err, models.ErrNamespaceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "configmap namespace not found"})
		} else if errors.Is(err, models.ErrTierNameRequired) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "tier name is required"})
		} else if errors.Is(err, models.ErrTierDescriptionRequired) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "tier description is required"})
		} else if errors.Is(err, models.ErrTierLevelInvalid) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "tier level must be non-negative"})
		} else if errors.Is(err, models.ErrInvalidKubernetesName) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "invalid kubernetes name format"})
		} else if errors.Is(err, models.ErrGroupNotFoundInCluster) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "group not found in cluster"})
		} else {
			c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}

	c.JSON(http.StatusCreated, tier)
}

// GetTiers handles GET /api/v1/tiers
// @Summary      List all tiers
// @Description  Retrieve a list of all tiers in the system
// @Tags         tiers
// @Produce      json
// @Success      200  {array}   models.Tier  "List of tiers"
// @Failure      500  {object}  ErrorResponse  "Internal server error"
// @Router       /tiers [get]
func (h *TierHandler) GetTiers(c *gin.Context) {
	log.Printf("GET /api/v1/tiers - Request received from %s", c.ClientIP())
	tiers, err := h.service.GetTiers()
	if err != nil {
		log.Printf("GET /api/v1/tiers - Error: %v", err)
		// Use errors.Is() to properly check wrapped errors
		if errors.Is(err, models.ErrNamespaceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "configmap namespace not found"})
		} else {
			c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}

	log.Printf("GET /api/v1/tiers - Returning %d tiers", len(tiers))
	c.JSON(http.StatusOK, tiers)
}

// GetTier handles GET /api/v1/tiers/:name
// @Summary      Get a specific tier
// @Description  Retrieve a tier by its name
// @Tags         tiers
// @Produce      json
// @Param        name  path      string  true  "Tier name"
// @Success      200    {object}  models.Tier  "Tier details"
// @Failure      404    {object}  ErrorResponse  "Tier not found"
// @Failure      500    {object}  ErrorResponse  "Internal server error"
// @Router       /tiers/{name} [get]
func (h *TierHandler) GetTier(c *gin.Context) {
	name := c.Param("name")
	tier, err := h.service.GetTier(name)
	if err != nil {
		// Use errors.Is() to properly check wrapped errors
		if errors.Is(err, models.ErrTierNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "tier not found"})
		} else if errors.Is(err, models.ErrNamespaceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "configmap namespace not found"})
		} else {
			c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}

	c.JSON(http.StatusOK, tier)
}

// UpdateTier handles PUT /api/v1/tiers/:name
// @Summary      Update a tier
// @Description  Update a tier's description, level, or groups. The tier name cannot be changed.
// @Tags         tiers
// @Accept       json
// @Produce      json
// @Param        name     path      string       true  "Tier name"
// @Param        updates  body      models.Tier  true  "Tier update object (name field is ignored)"
// @Success      200      {object}  models.Tier  "Updated tier"
// @Failure      400      {object}  ErrorResponse  "Bad request - validation error"
// @Failure      404      {object}  ErrorResponse  "Tier not found"
// @Failure      500      {object}  ErrorResponse  "Internal server error"
// @Router       /tiers/{name} [put]
func (h *TierHandler) UpdateTier(c *gin.Context) {
	name := c.Param("name")
	var updates models.Tier

	// Bind JSON - name field is optional for updates
	if err := c.ShouldBindJSON(&updates); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	// Check if user is trying to change the name (which is immutable)
	// We check the original value from JSON before overwriting it
	if updates.Name != "" && updates.Name != name {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: models.ErrTierNameImmutable.Error()})
		return
	}

	// Ensure name is set from URL path (not from JSON body) for validation
	updates.Name = name

	if err := h.service.UpdateTier(name, &updates); err != nil {
		// Use errors.Is() to properly check wrapped errors
		if errors.Is(err, models.ErrTierNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "tier not found"})
		} else if errors.Is(err, models.ErrNamespaceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "configmap namespace not found"})
		} else if errors.Is(err, models.ErrTierNameImmutable) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "tier name cannot be changed"})
		} else if errors.Is(err, models.ErrTierDescriptionRequired) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "tier description is required"})
		} else if errors.Is(err, models.ErrTierLevelInvalid) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "tier level must be non-negative"})
		} else if errors.Is(err, models.ErrInvalidKubernetesName) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "invalid kubernetes name format"})
		} else if errors.Is(err, models.ErrGroupNotFoundInCluster) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "group not found in cluster"})
		} else {
			c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}

	// Return updated tier
	tier, err := h.service.GetTier(name)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	c.JSON(http.StatusOK, tier)
}

// DeleteTier handles DELETE /api/v1/tiers/:name
// @Summary      Delete a tier
// @Description  Delete a tier by its name
// @Tags         tiers
// @Param        name  path  string  true  "Tier name"
// @Success      204   "No content - tier deleted successfully"
// @Failure      404   {object}  ErrorResponse  "Tier not found"
// @Failure      500   {object}  ErrorResponse  "Internal server error"
// @Router       /tiers/{name} [delete]
func (h *TierHandler) DeleteTier(c *gin.Context) {
	name := c.Param("name")
	if err := h.service.DeleteTier(name); err != nil {
		// Use errors.Is() to properly check wrapped errors
		if errors.Is(err, models.ErrTierNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "tier not found"})
		} else if errors.Is(err, models.ErrNamespaceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "configmap namespace not found"})
		} else {
			c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}

	c.JSON(http.StatusNoContent, nil)
}

// AddGroupRequest represents the request body for adding a group
// @Description Request body for adding a group to a tier
type AddGroupRequest struct {
	Group string `json:"group" binding:"required" example:"premium-users"` // Kubernetes group name to add
}

// AddGroup handles POST /api/v1/tiers/:name/groups
// @Summary      Add a group to a tier
// @Description  Add a Kubernetes group to a tier. The group must not already exist in the tier.
// @Tags         groups
// @Accept       json
// @Produce      json
// @Param        name   path      string           true  "Tier name"
// @Param        group  body      AddGroupRequest   true  "Group to add"
// @Success      200    {object}  models.Tier      "Updated tier with new group"
// @Failure      400    {object}  ErrorResponse    "Bad request - validation error"
// @Failure      404    {object}  ErrorResponse    "Tier not found"
// @Failure      409    {object}  ErrorResponse    "Conflict - group already exists"
// @Failure      500    {object}  ErrorResponse    "Internal server error"
// @Router       /tiers/{name}/groups [post]
func (h *TierHandler) AddGroup(c *gin.Context) {
	tierName := c.Param("name")
	var req AddGroupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	if err := h.service.AddGroup(tierName, req.Group); err != nil {
		// Use errors.Is() to properly check wrapped errors
		if errors.Is(err, models.ErrTierNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "tier not found"})
		} else if errors.Is(err, models.ErrNamespaceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "configmap namespace not found"})
		} else if errors.Is(err, models.ErrGroupAlreadyExists) {
			c.JSON(http.StatusConflict, ErrorResponse{Error: "group already exists in tier"})
		} else if errors.Is(err, models.ErrGroupRequired) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "group name is required"})
		} else if errors.Is(err, models.ErrInvalidKubernetesName) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "invalid kubernetes name format"})
		} else if errors.Is(err, models.ErrGroupNotFoundInCluster) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "group not found in cluster"})
		} else {
			c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}

	// Return updated tier
	tier, err := h.service.GetTier(tierName)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	c.JSON(http.StatusOK, tier)
}

// RemoveGroup handles DELETE /api/v1/tiers/:name/groups/:group
// @Summary      Remove a group from a tier
// @Description  Remove a Kubernetes group from a tier
// @Tags         groups
// @Produce      json
// @Param        name   path      string       true  "Tier name"
// @Param        group  path      string       true  "Group name to remove"
// @Success      200    {object}  models.Tier  "Updated tier with group removed"
// @Failure      404    {object}  ErrorResponse  "Tier or group not found"
// @Failure      500    {object}  ErrorResponse  "Internal server error"
// @Router       /tiers/{name}/groups/{group} [delete]
func (h *TierHandler) RemoveGroup(c *gin.Context) {
	tierName := c.Param("name")
	groupName := c.Param("group")

	if err := h.service.RemoveGroup(tierName, groupName); err != nil {
		// Use errors.Is() to properly check wrapped errors
		if errors.Is(err, models.ErrTierNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "tier not found"})
		} else if errors.Is(err, models.ErrGroupNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "group not found in tier"})
		} else if errors.Is(err, models.ErrNamespaceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "configmap namespace not found"})
		} else if errors.Is(err, models.ErrGroupRequired) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "group name is required"})
		} else if errors.Is(err, models.ErrInvalidKubernetesName) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "invalid kubernetes name format"})
		} else {
			c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}

	// Return updated tier
	tier, err := h.service.GetTier(tierName)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	c.JSON(http.StatusOK, tier)
}

// GetTiersByGroup handles GET /api/v1/groups/:group/tiers
// @Summary      Get tiers by group
// @Description  Retrieve all tiers that contain the specified Kubernetes group
// @Tags         groups
// @Produce      json
// @Param        group  path      string  true  "Group name"
// @Success      200    {array}   models.Tier  "List of tiers containing the group"
// @Failure      400    {object}  ErrorResponse  "Bad request - invalid group name format"
// @Failure      500    {object}  ErrorResponse  "Internal server error"
// @Router       /groups/{group}/tiers [get]
func (h *TierHandler) GetTiersByGroup(c *gin.Context) {
	groupName := c.Param("group")
	tiers, err := h.service.GetTiersByGroup(groupName)
	if err != nil {
		// Use errors.Is() to properly check wrapped errors
		if errors.Is(err, models.ErrInvalidKubernetesName) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "invalid kubernetes name format"})
		} else if errors.Is(err, models.ErrNamespaceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "configmap namespace not found"})
		} else {
			c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}

	c.JSON(http.StatusOK, tiers)
}

// GetLLMInferenceServicesByTier handles GET /api/v1/tiers/:name/llminferenceservices
// @Summary      Get LLMInferenceServices by tier
// @Description  Retrieve all LLMInferenceService instances that have the specified tier in their annotation
// @Tags         llminferenceservices
// @Produce      json
// @Param        name  path      string  true  "Tier name"
// @Success      200   {array}   models.LLMInferenceService  "List of LLMInferenceService instances with the tier"
// @Failure      404   {object}  ErrorResponse  "Tier not found"
// @Failure      500   {object}  ErrorResponse  "Internal server error"
// @Router       /tiers/{name}/llminferenceservices [get]
func (h *TierHandler) GetLLMInferenceServicesByTier(c *gin.Context) {
	tierName := c.Param("name")

	// Verify tier exists
	_, err := h.service.GetTier(tierName)
	if err != nil {
		if err == models.ErrTierNotFound {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: err.Error()})
		} else {
			c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}

	// Get LLMInferenceServices for this tier
	services, err := h.llmServiceService.GetLLMInferenceServicesByTier(tierName)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	c.JSON(http.StatusOK, services)
}

// GetLLMInferenceServicesByGroup handles GET /api/v1/groups/:group/llminferenceservices
// @Summary      Get LLMInferenceServices by group
// @Description  Retrieve all LLMInferenceService instances associated with the specified group (via tiers)
// @Tags         llminferenceservices
// @Produce      json
// @Param        group  path      string  true  "Group name"
// @Success      200    {array}   models.LLMInferenceService  "List of LLMInferenceService instances for the group"
// @Failure      400    {object}  ErrorResponse  "Bad request - invalid group name format"
// @Failure      500    {object}  ErrorResponse  "Internal server error"
// @Router       /groups/{group}/llminferenceservices [get]
func (h *TierHandler) GetLLMInferenceServicesByGroup(c *gin.Context) {
	groupName := c.Param("group")

	// Validate group name format
	if err := models.ValidateGroupName(groupName); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	// Get LLMInferenceServices for this group
	services, err := h.llmServiceService.GetLLMInferenceServicesByGroup(groupName)
	if err != nil {
		c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		return
	}

	c.JSON(http.StatusOK, services)
}

// AnnotateLLMInferenceService handles POST /api/v1/llminferenceservices/annotate
// @Summary      Annotate LLMInferenceService with a tier
// @Description  Add a tier annotation to an LLMInferenceService instance. The tier must exist before annotating.
// @Tags         llminferenceservices
// @Accept       json
// @Produce      json
// @Param        request  body      models.AnnotateRequest  true  "Annotation request with namespace, name, and tier"
// @Success      200      {object}  map[string]string  "Successfully annotated"
// @Failure      400      {object}  ErrorResponse  "Bad request - validation error"
// @Failure      404      {object}  ErrorResponse  "Tier or LLMInferenceService not found"
// @Failure      500      {object}  ErrorResponse  "Internal server error"
// @Router       /llminferenceservices/annotate [post]
func (h *TierHandler) AnnotateLLMInferenceService(c *gin.Context) {
	var req models.AnnotateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	// Validate request
	if err := req.Validate(); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	// Annotate the service
	if err := h.llmServiceService.AnnotateLLMInferenceServiceWithTier(req.Namespace, req.Name, req.Tier); err != nil {
		// Use errors.Is() to properly check wrapped errors
		if errors.Is(err, models.ErrTierNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "tier not found"})
		} else if errors.Is(err, models.ErrNamespaceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "namespace not found"})
		} else if errors.Is(err, models.ErrLLMInferenceServiceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "llminferenceservice not found"})
		} else if errors.Is(err, models.ErrNamespaceRequired) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "namespace is required"})
		} else if errors.Is(err, models.ErrNameRequired) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "name is required"})
		} else if errors.Is(err, models.ErrTierNameRequired) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "tier name is required"})
		} else {
			c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":   "Successfully annotated LLMInferenceService",
		"namespace": req.Namespace,
		"name":      req.Name,
		"tier":      req.Tier,
	})
}

// RemoveTierFromLLMInferenceService handles DELETE /api/v1/llminferenceservices/annotate
// @Summary      Remove tier from LLMInferenceService
// @Description  Remove a tier annotation from an LLMInferenceService instance.
// @Tags         llminferenceservices
// @Accept       json
// @Produce      json
// @Param        request  body      models.RemoveTierRequest  true  "Remove tier request with namespace, name, and tier"
// @Success      200      {object}  map[string]string  "Successfully removed tier"
// @Failure      400      {object}  ErrorResponse  "Bad request - validation error"
// @Failure      404      {object}  ErrorResponse  "Namespace, LLMInferenceService, or tier annotation not found"
// @Failure      500      {object}  ErrorResponse  "Internal server error"
// @Router       /llminferenceservices/annotate [delete]
func (h *TierHandler) RemoveTierFromLLMInferenceService(c *gin.Context) {
	var req models.RemoveTierRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	// Validate request
	if err := req.Validate(); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}

	// Remove the tier
	if err := h.llmServiceService.RemoveTierFromLLMInferenceService(req.Namespace, req.Name, req.Tier); err != nil {
		// Use errors.Is() to properly check wrapped errors
		if errors.Is(err, models.ErrNamespaceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "namespace not found"})
		} else if errors.Is(err, models.ErrLLMInferenceServiceNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "llminferenceservice not found"})
		} else if errors.Is(err, models.ErrTierNotFoundInAnnotation) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "tier not found in service annotation"})
		} else if errors.Is(err, models.ErrNamespaceRequired) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "namespace is required"})
		} else if errors.Is(err, models.ErrNameRequired) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "name is required"})
		} else if errors.Is(err, models.ErrTierNameRequired) {
			c.JSON(http.StatusBadRequest, ErrorResponse{Error: "tier name is required"})
		} else {
			c.JSON(http.StatusInternalServerError, ErrorResponse{Error: err.Error()})
		}
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message":   "Successfully removed tier from LLMInferenceService",
		"namespace": req.Namespace,
		"name":      req.Name,
		"tier":      req.Tier,
	})
}
