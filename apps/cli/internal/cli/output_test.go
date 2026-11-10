package cli

import (
	"bytes"
	"strings"
	"testing"
	"unicode"
)

func TestTablesAlignByDisplayWidth(t *testing.T) {
	var buffer bytes.Buffer
	err := writeTable(&buffer, []string{"ID", "TITLE", "LIKES"}, [][]string{
		{"ashfall", "灰烬王国", "8800"},
		{"ember", "Ember Drift", "9300"},
		{"empty", "", "0"},
		{"multi", "line\none\ttab", "1"},
	})
	if err != nil {
		t.Fatal(err)
	}
	want := strings.Join([]string{
		"ID       TITLE         LIKES",
		"ashfall  灰烬王国      8800",
		"ember    Ember Drift   9300",
		"empty    -             0",
		"multi    line one tab  1",
		"",
	}, "\n")
	if buffer.String() != want {
		t.Fatalf("table:\n%s\nwant:\n%s", buffer.String(), want)
	}
	// Every line reaches the last column at the same terminal cell, although the CJK title has fewer characters.
	for _, line := range strings.Split(strings.TrimSuffix(buffer.String(), "\n"), "\n") {
		last := strings.LastIndex(line, " ") + 1
		if got := displayWidth(line[:last]); got != 23 {
			t.Fatalf("last column of %q starts at cell %d, want 23", line, got)
		}
	}
}

func TestFieldsAlignValues(t *testing.T) {
	var buffer bytes.Buffer
	if err := writeFields(&buffer, []field{{"ID", "ashfall"}, {"AI generated", "no"}, {"Summary", ""}}); err != nil {
		t.Fatal(err)
	}
	want := "ID:            ashfall\nAI generated:  no\nSummary:       -\n"
	if buffer.String() != want {
		t.Fatalf("fields:\n%s\nwant:\n%s", buffer.String(), want)
	}
}

// Cell text comes from other users. No control character may reach the terminal, and the columns are aligned on the text that is really printed.
func TestCellTextNeutralisesControlCharacters(t *testing.T) {
	hostile := "A\x1b[31mRED\x1b[0m\x1b]0;title\aB\u009b2J\x7f\x00\u0085end"
	got := cellText(hostile)
	for _, r := range got {
		if unicode.IsControl(r) {
			t.Fatalf("cellText left the control character %U in %q", r, got)
		}
	}
	if want := "A�[31mRED�[0m�]0;title�B�2J���end"; got != want {
		t.Fatalf("cellText = %q, want %q", got, want)
	}
	// Tabs and line breaks keep their own treatment, and ordinary text is untouched.
	for input, want := range map[string]string{"a\tb\r\nc\nd\re": "a b c d e", "灰烬 Ember ✓": "灰烬 Ember ✓", "": "-"} {
		if got := cellText(input); got != want {
			t.Errorf("cellText(%q) = %q, want %q", input, got, want)
		}
	}

	var buffer bytes.Buffer
	if err := writeTable(&buffer, []string{"ID", "TITLE", "LIKES"}, [][]string{{"evil", "x\x1b[2Ky", "1"}, {"plain", "abc", "2"}}); err != nil {
		t.Fatal(err)
	}
	if want := "ID     TITLE   LIKES\nevil   x�[2Ky  1\nplain  abc     2\n"; buffer.String() != want {
		t.Fatalf("table:\n%q\nwant:\n%q", buffer.String(), want)
	}
}

func TestDisplayWidth(t *testing.T) {
	for text, want := range map[string]int{"": 0, "abc": 3, "灰烬": 4, "ゲーム": 6, "ＡＢ": 4, "a灰b": 4} {
		if got := displayWidth(text); got != want {
			t.Errorf("displayWidth(%q) = %d, want %d", text, got, want)
		}
	}
}
