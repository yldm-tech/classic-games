package cli

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode"

	"github.com/spf13/cobra"
	"golang.org/x/text/width"
)

// stdioPath is the conventional file argument that means standard input or standard output.
const stdioPath = "-"

// encodeJSON renders value as indented JSON with a trailing newline. HTML escaping is off so "<" and "&" in titles and prompts stay readable. encoding/json sorts map keys, which keeps DSL documents byte-stable between runs.
func encodeJSON(value any) ([]byte, error) {
	var buffer bytes.Buffer
	encoder := json.NewEncoder(&buffer)
	encoder.SetEscapeHTML(false)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(value); err != nil {
		return nil, fmt.Errorf("encode JSON: %w", err)
	}
	return buffer.Bytes(), nil
}

func writeJSON(w io.Writer, value any) error {
	data, err := encodeJSON(value)
	if err != nil {
		return err
	}
	_, err = w.Write(data)
	return err
}

// emit prints the result of a command: value as JSON under --output json, otherwise whatever human writes.
func (a *app) emit(cmd *cobra.Command, value any, human func(w io.Writer) error) error {
	if a.jsonOutput() {
		return writeJSON(cmd.OutOrStdout(), value)
	}
	return human(cmd.OutOrStdout())
}

// emitDocument prints a JSON document (a DSL or a patch) to stdout, or writes it to path and reports where it went. Documents are JSON in both output modes.
func (a *app) emitDocument(cmd *cobra.Command, path string, document any) error {
	if path == "" || path == stdioPath {
		return writeJSON(cmd.OutOrStdout(), document)
	}
	if err := writeDocumentFile(path, document); err != nil {
		return err
	}
	return a.emit(cmd, map[string]string{"out": path}, func(w io.Writer) error {
		_, err := fmt.Fprintf(w, "Wrote %s\n", path)
		return err
	})
}

func writeDocumentFile(path string, document any) error {
	data, err := encodeJSON(document)
	if err != nil {
		return err
	}
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}

// columnGap is the number of spaces between two table columns.
const columnGap = 2

// writeTable prints aligned columns. Cells never contain tabs or newlines after sanitising, so one row is always one line. Padding is computed from the display width, because titles and nicknames are often CJK text that takes two terminal cells per character.
func writeTable(w io.Writer, header []string, rows [][]string) error {
	lines := make([][]string, 0, len(rows)+1)
	lines = append(lines, header)
	for _, row := range rows {
		cells := make([]string, len(row))
		for i, cell := range row {
			cells[i] = cellText(cell)
		}
		lines = append(lines, cells)
	}
	widths := make([]int, len(header))
	for _, line := range lines {
		for i, cell := range line {
			widths[i] = max(widths[i], displayWidth(cell))
		}
	}
	var out strings.Builder
	for _, line := range lines {
		for i, cell := range line {
			out.WriteString(cell)
			if i < len(line)-1 {
				out.WriteString(strings.Repeat(" ", widths[i]-displayWidth(cell)+columnGap))
			}
		}
		out.WriteByte('\n')
	}
	_, err := io.WriteString(w, out.String())
	return err
}

// field is one "Label: value" line of a detail view.
type field struct {
	Label string
	Value string
}

func writeFields(w io.Writer, fields []field) error {
	labelWidth := 0
	for _, f := range fields {
		labelWidth = max(labelWidth, displayWidth(f.Label)+1)
	}
	var out strings.Builder
	for _, f := range fields {
		label := f.Label + ":"
		out.WriteString(label)
		out.WriteString(strings.Repeat(" ", labelWidth-displayWidth(label)+columnGap))
		out.WriteString(cellText(f.Value))
		out.WriteByte('\n')
	}
	_, err := io.WriteString(w, out.String())
	return err
}

// displayWidth returns the number of terminal cells s occupies: two for East Asian wide and fullwidth characters, one for everything else.
func displayWidth(s string) int {
	total := 0
	for _, r := range s {
		switch width.LookupRune(r).Kind() {
		case width.EastAsianWide, width.EastAsianFullwidth:
			total += 2
		default:
			total++
		}
	}
	return total
}

var cellReplacer = strings.NewReplacer("\t", " ", "\r\n", " ", "\n", " ", "\r", " ")

// cellText makes a value safe to print in a table or a detail view; every such value goes through it. Tabs and line breaks become a space so one row stays one line. Every other control character (ESC, BEL, DEL and the C1 range, which includes the single-byte CSI) becomes U+FFFD: titles, summaries, tags and nicknames are written by other users, and a terminal would run the escape sequences in them. JSON output does not need this, because encoding/json escapes control characters itself.
func cellText(value string) string {
	value = cellReplacer.Replace(value)
	value = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return unicode.ReplacementChar
		}
		return r
	}, value)
	if value == "" {
		return "-"
	}
	return value
}

func formatTime(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format(time.RFC3339)
}

func formatBool(value bool) string {
	if value {
		return "yes"
	}
	return "no"
}

func formatInt(value int) string { return strconv.Itoa(value) }

// orEmpty replaces a nil slice with an empty one so JSON output always carries an array, never null.
func orEmpty[T any](items []T) []T {
	if items == nil {
		return []T{}
	}
	return items
}

// itemList is the JSON shape of every unpaginated listing.
type itemList[T any] struct {
	Items []T `json:"items"`
}

// itemPage is the JSON shape of a cursor-paginated listing.
type itemPage[T any] struct {
	Items      []T    `json:"items"`
	NextCursor string `json:"next_cursor"`
}
