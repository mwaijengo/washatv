import { randomUUID } from 'node:crypto';
import type { FastifyReply } from 'fastify';

/**
 * In-process SSE broadcast. For multiple Railway replicas, add Redis pub/sub or Postgres NOTIFY.
 */
export class SseHub {
  private readonly clients = new Set<{ reply: FastifyReply; id: string }>();

  subscribe(reply: FastifyReply): string {
    const id = randomUUID();
    this.clients.add({ reply, id });
    reply.raw.on('close', () => this.drop(reply));
    return id;
  }

  private drop(reply: FastifyReply) {
    for (const c of this.clients) {
      if (c.reply === reply) this.clients.delete(c);
    }
  }

  broadcast(event: string, data: Record<string, unknown>) {
    const payload = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
    for (const { reply } of this.clients) {
      try {
        reply.raw.write(payload);
      } catch {
        /* ignore broken pipes */
      }
    }
  }

  notifyConfigVersion(version: number) {
    this.broadcast('config', { version, at: new Date().toISOString() });
  }
}
