package ai

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"hash/fnv"
	"math"
	"reflect"
	"sort"
	"strings"

	"github.com/yldm-tech/classic-games/packages/dsl"
)

var (
	ErrInvalidDifficulty = errors.New("ai: difficulty must be between 1 and 5")
	ErrInvalidStructure  = errors.New("ai: structure requires prompt, current_dsl, count 1..8 and difficulty 1..5")
)

type BalanceRequest struct {
	Runtime          string         `json:"runtime"`
	CurrentDSL       map[string]any `json:"current_dsl"`
	TargetDifficulty int            `json:"target_difficulty"`
}

type BalanceMetrics struct {
	Before float64 `json:"before"`
	After  float64 `json:"after"`
}

type BalanceResponse struct {
	DSLPatch   []dsl.Op       `json:"dsl_patch"`
	NewDSL     map[string]any `json:"new_dsl"`
	Metrics    BalanceMetrics `json:"metrics"`
	Model      string         `json:"model"`
	Hint       string         `json:"balance_hint"`
	Provenance string         `json:"provenance,omitempty"`
}

type StructureRequest struct {
	Runtime    string         `json:"runtime"`
	CurrentDSL map[string]any `json:"current_dsl"`
	Prompt     string         `json:"prompt"`
	Count      int            `json:"count"`
	Difficulty int            `json:"difficulty"`
}

type StructureResponse struct {
	DSLPatch      []dsl.Op       `json:"dsl_patch"`
	NewDSL        map[string]any `json:"new_dsl"`
	GeneratedKeys []string       `json:"generated_keys"`
	Model         string         `json:"model"`
	BalanceHint   string         `json:"balance_hint"`
	Provenance    string         `json:"provenance,omitempty"`
}

func raw(value any) json.RawMessage {
	b, _ := json.Marshal(value)
	return b
}

func replace(path string, value any) dsl.Op {
	return dsl.Op{Op: "replace", Path: path, Value: raw(value)}
}
func add(path string, value any) dsl.Op { return dsl.Op{Op: "add", Path: path, Value: raw(value)} }

func object(value any) map[string]any {
	result, _ := value.(map[string]any)
	return result
}

func number(value any) float64 {
	switch v := value.(type) {
	case float64:
		return v
	case int:
		return float64(v)
	default:
		return 0
	}
}

func sortedKeys(value map[string]any) []string {
	keys := make([]string, 0, len(value))
	for key := range value {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func (s *Service) AutoBalance(req BalanceRequest) (BalanceResponse, error) {
	if req.CurrentDSL == nil {
		return BalanceResponse{}, ErrNoCurrentDSL
	}
	if req.TargetDifficulty < 1 || req.TargetDifficulty > 5 {
		return BalanceResponse{}, ErrInvalidDifficulty
	}
	name, d := runtimeName(req.Runtime), req.TargetDifficulty
	ops := make([]dsl.Op, 0, 32)
	switch name {
	case "shooter":
		enemies := object(req.CurrentDSL["enemies"])
		ops = append(ops,
			replace("/stage/difficulty", d),
			replace("/player/hp", 160-17*d),
			add("/player/weapon/damage", 48-5*d),
		)
		for _, key := range sortedKeys(enemies) {
			ops = append(ops,
				replace("/enemies/"+key+"/count", 8+5*d),
				replace("/enemies/"+key+"/hp", 8+9*d),
				add("/enemies/"+key+"/speed", 5+4*d),
			)
		}
	case "survivor":
		ops = append(ops,
			replace("/hero/hp", 180-20*d),
			replace("/weapon/damage", 50-6*d),
			replace("/weapon/cooldown", 0.35+0.12*float64(d)),
		)
		for _, key := range sortedKeys(object(req.CurrentDSL["waves"])) {
			ops = append(ops,
				replace("/waves/"+key+"/count", 8+8*d),
				replace("/waves/"+key+"/hp", 10+12*d),
				replace("/waves/"+key+"/speed", 50+15*d),
				replace("/waves/"+key+"/interval", math.Max(0.25, 1.3-0.15*float64(d))),
			)
		}
	case "tower_defense":
		ops = append(ops,
			replace("/stage/starting_gold", 350-50*d),
			replace("/stage/base_hp", 35-4*d),
		)
		for _, key := range sortedKeys(object(req.CurrentDSL["waves"])) {
			ops = append(ops,
				replace("/waves/"+key+"/count", 6+7*d),
				replace("/waves/"+key+"/hp", 15+18*d),
				replace("/waves/"+key+"/speed", 45+13*d),
				replace("/waves/"+key+"/interval", math.Max(0.25, 1.4-0.17*float64(d))),
			)
		}
	default:
		return BalanceResponse{}, fmt.Errorf("ai: unsupported runtime %s", name)
	}
	newDSL, err := dsl.Apply(req.CurrentDSL, ops)
	if err != nil {
		return BalanceResponse{}, err
	}
	if err = s.validator.Validate(req.Runtime, newDSL); err != nil {
		return BalanceResponse{}, fmt.Errorf("%w: %v", ErrDSLInvalid, err)
	}
	// 不签发 AI 溯源令牌:AutoBalance 是确定性算术、不调用 LLM,且 /ai/balance 无鉴权无配额。
	// 若在此签发,任何人可匿名、免费、不限量地拿到"AI 生成"令牌去给纯手工内容打 AI 标记。
	return BalanceResponse{
		DSLPatch: ops, NewDSL: newDSL,
		Metrics: BalanceMetrics{Before: difficultyPressure(name, req.CurrentDSL), After: difficultyPressure(name, newDSL)},
		Model:   "classic-games-balance-v1", Hint: fmt.Sprintf("已自动调至难度 %d/5，并通过 Runtime Schema 校验", d),
	}, nil
}

func difficultyPressure(runtime string, data map[string]any) float64 {
	switch runtime {
	case "shooter":
		player := object(data["player"])
		weapon := object(player["weapon"])
		pressure := 0.0
		for _, value := range object(data["enemies"]) {
			e := object(value)
			pressure += number(e["count"]) * number(e["hp"]) * math.Max(1, number(e["speed"]))
		}
		return pressure * math.Max(1, number(object(data["stage"])["difficulty"])) / math.Max(1, number(player["hp"])*number(weapon["damage"]))
	case "survivor":
		hero, weapon := object(data["hero"]), object(data["weapon"])
		pressure := 0.0
		for _, value := range object(data["waves"]) {
			w := object(value)
			pressure += number(w["count"]) * number(w["hp"]) * number(w["speed"]) / math.Max(.05, number(w["interval"]))
		}
		return pressure * math.Max(.05, number(weapon["cooldown"])) / math.Max(1, number(hero["hp"])*number(weapon["damage"]))
	case "tower_defense":
		stage := object(data["stage"])
		pressure := 0.0
		for _, value := range object(data["waves"]) {
			w := object(value)
			pressure += number(w["count"]) * number(w["hp"]) * number(w["speed"]) / math.Max(.05, number(w["interval"]))
		}
		return pressure / math.Max(1, number(stage["starting_gold"])+number(stage["base_hp"])*10)
	}
	return 0
}

func (s *Service) GenerateStructure(ctx context.Context, req StructureRequest) (StructureResponse, error) {
	if req.CurrentDSL == nil || strings.TrimSpace(req.Prompt) == "" || req.Count < 1 || req.Count > 8 || req.Difficulty < 1 || req.Difficulty > 5 {
		return StructureResponse{}, ErrInvalidStructure
	}
	name := runtimeName(req.Runtime)
	containerName := "enemies"
	if name != "shooter" {
		containerName = "waves"
	}
	// Production provider gets the semantic intent and must prove a real structural delta.
	// The deterministic generator below is only the explicit offline Stub fallback.
	if s.provider != nil {
		hint, attemptedReal := "", false
		for attempt := 0; attempt <= s.maxRetries; attempt++ {
			prompt := fmt.Sprintf("[CLASSIC_GAMES_STRUCTURE]\n用户意图:%s\n在 /%s 中新增恰好 %d 个稳定 ID 节点，目标难度 %d/5；不要只改参数或外观。", strings.TrimSpace(req.Prompt), containerName, req.Count, req.Difficulty)
			suggestion, err := s.provider.GenerateModPatch(ctx, req.Runtime, req.CurrentDSL, prompt, hint)
			if err != nil {
				return StructureResponse{}, err
			}
			if suggestion.Model == "stub" {
				break
			}
			attemptedReal = true
			candidate, applyErr := dsl.Apply(req.CurrentDSL, suggestion.Ops)
			if applyErr != nil {
				hint = "结构补丁 apply 失败:" + applyErr.Error()
				s.record(ctx, req.Runtime, suggestion, attempt, false, "PATCH_APPLY_FAILED")
				continue
			}
			generated := addedStructureKeys(req.CurrentDSL, candidate, containerName)
			if len(generated) != req.Count || !structureOnlyAppends(req.CurrentDSL, candidate, containerName) {
				hint = fmt.Sprintf("必须只在 /%s 新增恰好 %d 个节点，不得修改或删除任何既有内容", containerName, req.Count)
				s.record(ctx, req.Runtime, suggestion, attempt, false, "STRUCTURE_INVALID")
				continue
			}
			if validErr := s.validator.Validate(req.Runtime, candidate); validErr != nil {
				hint = "结构结果未通过 Schema:" + validErr.Error()
				s.record(ctx, req.Runtime, suggestion, attempt, false, "DSL_INVALID")
				continue
			}
			s.record(ctx, req.Runtime, suggestion, attempt, true, "")
			return StructureResponse{DSLPatch: suggestion.Ops, NewDSL: candidate, GeneratedKeys: generated, Model: suggestion.Model, BalanceHint: suggestion.BalanceHint, Provenance: s.mintProvenance()}, nil
		}
		if attemptedReal {
			return StructureResponse{}, ErrDSLInvalid
		}
	}
	h := fnv.New32a()
	_, _ = h.Write([]byte(name + "\x00" + strings.TrimSpace(req.Prompt)))
	seed := h.Sum32()
	ops := make([]dsl.Op, 0, req.Count)
	keys := make([]string, 0, req.Count)
	existing := object(req.CurrentDSL[containerName])
	for ordinal := 1; len(keys) < req.Count; ordinal++ {
		key := fmt.Sprintf("ai_%08x_%02d", seed, ordinal)
		if _, collision := existing[key]; collision {
			continue
		}
		i := len(keys)
		keys = append(keys, key)
		d := req.Difficulty
		switch name {
		case "shooter":
			types := []string{"dog", "bird", "turret", "bomber", "swarm"}
			behaviors := []string{"chase", "sine", "static", "dive", "flock"}
			idx := int(seed+uint32(i)) % len(types)
			ops = append(ops, add("/enemies/"+key, map[string]any{"type": types[idx], "behavior": behaviors[idx], "count": 6 + d*4 + i*2, "hp": 8 + d*8 + i*3, "speed": 4 + d*3}))
		case "survivor":
			enemies := []string{"slime", "bat", "skeleton", "ghost", "golem"}
			idx := int(seed+uint32(i)) % len(enemies)
			ops = append(ops, add("/waves/"+key, map[string]any{"enemy": enemies[idx], "start": i * (12 + d*2), "interval": math.Max(.2, 1.2-.12*float64(d)), "count": 8 + d*5 + i*3, "hp": 10 + d*10 + i*4, "speed": 45 + d*12, "xp": 2 + d}))
		case "tower_defense":
			enemies := []string{"grunt", "runner", "tank", "flyer", "boss"}
			idx := int(seed+uint32(i)) % len(enemies)
			ops = append(ops, add("/waves/"+key, map[string]any{"enemy": enemies[idx], "count": 6 + d*4 + i*2, "hp": 15 + d*15 + i*5, "speed": 40 + d*12, "reward": 5 + d*2, "start": i * (15 + d*2), "interval": math.Max(.25, 1.3-.14*float64(d))}))
		default:
			return StructureResponse{}, ErrInvalidStructure
		}
	}
	newDSL, err := dsl.Apply(req.CurrentDSL, ops)
	if err != nil {
		return StructureResponse{}, err
	}
	if err = s.validator.Validate(req.Runtime, newDSL); err != nil {
		return StructureResponse{}, fmt.Errorf("%w: %v", ErrDSLInvalid, err)
	}
	s.record(ctx, req.Runtime, PatchSuggestion{Ops: ops, Model: "classic-games-structure-v1"}, 0, true, "")
	return StructureResponse{DSLPatch: ops, NewDSL: newDSL, GeneratedKeys: keys, Model: "classic-games-structure-v1", BalanceHint: "已生成结构并通过 Runtime Schema 校验，可继续自动平衡", Provenance: s.mintProvenance()}, nil
}

func addedStructureKeys(before, after map[string]any, container string) []string {
	oldValues, newValues := object(before[container]), object(after[container])
	keys := make([]string, 0)
	for key := range newValues {
		if _, existed := oldValues[key]; !existed {
			keys = append(keys, key)
		}
	}
	sort.Strings(keys)
	return keys
}

// structureOnlyAppends guarantees the structure tool cannot smuggle unrelated
// tuning changes into a valid-looking response. Existing nodes and every field
// outside the target container must remain byte-for-byte equivalent as values.
func structureOnlyAppends(before, after map[string]any, container string) bool {
	if len(before) != len(after) {
		return false
	}
	for key, oldValue := range before {
		newValue, exists := after[key]
		if !exists {
			return false
		}
		if key != container && !reflect.DeepEqual(oldValue, newValue) {
			return false
		}
	}
	oldValues, newValues := object(before[container]), object(after[container])
	if len(newValues) < len(oldValues) {
		return false
	}
	for key, oldValue := range oldValues {
		newValue, exists := newValues[key]
		if !exists || !reflect.DeepEqual(oldValue, newValue) {
			return false
		}
	}
	return true
}
