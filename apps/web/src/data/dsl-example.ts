import { isDeepStrictEqual } from 'node:util';
// fast-json-patch ships CommonJS, so its functions are reached through the default export.
import jsonPatch, { type Operation } from 'fast-json-patch';
import baseline from '../../../client/runtime/shooter/baseline.dsl.json';
import golden from '../../../client/runtime/shooter/testdata/fork_expected.dsl.json';
import forkPatch from './fork-patch.json';

// The landing page shows the fork patch that the repository's own tests use: the prompt and patch come from apps/server/internal/ai/service_test.go, and the same patch is asserted against the same golden file by packages/dsl/patch_test.go and apps/client/spike_test.gd. The baseline and golden documents are imported straight from the client fixtures, and the patch copy in fork-patch.json is re-applied here at build time. If the fixtures and the copy ever disagree, the build stops instead of publishing an example that is no longer true.

/** Repository paths the example is taken from, relative to the repository root. */
export const EXAMPLE_SOURCES = {
	prompt: 'apps/server/internal/ai/service_test.go',
	baseline: 'apps/client/runtime/shooter/baseline.dsl.json',
	golden: 'apps/client/runtime/shooter/testdata/fork_expected.dsl.json',
	goTest: 'packages/dsl/patch_test.go',
	godotTest: 'apps/client/spike_test.gd',
} as const;

/** Prompt string used by the orchestration test, verbatim. */
export const EXAMPLE_PROMPT_ZH = '把飞机换成猫,加只鸟,删掉炮台';

export type PatchOpKind = 'add' | 'remove' | 'replace';

export interface PatchLine {
	op: PatchOpKind;
	path: string;
	/** Compact JSON of the operation value, absent for remove. */
	value?: string;
	/** Compact JSON of what the baseline holds at this path, absent when the path is new. */
	before?: string;
	/** Compact JSON of what the patched document holds at this path, absent when the path was removed. */
	after?: string;
}

function isShownOp(op: string): op is PatchOpKind {
	return op === 'add' || op === 'remove' || op === 'replace';
}

function compact(value: unknown): string {
	return JSON.stringify(value).replaceAll('":', '": ').replaceAll(',"', ', "');
}

function lookup(document: unknown, pointer: string): unknown {
	try {
		return jsonPatch.getValueByPointer(document, pointer);
	} catch {
		return undefined;
	}
}

function enemyTotal(document: { enemies: Record<string, { count: number }> }): number {
	return Object.values(document.enemies).reduce((sum, enemy) => sum + enemy.count, 0);
}

const operations = forkPatch as Operation[];
const patched = jsonPatch.applyPatch(baseline, operations, true, false).newDocument;

if (!isDeepStrictEqual(patched, golden)) {
	throw new Error(`The fork patch in src/data/fork-patch.json no longer turns ${EXAMPLE_SOURCES.baseline} into ${EXAMPLE_SOURCES.golden}. Update the copy to match the patch used in ${EXAMPLE_SOURCES.goTest}.`);
}

export const patchLines: PatchLine[] = operations.map((operation) => {
	if (!isShownOp(operation.op)) throw new Error(`Unsupported operation "${operation.op}" in the fork patch example.`);
	const before = lookup(baseline, operation.path);
	const after = lookup(golden, operation.path);
	return {
		op: operation.op,
		path: operation.path,
		value: 'value' in operation ? compact(operation.value) : undefined,
		before: before === undefined ? undefined : compact(before),
		after: after === undefined ? undefined : compact(after),
	};
});

/** Runtime identifier of the example, for example "shooter@1.0.0". */
export const exampleRuntime = `${baseline.meta.runtime}@${baseline.meta.runtime_version}`;

/** Sum of enemy counts before and after the patch, the scalar both test suites assert on. */
export const enemyTotals = { before: enemyTotal(baseline), after: enemyTotal(golden) };
