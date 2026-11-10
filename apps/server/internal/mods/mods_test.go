package mods

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/yldm-tech/classic-games/apps/server/pkg/provenance"
	"github.com/yldm-tech/classic-games/packages/dsl"
)

// 有效 AI 溯源令牌 → mod 标记 AI;无效/缺失 → 非 AI。IsAIGenerated 据此回报。
func TestCreateMod_AIProvenance(t *testing.T) {
	s := newSvc(t)
	signer := provenance.NewSigner("test-secret")
	s.SetProvenanceVerifier(signer)

	good := signer.Mint(time.Now(), time.Hour)
	m, err := s.CreateRoot("shooter@1.0.0", nil, s.VerifyProvenance(good))
	if err != nil {
		t.Fatal(err)
	}
	if !m.AIGenerated || !s.IsAIGenerated(m.ID) {
		t.Error("有效令牌应把 mod 标记为 AI 生成")
	}
	m2, _ := s.CreateRoot("shooter@1.0.0", nil, s.VerifyProvenance("forged"))
	if m2.AIGenerated || s.IsAIGenerated(m2.ID) {
		t.Error("伪造/无效令牌不应标记 AI 生成")
	}
	// Fork 继承父的 AI 标识
	f, _ := s.Fork(m.ID)
	if !f.AIGenerated {
		t.Error("基于 AI mod 的 Fork 应继承 AI 标识")
	}
}

func TestDraftsReturnsOnlyDraftModsForAuthor(t *testing.T) {
	s := newSvc(t)
	_, _ = s.CreateRootFor("owner", "shooter@1.0.0", nil, false, false)
	draft, _ := s.CreateRootFor("owner", "shooter@1.0.0", nil, false, true)
	_, _ = s.CreateRootFor("other", "shooter@1.0.0", nil, false, true)
	got, err := s.Drafts("owner")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].ID != draft.ID {
		t.Fatalf("drafts=%+v", got)
	}
}

// 测试用基线:从仓库内 client 基线加载(mods 包在 apps/server/internal/mods → 仓库根 4 层)。
type fileBaselines struct{ t *testing.T }

func (b fileBaselines) BaselineFor(runtime string) (map[string]any, error) {
	p := filepath.Join("..", "..", "..", "..", "apps", "client", "runtime", "shooter", "baseline.dsl.json")
	data, err := os.ReadFile(p)
	if err != nil {
		return nil, err
	}
	var m map[string]any
	return m, json.Unmarshal(data, &m)
}

func ops(t *testing.T, raw string) []dsl.Op {
	t.Helper()
	var o []dsl.Op
	if err := json.Unmarshal([]byte(raw), &o); err != nil {
		t.Fatal(err)
	}
	return o
}

func newSvc(t *testing.T) *Service {
	return NewService(NewMemRepo(), fileBaselines{t})
}

func sprite(dsl map[string]any) string {
	return dsl["player"].(map[string]any)["sprite"].(string)
}

func enemyCount(dsl map[string]any) int {
	return len(dsl["enemies"].(map[string]any))
}

func TestEffectiveDSL_RootPatch(t *testing.T) {
	s := newSvc(t)
	root, err := s.CreateRoot("shooter@1.0.0", ops(t, `[{"op":"replace","path":"/player/sprite","value":"cat"}]`), false)
	if err != nil {
		t.Fatal(err)
	}
	eff, err := s.EffectiveDSL(root.ID)
	if err != nil {
		t.Fatal(err)
	}
	if sprite(eff) != "cat" {
		t.Errorf("root 生效 DSL sprite=%s, 期望 cat", sprite(eff))
	}
}

func TestFork_InheritsParentEffective(t *testing.T) {
	s := newSvc(t)
	root, _ := s.CreateRoot("shooter@1.0.0", ops(t, `[{"op":"replace","path":"/player/sprite","value":"cat"}]`), false)

	// Fork:空 patch,生效 DSL 应等于父
	forked, err := s.Fork(root.ID)
	if err != nil {
		t.Fatal(err)
	}
	if forked.ParentID != root.ID {
		t.Errorf("Fork 的 parent=%s, 期望 %s", forked.ParentID, root.ID)
	}
	parentEff, _ := s.EffectiveDSL(root.ID)
	forkEff, _ := s.EffectiveDSL(forked.ID)
	pb, _ := json.Marshal(parentEff)
	fb, _ := json.Marshal(forkEff)
	if string(pb) != string(fb) {
		t.Error("Fork 初始生效 DSL 应等于被 Fork 的 mod")
	}
}

func TestEffectiveDSL_ChainApplies(t *testing.T) {
	s := newSvc(t)
	// 根:换皮 cat
	root, _ := s.CreateRoot("shooter@1.0.0", ops(t, `[{"op":"replace","path":"/player/sprite","value":"cat"}]`), false)
	// 子:加一只鸟(相对父生效)
	child, _ := s.CreateChild(root.ID, ops(t, `[{"op":"add","path":"/enemies/bird_1","value":{"type":"bird","behavior":"sine","count":10,"hp":15,"speed":12}}]`), false)
	// 孙:删掉炮台
	grand, _ := s.CreateChild(child.ID, ops(t, `[{"op":"remove","path":"/enemies/turret_1"}]`), false)

	eff, err := s.EffectiveDSL(grand.ID)
	if err != nil {
		t.Fatal(err)
	}
	if sprite(eff) != "cat" {
		t.Errorf("链上换皮应保留, sprite=%s", sprite(eff))
	}
	// 基线 enemies: dog_1 + turret_1 = 2;+bird_1 -turret_1 = 2
	if got := enemyCount(eff); got != 2 {
		t.Errorf("生效 enemies 数=%d, 期望 2(dog_1+bird_1)", got)
	}
	if _, has := eff["enemies"].(map[string]any)["turret_1"]; has {
		t.Error("turret_1 应在孙级被删除")
	}
	if _, has := eff["enemies"].(map[string]any)["bird_1"]; !has {
		t.Error("bird_1 应在子级加入并保留到孙级")
	}
}

func TestEffectiveDSL_NotFound(t *testing.T) {
	s := newSvc(t)
	if _, err := s.EffectiveDSL("mod_nope"); err == nil {
		t.Error("不存在的 mod 应报错")
	}
}

func TestLineageAndForkTree(t *testing.T) {
	s := newSvc(t)
	root, _ := s.CreateRoot("shooter@1.0.0", nil, false)
	child, _ := s.CreateChild(root.ID, nil, false)
	grand, _ := s.CreateChild(child.ID, nil, false)
	sibling, _ := s.CreateChild(root.ID, nil, false) // root 的另一个子

	// 创作链:root → child → grand
	chain, err := s.Lineage(grand.ID, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(chain) != 3 || chain[0].ID != root.ID || chain[2].ID != grand.ID {
		t.Errorf("创作链不对: %+v", chain)
	}

	// Fork Tree(child):祖先 [root]、自身 child、子 [grand]
	view, _ := s.ForkTree(child.ID, "")
	if len(view.Ancestors) != 1 || view.Ancestors[0].ID != root.ID {
		t.Errorf("祖先链不对: %+v", view.Ancestors)
	}
	if view.Node.ID != child.ID {
		t.Errorf("node 不对: %s", view.Node.ID)
	}
	if len(view.Children) != 1 || view.Children[0].ID != grand.ID {
		t.Errorf("子节点不对: %+v", view.Children)
	}

	// root 有两个直接子:child + sibling
	rootView, _ := s.ForkTree(root.ID, "")
	if len(rootView.Children) != 2 {
		t.Errorf("root 应有 2 个直接子, got %d", len(rootView.Children))
	}
	_ = sibling
}

// 他人未发布的草稿祖先不应经血缘链/Fork Tree 泄露给第三方(其 Patch/AuthorID),但作者本人可见。回归守卫 C17。
func TestLineageRedactsForeignDraftAncestors(t *testing.T) {
	s := newSvc(t)
	draft, _ := s.CreateRootFor("owner", "shooter@1.0.0", nil, false, true) // owner 的私有草稿根
	child, _ := s.CreateChildFor("owner", draft.ID, nil, false)             // owner 在草稿之上发布的非草稿子
	if child.Draft {
		t.Fatal("child 应为非草稿")
	}

	// 第三方读 child 的血缘链:不应包含 owner 的草稿祖先。
	chain, err := s.Lineage(child.ID, "outsider")
	if err != nil {
		t.Fatal(err)
	}
	for _, m := range chain {
		if m.ID == draft.ID {
			t.Fatalf("第三方不应看到他人草稿祖先: %+v", chain)
		}
	}
	// 作者本人读:应看到自己的草稿祖先。
	ownerChain, _ := s.Lineage(child.ID, "owner")
	if len(ownerChain) != 2 {
		t.Fatalf("作者应看到完整链(含自己的草稿祖先), got %+v", ownerChain)
	}
	// Fork Tree 的祖先字段同样不应泄露。
	view, _ := s.ForkTree(child.ID, "outsider")
	for _, m := range view.Ancestors {
		if m.ID == draft.ID {
			t.Fatalf("Fork Tree 祖先不应泄露他人草稿: %+v", view.Ancestors)
		}
	}
}

func TestPrivateDraftVisibilityAndParentAuthorization(t *testing.T) {
	s := newSvc(t)
	root, _ := s.CreateRootFor("owner", "shooter@1.0.0", nil, false)
	private, _ := s.CreateChildFor("owner", root.ID, nil, false, true)
	if err := s.CanRead(private.ID, "owner"); err != nil {
		t.Fatalf("owner read: %v", err)
	}
	if err := s.CanRead(private.ID, "outsider"); err != ErrForbidden {
		t.Fatalf("outsider read: %v", err)
	}
	if _, err := s.CreateChildFor("outsider", private.ID, nil, false); err != ErrForbidden {
		t.Fatalf("foreign private parent: %v", err)
	}
	if _, err := s.ForkFor("outsider", private.ID); err != ErrForbidden {
		t.Fatalf("foreign private fork: %v", err)
	}
	view, err := s.ForkTree(root.ID, "")
	if err != nil || len(view.Children) != 0 {
		t.Fatalf("private child leaked: %+v %v", view.Children, err)
	}
}
