package app

import (
	"fmt"

	"github.com/yldm-tech/classic-games/apps/server/internal/ai"
	"github.com/yldm-tech/classic-games/apps/server/internal/analytics"
	"github.com/yldm-tech/classic-games/apps/server/internal/auth"
	"github.com/yldm-tech/classic-games/apps/server/internal/commerce"
	"github.com/yldm-tech/classic-games/apps/server/internal/community"
	"github.com/yldm-tech/classic-games/apps/server/internal/feedback"
	"github.com/yldm-tech/classic-games/apps/server/internal/games"
	"github.com/yldm-tech/classic-games/apps/server/internal/inbox"
	"github.com/yldm-tech/classic-games/apps/server/internal/library"
	"github.com/yldm-tech/classic-games/apps/server/internal/moderation"
	"github.com/yldm-tech/classic-games/apps/server/internal/mods"
	"github.com/yldm-tech/classic-games/apps/server/internal/participation"
	"github.com/yldm-tech/classic-games/apps/server/internal/payments"
	"github.com/yldm-tech/classic-games/apps/server/internal/prefs"
	"github.com/yldm-tech/classic-games/apps/server/internal/quota"
	"github.com/yldm-tech/classic-games/apps/server/internal/replays"
	"github.com/yldm-tech/classic-games/apps/server/internal/rooms"
	"github.com/yldm-tech/classic-games/apps/server/internal/social"
	"github.com/yldm-tech/classic-games/apps/server/internal/users"

	"gorm.io/gorm"
)

type Migration struct {
	ID     string
	Models []any
	After  func(*gorm.DB) error
}

func DefaultMigrations() []Migration {
	return []Migration{
		{ID: "001_ai", Models: ai.MigrationModels()},
		{ID: "002_analytics", Models: analytics.MigrationModels()},
		{ID: "003_auth_identity", Models: auth.IdentityMigrationModels(), After: auth.AfterIdentityMigration},
		{ID: "004_auth_runtime", Models: auth.RuntimeMigrationModels()},
		{ID: "005_commerce", Models: commerce.MigrationModels()},
		{ID: "006_community", Models: community.MigrationModels()},
		{ID: "007_feedback", Models: feedback.MigrationModels()},
		{ID: "008_games", Models: games.MigrationModels()},
		{ID: "009_inbox", Models: inbox.MigrationModels()},
		{ID: "010_library", Models: library.MigrationModels()},
		{ID: "011_moderation", Models: moderation.MigrationModels()},
		{ID: "012_mods", Models: mods.MigrationModels()},
		{ID: "013_participation", Models: participation.MigrationModels(), After: participation.AfterMigration},
		{ID: "014_payments", Models: payments.MigrationModels()},
		{ID: "015_prefs", Models: prefs.MigrationModels()},
		{ID: "016_quota", Models: quota.MigrationModels()},
		{ID: "017_replays", Models: replays.MigrationModels()},
		{ID: "018_rooms", Models: rooms.MigrationModels(), After: rooms.AfterMigration},
		{ID: "019_social", Models: social.MigrationModels()},
		{ID: "020_users", Models: users.MigrationModels()},
	}
}

func Migrate(db *gorm.DB, migrations []Migration) error {
	if db == nil {
		return fmt.Errorf("migrate: database is required")
	}
	if err := validateMigrations(migrations); err != nil {
		return err
	}
	for _, migration := range migrations {
		if err := db.AutoMigrate(migration.Models...); err != nil {
			return fmt.Errorf("migrate %s models: %w", migration.ID, err)
		}
		if migration.After != nil {
			if err := migration.After(db); err != nil {
				return fmt.Errorf("migrate %s after hook: %w", migration.ID, err)
			}
		}
	}
	return nil
}

func validateMigrations(migrations []Migration) error {
	previous := ""
	seen := make(map[string]struct{}, len(migrations))
	for index, migration := range migrations {
		if migration.ID == "" {
			return fmt.Errorf("migrate: migration %d has empty ID", index)
		}
		if _, exists := seen[migration.ID]; exists {
			return fmt.Errorf("migrate: duplicate migration ID %q", migration.ID)
		}
		if migration.ID <= previous {
			return fmt.Errorf("migrate: migration ID %q is not ordered after %q", migration.ID, previous)
		}
		if len(migration.Models) == 0 {
			return fmt.Errorf("migrate: migration %q has no models", migration.ID)
		}
		seen[migration.ID] = struct{}{}
		previous = migration.ID
	}
	return nil
}
