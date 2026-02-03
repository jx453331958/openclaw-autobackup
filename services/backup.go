package services

import (
	"openclaw-autobackup/config"
	"openclaw-autobackup/models"
	"fmt"
	"log"
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

	if len(workspaces) == 0 {
		return fmt.Errorf("no workspaces configured")
	}

	// Sync each workspace
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

// syncWorkspace syncs agent core files from source to destination
func syncWorkspace(srcPath, dstPath string) error {
	return runCmd("", "rsync", "-av", "--delete",
		"--include=*.md",
		"--include=memory/", "--include=memory/**",
		"--include=skills/", "--include=skills/**",
		"--include=.clawhub/", "--include=.clawhub/**",
		"--include=canvas/", "--include=canvas/**",
		"--exclude=*",
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
	// Check for changes
	cmd := exec.Command("git", "status", "--porcelain")
	cmd.Dir = repoPath
	output, err := cmd.CombinedOutput()
	if err != nil {
		return 0, "", "", fmt.Errorf("git status failed: %w", err)
	}

	changes := strings.TrimSpace(string(output))
	if changes == "" {
		return 0, "", "No changes", nil
	}

	filesChanged := len(strings.Split(changes, "\n"))

	if err := runCmd(repoPath, "git", "add", "-A"); err != nil {
		return 0, "", "", err
	}

	commitMsg := fmt.Sprintf("Auto backup at %s", time.Now().Format("2006-01-02 15:04:05"))
	if err := runCmd(repoPath, "git", "commit", "-m", commitMsg); err != nil {
		return 0, "", "", err
	}

	cmd = exec.Command("git", "rev-parse", "HEAD")
	cmd.Dir = repoPath
	output, err = cmd.CombinedOutput()
	if err != nil {
		return 0, "", "", fmt.Errorf("git rev-parse failed: %w", err)
	}
	commitHash := strings.TrimSpace(string(output))

	// Push via shell with explicit SSH command using configured SSH key
	sshKeyPath := cfg.SSHKeyPath
	if sshKeyPath == "" {
		return 0, "", "", fmt.Errorf("SSH_KEY_PATH not configured")
	}

	gitSSHCmd := fmt.Sprintf(`GIT_SSH_COMMAND="ssh -i %s -o StrictHostKeyChecking=no -p 443" git push`, sshKeyPath)
	cmd = exec.Command("sh", "-c", gitSSHCmd)
	cmd.Dir = repoPath
	if pushOut, err := cmd.CombinedOutput(); err != nil {
		return 0, "", "", fmt.Errorf("git push failed: %w, output: %s", err, string(pushOut))
	}

	return filesChanged, commitHash, commitMsg, nil
}

// GetWorkspaces returns parsed workspaces from config
func GetWorkspaces(cfg *config.Config) (map[string]string, error) {
	return parseWorkspaces(cfg.Workspaces)
}

func GetWorkspaceModTime(path string) (time.Time, error) {
	// Get the most recent file modification time via find
	cmd := exec.Command("find", path, "-maxdepth", "2", "-name", "*.md", "-newer", path, "-print", "-quit")
	output, err := cmd.CombinedOutput()
	if err != nil || strings.TrimSpace(string(output)) == "" {
		// Fallback to directory mtime
		cmd = exec.Command("stat", "-f", "%m", path)
		output, err = cmd.CombinedOutput()
		if err != nil {
			return time.Time{}, err
		}
	}
	// Just return current stat
	cmd = exec.Command("stat", "-f", "%Sm", "-t", "%Y-%m-%dT%H:%M:%S", path)
	output, err = cmd.CombinedOutput()
	if err != nil {
		return time.Time{}, err
	}
	t, err := time.Parse("2006-01-02T15:04:05", strings.TrimSpace(string(output)))
	return t, err
}
