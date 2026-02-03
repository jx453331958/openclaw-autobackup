package main

import (
	"openclaw-autobackup/config"
	"openclaw-autobackup/handlers"
	"openclaw-autobackup/models"
	"openclaw-autobackup/services"
	"embed"
	"html/template"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

//go:embed templates/*
var templatesFS embed.FS

func main() {
	cfg := config.Load()

	models.InitDB(cfg.DatabaseURL)

	handlers.SetConfig(cfg)

	services.StartScheduler(cfg)

	r := gin.Default()

	tmpl := template.Must(template.ParseFS(templatesFS, "templates/*.html"))
	r.SetHTMLTemplate(tmpl)

	// Routes
	r.GET("/", handlers.IndexPage)
	r.GET("/api/status", handlers.GetStatus)
	r.GET("/api/backups", handlers.GetBackups)
	r.POST("/api/backups/trigger", handlers.TriggerBackup)

	log.Printf("Backup Monitor starting on port %s", cfg.Port)
	if err := r.Run(":" + cfg.Port); err != nil && err != http.ErrServerClosed {
		log.Fatalf("Failed to start server: %v", err)
	}
}
