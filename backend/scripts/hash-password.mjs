#!/usr/bin/env node
/**
 * Usage: node scripts/hash-password.mjs "your-strong-password"
 * Paste ADMIN_PASSWORD_HASH=.env output into Railway variables.
 */
import bcrypt from 'bcrypt';

const pwd = process.argv[2];
if (!pwd) {
  console.error('Usage: node scripts/hash-password.mjs "your-password"');
  process.exit(1);
}

const hash = await bcrypt.hash(pwd, 12);
console.log(hash);
