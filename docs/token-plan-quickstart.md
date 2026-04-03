# Quick Start: MiniMax Token Plan for GoClaw

## Your Current Configuration

All 9 GoClaw agents are now configured to use **MiniMax Token Plan** by default:

### Agent Configuration Summary

| Agent | Model | Provider | Purpose |
|-------|-------|----------|---------|
| po (Product Owner) | MiniMax-M2.7 | minimax-token | Requirements gathering |
| techlead (Technical Lead) | MiniMax-M2.7 | minimax-token | Architecture decisions |
| orchestrator | MiniMax-M2.7 | minimax-token | Pipeline coordination |
| be (Backend) | MiniMax-M2.7 | minimax-token | API implementation |
| fe (Frontend) | MiniMax-M2.7 | minimax-token | UI implementation |
| db (Database) | MiniMax-M2.7 | minimax-token | Schema management |
| qa (QA) | MiniMax-M2.5 | minimax-token | Testing (waves 1,3) |
| devops | MiniMax-M2.5 | minimax-token | Infrastructure |
| review | MiniMax-M2.5 | minimax-token | Code review |

**Default Provider:** `minimax-token`
**Endpoint:** `https://api.minimax.io/anthropic`

## Setup Instructions

### 1. Get Your MiniMax Token

Visit https://platform.minimax.io and:
- Sign up or log in
- Navigate to Token Plan section
- Generate your access token
- Copy the token

### 2. Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit .env file
vim .env

# Add your MiniMax token:
MINIMAX_API_KEY=your_token_here
```

### 3. Validate Configuration

```bash
# Validate all configuration files
./scripts/load-config.sh validate
```

Expected output:
```
✓ MiniMax Token Plan (minimax-token) - ENABLED
✓   ✓ po: minimax-token/MiniMax-M2.7
✓   ✓ techlead: minimax-token/MiniMax-M2.7
...
✓ All validation checks passed
```

### 4. Start Pipeline

```bash
# Start GoClaw and Redis
./scripts/start-pipeline.sh

# Or use Docker Compose directly
docker-compose -f /root/docker-compose.goclaw.yml up -d
```

## Using the Configuration

### Check Current Provider

```bash
# Check which provider an agent is using
./scripts/load-config.sh get-provider po
# Output: minimax-token/MiniMax-M2.7
```

### List All Providers

```bash
# List all available providers
./scripts/load-config.sh list-providers
```

### Switch Providers (Optional)

If you want to switch to GPT Codex Plus:

```bash
# Switch techlead to GPT Codex Plus
./scripts/switch-provider.sh techlead gpt-codex-plus

# Verify the change
./scripts/load-config.sh get-provider techlead
# Output: gpt-codex-plus/gpt-codex-plus
```

**Note:** You need to enable `gpt-codex-plus` provider first:

```bash
# Edit providers-config.json
vim .goclaw/providers-config.json

# Change "enabled": false to "enabled": true for gpt-codex-plus
```

## Model Selection

### MiniMax-M2.7 (Latest Generation)

**Used by:** po, techlead, orchestrator, be, fe, db

- Best for: Complex reasoning, architecture, code generation
- Context: 128K tokens
- Cost: $0.00060 per 1K tokens

### MiniMax-M2.5 (Previous Generation)

**Used by:** qa, devops, review

- Best for: Simple tasks, testing, infrastructure
- Context: 128K tokens
- Cost: $0.00048 per 1K tokens (20% cheaper)

## Troubleshooting

### Authentication Failed

```bash
# Check if token is set
echo $MINIMAX_API_KEY

# If empty, add to .env:
vim .env
# Add: MINIMAX_API_KEY=your_token_here

# Source the .env file
source .env
```

### Provider Not Enabled

```bash
# Check provider status
./scripts/load-config.sh list-providers

# If minimax-token is disabled:
vim .goclaw/providers-config.json
# Change "enabled": false to "enabled": true
```

### Connection Timeout

```bash
# Test connectivity to MiniMax API
curl -I https://api.minimax.io

# Check firewall rules
sudo ufw status
```

## Cost Optimization

Current configuration is optimized for cost:

- **6 agents on M2.7** ($0.00060/1K) - Complex tasks requiring latest model
- **3 agents on M2.5** ($0.00048/1K) - Simple tasks where previous gen is sufficient

**Estimated cost per sprint:** ~$0.50-2.00 depending on workload

## Advanced Configuration

### Switch All Agents to M2.5 (Maximum Cost Savings)

```bash
# Edit agents-config.json
vim .goclaw/agents-config.json

# Replace all "MiniMax-M2.7" with "MiniMax-M2.5"
# Use: :%s/MiniMax-M2\.7/MiniMax-M2.5/g
```

### Enable Fallback Provider

```bash
# Set up fallback for critical agents
./scripts/switch-provider.sh orchestrator minimax-token --fallback gpt-codex-plus
```

### Use GPT Codex Plus for Code Generation

```bash
# Enable gpt-codex-plus provider
vim .goclaw/providers-config.json
# Set "enabled": true for gpt-codex-plus

# Switch code-focused agents
./scripts/switch-provider.sh be gpt-codex-plus
./scripts/switch-provider.sh fe gpt-codex-plus
```

## Documentation

- **Full Token Plan Guide:** `docs/minimax-token-plan.md`
- **Dynamic Configuration Guide:** `docs/dynamic-configuration.md`
- **Setup Script:** `goclay-setup.sh`

## Support

For MiniMax token plan issues:
- Platform: https://platform.minimax.io
- Docs: https://platform.minimax.io/docs/token-plan
- Config validation: `./scripts/load-config.sh validate`

## Next Steps

1. ✅ Get MiniMax token from platform
2. ✅ Configure `.env` with token
3. ✅ Validate configuration: `./scripts/load-config.sh validate`
4. ✅ Start pipeline: `./scripts/start-pipeline.sh`
5. ✅ Monitor first sprint execution
6. ✅ Adjust models based on cost/performance needs

Your GoClaw pipeline is now ready to run with MiniMax Token Plan! 🚀
