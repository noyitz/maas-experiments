package main

import (
	"flag"
	"fmt"
	"log"
	"os"
	"tier-to-group-admin/docs"
	"tier-to-group-admin/internal/api"
	"tier-to-group-admin/internal/service"
	"tier-to-group-admin/internal/storage"
)

// @title           Tier-to-Group Admin API
// @version         1.0
// @description     REST API service for managing tier-to-group mappings in the Open Data Hub Model as a Service (MaaS) project.
// @description     This API provides CRUD operations for managing tiers that map Kubernetes groups to user-defined subscription tiers.

// @contact.name   API Support
// @contact.url    https://github.com/opendatahub-io/maas-billing
// @contact.email  support@example.com

// @license.name  Apache 2.0
// @license.url   http://www.apache.org/licenses/LICENSE-2.0.html

// @host      localhost:8080
// @BasePath  /api/v1

// @schemes   http https

func init() {
	// Initialize Swagger docs
	docs.SwaggerInfo.Title = "Tier-to-Group Admin API"
	docs.SwaggerInfo.Version = "1.0"
	docs.SwaggerInfo.Description = "REST API service for managing tier-to-group mappings in the Open Data Hub Model as a Service (MaaS) project."
	docs.SwaggerInfo.BasePath = "/api/v1"
	docs.SwaggerInfo.Schemes = []string{"http", "https"}

	// Set Swagger host from environment variable or default to localhost
	// In OpenShift, set ROUTE_HOST environment variable to the route hostname
	swaggerHost := os.Getenv("ROUTE_HOST")
	if swaggerHost == "" {
		swaggerHost = "localhost:8080"
	}
	docs.SwaggerInfo.Host = swaggerHost
}

// @title           Tier-to-Group Admin API
// @version         1.0
// @description     REST API service for managing tier-to-group mappings in the Open Data Hub Model as a Service (MaaS) project.
// @description     This API provides CRUD operations for managing tiers that map Kubernetes groups to user-defined subscription tiers.

// @contact.name   API Support
// @contact.url    https://github.com/opendatahub-io/maas-billing
// @contact.email  support@example.com

// @license.name  Apache 2.0
// @license.url   http://www.apache.org/licenses/LICENSE-2.0.html

// @host      localhost:8080
// @BasePath  /api/v1

// @schemes   http https

func main() {
	// Command line flags
	port := flag.String("port", "8080", "Port to run the server on")
	flag.Parse()

	// Get environment variables for Kubernetes configuration
	namespace := os.Getenv("NAMESPACE")
	if namespace == "" {
		namespace = "maas-api"
	}

	configMapName := os.Getenv("CONFIGMAP_NAME")
	if configMapName == "" {
		configMapName = "tier-to-group-mapping"
	}

	// Initialize Kubernetes client
	k8sClient, err := storage.NewKubernetesClient()
	if err != nil {
		log.Fatalf("Failed to create Kubernetes client: %v", err)
		os.Exit(1)
	}

	// Create Kubernetes storage
	tierStorage := storage.NewK8sTierStorage(k8sClient, namespace, configMapName)
	log.Printf("Using Kubernetes ConfigMap storage")
	log.Printf("Namespace: %s", namespace)
	log.Printf("ConfigMap: %s", configMapName)

	// Initialize service
	tierService := service.NewTierService(tierStorage)

	// Setup router
	router := api.SetupRouter(tierService)

	// Start server
	addr := fmt.Sprintf(":%s", *port)
	log.Printf("Starting server on %s", addr)

	if err := router.Run(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
		os.Exit(1)
	}
}
