package services

import (
	"openclaw-autobackup/config"
	"log"

	"github.com/robfig/cron/v3"
)

func StartScheduler(cfg *config.Config) {
	c := cron.New()

	cronExpr := cfg.BackupCron
	if cronExpr == "" {
		cronExpr = "0 * * * *"
	}

	_, err := c.AddFunc(cronExpr, func() {
		log.Println("Scheduled backup triggered")
		if err := ExecuteBackup(cfg); err != nil {
			log.Printf("Scheduled backup failed: %v", err)
		}
	})

	if err != nil {
		log.Fatalf("Failed to schedule backup: %v", err)
	}

	c.Start()
	log.Printf("Backup scheduler started (cron: %s)", cronExpr)
}
