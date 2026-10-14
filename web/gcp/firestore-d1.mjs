// Olympus Link on Google Cloud: the existing, reviewed D1/SQLite core over a durable Firestore
// journal. Cloud Run is deliberately configured with one instance and concurrency one: every
// accepted mutation is appended to Firestore before it is committed to the local SQLite cache,
// and a cold start rebuilds that cache by replaying the journal. The journal is the durable source;
// the container filesystem is never relied on.

import { DatabaseSync } from 'node:sqlite';

const WRITE = /^(?:INSERT|UPDATE|DELETE|REPLACE|CREATE|DROP|ALTER)\b/i;
const EVENT_VERSION = 1;
const MAX_EVENT_BYTES = 64 * 1024;

function cleanArgs(args) {
	return args.map((v) => (v === undefined ? null : typeof v === 'bigint' ? Number(v) : v));
}

function eventOf(statements) {
	const ops = statements.map(({ sql, args = [] }) => ({ sql: String(sql), args: cleanArgs(args) }));
	const event = { version: EVENT_VERSION, ops };
	if (Buffer.byteLength(JSON.stringify(event), 'utf8') > MAX_EVENT_BYTES) throw new Error('Olympus Link Firestore journal event is too large');
	return event;
}

function validEvent(event) {
	return (
		event &&
		event.version === EVENT_VERSION &&
		Array.isArray(event.ops) &&
		event.ops.length > 0 &&
		event.ops.every((op) => op && typeof op.sql === 'string' && WRITE.test(op.sql.trim()) && Array.isArray(op.args))
	);
}

// The test journal also documents the tiny interface a different durable store may implement.
export class MemoryJournal {
	constructor(events = []) {
		this.events = structuredClone(events);
	}
	async load() {
		return structuredClone(this.events);
	}
	async append(event) {
		this.events.push(structuredClone(event));
		return this.events.length;
	}
}

// `firestore` is an @google-cloud/firestore Firestore instance. Sequence allocation and the event
// itself are one Firestore transaction, so a cold start never observes half an append.
export class FirestoreJournal {
	constructor(firestore, { prefix = 'olympus_link' } = {}) {
		if (!firestore || typeof firestore.collection !== 'function' || typeof firestore.runTransaction !== 'function') {
			throw new TypeError('A Firestore client is required');
		}
		if (!/^[a-z][a-z0-9_]{2,40}$/.test(prefix)) throw new Error('FIRESTORE_PREFIX must be a short lowercase identifier');
		this.firestore = firestore;
		this.events = firestore.collection(`${prefix}_events`);
		this.meta = firestore.collection(`${prefix}_meta`).doc('journal');
	}

	async load() {
		const snap = await this.events.orderBy('seq', 'asc').get();
		return snap.docs.map((doc) => {
			const data = doc.data();
			return { version: data.version, ops: data.ops };
		});
	}

	async append(event) {
		if (!validEvent(event)) throw new Error('Invalid Olympus Link journal event');
		return this.firestore.runTransaction(async (tx) => {
			const current = await tx.get(this.meta);
			const seq = Number(current.exists && current.data().next) || 1;
			const id = String(seq).padStart(16, '0');
			tx.create(this.events.doc(id), { seq, version: event.version, ops: event.ops, createdAt: Date.now() });
			tx.set(this.meta, { next: seq + 1 }, { merge: true });
			return seq;
		});
	}
}

function rawExecute(db, op, mode = 'run') {
	const statement = db.prepare(op.sql);
	if (mode === 'first') {
		const row = statement.get(...op.args);
		return row ? { ...row } : null;
	}
	if (mode === 'all') return { success: true, results: statement.all(...op.args).map((row) => ({ ...row })) };
	const result = statement.run(...op.args);
	return { success: true, meta: { changes: Number(result.changes), last_row_id: Number(result.lastInsertRowid) } };
}

function transaction(db, ops, keep, mode = 'run') {
	db.exec('BEGIN IMMEDIATE');
	try {
		const results = ops.map((op) => rawExecute(db, op, mode));
		db.exec(keep ? 'COMMIT' : 'ROLLBACK');
		return results;
	} catch (err) {
		try {
			db.exec('ROLLBACK');
		} catch {}
		throw err;
	}
}

export async function createFirestoreD1({ schema, journal }) {
	if (typeof schema !== 'string' || !schema.trim()) throw new TypeError('The SQLite schema is required');
	if (!journal || typeof journal.load !== 'function' || typeof journal.append !== 'function') throw new TypeError('A durable journal is required');

	const sqlite = new DatabaseSync(':memory:');
	sqlite.exec(schema);
	for (const event of await journal.load()) {
		if (!validEvent(event)) throw new Error('Invalid Olympus Link event in Firestore');
		transaction(sqlite, event.ops, true);
	}

	let tail = Promise.resolve();
	const afterWrites = () => tail;
	const write = (ops, mode = 'run') => {
		const event = eventOf(ops);
		const task = tail.then(async () => {
			// Catch constraints before the durable append. The real commit is the same statements
			// against the same single-writer state, so a bad operation cannot poison the journal.
			transaction(sqlite, event.ops, false, mode);
			await journal.append(event);
			return transaction(sqlite, event.ops, true, mode);
		});
		tail = task.then(
			() => undefined,
			() => undefined,
		);
		return task;
	};

	const statement = (sql, args = []) => ({
		sql: String(sql),
		args,
		bind: (...next) => statement(sql, next),
		async first() {
			if (WRITE.test(String(sql).trim())) return (await write([{ sql: String(sql), args: cleanArgs(args) }], 'first'))[0];
			await afterWrites();
			const row = sqlite.prepare(sql).get(...cleanArgs(args));
			return row ? { ...row } : null;
		},
		async all() {
			if (WRITE.test(String(sql).trim())) return (await write([{ sql: String(sql), args: cleanArgs(args) }], 'all'))[0];
			await afterWrites();
			return { success: true, results: sqlite.prepare(sql).all(...cleanArgs(args)).map((row) => ({ ...row })) };
		},
		async run() {
			if (!WRITE.test(String(sql).trim())) throw new Error('run() accepts a mutation only');
			return (await write([{ sql: String(sql), args: cleanArgs(args) }]))[0];
		},
	});

	return {
		sqlite,
		prepare: (sql) => statement(sql),
		async exec(sql) {
			// Schema is applied locally at construction and is versioned with the image. Runtime
			// callers may execute only reads through prepare; migrations belong in schema.sql.
			throw new Error(`Runtime exec() is disabled; update schema.sql instead (${String(sql).slice(0, 24)})`);
		},
		async batch(list) {
			if (!Array.isArray(list) || list.length === 0) return [];
			const ops = list.map((item) => ({ sql: item.sql, args: cleanArgs(item.args || []) }));
			if (ops.some((op) => !WRITE.test(String(op.sql).trim()))) throw new Error('batch() accepts mutations only');
			return write(ops);
		},
		idle: afterWrites,
	};
}

