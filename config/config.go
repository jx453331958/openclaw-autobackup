package config

import (
	"os"
)

type Config struct {
	Port             string
	DatabaseURL      string
	Workspaces       string // Format: 'name1:/path1,name2:/path2'
	BackupRepo       string
	GitRemote        string
	SSHKeyPath       string
	TelegramBotToken string
	TelegramChatID   string
}

func Load() *Config {
	return &Config{
		Port:             getEnv("PORT", "3458"),
		DatabaseURL:      getEnv("DATABASE_URL", "./data/backup.db"),
		Workspaces:       getEnv("WORKSPACES", ""),
		BackupRepo:       getEnv("BACKUP_REPO", ""),
		GitRemote:        getEnv("GIT_REMOTE", ""),
		SSHKeyPath:       getEnv("SSH_KEY_PATH", ""),
		TelegramBotToken: getEnv("TELEGRAM_BOT_TOKEN", ""),
		TelegramChatID:   getEnv("TELEGRAM_CHAT_ID", ""),
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
