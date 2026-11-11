import { isDeepStrictEqual } from 'node:util';
// fast-json-patch ships CommonJS, so its functions are reached through the default export.
import jsonPatch, { type Operation } from 'fast-json-patch';
import baseline from '../../../client/runtime/shooter/baseline.dsl.json';
import golden from '../../../client/runtime/shooter/testdata/fork_expected.dsl.json';
import forkPatch from './fork-patch.json';

// The landing page shows a patch that the repository's own tests use: packages/dsl/patch_test.go applies the same four operations to the same baseline and asserts on the same golden file, which the GDScript implementation is tested against as well. The baseline and golden documents are imported straight from the client fixtures, and the patch copy in fork-patch.json is re-applied here at build time: if it no longer produces the golden file, the build fails instead of publishing a stale example.

/** Repository paths the example is taken from, relative to the repository root. */
export const EXAMPLE_SOURCES = {
	baseline: 'apps/client/runtime/shooter/baseline.dsl.json',
	golden: 'apps/client/runtime/shooter/testdata/fork_expected.dsl.json',
	goTest: 'packages/dsl/patch_test.go',
} as const;

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
	throw new Error(`The patch in src/data/fork-patch.json no longer turns ${EXAMPLE_SOURCES.baseline} into ${EXAMPLE_SOURCES.golden}. Update the copy to match the patch used in ${EXAMPLE_SOURCES.goTest}.`);
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
