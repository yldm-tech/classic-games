// Single source of truth for site-wide constants. Import from here instead of repeating a URL or a path.

/** Canonical repository URL. Every link to the repository is derived from this value. */
export const REPO_URL = 'https://github.com/yldm-tech/classic-games';

/** Default branch used for source and edit links. */
export const REPO_BRANCH = 'main';

/** Site origin used for canonical URLs and the sitemap. Override with SITE_URL when deploying. */
export const DEFAULT_SITE_URL = 'http://localhost:4321';

export const SITE_NAME = 'Classic Games';

export const LICENSE_NAME = 'Apache-2.0';

/** Link to a file in the repository on the default branch. */
export function repoFile(path: string): string {
	return `${REPO_URL}/blob/${REPO_BRANCH}/${trimSlashes(path)}`;
}

/** Link to a directory in the repository on the default branch. */
export function repoDir(path: string): string {
	return `${REPO_URL}/tree/${REPO_BRANCH}/${trimSlashes(path)}`;
}

/** Link to the GitHub editor for a file on the default branch. */
export function repoEdit(path: string): string {
	return `${REPO_URL}/edit/${REPO_BRANCH}/${trimSlashes(path)}`;
}

function trimSlashes(path: string): string {
	let start = 0;
	let end = path.length;
	while (start < end && path[start] === '/') start++;
	while (end > start && path[end - 1] === '/') end--;
	return path.slice(start, end);
}
