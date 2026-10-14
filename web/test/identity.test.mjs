import assert from 'node:assert/strict';
import { beforeEach, describe, test } from 'node:test';
import {
	forgetUser,
	handleIdentity,
	issueIdentitySnapshots,
	parseIdentitySnapshot,
	verifyIdentitySnapshot,
} from '../worker/link-core.mjs';
import { makeD1, vectors } from './helpers.mjs';

const probe = await makeD1();
const NOW = 1800000000;
const USER = { id: '123456789012345678', username: 'identity.test' };
const ORIGIN = 'https://link.example.org';
const TOKEN = 'discord-access-token-for-identity-tests';
let env;

async function setup() {
	const DB = await makeD1();
	env = {
		DB,
		LINK_BACKEND_SEED: vectors.backend.seed_b64url,
		LINK_BACKEND_PUBLIC: vectors.backend.public_hex,
		LINK_IDENTITY_SECRET: 'identity-test-secret-32-characters-minimum',
		LINK_ORIGIN: ORIGIN,
		DISCORD_CLIENT_ID: '300000000000000001',
	};
	for (const [i, character] of ['Some Player-ClassicBetaPvP', 'Some Alt-ClassicBetaPvP'].entries()) {
		await DB.prepare('INSERT INTO members (character, discord_id, guild, gv, faction, r, linked) VALUES (?, ?, ?, ?, ?, ?, ?)')
			.bind(character, USER.id, 'Olympus II', 'r', 'Alliance', `R${i}`, NOW - 100 + i)
			.run();
	}
	return DB;
}

function discordStub() {
	return async () => Response.json({
		application: { id: env.DISCORD_CLIENT_ID },
		scopes: ['identify'],
		expires: '2027-06-01T00:00:00+00:00',
		user: { id: USER.id, username: USER.username, avatar: null, global_name: null },
	});
}

describe('consented OLI1 identity snapshots', { skip: probe ? false : 'node:sqlite is not available in this Node' }, () => {
	beforeEach(setup);

	test('explicit consent issues compact per-character tokens with one opaque stable subject', async () => {
		const refused = await issueIdentitySnapshots(env, USER.id, { consent: false, t: NOW });
		assert.equal(refused.reason, 'format');
		const first = await issueIdentitySnapshots(env, USER.id, { consent: true, t: NOW });
		assert.equal(first.status, 'published');
		assert.equal(first.revision, 1);
		assert.equal(first.tokens.length, 2);
		const proofs = [];
		for (const item of first.tokens) {
			assert.ok(Buffer.byteLength(item.command) <= 255, item.character);
			assert.doesNotMatch(item.token, new RegExp(USER.id));
			assert.doesNotMatch(item.token, /identity\.test/);
			const parsed = parseIdentitySnapshot(item.token);
			assert.equal(parsed.character, item.character);
			assert.equal(parsed.bothConsented, true);
			assert.equal((await verifyIdentitySnapshot(env, item.token, { t: NOW })).character, item.character);
			assert.equal(await verifyIdentitySnapshot(env, `${item.token.slice(0, -1)}A`, { t: NOW }), null);
			proofs.push(parsed);
		}
		assert.equal(proofs[0].subject, proofs[1].subject);

		const second = await issueIdentitySnapshots(env, USER.id, { consent: true, t: NOW + 60 });
		assert.equal(second.revision, 2);
		assert.equal(parseIdentitySnapshot(second.tokens[0].token).subject, proofs[0].subject);
		assert.equal(await verifyIdentitySnapshot(env, first.tokens[0].token, { t: first.expires }), null, 'expiry is fail-closed');
	});

	test('the HTTP route requires the configured origin, explicit publish and a live Discord sign-in', async () => {
		const call = (body, origin = ORIGIN) => handleIdentity(new Request(`${ORIGIN}/api/link/identity`, {
			method: 'POST',
			headers: { Origin: origin, 'Content-Type': 'application/json' },
			body: JSON.stringify(body),
		}), env, { fetchImpl: discordStub() });
		let res = await call({ discordToken: TOKEN });
		assert.equal(res.status, 400);
		assert.equal((await res.json()).reason, 'format');
		res = await call({ publish: true, discordToken: TOKEN }, 'https://evil.example');
		assert.equal(res.status, 403);
		res = await call({ publish: true, discordToken: TOKEN });
		assert.equal(res.status, 200);
		const answer = await res.json();
		assert.equal(answer.status, 'published');
		assert.equal(answer.tokens.length, 2);
	});

	test('forgetting a Discord account removes its identity revision from the service', async () => {
		await issueIdentitySnapshots(env, USER.id, { consent: true, t: NOW });
		assert.ok(await env.DB.prepare('SELECT subject FROM identity_snapshots WHERE discord_id = ?').bind(USER.id).first());
		await forgetUser(env, USER.id, NOW + 1);
		assert.equal(await env.DB.prepare('SELECT subject FROM identity_snapshots WHERE discord_id = ?').bind(USER.id).first(), null);
	});
});
