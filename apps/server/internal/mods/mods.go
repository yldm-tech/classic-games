// Package mods 实现 Fork 模型:Mod 是相对父级的 DSL 补丁,生效 DSL 由
// 基线沿父链逐层 apply 6902 补丁得到(见 docs/05-dsl-design.md、10-data-model.md)。
//
// 本包只做纯逻辑 + 仓库接口;持久化(GORM/PostgreSQL)是 Repository 的另一实现,
// 测试用内存实现。
package mods

import (
	"errors"
	"fmt"
	"time"

	"github.com/yldm-tech/classic-games/packages/dsl"
)

// maxChainDepth 防御异常深链 / 环。
const maxChainDepth = 256

// Mod 一条创作:相对父 mod 生效 DSL 的补丁。ParentID 为空表示直接基于 Runtime 基线。
// gorm tag 让同一结构既是领域对象又是持久化模型(Patch 存 JSON 列)。
type Mod struct {
	ID       string   `json:"id" gorm:"primaryKey"`
	ParentID string   `json:"parent_id,omitempty" gorm:"index"`
	Runtime  string   `json:"runtime"` // "shooter@1.0.0"
	Patch    []dsl.Op `json:"patch" gorm:"serializer:json"`
	// AIGenerated 标记该创作是否 AI 生成。仅在建 mod 时携带服务端签发的有效溯源令牌才会置 true,
	// 客户端无法凭空伪造;发布时据此强制标识,不可被改成非 AI(防漏标,docs/14)。
	AIGenerated bool      `json:"ai_generated"`
	AuthorID    string    `json:"author_id,omitempty" gorm:"index"`
	CreatedAt   time.Time `json:"created_at" gorm:"index"`
	Draft       bool      `json:"draft" gorm:"index"`
}

// Repository 是 mods 的存储抽象。
type Repository interface {
	Get(id string) (Mod, error)
	Create(m Mod) (Mod, error)                   // 分配 ID 并落库,返回带 ID 的 Mod
	ListChildren(parentID string) ([]Mod, error) // 直接子 mod(Fork Tree 用)
	ListByAuthor(authorID string) ([]Mod, error)
	SetDraft(id string, draft bool) error // 切换草稿标记(草稿发布后清除,发布失败时回滚)
}

// BaselineProvider 提供某 Runtime 版本的基线 DSL(对应 runtimes.baseline_dsl)。
type BaselineProvider interface {
	BaselineFor(runtime string) (map[string]any, error)
}

var ErrNotFound = errors.New("mods: not found")
var ErrForbidden = errors.New("mods: 无权修改该草稿")
var ErrNotDraft = errors.New("mods: 目标不是草稿")

// ProvenanceVerifier 校验「AI 生成」溯源令牌(由 pkg/provenance 实现)。
type ProvenanceVerifier interface {
	Verify(token string, now time.Time) bool
}

// Service 编排生效 DSL 计算与 Fork。
type Service struct {
	repo      Repository
	baselines BaselineProvider
	verifier  ProvenanceVerifier // 可空;非空则校验 AI 溯源令牌
}

func NewService(repo Repository, baselines BaselineProvider) *Service {
	return &Service{repo: repo, baselines: baselines}
}

// SetProvenanceVerifier 注入 AI 溯源令牌校验器。
func (s *Service) SetProvenanceVerifier(v ProvenanceVerifier) { s.verifier = v }

// VerifyProvenance 校验客户端回带的 AI 溯源令牌是否有效(签名对 + 未过期)。
func (s *Service) VerifyProvenance(token string) bool {
	return s.verifier != nil && s.verifier.Verify(token, time.Now())
}

// IsAIGenerated 返回某 mod 是否为 AI 生成(供发布层据此强制标识)。
func (s *Service) IsAIGenerated(modID string) bool {
	m, err := s.repo.Get(modID)
	return err == nil && m.AIGenerated
}

// CreateRoot 直接基于 Runtime 基线创建一条 mod(patch 相对基线)。aiGenerated 由调用方校验溯源令牌后传入。
func (s *Service) CreateRoot(runtime string, patch []dsl.Op, aiGenerated bool) (Mod, error) {
	return s.CreateRootFor("", runtime, patch, aiGenerated)
}
func (s *Service) CreateRootFor(author, runtime string, patch []dsl.Op, aiGenerated bool, draft ...bool) (Mod, error) {
	isDraft := len(draft) > 0 && draft[0]
	return s.repo.Create(Mod{Runtime: runtime, Patch: patch, AIGenerated: aiGenerated, AuthorID: author, CreatedAt: time.Now().UTC(), Draft: isDraft})
}

// CreateChild 在某父 mod 之上创建子 mod(patch 相对父 mod 的生效 DSL)。
func (s *Service) CreateChild(parentID string, patch []dsl.Op, aiGenerated bool) (Mod, error) {
	return s.CreateChildFor("", parentID, patch, aiGenerated)
}
func (s *Service) CreateChildFor(authorID, parentID string, patch []dsl.Op, aiGenerated bool, draft ...bool) (Mod, error) {
	parent, err := s.repo.Get(parentID)
	if err != nil {
		return Mod{}, err
	}
	if parent.Draft && parent.AuthorID != authorID {
		return Mod{}, ErrForbidden
	}
	isDraft := len(draft) > 0 && draft[0]
	return s.repo.Create(Mod{ParentID: parentID, Runtime: parent.Runtime, Patch: patch, AIGenerated: parent.AIGenerated || aiGenerated, AuthorID: authorID, CreatedAt: time.Now().UTC(), Draft: isDraft})
}

// Fork 以某 mod 为起点创建一个新草稿:父 = 该 mod,patch 为空,
// 故其生效 DSL 初始等于被 Fork 的 mod(docs/05-dsl-design.md 的 Fork 补丁链)。
// AI 标识从父 mod 继承(基于 AI 创作 Fork 出的草稿仍属 AI 衍生)。
func (s *Service) Fork(modID string) (Mod, error) {
	return s.ForkFor("", modID)
}
func (s *Service) ForkFor(authorID, modID string) (Mod, error) {
	parent, err := s.repo.Get(modID)
	if err != nil {
		return Mod{}, err
	}
	if parent.Draft && parent.AuthorID != authorID {
		return Mod{}, ErrForbidden
	}
	return s.repo.Create(Mod{ParentID: modID, Runtime: parent.Runtime, Patch: nil, AIGenerated: parent.AIGenerated, AuthorID: authorID, CreatedAt: time.Now().UTC(), Draft: true})
}
func (s *Service) Mine(authorID string) ([]Mod, error) { return s.repo.ListByAuthor(authorID) }
func (s *Service) Get(id string) (Mod, error)          { return s.repo.Get(id) }

// SetDraft 切换某 mod 的草稿标记。草稿发布成功后须清除(draft=false),否则其他用户 Fork 该
// 已发布游戏时会被 ForkFor 的 `parent.Draft && parent.AuthorID != authorID` 判为 ErrForbidden。
func (s *Service) SetDraft(id string, draft bool) error { return s.repo.SetDraft(id, draft) }

func (s *Service) CanRead(id, viewer string) error {
	m, err := s.repo.Get(id)
	if err != nil {
		return err
	}
	if m.Draft && (viewer == "" || m.AuthorID != viewer) {
		return ErrForbidden
	}
	return nil
}

func (s *Service) Drafts(authorID string) ([]Mod, error) {
	items, err := s.repo.ListByAuthor(authorID)
	if err != nil {
		return nil, err
	}
	out := make([]Mod, 0, len(items))
	for _, item := range items {
		if item.Draft {
			out = append(out, item)
		}
	}
	return out, nil
}

func (s *Service) SaveDraftFor(authorID, parentID string, patch []dsl.Op) (Mod, error) {
	parent, err := s.repo.Get(parentID)
	if err != nil {
		return Mod{}, err
	}
	if !parent.Draft {
		return Mod{}, ErrNotDraft
	}
	if authorID == "" || parent.AuthorID != authorID {
		return Mod{}, ErrForbidden
	}
	return s.CreateChildFor(authorID, parentID, patch, false, true)
}

// redactForeignDrafts 从链中剔除属于他人的草稿节点:第三方不应经祖先链看到别人未发布草稿的
// Patch/AuthorID(CanRead 只看叶子节点,漏了祖先)。查看者本人的草稿保留。与 ForkTree 过滤草稿
// 子节点的口径一致。
func redactForeignDrafts(chain []Mod, viewer string) []Mod {
	out := make([]Mod, 0, len(chain))
	for _, m := range chain {
		if m.Draft && (viewer == "" || m.AuthorID != viewer) {
			continue
		}
		out = append(out, m)
	}
	return out
}

// Lineage 创作链:从根到 modID 的 mod 序列(根在前),对应原型「A → B → 本作」。
// viewer 用于剔除他人草稿祖先(防未发布草稿经血缘链泄露)。
func (s *Service) Lineage(modID, viewer string) ([]Mod, error) {
	chain, _, err := s.chainRootFirst(modID)
	if err != nil {
		return nil, err
	}
	return redactForeignDrafts(chain, viewer), nil
}

// ForkTreeView 是某 mod 的局部 Fork Tree 视图(docs/09-api-design.md:祖先链 + 直接子节点)。
type ForkTreeView struct {
	Ancestors []Mod `json:"ancestors"` // 根 → 父
	Node      Mod   `json:"node"`
	Children  []Mod `json:"children"` // 直接子节点
}

// ForkTree 返回某 mod 的祖先链、自身、直接子节点。
// viewer 用于剔除他人草稿祖先/子节点(防未发布草稿泄露)。
func (s *Service) ForkTree(modID, viewer string) (ForkTreeView, error) {
	chain, _, err := s.chainRootFirst(modID)
	if err != nil {
		return ForkTreeView{}, err
	}
	children, err := s.repo.ListChildren(modID)
	if err != nil {
		return ForkTreeView{}, err
	}
	publicChildren := make([]Mod, 0, len(children))
	for _, child := range children {
		if !child.Draft {
			publicChildren = append(publicChildren, child)
		}
	}
	return ForkTreeView{
		Ancestors: redactForeignDrafts(chain[:len(chain)-1], viewer),
		Node:      chain[len(chain)-1],
		Children:  publicChildren,
	}, nil
}

// EffectiveDSL 计算某 mod 的生效 DSL = 基线 + 沿父链逐层 apply patch。
func (s *Service) EffectiveDSL(modID string) (map[string]any, error) {
	chain, runtime, err := s.chainRootFirst(modID)
	if err != nil {
		return nil, err
	}
	cur, err := s.baselines.BaselineFor(runtime)
	if err != nil {
		return nil, fmt.Errorf("取基线失败: %w", err)
	}
	for _, m := range chain {
		if len(m.Patch) == 0 {
			continue
		}
		cur, err = dsl.Apply(cur, m.Patch)
		if err != nil {
			return nil, fmt.Errorf("mod %s 补丁 apply 失败: %w", m.ID, err)
		}
	}
	return cur, nil
}

// chainRootFirst 返回从根到 modID 的链(根在前),以及该链的 runtime。
func (s *Service) chainRootFirst(modID string) ([]Mod, string, error) {
	var rev []Mod
	id := modID
	for id != "" {
		if len(rev) >= maxChainDepth {
			return nil, "", fmt.Errorf("mods: 链过深或成环(>%d)", maxChainDepth)
		}
		m, err := s.repo.Get(id)
		if err != nil {
			return nil, "", err
		}
		rev = append(rev, m)
		id = m.ParentID
	}
	if len(rev) == 0 {
		return nil, "", ErrNotFound
	}
	// 反转成根在前
	chain := make([]Mod, len(rev))
	for i, m := range rev {
		chain[len(rev)-1-i] = m
	}
	return chain, chain[0].Runtime, nil
}
