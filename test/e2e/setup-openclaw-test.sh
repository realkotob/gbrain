#!/bin/bash
set -e

# Wait for Postgres to accept connections (no pg_isready in this image)
echo "Waiting for Postgres..."
for i in $(seq 1 30); do
  if node -e "const net=require('net');const s=net.connect(5432,'postgres',()=>{s.end();process.exit(0)});s.on('error',()=>process.exit(1))" 2>/dev/null; then
    echo "Postgres ready."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Postgres not ready after 30s"
    exit 1
  fi
  sleep 1
done

# Configure OpenClaw test agent with gbrain MCP server
echo "Configuring OpenClaw test agent..."

# Create test agent pointing at gbrain workspace
openclaw agents add gbrain-e2e-test \
  --workspace /app/gbrain \
  --non-interactive 2>/dev/null || true

# Wire gbrain MCP server pointing at the test DB (injected via env)
openclaw mcp set gbrain "{
  \"command\": \"bun\",
  \"args\": [\"run\", \"src/cli.ts\", \"serve\"],
  \"cwd\": \"/app/gbrain\",
  \"env\": {\"DATABASE_URL\": \"${DATABASE_URL}\"}
}" 2>/dev/null

echo "OpenClaw agent configured. Running skill tests..."

# Run the skill tests (OPENCLAW_E2E_DOCKER tells the test to skip local agent setup)
DATABASE_URL="${DATABASE_URL}" \
OPENAI_API_KEY="${OPENAI_API_KEY}" \
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
OPENCLAW_E2E_DOCKER=1 \
  bun test test/e2e/skills.test.ts

EXIT_CODE=$?

# Cleanup
echo "Cleaning up OpenClaw test agent..."
openclaw agents delete gbrain-e2e-test --yes 2>/dev/null || true
openclaw mcp unset gbrain 2>/dev/null || true

exit $EXIT_CODE
