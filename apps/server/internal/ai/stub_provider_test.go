package ai

import (
	"context"
	"testing"
)

func TestStubProvider_DefaultPatchForEveryRuntime(t *testing.T) {
	cases := map[string]string{"shooter@1.0.0": "/player/sprite", "survivor@1.0.0": "/hero/sprite", "tower_defense@1.0.0": "/stage/background"}
	for runtime, path := range cases {
		sug, err := (StubProvider{}).GenerateModPatch(context.Background(), runtime, nil, "change it", "")
		if err != nil || len(sug.Ops) == 0 || sug.Ops[0].Path != path {
			t.Errorf("%s patch=%+v err=%v", runtime, sug.Ops, err)
		}
	}
}
