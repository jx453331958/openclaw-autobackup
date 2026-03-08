package services

import (
	"openclaw-autobackup/config"
	"openclaw-autobackup/models"
	"fmt"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

var (
	isRunning bool
	mu        sync.Mutex
)

func IsBackupRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return isRunning
}

func ExecuteBackup(cfg *config.Config) error {
	mu.Lock()
	if isRunning {
		mu.Unlock()
		return fmt.Errorf("backup is already running")
	}
	isRunning = true
	mu.Unlock()

	defer func() {
		mu.Lock()
		isRunning = false
		mu.Unlock()
	}()

	now := time.Now()
	backup := &models.Backup{
		StartedAt: now,
		Status:    "running",
	}
	models.DB.Create(backup)

	startTime := time.Now()
	err := runBackup(cfg, backup)
	duration := time.Since(startTime)

	finished := time.Now()
	backup.FinishedAt = &finished
	backup.DurationMs = duration.Milliseconds()

	if err != nil {
		backup.Status = "failed"
		backup.ErrorMessage = err.Error()
		log.Printf("Backup failed: %v", err)
	} else {
		backup.Status = "success"
		log.Println("Backup completed successfully")
	}

	models.DB.Save(backup)

	// Send Telegram notification
	SendBackupNotification(cfg, backup)

	return err
}

func runBackup(cfg *config.Config, backup *models.Backup) error {
	repoPath := cfg.BackupRepo

	// Parse workspaces from config
	workspaces, err := parseWorkspaces(cfg.Workspaces)
	if err != nil {
		return fmt.Errorf("parse workspaces failed: %w", err)
	}

	// Sync each workspace (skip if none configured — useful when BACKUP_REPO is the workspace itself)
	for name, path := range workspaces {
		dstPath := filepath.Join(repoPath, name+"-backup")
		if err := syncWorkspace(path, dstPath); err != nil {
			return fmt.Errorf("sync workspace %s failed: %w", name, err)
		}
		log.Printf("Synced workspace: %s (%s → %s)", name, path, dstPath)
	}

	// Git add + commit + push
	filesChanged, commitHash, commitMsg, err := commitAndPush(cfg, repoPath)
	if err != nil {
		return err
	}

	backup.FilesChanged = filesChanged
	backup.CommitHash = commitHash
	backup.CommitMessage = commitMsg
	return nil
}

// parseWorkspaces parses WORKSPACES config string into map
// Format: 'name1:/path1,name2:/path2'
func parseWorkspaces(workspacesStr string) (map[string]string, error) {
	workspaces := make(map[string]string)
	if workspacesStr == "" {
		return workspaces, nil
	}

	pairs := strings.Split(workspacesStr, ",")
	for _, pair := range pairs {
		parts := strings.SplitN(strings.TrimSpace(pair), ":", 2)
		if len(parts) != 2 {
			return nil, fmt.Errorf("invalid workspace format: %s (expected 'name:/path')", pair)
		}
		name := strings.TrimSpace(parts[0])
		path := strings.TrimSpace(parts[1])
		if name == "" || path == "" {
			return nil, fmt.Errorf("workspace name and path cannot be empty: %s", pair)
		}
		workspaces[name] = path
	}
	return workspaces, nil
}

// syncWorkspace syncs all files from source to destination, excluding .git
func syncWorkspace(srcPath, dstPath string) error {
	return runCmd("", "rsync", "-av", "--delete",
		"--exclude=.git/",
		srcPath+"/", dstPath+"/")
}

func runCmd(dir string, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s failed: %w, output: %s", name, err, string(output))
	}
	return nil
}

func commitAndPush(cfg *config.Config, repoPath string) (int, string, string, error) {
	sshKeyPath := cfg.SSHKeyPath
	if sshKeyPath == "" {
		return 0, "", "", fmt.Errorf("SSH_KEY_PATH not configured")
	}

	// Sync remote URL with GIT_REMOTE config
	if cfg.GitRemote != "" {
		if err := runCmd(repoPath, "git", "remote", "set-url", "origin", cfg.GitRemote); err != nil {
			return 0, "", "", fmt.Errorf("git remote set-url failed: %w", err)
		}
	}

	// Always build explicit SSH command with key and port from config.
	// Never rely on ~/.ssh/config — containers don't have it.
	gitSSHEnv := fmt.Sprintf(`GIT_SSH_COMMAND=ssh -i %s -o StrictHostKeyChecking=no -p %s`, sshKeyPath, cfg.SSHPort)

	// Pull --rebase FIRST, before checking for changes.
	// This also pushes any previously committed but unpushed changes
	// (e.g., from a prior run where commit succeeded but push failed).
	pullCmd := exec.Command("git", "pull", "--rebase", "origin", "HEAD")
	pullCmd.Dir = repoPath
	pullCmd.Env = append(os.Environ(), gitSSHEnv)
	if pullOut, err := pullCmd.CombinedOutput(); err != nil {
		return 0, "", "", fmt.Errorf("git pull --rebase failed: %w, output: %s", err, string(pullOut))
	}

	// Check for changes
	cmd := exec.Command("git", "status", "--porcelain")
	cmd.Dir = repoPath
	output, err := cmd.CombinedOutput()
	if err != nil {
		return 0, "", "", fmt.Errorf("git status failed: %w", err)
	}

	changes := strings.TrimSpace(string(output))

	// Check if we have unpushed commits from previous failed runs
	hasUnpushed := hasUnpushedCommits(repoPath)

	if changes == "" && !hasUnpushed {
		return 0, "", "No changes", nil
	}

	filesChanged := 0
	var commitHash, commitMsg string

	if changes != "" {
		filesChanged = len(strings.Split(changes, "\n"))

		if err := runCmd(repoPath, "git", "add", "-A"); err != nil {
			return 0, "", "", err
		}

		commitMsg = fmt.Sprintf("Auto backup at %s", time.Now().Format("2006-01-02 15:04:05"))
		if err := runCmd(repoPath, "git", "commit", "-m", commitMsg); err != nil {
			return 0, "", "", err
		}

		cmd = exec.Command("git", "rev-parse", "HEAD")
		cmd.Dir = repoPath
		output, err = cmd.CombinedOutput()
		if err != nil {
			return 0, "", "", fmt.Errorf("git rev-parse failed: %w", err)
		}
		commitHash = strings.TrimSpace(string(output))
	}

	// Push all commits (new + any previously stuck unpushed ones)
	pushCmd := exec.Command("git", "push", "origin", "HEAD")
	pushCmd.Dir = repoPath
	pushCmd.Env = append(os.Environ(), gitSSHEnv)
	if pushOut, err := pushCmd.CombinedOutput(); err != nil {
		return 0, "", "", fmt.Errorf("git push failed: %w, output: %s", err, string(pushOut))
	}

	if changes == "" {
		return 0, "", "Pushed previously stuck commits", nil
	}

	return filesChanged, commitHash, commitMsg, nil
}

// hasUnpushedCommits checks if local branch is ahead of remote
func hasUnpushedCommits(repoPath string) bool {
	cmd := exec.Command("git", "rev-list", "--count", "HEAD...@{upstream}")
	cmd.Dir = repoPath
	output, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}
	count := strings.TrimSpace(string(output))
	return count != "0"
}

// GetWorkspaces returns parsed workspaces from config
func GetWorkspaces(cfg *config.Config) (map[string]string, error) {
	return parseWorkspaces(cfg.Workspaces)
}

func GetWorkspaceModTime(path string) (time.Time, error) {
	info, err := os.Stat(path)
	if err != nil {
		return time.Time{}, err
	}
	return info.ModTime(), nil
}
