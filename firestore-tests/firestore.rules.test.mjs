/**
 * Firestore security rules tests (run with Firestore emulator).
 *
 * From repo root: npm install && npm run test:firestore-rules
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, Timestamp } from 'firebase/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(join(__dirname, '..', 'firestore.rules'), 'utf8');

const projectId = 'demo-cards-firestore-rules';

/** @type {import('@firebase/rules-unit-testing').RulesTestEnvironment | undefined} */
let testEnv;

function profilePayload(partial = {}) {
  return {
    displayName: 'Test',
    updatedAt: Timestamp.now(),
    profileLastChangedAt: Timestamp.now(),
    ...partial,
  };
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv?.cleanup();
});

describe('metadata/online_count', () => {
  it('allows unauthenticated read', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(getDoc(doc(db, 'metadata', 'online_count')));
  });

  it('denies unauthenticated write', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(db, 'metadata', 'online_count'), { n: 1 }));
  });

  it('denies authenticated write', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(setDoc(doc(db, 'metadata', 'online_count'), { n: 1 }));
  });
});

describe('users/{uid}', () => {
  it('allows self read when authenticated', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(getDoc(doc(db, 'users', 'alice')));
  });

  it('allows read of another user doc when authenticated', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(getDoc(doc(db, 'users', 'bob')));
  });

  it('denies unauthenticated read', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'users', 'alice')));
  });

  it('allows create with only whitelisted fields', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'users', 'alice'), profilePayload({ displayName: 'Alice' })),
    );
  });

  it('denies create with extra fields', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      setDoc(doc(db, 'users', 'alice'), {
        ...profilePayload(),
        isAdmin: true,
      }),
    );
  });

  it('allows merge update with whitelisted fields only', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    const ref = doc(db, 'users', 'alice');
    await assertSucceeds(setDoc(ref, profilePayload({ displayName: 'A' })));
    await assertSucceeds(
      setDoc(
        ref,
        {
          displayName: 'Alice2',
          updatedAt: Timestamp.now(),
          profileLastChangedAt: Timestamp.now(),
        },
        { merge: true },
      ),
    );
  });

  it('allows avatarUrl set to null (clear avatar)', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    const ref = doc(db, 'users', 'alice');
    await assertSucceeds(setDoc(ref, profilePayload({ displayName: 'A' })));
    await assertSucceeds(
      setDoc(
        ref,
        {
          avatarUrl: null,
          updatedAt: Timestamp.now(),
          profileLastChangedAt: Timestamp.now(),
        },
        { merge: true },
      ),
    );
  });

  it('denies write to another user doc even with valid fields', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      setDoc(doc(db, 'users', 'bob'), profilePayload({ displayName: 'Hijack' })),
    );
  });

  it('denies delete of own profile (delete not allowed)', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    const ref = doc(db, 'users', 'alice');
    await assertSucceeds(setDoc(ref, profilePayload({ displayName: 'Alice' })));
    await assertFails(deleteDoc(ref));
  });
});

describe('ranked_stats/{uid}', () => {
  it('denies read when unauthenticated', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'ranked_stats', 'alice')));
  });

  it('allows read when authenticated', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(getDoc(doc(db, 'ranked_stats', 'alice')));
  });

  it('denies client write', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      setDoc(doc(db, 'ranked_stats', 'alice'), { displayName: 'x', wins: 1 }),
    );
  });
});

describe('leaderboard_single_player/{uid}', () => {
  it('denies read when unauthenticated', async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'leaderboard_single_player', 'alice')));
  });

  it('allows own write', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'leaderboard_single_player', 'alice'),
        { displayName: 'A', wins: 1, losses: 0, gamesPlayed: 1 },
        { merge: true },
      ),
    );
  });

  it('denies write to another uid', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      setDoc(
        doc(db, 'leaderboard_single_player', 'bob'),
        { displayName: 'X', wins: 999 },
        { merge: true },
      ),
    );
  });
});

describe('leaderboard_online/{uid} (server-only writes)', () => {
  it('denies client write for own uid', async () => {
    const db = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      setDoc(
        doc(db, 'leaderboard_online', 'alice'),
        { displayName: 'A', wins: 1 },
        { merge: true },
      ),
    );
  });
});

/** Mirrors rules: same pattern as leaderboard_single_player (auth uid === doc id). */
const clientWritableLeaderboardCollections = [
  'leaderboard_tournament_ai',
  'leaderboard_bust_offline',
];

for (const collection of clientWritableLeaderboardCollections) {
  describe(`${collection}/{uid} (client-writable)`, () => {
    it('allows own write', async () => {
      const db = testEnv.authenticatedContext('alice').firestore();
      await assertSucceeds(
        setDoc(
          doc(db, collection, 'alice'),
          { displayName: 'A', wins: 1, losses: 0, gamesPlayed: 1 },
          { merge: true },
        ),
      );
    });

    it('denies write to another uid', async () => {
      const db = testEnv.authenticatedContext('alice').firestore();
      await assertFails(
        setDoc(
          doc(db, collection, 'bob'),
          { displayName: 'X', wins: 999 },
          { merge: true },
        ),
      );
    });
  });
}

/** Same rule shape as leaderboard_online — guards copy/paste drift in firestore.rules */
const serverOnlyLeaderboardCollections = [
  'leaderboard_tournament_online',
  'leaderboard_bust_online',
];

for (const collection of serverOnlyLeaderboardCollections) {
  describe(`${collection}/{uid} (server-only writes)`, () => {
    it('denies client write for own uid', async () => {
      const db = testEnv.authenticatedContext('alice').firestore();
      await assertFails(
        setDoc(
          doc(db, collection, 'alice'),
          { displayName: 'A', wins: 1 },
          { merge: true },
        ),
      );
    });
  });
}
