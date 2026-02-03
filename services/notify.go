package services

import (
	"openclaw-autobackup/config"
	"openclaw-autobackup/models"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"
)

func SendBackupNotification(cfg *config.Config, backup *models.Backup) {
	if cfg.TelegramBotToken == "" || cfg.TelegramChatID == "" {
		log.Println("Telegram notification skipped: no bot token or chat ID configured")
		return
	}

	var emoji, status string
	if backup.Status == "success" {
		emoji = "✅"
		status = "成功"
	} else {
		emoji = "❌"
		status = "失败"
	}

	var duration string
	if backup.DurationMs > 0 {
		duration = fmt.Sprintf("%.1f秒", float64(backup.DurationMs)/1000)
	} else {
		duration = "未知"
	}

	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("%s <b>定时备份%s</b>\n\n", emoji, status))
	sb.WriteString(fmt.Sprintf("⏱ 耗时: %s\n", duration))
	sb.WriteString(fmt.Sprintf("📁 变更文件: %d\n", backup.FilesChanged))

	if backup.CommitHash != "" && backup.CommitHash != "" {
		short := backup.CommitHash
		if len(short) > 7 {
			short = short[:7]
		}
		sb.WriteString(fmt.Sprintf("🔗 Commit: <code>%s</code>\n", short))
	}

	if backup.Status == "failed" && backup.ErrorMessage != "" {
		sb.WriteString(fmt.Sprintf("\n⚠️ 错误: %s", backup.ErrorMessage))
	}

	sb.WriteString(fmt.Sprintf("\n🕐 %s", time.Now().Format("2006-01-02 15:04:05")))

	sendTelegram(cfg.TelegramBotToken, cfg.TelegramChatID, sb.String())
}

func sendTelegram(token, chatID, text string) {
	apiURL := fmt.Sprintf("https://api.telegram.org/bot%s/sendMessage", token)

	resp, err := http.PostForm(apiURL, url.Values{
		"chat_id":    {chatID},
		"text":       {text},
		"parse_mode": {"HTML"},
	})
	if err != nil {
		log.Printf("Telegram notification failed: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		log.Printf("Telegram notification returned status %d", resp.StatusCode)
	} else {
		log.Println("Telegram notification sent successfully")
	}
}
