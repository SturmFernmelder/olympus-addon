import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { createFirestoreD1, MemoryJournal } from '../gcp/firestore-d1.mjs';

const schema = await readFile(new URL('../worker/schema.sql', import.meta.url), 'utf8');

test('the Firestore journal adapter durably replays writes and mutation RETURNING results', async () => {
	const journal = new MemoryJournal();
	const first = await createFirestoreD1({ schema, journal });
	await first.prepare('INSERT INTO limits (k, until, n) VALUES (?, ?, ?)').bind('plain', 10, 1).run();
	const counted = await first.prepare(
		'INSERT INTO limits (k, until, n) VALUES (?, ?, 1) ON CONFLICT(k) DO UPDATE SET n = limits.n + 1 RETURNING n',
	).bind('returning', 20).first();
	assert.equal(counted.n, 1);
	assert.equal(journal.events.length, 2);

	const replayed = await createFirestoreD1({ schema, journal });
	assert.deepEqual(await replayed.prepare('SELECT until, n FROM limits WHERE k = ?').bind('plain').first(), { until: 10, n: 1 });
	assert.deepEqual(await replayed.prepare('SELECT until, n FROM limits WHERE k = ?').bind('returning').first(), { until: 20, n: 1 });
});

test('a rejected SQLite mutation never poisons the durable Firestore journal', async () => {
	const journal = new MemoryJournal();
	const db = await createFirestoreD1({ schema, journal });
	await db.prepare('INSERT INTO limits (k, until, n) VALUES (?, ?, ?)').bind('once', 10, 1).run();
	const before = journal.events.length;
	await assert.rejects(() => db.prepare('INSERT INTO limits (k, until, n) VALUES (?, ?, ?)').bind('once', 11, 2).run(), /constraint|unique/i);
	assert.equal(journal.events.length, before);
	const replayed = await createFirestoreD1({ schema, journal });
	assert.deepEqual(await replayed.prepare('SELECT until, n FROM limits WHERE k = ?').bind('once').first(), { until: 10, n: 1 });
});
