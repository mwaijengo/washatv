import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().default(8080),
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(16).default('dev-only-change-this-jwt-secret-please'),
  ADMIN_EMAIL: z.string().email().optional(),
  ADMIN_PASSWORD_HASH: z.string().min(20).optional(),
  ADMIN_API_KEY: z.string().optional(),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  CORS_ORIGIN: z.string().default('*'),
});

export type Env = z.infer<typeof envSchema>;

export function loadEnv(): Env {
  const parsed = envSchema.safeParse(process.env);
  if (!parsed.success) {
    console.error('Invalid environment:', parsed.error.flatten().fieldErrors);
    throw new Error('Missing or invalid environment variables');
  }
  const env = parsed.data;
  if (env.NODE_ENV === 'production' && env.JWT_SECRET == 'dev-only-change-this-jwt-secret-please') {
    console.warn('[env] JWT_SECRET is using development default. Set a strong value in Railway variables.');
  }
  return env;
}
