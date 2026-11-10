package cli

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"slices"
	"strings"

	"forgeplay/dsl"
	"forgeplay/sdk"

	"github.com/spf13/cobra"
)

// awaitStdin runs read on standard input in its own goroutine and returns its result, or the context error as soon as the command is interrupted. A read from a terminal or a pipe cannot be cancelled, so without this the first interrupt would be swallowed until the stream ends. The goroutine is abandoned on an interrupt, which is fine because the process is about to exit.
func awaitStdin[T any](cmd *cobra.Command, read func(io.Reader) (T, error)) (T, error) {
	type outcome struct {
		value T
		err   error
	}
	done := make(chan outcome, 1)
	go func() {
		value, err := read(cmd.InOrStdin())
		done <- outcome{value: value, err: err}
	}()
	select {
	case <-cmd.Context().Done():
		var zero T
		return zero, cmd.Context().Err()
	case result := <-done:
		return result.value, result.err
	}
}

// readInput reads a file argument; "-" reads standard input, and an interrupt ends the wait for it.
func readInput(cmd *cobra.Command, path string) ([]byte, error) {
	if path == stdioPath {
		data, err := awaitStdin(cmd, io.ReadAll)
		if cmd.Context().Err() != nil {
			return nil, cmd.Context().Err()
		}
		if err != nil {
			return nil, fmt.Errorf("read standard input: %w", err)
		}
		return data, nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", path, err)
	}
	return data, nil
}

// readDSL reads a Mod DSL document, which must be a JSON object.
func readDSL(cmd *cobra.Command, path string) (map[string]any, error) {
	data, err := readInput(cmd, path)
	if err != nil {
		return nil, err
	}
	var document map[string]any
	if err := json.Unmarshal(data, &document); err != nil {
		return nil, fmt.Errorf("%s: not a JSON object: %w", displayPath(path), err)
	}
	if document == nil {
		return nil, fmt.Errorf("%s: a DSL document must be a JSON object, got null", displayPath(path))
	}
	return document, nil
}

// readPatch reads an RFC 6902 patch, which must be a JSON array of operations. The result is never nil, so an empty patch is sent as [] rather than null.
func readPatch(cmd *cobra.Command, path string) ([]dsl.Op, error) {
	data, err := readInput(cmd, path)
	if err != nil {
		return nil, err
	}
	var ops []dsl.Op
	if err := json.Unmarshal(data, &ops); err != nil {
		return nil, fmt.Errorf("%s: not a JSON Patch array: %w", displayPath(path), err)
	}
	if ops == nil {
		return nil, fmt.Errorf("%s: a patch must be a JSON array of operations, got null", displayPath(path))
	}
	for i, op := range ops {
		if op.Op == "" {
			return nil, fmt.Errorf("%s: operation %d has no \"op\"", displayPath(path), i)
		}
		// move and copy can never be applied, neither by the backend nor by dsl.Apply, and their "from" member has no place in dsl.Op, so sending one would store a patch that differs from the file and breaks the mod for good.
		if !slices.Contains(supportedOps, op.Op) {
			return nil, fmt.Errorf("%s: operation %d uses unsupported op %q (supported: %s)", displayPath(path), i, op.Op, strings.Join(supportedOps, ", "))
		}
	}
	return ops, nil
}

// supportedOps are the RFC 6902 operations the Mod DSL accepts, on the backend, in the client and in forgeplay/dsl.
var supportedOps = []string{"add", "replace", "remove", "test"}

// toSDKPatch converts a patch to the wire type of the SDK. The two types have identical fields.
func toSDKPatch(ops []dsl.Op) []sdk.PatchOp {
	converted := make([]sdk.PatchOp, len(ops))
	for i, op := range ops {
		converted[i] = sdk.PatchOp(op)
	}
	return converted
}

func displayPath(path string) string {
	if path == stdioPath {
		return "standard input"
	}
	return path
}

// readLine reads one line from standard input without its line ending. It is used for secrets and one-time codes, which are passed on stdin so they never appear in the process list or shell history. An interrupt ends the wait for a terminal that never sends a line.
func readLine(cmd *cobra.Command) (string, error) {
	line, err := awaitStdin(cmd, func(stdin io.Reader) (string, error) {
		return bufio.NewReader(stdin).ReadString('\n')
	})
	if cmd.Context().Err() != nil {
		return "", cmd.Context().Err()
	}
	if err != nil && !(errors.Is(err, io.EOF) && line != "") {
		if errors.Is(err, io.EOF) {
			return "", errors.New("standard input is empty")
		}
		return "", fmt.Errorf("read standard input: %w", err)
	}
	return strings.TrimRight(line, "\r\n"), nil
}

// runtimeRefOf builds the runtime ref "<name>@<version>" a DSL document declares in meta.runtime and meta.runtime_version.
func runtimeRefOf(document map[string]any) (string, bool) {
	meta, _ := document["meta"].(map[string]any)
	name, _ := meta["runtime"].(string)
	version, _ := meta["runtime_version"].(string)
	if name == "" || version == "" {
		return "", false
	}
	return name + "@" + version, true
}
