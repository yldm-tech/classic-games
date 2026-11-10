// Package schemas reads the Mod DSL JSON Schemas from a directory on disk (packages/schemas in the repository) and validates DSL documents against them, reporting each violation with its location.
package schemas

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"

	"forgeplay/dsl"

	"github.com/santhosh-tekuri/jsonschema/v6"
	"github.com/santhosh-tekuri/jsonschema/v6/kind"
)

// fileSuffix is the naming convention of a schema file: <name>-<version>.schema.json.
const fileSuffix = ".schema.json"

// Runtime describes one runtime version that has a schema in the catalog.
type Runtime struct {
	// Ref is the runtime ref, "<name>@<version>", such as "shooter@1.0.0".
	Ref     string
	Name    string
	Version string
	// Title is the title keyword of the schema, or "" when the schema has none.
	Title string
	// Sections are the top-level properties a document of this runtime may contain, sorted by name.
	Sections []string
	// Required are the top-level properties a document must contain, in schema order.
	Required []string
	// Schema is the schema file content.
	Schema json.RawMessage
}

// Violation is one place where a document breaks its schema.
type Violation struct {
	// Path is a JSON Pointer to the offending value; "" is the document root.
	Path string
	// Message says what is wrong at Path.
	Message string
}

// Catalog is the set of runtime schemas found in one directory. The files are read and compiled once by Open, so the schema a client is shown and the schema validation enforces are always the same bytes, also when the files change on disk later. It is safe for concurrent use.
type Catalog struct {
	dir       string
	runtimes  []Runtime
	validator *dsl.SchemaValidator
}

// Open reads and compiles every <name>-<version>.schema.json file in dir. It fails when dir cannot be read, holds no schema file, or holds one that is not a JSON object or does not compile as a JSON Schema.
func Open(dir string) (*Catalog, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("read schema directory %s: %w", dir, err)
	}
	catalog := &Catalog{dir: dir, validator: dsl.NewRegisteredSchemaValidator()}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name, version, ok := splitFileName(entry.Name())
		if !ok {
			continue
		}
		content, err := os.ReadFile(filepath.Join(dir, entry.Name()))
		if err != nil {
			return nil, fmt.Errorf("read schema %s: %w", entry.Name(), err)
		}
		var header struct {
			Title      string                     `json:"title"`
			Required   []string                   `json:"required"`
			Properties map[string]json.RawMessage `json:"properties"`
		}
		if err := json.Unmarshal(content, &header); err != nil {
			return nil, fmt.Errorf("schema %s is not a JSON object: %w", entry.Name(), err)
		}
		if err := catalog.validator.Register(name+"@"+version, content); err != nil {
			if errors.Is(err, dsl.ErrInvalidRuntimeRef) {
				return nil, fmt.Errorf("schema file %s does not name a runtime: <name> and <version> may only contain letters, digits, \".\", \"_\" and \"-\"", entry.Name())
			}
			return nil, fmt.Errorf("schema %s does not compile: %w", entry.Name(), err)
		}
		sections := make([]string, 0, len(header.Properties))
		for section := range header.Properties {
			sections = append(sections, section)
		}
		sort.Strings(sections)
		catalog.runtimes = append(catalog.runtimes, Runtime{
			Ref:      name + "@" + version,
			Name:     name,
			Version:  version,
			Title:    header.Title,
			Sections: sections,
			Required: slices.Clone(header.Required),
			Schema:   content,
		})
	}
	if len(catalog.runtimes) == 0 {
		return nil, fmt.Errorf("schema directory %s holds no <runtime>-<version>%s file", dir, fileSuffix)
	}
	sort.Slice(catalog.runtimes, func(i, j int) bool { return catalog.runtimes[i].Ref < catalog.runtimes[j].Ref })
	return catalog, nil
}

// IsSchemaFile reports whether a file name follows the <name>-<version>.schema.json convention, which is what Open loads.
func IsSchemaFile(file string) bool {
	_, _, ok := splitFileName(file)
	return ok
}

// splitFileName turns "tower_defense-1.0.0.schema.json" into ("tower_defense", "1.0.0"). The version starts after the first "-" that is followed by a digit, so a pre-release suffix such as "1.0.0-rc.1" stays in the version.
func splitFileName(file string) (name, version string, ok bool) {
	stem, found := strings.CutSuffix(file, fileSuffix)
	if !found {
		return "", "", false
	}
	for i := 0; i+1 < len(stem); i++ {
		if stem[i] == '-' && stem[i+1] >= '0' && stem[i+1] <= '9' {
			if i == 0 {
				return "", "", false
			}
			return stem[:i], stem[i+1:], true
		}
	}
	return "", "", false
}

// Dir returns the directory the catalog was read from.
func (c *Catalog) Dir() string { return c.dir }

// Runtimes returns every runtime in the catalog, sorted by ref. The slice must not be modified.
func (c *Catalog) Runtimes() []Runtime { return c.runtimes }

// Refs returns the runtime refs in the catalog, sorted.
func (c *Catalog) Refs() []string {
	refs := make([]string, len(c.runtimes))
	for i, runtime := range c.runtimes {
		refs[i] = runtime.Ref
	}
	return refs
}

// Lookup returns the runtime with the given ref.
func (c *Catalog) Lookup(ref string) (Runtime, bool) {
	for _, runtime := range c.runtimes {
		if runtime.Ref == ref {
			return runtime, true
		}
	}
	return Runtime{}, false
}

// RefOf builds the runtime ref of a document from its meta.runtime and meta.runtime_version fields. ok is false when either is missing or not a string.
func RefOf(document map[string]any) (ref string, ok bool) {
	meta, _ := document["meta"].(map[string]any)
	name, _ := meta["runtime"].(string)
	version, _ := meta["runtime_version"].(string)
	if name == "" || version == "" {
		return "", false
	}
	return name + "@" + version, true
}

// Validate checks document against the schema of the runtime ref. used is the ref of the schema the document was really checked against. It equals ref except for a legacy shooter@0.x document: forgeplay/dsl migrates those to shooter@1.0.0 first, so used is shooter@1.0.0 and the violations describe the migrated document. A nil slice and a nil error mean the document is valid. Schema violations are returned as the slice, sorted by path; an error means validation could not run, for example because the catalog has no schema for ref.
func (c *Catalog) Validate(ref string, document map[string]any) (used string, violations []Violation, err error) {
	used, err = c.validator.ValidateResolved(ref, document)
	if err == nil {
		return used, nil, nil
	}
	var validationErr *jsonschema.ValidationError
	if !errors.As(err, &validationErr) {
		available := strings.Join(c.Refs(), ", ")
		switch {
		case errors.Is(err, dsl.ErrUnknownRuntime):
			return "", nil, fmt.Errorf("no schema for runtime %q: the schemas available are %s", ref, available)
		case errors.Is(err, dsl.ErrInvalidRuntimeRef):
			return "", nil, fmt.Errorf("%q is not a valid runtime ref: use <name>@<version> made of letters, digits, \".\", \"_\" and \"-\", such as one of %s", ref, available)
		default:
			return "", nil, fmt.Errorf("cannot validate against runtime %q (schemas available: %s): %w", ref, available, err)
		}
	}
	found := leaves(validationErr)
	violations = make([]Violation, len(found))
	for i, item := range found {
		violations[i] = Violation{Path: pointer(item.location), Message: item.message}
	}
	sort.SliceStable(violations, func(i, j int) bool {
		if violations[i].Path != violations[j].Path {
			return violations[i].Path < violations[j].Path
		}
		return violations[i].Message < violations[j].Message
	})
	return used, slices.Compact(violations), nil
}

// leaf is one concrete reason a document failed validation.
type leaf struct {
	location []string
	message  string
	// constMismatch marks a value that differs from a const keyword, which is how a discriminated union rejects the wrong alternative.
	constMismatch bool
}

// leaves walks a validation error tree and returns its leaves. Inner nodes only say that a subschema or a $ref failed; the leaves carry the concrete reason.
func leaves(node *jsonschema.ValidationError) []leaf {
	if names, ok := node.ErrorKind.(*kind.PropertyNames); ok {
		// The validator checks a property name as a standalone value, so the error carries no location of the object that holds the key.
		reason := "it does not satisfy the propertyNames rule of its object"
		if inner := leavesOfCauses(node); len(inner) > 0 {
			reason = inner[0].message
		}
		return []leaf{{location: node.InstanceLocation, message: fmt.Sprintf("object key %q is not allowed: %s (the validator does not report which object holds the key)", names.Property, reason)}}
	}
	if len(node.Causes) == 0 {
		_, constMismatch := node.ErrorKind.(*kind.Const)
		return []leaf{{location: node.InstanceLocation, message: node.BasicOutput().Error.String(), constMismatch: constMismatch}}
	}
	switch node.ErrorKind.(type) {
	case *kind.OneOf, *kind.AnyOf:
		return closestAlternatives(node)
	}
	return leavesOfCauses(node)
}

func leavesOfCauses(node *jsonschema.ValidationError) []leaf {
	var out []leaf
	for _, cause := range node.Causes {
		out = append(out, leaves(cause)...)
	}
	return out
}

// closestAlternatives reduces a failed oneOf or anyOf, which fails once per alternative, to the alternatives the value most plausibly aimed at. Alternatives rejected by a const on a direct child (the discriminator of a tagged union such as the shooter weapon's type) are dropped when another alternative accepts that child; of the rest, those with the fewest violations are kept. Without this, one wrong weapon field would be reported once per weapon type.
func closestAlternatives(node *jsonschema.ValidationError) []leaf {
	var all, matching [][]leaf
	for _, cause := range node.Causes {
		found := leaves(cause)
		all = append(all, found)
		if !slices.ContainsFunc(found, func(item leaf) bool {
			return item.constMismatch && len(item.location) == len(node.InstanceLocation)+1
		}) {
			matching = append(matching, found)
		}
	}
	candidates := matching
	if len(candidates) == 0 {
		candidates = all
	}
	fewest := len(candidates[0])
	for _, candidate := range candidates {
		fewest = min(fewest, len(candidate))
	}
	var out []leaf
	for _, candidate := range candidates {
		if len(candidate) == fewest {
			out = append(out, candidate...)
		}
	}
	return out
}

// pointer encodes path tokens as a JSON Pointer (RFC 6901).
func pointer(tokens []string) string {
	var builder strings.Builder
	for _, token := range tokens {
		builder.WriteByte('/')
		token = strings.ReplaceAll(token, "~", "~0")
		builder.WriteString(strings.ReplaceAll(token, "/", "~1"))
	}
	return builder.String()
}
