package app

import (
	"encoding/json"
	"fmt"
	"log"
	"os"

	"forgeplay/dsl"
	"forgeplay/server/internal/ai"
	"forgeplay/server/internal/games"
	"forgeplay/server/internal/mods"
	"forgeplay/server/internal/quota"
	"forgeplay/server/internal/runtimes"
	"forgeplay/server/pkg/provenance"
)

type creationModule struct{}

type CreationModuleResult struct {
	ModGateway    games.ModGateway
	DraftGateway  games.DraftGateway
	IsAIGenerated func(string) bool
	Runtime       func(string) (string, bool)
	Owner         func(string) (string, bool)
	Validate      func(string) bool
}

func (creationModule) Name() string           { return "creation" }
func (creationModule) Dependencies() []string { return []string{"identity"} }

func (creationModule) Install(ctx *moduleContext) error {
	recorder, err := ai.NewGormRecorder(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize AI audit: %w", err)
	}
	aiService := ai.NewService(ctx.provider, dsl.NewSchemaValidator(ctx.cfg.Content.SchemaDir), recorder, 2)
	signer := provenance.NewSigner(ctx.cfg.Security.Secret)
	if !signer.Enabled() {
		log.Print("provenance: 未设 FORGEPLAY_SECRET,AI 溯源令牌禁用(AI 标识回退为客户端自报)")
	}
	aiService.SetProvenanceSigner(signer)

	baselines := mods.NewMapBaselines()
	for _, source := range []struct{ label, runtimeRef, path string }{
		{label: "shooter", runtimeRef: "shooter@1.0.0", path: ctx.cfg.Content.ShooterBaseline},
		{label: "survivor", runtimeRef: "survivor@1.0.0", path: ctx.cfg.Content.SurvivorBaseline},
		{label: "tower defense", runtimeRef: "tower_defense@1.0.0", path: ctx.cfg.Content.TowerDefenseBaseline},
	} {
		baseline, loadErr := loadDSL(source.path)
		if loadErr != nil {
			return fmt.Errorf("%s baseline: %w", source.label, loadErr)
		}
		baselines.Register(source.runtimeRef, baseline)
	}
	repository, err := mods.NewGormRepo(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize mods repository: %w", err)
	}
	modsService := mods.NewService(repository, baselines)
	modsService.SetProvenanceVerifier(signer)

	quotaStore, err := quota.NewGormStateStore(ctx.db)
	if err != nil {
		return fmt.Errorf("initialize quota store: %w", err)
	}
	quotaService, err := quota.NewServiceWithStore(20, quotaStore)
	if err != nil {
		return fmt.Errorf("initialize quota state: %w", err)
	}
	ai.RegisterRoutes(ctx.engine, aiService, ctx.identity.Optional, quota.Middleware(quotaService, quota.UserOrIP))
	ai.RegisterQuotaRoute(ctx.engine, quotaService, ctx.identity.Optional)
	mods.RegisterRoutes(ctx.engine, modsService, ctx.identity.Required, ctx.identity.Optional)
	runtimes.RegisterRoutes(ctx.engine, ctx.cfg.Content.SchemaDir, ctx.cfg.Content.RuntimeDir)
	ctx.creation = &CreationModuleResult{
		ModGateway:    modsService,
		DraftGateway:  modsService,
		IsAIGenerated: modsService.IsAIGenerated,
		Runtime: func(id string) (string, bool) {
			mod, getErr := modsService.Get(id)
			return mod.Runtime, getErr == nil
		},
		Owner: func(id string) (string, bool) {
			mod, getErr := modsService.Get(id)
			return mod.AuthorID, getErr == nil
		},
		Validate: func(id string) bool {
			mod, getErr := modsService.Get(id)
			if getErr != nil {
				return false
			}
			effective, effectiveErr := modsService.EffectiveDSL(id)
			return effectiveErr == nil && aiService.Validate(mod.Runtime, effective) == nil
		},
	}
	return nil
}

func loadDSL(path string) (map[string]any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		return nil, fmt.Errorf("decode %s: %w", path, err)
	}
	return document, nil
}
