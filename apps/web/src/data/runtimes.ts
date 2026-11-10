import shooterBaseline from '../../../client/runtime/shooter/baseline.dsl.json';
import survivorBaseline from '../../../client/runtime/survivor/baseline.dsl.json';
import towerDefenseBaseline from '../../../client/runtime/tower_defense/baseline.dsl.json';
import shooterSchema from '../../../../packages/schemas/shooter-1.0.0.schema.json';
import survivorSchema from '../../../../packages/schemas/survivor-1.0.0.schema.json';
import towerDefenseSchema from '../../../../packages/schemas/tower_defense-1.0.0.schema.json';

// Runtime facts shown on the landing page are read from the schema and baseline files themselves, so the page cannot list a runtime, a version or a DSL section that the repository does not have.

export type RuntimeKey = 'shooter' | 'survivor' | 'tower_defense';

export interface RuntimeInfo {
	key: RuntimeKey;
	/** Identifier accepted by GameSession and the backend, for example "shooter@1.0.0". */
	id: string;
	/** Top-level DSL sections a Mod can change, in schema order, without the bookkeeping "meta" block. */
	sections: string[];
	schemaPath: string;
	baselinePath: string;
}

interface BaselineMeta {
	meta: { runtime: string; runtime_version: string };
}

/** Build one entry and check that the imported schema file is the one the baseline's version points at. */
function describe(key: RuntimeKey, baseline: BaselineMeta, schema: { properties: Record<string, unknown> }, schemaFile: string): RuntimeInfo {
	if (baseline.meta.runtime !== key) throw new Error(`Baseline for "${key}" declares runtime "${baseline.meta.runtime}".`);
	const version = baseline.meta.runtime_version;
	if (schemaFile !== `${key}-${version}.schema.json`) throw new Error(`Baseline for "${key}" is at version ${version} but src/data/runtimes.ts imports ${schemaFile}. Update the import.`);
	return {
		key,
		id: `${key}@${version}`,
		sections: Object.keys(schema.properties).filter((name) => name !== 'meta'),
		schemaPath: `packages/schemas/${schemaFile}`,
		baselinePath: `apps/client/runtime/${key}/baseline.dsl.json`,
	};
}

/** Every schema location outside the bookkeeping "meta" block that is neither an enum, a ranged number nor a boolean, as "<runtime>:<JSON pointer>". The "Enums, ranges, switches" pillar in src/i18n/landing.ts names exactly these exceptions: an id reference, the length-capped lists and Shooter's free-form bgm key. */
const FREE_FORM_FIELDS = [
	'shooter:/properties/stage/properties/bgm',
	'survivor:/properties/progression/properties/upgrades',
	'tower_defense:/$defs/placement/properties/tower',
	'tower_defense:/$defs/point',
	'tower_defense:/properties/path/properties/points',
];

/** Collect the JSON pointers of all strings without an enum and all arrays in a schema. */
function freeFormPointers(node: unknown, pointer: string, found: string[]): string[] {
	if (Array.isArray(node)) {
		node.forEach((item, index) => freeFormPointers(item, `${pointer}/${index}`, found));
	} else if (typeof node === 'object' && node !== null) {
		const schema = node as Record<string, unknown>;
		const types = Array.isArray(schema.type) ? schema.type : [schema.type];
		const freeString = types.includes('string') && !('enum' in schema) && !('const' in schema);
		if (freeString || types.includes('array')) found.push(pointer);
		for (const [key, value] of Object.entries(schema)) {
			if (pointer === '/properties' && key === 'meta') continue;
			freeFormPointers(value, `${pointer}/${key}`, found);
		}
	}
	return found;
}

/** Fail the build when a schema gains or loses a free-form field, so the landing copy that lists them is updated in the same change. */
function assertFreeFormFields(schemas: Record<RuntimeKey, unknown>): void {
	const actual = Object.entries(schemas)
		.flatMap(([key, schema]) => freeFormPointers(schema, '', []).map((pointer) => `${key}:${pointer}`))
		.sort();
	const expected = [...FREE_FORM_FIELDS].sort();
	if (actual.join('\n') !== expected.join('\n')) {
		throw new Error(`The runtime schemas' free-form fields changed. Update FREE_FORM_FIELDS in src/data/runtimes.ts and the "Enums, ranges, switches" copy in src/i18n/landing.ts.\nExpected:\n  ${expected.join('\n  ')}\nFound:\n  ${actual.join('\n  ')}`);
	}
}

assertFreeFormFields({ shooter: shooterSchema, survivor: survivorSchema, tower_defense: towerDefenseSchema });

export const runtimes: RuntimeInfo[] = [
	describe('shooter', shooterBaseline, shooterSchema, 'shooter-1.0.0.schema.json'),
	describe('survivor', survivorBaseline, survivorSchema, 'survivor-1.0.0.schema.json'),
	describe('tower_defense', towerDefenseBaseline, towerDefenseSchema, 'tower_defense-1.0.0.schema.json'),
];
