/**
 * Quick regression checks for SonicPesa status parsing.
 * Run: npx tsx src/lib/sonicpesa.status.test.ts
 */
import {
  isSonicpesaFailure,
  isSonicpesaSuccess,
  readPaymentStatus,
} from './sonicpesa.js';

function assert(cond: boolean, msg: string) {
  if (!cond) throw new Error(msg);
}

const cases: Array<{ name: string; raw: Record<string, unknown>; expect: string }> = [
  {
    name: 'nested data.status success (API envelope + paid)',
    raw: { status: 'success', data: { status: 'success', order_id: 'sp_1', amount: 25000 } },
    expect: 'SUCCESS',
  },
  {
    name: 'top-level status success with order context',
    raw: { status: 'success', order_id: 'sp_1', amount: 25000 },
    expect: 'SUCCESS',
  },
  {
    name: 'payment_status SUCCESS preferred',
    raw: { status: 'success', payment_status: 'SUCCESS', order_id: 'sp_1' },
    expect: 'SUCCESS',
  },
  {
    name: 'order_status completed',
    raw: { status: 'success', data: { order_status: 'completed', order_id: 'sp_1' } },
    expect: 'COMPLETED',
  },
  {
    name: 'nested failed is payment failure not API error',
    raw: { status: 'success', data: { status: 'failed', order_id: 'sp_1', amount: 1000 } },
    expect: 'FAILED',
  },
  {
    name: 'pending stays pending',
    raw: { status: 'success', data: { status: 'pending', order_id: 'sp_1' } },
    expect: 'PENDING',
  },
  {
    name: 'bare transport success without order → pending',
    raw: { status: 'success' },
    expect: 'PENDING',
  },
];

for (const c of cases) {
  const got = readPaymentStatus(c.raw);
  assert(got === c.expect, `${c.name}: expected ${c.expect}, got ${got}`);
}

assert(isSonicpesaSuccess(readPaymentStatus(cases[0].raw)), 'success detected');
assert(isSonicpesaFailure(readPaymentStatus(cases[4].raw)), 'failure detected');

console.log(`ok — ${cases.length} sonicpesa status cases passed`);
