package models

import (
	"time"
)

type Backup struct {
	ID             uint      `json:"id" gorm:"primaryKey"`
	StartedAt      time.Time `json:"started_at" gorm:"not null"`
	FinishedAt     *time.Time `json:"finished_at"`
	Status         string    `json:"status" gorm:"not null"` // 'success', 'failed', 'running'
	FilesChanged   int       `json:"files_changed" gorm:"default:0"`
	CommitHash     string    `json:"commit_hash"`
	CommitMessage  string    `json:"commit_message"`
	ErrorMessage   string    `json:"error_message"`
	DurationMs     int64     `json:"duration_ms"`
}
