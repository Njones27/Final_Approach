import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { emptyTally, isOpen, isUsableVote, scoreOf, standingOf } from '../src/votes/standing.ts';

const rules = { scaleMax: 5, minVotes: 5 };
const tally = (voteCount: number, total: number, weightSum = voteCount) => ({
  voteCount,
  weightSum,
  weightedValueSum: total,
});
const closesAt = '2026-11-27T12:00:00.000Z';
const before = new Date('2026-11-27T11:59:59.999Z');
const atClose = new Date(closesAt);

describe('a vote', () => {
  test('is a whole number of stars from 1 to the top of the scale', () => {
    for (const value of [1, 2, 3, 4, 5]) assert.ok(isUsableVote(value, rules));
    for (const value of [0, 6, -1, 2.5, '4', null, undefined, Number.NaN]) {
      assert.ok(!isUsableVote(value, rules), String(value));
    }
  });
});

describe('the grade the votes give', () => {
  test('runs from 0 for all one star to 100 for all five stars', () => {
    assert.equal(scoreOf(tally(5, 5), rules), 0);
    assert.equal(scoreOf(tally(5, 15), rules), 50);
    assert.equal(scoreOf(tally(5, 20), rules), 75);
    assert.equal(scoreOf(tally(5, 25), rules), 100);
  });

  test('is rounded to a whole number', () => {
    // Three votes of 4, 4, and 5 average 4.33 stars.
    assert.equal(scoreOf(tally(3, 13), rules), 83);
  });

  test('gives a heavier voter more say', () => {
    // A five from a voter of weight 3 and a one from a voter of weight 1.
    assert.equal(scoreOf(tally(2, 16, 4), rules), 75);
  });

  test('follows the scale in the settings', () => {
    assert.equal(scoreOf(tally(2, 14), { scaleMax: 10, minVotes: 1 }), 67);
  });

  test('is 0 with no votes, and stays inside 0 to 100', () => {
    assert.equal(scoreOf(emptyTally, rules), 0);
    assert.equal(scoreOf(tally(1, 9), rules), 100);
    assert.equal(scoreOf(tally(1, 0.5), rules), 0);
  });
});

describe('where a post stands', () => {
  test('it is open for its whole window, however many votes it has', () => {
    assert.ok(isOpen({ closesAt, ...tally(50, 200) }, before, rules));
    assert.deepEqual(standingOf({ closesAt, ...tally(50, 200) }, before, rules), { status: 'voting' });
  });

  test('it closes when the window has ended and it has the votes it needs', () => {
    assert.ok(!isOpen({ closesAt, ...tally(5, 20) }, atClose, rules));
    assert.deepEqual(standingOf({ closesAt, ...tally(5, 20) }, atClose, rules), { status: 'final', score: 75 });
  });

  test('it stays open past its window until it has the votes it needs', () => {
    const muchLater = new Date('2027-06-01T00:00:00.000Z');
    assert.ok(isOpen({ closesAt, ...tally(4, 20) }, muchLater, rules));
    assert.ok(isOpen({ closesAt, ...emptyTally }, muchLater, rules));
    assert.ok(!isOpen({ closesAt, ...tally(5, 20) }, muchLater, rules));
  });

  test('no score is given while voting is open', () => {
    assert.ok(!('score' in standingOf({ closesAt, ...tally(4, 20) }, atClose, rules)));
  });
});
