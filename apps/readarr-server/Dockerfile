FROM oven/bun:1.2-slim

RUN chown bun:bun .
USER bun

COPY package.json bun.lock ./
RUN bun install --frozen-lockfile --production

COPY . .

ENV NODE_ENV=production
CMD ["bun", "start"]
