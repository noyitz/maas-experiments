package api

import (
	"os"
	"tier-to-group-admin/docs"
	"tier-to-group-admin/internal/service"

	"github.com/gin-gonic/gin"
	swaggerFiles "github.com/swaggo/files"
	ginSwagger "github.com/swaggo/gin-swagger"
)

// SetupRouter configures and returns the Gin router with all routes
func SetupRouter(tierService *service.TierService) *gin.Engine {
	// Ensure we're not in release mode (which disables logging)
	// This must be called before creating the router
	gin.SetMode(gin.DebugMode)

	// Use Default() which includes Logger and Recovery middleware
	// Logger middleware logs all HTTP requests
	router := gin.Default()

	// Create handler
	handler := NewTierHandler(tierService)

	// API v1 routes
	v1 := router.Group("/api/v1")
	{
		v1.POST("/tiers", handler.CreateTier)
		v1.GET("/tiers", handler.GetTiers)
		v1.GET("/tiers/:name", handler.GetTier)
		v1.PUT("/tiers/:name", handler.UpdateTier)
		v1.DELETE("/tiers/:name", handler.DeleteTier)

		// Group management routes
		v1.POST("/tiers/:name/groups", handler.AddGroup)
		v1.DELETE("/tiers/:name/groups/:group", handler.RemoveGroup)
	}

	// Health check endpoint
	router.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})

	// Swagger documentation endpoint with dynamic host detection
	// Middleware to update Swagger host from request if ROUTE_HOST env var is not set
	swaggerHandler := func(c *gin.Context) {
		// Dynamically set host from request if ROUTE_HOST env var is not set
		if os.Getenv("ROUTE_HOST") == "" {
			host := c.Request.Host
			if host != "" {
				docs.SwaggerInfo.Host = host
			}
		}
		ginSwagger.WrapHandler(swaggerFiles.Handler)(c)
	}
	router.GET("/swagger/*any", swaggerHandler)

	return router
}
