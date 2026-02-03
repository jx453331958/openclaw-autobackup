package handlers

import (
	"openclaw-autobackup/config"
	"openclaw-autobackup/models"
	"openclaw-autobackup/services"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

var cfg *config.Config

func SetConfig(config *config.Config) {
	cfg = config
}

func GetStatus(c *gin.Context) {
	var lastBackup models.Backup
	result := models.DB.Order("started_at DESC").First(&lastBackup)

	status := map[string]interface{}{
		"is_running": services.IsBackupRunning(),
	}

	if result.Error == nil {
		status["last_backup"] = lastBackup
	} else {
		status["last_backup"] = nil
	}

	// Get all workspace mod times dynamically
	workspaces, err := services.GetWorkspaces(cfg)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	workspaceStatus := make(map[string]interface{})
	for name, path := range workspaces {
		modTime, _ := services.GetWorkspaceModTime(path)
		workspaceStatus[name] = map[string]interface{}{
			"path":     path,
			"mod_time": modTime,
		}
	}
	status["workspaces"] = workspaceStatus

	c.JSON(http.StatusOK, status)
}

func GetBackups(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))

	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	var total int64
	models.DB.Model(&models.Backup{}).Count(&total)

	var backups []models.Backup
	offset := (page - 1) * pageSize
	models.DB.Order("started_at DESC").Limit(pageSize).Offset(offset).Find(&backups)

	c.JSON(http.StatusOK, gin.H{
		"backups":   backups,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func TriggerBackup(c *gin.Context) {
	if services.IsBackupRunning() {
		c.JSON(http.StatusConflict, gin.H{"error": "Backup is already running"})
		return
	}

	// Run backup in background
	go services.ExecuteBackup(cfg)

	c.JSON(http.StatusOK, gin.H{"message": "Backup started"})
}

func IndexPage(c *gin.Context) {
	c.HTML(http.StatusOK, "index.html", nil)
}
