package pagex

import "testing"

func TestPage_Walk(t *testing.T) {
	all := []int{1, 2, 3, 4, 5}

	// 第一页 limit 2
	p1, c1, err := Page(all, "", 2)
	if err != nil {
		t.Fatal(err)
	}
	if len(p1) != 2 || p1[0] != 1 || c1 == "" {
		t.Fatalf("第一页不对: %v cursor=%q", p1, c1)
	}
	// 第二页
	p2, c2, _ := Page(all, c1, 2)
	if len(p2) != 2 || p2[0] != 3 || c2 == "" {
		t.Fatalf("第二页不对: %v cursor=%q", p2, c2)
	}
	// 第三页(最后一项,nextCursor 空)
	p3, c3, _ := Page(all, c2, 2)
	if len(p3) != 1 || p3[0] != 5 || c3 != "" {
		t.Fatalf("末页不对: %v cursor=%q", p3, c3)
	}
}

func TestPage_OffsetBeyond(t *testing.T) {
	all := []int{1, 2}
	p, c, _ := Page(all, Encode(10), 5)
	if len(p) != 0 || c != "" {
		t.Errorf("越界应返回空页, got %v %q", p, c)
	}
}

func TestDecode_Invalid(t *testing.T) {
	if _, err := Decode("!!!not-base64"); err == nil {
		t.Error("非法游标应报错")
	}
}

func TestClampLimit(t *testing.T) {
	if ClampLimit(0) != DefaultLimit {
		t.Error("0 应取默认")
	}
	if ClampLimit(9999) != MaxLimit {
		t.Error("超限应裁到 MaxLimit")
	}
	if ClampLimit(15) != 15 {
		t.Error("正常值应保留")
	}
}
