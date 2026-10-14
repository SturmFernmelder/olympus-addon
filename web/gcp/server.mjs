// Olympus Link on Cloud Run. Secrets are injected from Secret Manager as environment variables;
// Firestore is the durable journal and the existing Worker/core remains the source of link rules.

import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { Firestore } from '@google-cloud/firestore';
import { handleLink } from '../worker/link-worker.js';
import { adminAuthorized, failure, pruneLink, respond } from '../worker/link-core.mjs';
import { createFirestoreD1, FirestoreJournal } from './firestore-d1.mjs';

const BODY_MAX = 16 * 1024;

function runtimeEnv(source, db) {
	return { ...source, LINK_DB: db };
}

async function bodyOf(req) {
	const chunks = [];
	let size = 0;
	for await (const chunk of req) {
		size += chunk.length;
		if (size > BODY_MAX) throw Object.assign(new Error('Request body too large'), { status: 413 });
		chunks.push(chunk);
	}
	return Buffer.concat(chunks);
}

async function webRequest(req, publicOrigin) {
	const body = req.method === 'GET' || req.method === 'HEAD' ? undefined : await bodyOf(req);
	const origin = publicOrigin || `https://${req.headers.host || 'localhost'}`;
	return new Request(new URL(req.url || '/', origin), { method: req.method, headers: req.headers, body });
}

async function nodeResponse(res, answer) {
	res.statusCode = answer.status;
	answer.headers.forEach((value, name) => res.setHeader(name, value));
	res.end(Buffer.from(await answer.arrayBuffer()));
}

export function createCloudRunHandler(env) {
	return async function cloudRun(request) {
		const url = new URL(request.url);
		if (request.method === 'GET' && url.pathname === '/healthz') return respond({ ok: true, service: 'olympus-link' });
		if (request.method === 'POST' && url.pathname === '/internal/prune') {
			if (!(await adminAuthorized(request, env))) return respond(failure('auth', 'Wrong admin token.'));
			return respond(await pruneLink(env));
		}
		return (await handleLink(request, env, { waitUntil() {} })) || new Response('Not found', { status: 404 });
	};
}

export async function createService({ source = process.env, firestore = new Firestore() } = {}) {
	const schema = await readFile(new URL('../worker/schema.sql', import.meta.url), 'utf8');
	const journal = new FirestoreJournal(firestore, { prefix: source.FIRESTORE_PREFIX || 'olympus_link' });
	const db = await createFirestoreD1({ schema, journal });
	return createCloudRunHandler(runtimeEnv(source, db));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	const service = await createService();
	const port = Number(process.env.PORT) || 8080;
	const server = http.createServer(async (req, res) => {
		try {
			await nodeResponse(res, await service(await webRequest(req, process.env.PUBLIC_ORIGIN)));
		} catch (err) {
			console.error('olympus-link cloud run', err && err.stack ? err.stack : err);
			res.statusCode = Number(err && err.status) || 500;
			res.setHeader('Content-Type', 'application/json; charset=utf-8');
			res.end(JSON.stringify({ status: 'error', reason: 'server' }));
		}
	});
	server.listen(port, '0.0.0.0', () => console.log(`Olympus Link listening on ${port}`));
}

