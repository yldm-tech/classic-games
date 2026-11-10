# github.com/yldm-tech/classic-games/packages/dsl

The Go implementation of the Classic Games Mod DSL rules: applying RFC 6902 JSON Patch documents, migrating documents written for an older runtime major, and validating a document against the JSON Schemas in [`packages/schemas`](../schemas). It is one package, `dsl`, shared by the backend (`apps/server`), the `classic-games` CLI (`apps/cli`) and the MCP server (`apps/mcp`), so all three reach the same verdict on the same document.

The game client has its own GDScript implementation of the patch and migration semantics ([`apps/client/runtime/json_patch.gd`](../../apps/client/runtime/json_patch.gd), [`apps/client/runtime/dsl_migrations.gd`](../../apps/client/runtime/dsl_migrations.gd)). The two must agree, and the tests of this package read the same baseline and golden file as the client's tests to pin them together. A change to the semantics here is a change to the client in the same pull request.

## Install

The module lives in this repository and is consumed through a `replace` directive. From `apps/cli`, for example:

```
require github.com/yldm-tech/classic-games/packages/dsl v0.0.0

replace github.com/yldm-tech/classic-games/packages/dsl => ../../packages/dsl
```

Then run `GOWORK=off go mod tidy`. A `replace` is not inherited: a module that requires another local module which itself requires `github.com/yldm-tech/classic-games/packages/dsl` needs its own `replace` for it.

## API

| Symbol | What it does |
| --- | --- |
| `type Op struct { Op, Path string; Value json.RawMessage }` | One RFC 6902 operation in its wire shape. A patch is `[]dsl.Op` and unmarshals directly from a JSON array. |
| `func Apply(doc map[string]any, ops []Op) (map[string]any, error)` | Applies a patch and returns a new document; the input is deep-copied once and never mutated. Stops at the first failing operation and returns it as `*OpError`. |
| `type OpError struct { Index int; Err error }` | The error of `Apply` for a failing operation: `Index` is the zero-based position of the operation in the patch, and `Error()` is the message of `Err`. |
| `func Migrate(runtime, targetVersion string, input map[string]any) (string, map[string]any, error)` | Upgrades a document to a newer runtime major and returns the new runtime ref and a migrated copy. The only existing path is `shooter@0.x` to `1.x`. `targetVersion` is written into `meta.runtime_version`, so it has to be a plain `<major>.<minor>.<patch>` version such as `1.0.0`; anything else is refused. |
| `func NewSchemaValidator(schemaDir string) *SchemaValidator` | Creates a validator that loads `<schemaDir>/<name>-<version>.schema.json` on demand. Does no I/O itself. |
| `func NewRegisteredSchemaValidator() *SchemaValidator` | Creates a validator that never reads the disk and only knows the schemas added with `Register`. |
| `func (v *SchemaValidator) Register(runtime string, schema []byte) error` | Compiles the content of a schema file and uses it for the runtime ref from now on. Fails when the schema does not compile. |
| `func (v *SchemaValidator) Validate(runtime string, dsl map[string]any) error` | Validates a document against the schema of a runtime ref such as `shooter@1.0.0`. Safe for concurrent use; compiled schemas are cached. |
| `func (v *SchemaValidator) ValidateResolved(runtime string, dsl map[string]any) (string, error)` | `Validate` that also returns the ref of the schema that was really used, which is `shooter@1.0.0` for a migrated `shooter@0.x` document. |

```go
var doc map[string]any          // json.Unmarshal of a DSL file
var ops []dsl.Op                // json.Unmarshal of a patch file

patched, err := dsl.Apply(doc, ops)
if err != nil {
	return err
}
validator := dsl.NewSchemaValidator("packages/schemas")
if err := validator.Validate("shooter@1.0.0", patched); err != nil {
	return err
}
```

Behaviour worth knowing:

- Supported operations are `add`, `replace`, `remove` and `test`. `move` and `copy` are rejected, and so is any operation on the root path `""`. `replace` and `remove` need an existing target, `add` needs an existing parent, and the array token `-` appends and is valid for `add` only.
- Documents are in `encoding/json` shape (`map[string]any`, `[]any`, `float64`, `string`, `bool`, `nil`). `json.Marshal` sorts map keys, so the marshalled result is a canonical form for comparisons.
- A runtime ref is `<name>@<version>`. Name and version may contain letters, digits, `.`, `_` and `-` only, so a ref cannot address a file outside the schema directory.
- A schema violation is returned as an error wrapping `*jsonschema.ValidationError` from `github.com/santhosh-tekuri/jsonschema/v6`; use `errors.As` to reach the per-field output.
- When no schema file exists for a `shooter@0.x` ref, `Validate` migrates a copy to `shooter@1.0.0` and validates that. The caller's document is not modified.
- Error messages of this package are Chinese plain strings and are part of its behaviour: the backend shows them to users and the client implementation produces the same text. A patch error names the last pointer token, not the full path, so callers that report it should add the operation index and path themselves, as the CLI and the MCP server do.
- Errors are classified without changing their text. `errors.Is` matches `ErrTargetMissing`, `ErrParentMissing`, `ErrIndexOutOfRange`, `ErrTestFailed`, `ErrRootPath` and `ErrUnsupportedOp` for a patch operation, and `ErrInvalidRuntimeRef` and `ErrUnknownRuntime` for a runtime ref; `errors.As` with `*OpError` gives the index of the failing operation. A caller that needs its own wording, such as the MCP server with its English tool errors, builds it from these.
- A schema is compiled without a loader for external references. A `$ref` that points outside the schema document (`file://`, `http://`, `https://`, or a relative file name) makes the schema fail to compile; it is never opened or fetched. The schemas in `packages/schemas` only use `#/$defs/...` references.
- The schemas are read from disk. They are not embedded, because `packages/schemas` is not a Go module.

## Development

```sh
cd packages/dsl
GOWORK=off go vet ./...
GOWORK=off go test ./... -count=1
```

From the repository root, `make dsl-test` runs the tests inside the Go workspace. The tests read `apps/client/runtime/shooter/baseline.dsl.json` and `apps/client/runtime/shooter/testdata/fork_expected.dsl.json`, two levels above this directory, and fail rather than skip when the files are missing.
