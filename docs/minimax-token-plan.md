# MiniMax Token Plan Setup Guide

## Overview

The GoClaw pipeline now supports **MiniMax Token Plan**, an OAuth-based authentication method that provides access to MiniMax's LLM models through token-based API endpoints.

**Benefits:**
- ✅ **Token-based authentication** - No need for API keys
- ✅ **Multiple model access** - M2.5 and M2.7 models
- ✅ **Cost-effective** - Token plans often cheaper than direct API
- ✅ **OpenAI-compatible endpoints** - Easy integration
- ✅ **Anthropic-compatible endpoints** - Claude-like API

## Available MiniMax Endpoints

### 1. Anthropic-Compatible Endpoint (Recommended)

**Endpoint:** `https://api.minimax.io/anthropic`

**Models:**
- `MiniMax-M2.7` - Latest generation, 128K context
- `MiniMax-M2.5` - Previous generation, 128K context

**Provider ID:** `minimax-token`

**Authentication:** Uses `x-api-key` header with your MiniMax token

**Configuration:**
```json
{
  "provider": "minimax-token",
  "model": "MiniMax-M2.7",
  "base_url": "https://api.minimax.io/anthropic"
}
```

### 2. OpenAI-Compatible Endpoint

**Endpoint:** `https://api.minimax.io/openai`

**Models:**
- `gpt-codex-plus` - GPT-based code generation model

**Provider ID:** `gpt-codex-plus`

**Authentication:** Uses `authorization: Bearer <token>` header

**Configuration:**
```json
{
  "provider": "gpt-codex-plus",
  "model": "gpt-codex-plus",
  "base_url": "https://api.minimax.io/openai"
}
```

## Quick Start

### Step 1: Get Your MiniMax Token

1. Visit the MiniMax platform: https://platform.minimax.io
2. Sign up or log in
3. Navigate to the token plan section
4. Generate your access token
5. Copy the token for configuration

### Step 2: Configure Environment Variables

Edit your `.env` file:

```bash
# MiniMax Token Plan (required)
MINIMAX_API_KEY=your_token_here

# Optional: If using OpenAI-compatible endpoint
OPENAI_API_KEY=your_openai_token_here
```

### Step 3: Enable Token Plan Provider

Edit `.goclaw/providers-config.json`:

```json
{
  "providers": {
    "minimax-token": {
      "enabled": true
    }
  }
}
```

### Step 4: Validate Configuration

```bash
./scripts/load-config.sh validate
```

Expected output:
```
✓ MiniMax Token Plan (minimax-token) - ENABLED
✓   ✓ po: minimax-token/MiniMax-M2.7
```

## Provider Configuration

### Anthropic-Compatible (Default for All Agents)

**Use for:** General-purpose tasks, complex reasoning, code generation

```json
{
  "minimax-token": {
    "name": "MiniMax Token Plan",
    "api_key_env": "MINIMAX_API_KEY",
    "base_url": "https://api.minimax.io/anthropic",
    "auth_header": "x-api-key",
    "auth_type": "anthropic-compatible",
    "models": {
      "MiniMax-M2.7": {
        "name": "MiniMax-M2.7",
        "max_tokens": 128000,
        "input_cost_per_1k": 0.00015,
        "output_cost_per_1k": 0.0006
      }
    },
    "enabled": true
  }
}
```

**Agent assignments:**
- `po`, `techlead`, `orchestrator`, `be`, `fe`, `db` → `MiniMax-M2.7`
- `qa`, `devops`, `review` → `MiniMax-M2.5` (cost optimization)

### OpenAI-Compatible (Optional)

**Use for:** Code-specific tasks, when OpenAI API is unavailable

```json
{
  "gpt-codex-plus": {
    "name": "GPT Codex Plus",
    "api_key_env": "OPENAI_API_KEY",
    "base_url": "https://api.minimax.io/openai",
    "auth_header": "authorization",
    "auth_type": "bearer-token",
    "models": {
      "gpt-codex-plus": {
        "name": "gpt-codex-plus",
        "max_tokens": 128000,
        "input_cost_per_1k": 0.00015,
        "output_cost_per_1k": 0.0006
      }
    },
    "enabled": false
  }
}
```

## Switching Between Providers

### Use Anthropic-Compatible Endpoint (Default)

All agents are configured to use `minimax-token` with `MiniMax-M2.7` by default:

```bash
# Verify current configuration
./scripts/load-config.sh get-provider po
# Output: minimax-token/MiniMax-M2.7

# Switch specific agent to M2.5 (cheaper)
vim .goclaw/agents-config.json
# Change "model": "MiniMax-M2.7" to "model": "MiniMax-M2.5"
```

### Switch to OpenAI-Compatible Endpoint

```bash
# Switch agent to GPT Codex Plus
./scripts/switch-provider.sh techlead gpt-codex-plus

# Verify
./scripts/load-config.sh get-provider techlead
# Output: gpt-codex-plus/gpt-codex-plus
```

## Model Selection Guide

| Task Type | Recommended Model | Provider | Cost (per 1K tokens) |
|-----------|------------------|----------|---------------------|
| Product Owner | MiniMax-M2.7 | minimax-token | $0.00060 |
| Technical Lead | MiniMax-M2.7 | minimax-token | $0.00060 |
| Backend/Frontend | MiniMax-M2.7 | minimax-token | $0.00060 |
| Code Generation | gpt-codex-plus | gpt-codex-plus | $0.00060 |
| QA/DevOps | MiniMax-M2.5 | minimax-token | $0.00048 |
| Code Review | MiniMax-M2.5 | minimax-token | $0.00048 |

## Environment Variables

### Required

```bash
MINIMAX_API_KEY=your_token_here  # Required for minimax-token provider
```

### Optional (for GPT Codex Plus)

```bash
OPENAI_API_KEY=your_openai_token_here  # Required for gpt-codex-plus provider
```

### Configuration

```bash
DEFAULT_PROVIDER=minimax-token  # Use MiniMax token plan by default
CONFIG_HOT_RELOAD=true          # Reload config without restart
```

## Troubleshooting

### Authentication Errors

**Problem:** `401 Unauthorized` or `authentication failed`

**Solution:**
```bash
# Verify token is set
echo $MINIMAX_API_KEY

# Check token format (should be long string)
# Re-generate token if expired at https://platform.minimax.io
```

### Provider Not Enabled

**Problem:** `Provider is not enabled: minimax-token`

**Solution:**
```bash
# Edit providers-config.json
vim .goclaw/providers-config.json

# Change "enabled": false to "enabled": true
```

### Model Not Found

**Problem:** `Model not found: MiniMax-M2.7`

**Solution:**
```bash
# Validate configuration
./scripts/load-config.sh validate

# Check provider supports the model
./scripts/load-config.sh list-providers
```

### Network Issues

**Problem:** `Connection timeout` or `DNS resolution failed`

**Solution:**
```bash
# Test connectivity to MiniMax API
curl -I https://api.minimax.io

# Check firewall rules
sudo ufw status

# Test with verbose curl
curl -v https://api.minimax.io/anthropic/v1/messages
```

## Migration from Standard MiniMax API

If you were previously using the standard MiniMax API (`api.minimax.chat`):

### Old Configuration (API Key)

```json
{
  "minimax": {
    "base_url": "https://api.minimax.chat/v1",
    "api_key_env": "MINIMAX_API_KEY",
    "models": ["abab6.5s-chat", "abab6-chat"]
  }
}
```

### New Configuration (Token Plan)

```json
{
  "minimax-token": {
    "base_url": "https://api.minimax.io/anthropic",
    "api_key_env": "MINIMAX_API_KEY",
    "models": ["MiniMax-M2.7", "MiniMax-M2.5"]
  }
}
```

### Migration Steps

1. **Backup current configuration:**
   ```bash
   cp .goclaw/agents-config.json .goclaw/agents-config.json.backup
   cp .goclaw/providers-config.json .goclaw/providers-config.json.backup
   ```

2. **Update provider in agents-config.json:**
   ```bash
   # Find and replace "minimax" with "minimax-token"
   vim .goclaw/agents-config.json
   ```

3. **Update model names:**
   - `abab6.5s-chat` → `MiniMax-M2.7`
   - `abab6-chat` → `MiniMax-M2.5`

4. **Validate:**
   ```bash
   ./scripts/load-config.sh validate
   ```

## Cost Comparison

### MiniMax Token Plan vs Standard API

| Model | Token Plan | Standard API | Savings |
|-------|-----------|--------------|---------|
| M2.7 | $0.00060/1K | N/A | N/A |
| M2.5 | $0.00048/1K | N/A | N/A |
| GPT Codex Plus | $0.00060/1K | N/A | N/A |

**Note:** Token plan pricing is often more competitive than direct API access.

## Advanced Configuration

### Custom Temperature Settings

Different models may require different temperature settings:

```json
{
  "agents": {
    "po": {
      "temperature": 0.7  // Higher creativity for requirements
    },
    "techlead": {
      "temperature": 0.3  // Lower for technical precision
    },
    "review": {
      "temperature": 0.2  // Lowest for code review
    }
  }
}
```

### Fallback Configuration

Set up fallback providers if primary fails:

```bash
# Configure fallback for critical agents
./scripts/switch-provider.sh orchestrator minimax-token --fallback gpt-codex-plus
```

### Wave-Specific Model Selection

Use cheaper models for specific waves:

```json
{
  "qa": {
    "model": "MiniMax-M2.5",
    "waves": ["1", "3"]  // Only active in waves 1 and 3
  }
}
```

## Best Practices

1. **Start with MiniMax-M2.7** - Best performance for most tasks
2. **Use M2.5 for simple tasks** - Cost optimization for QA, DevOps
3. **Set up fallbacks** - Prevent pipeline failures if primary provider is down
4. **Monitor token usage** - Check MiniMax platform dashboard
5. **Test after configuration changes** - Validate before running critical sprints

## Support

For issues or questions:
- MiniMax Platform: https://platform.minimax.io
- Token Plan Docs: https://platform.minimax.io/docs/token-plan
- Configuration Validation: `./scripts/load-config.sh validate`
- Provider Status: `./scripts/load-config.sh list-providers`

## Changelog

### Version 1.0 (2026-04-04)
- Initial MiniMax Token Plan support
- Anthropic-compatible endpoint (`/anthropic`)
- OpenAI-compatible endpoint (`/openai`)
- M2.5 and M2.7 model support
- GPT Codex Plus integration
- OAuth-based authentication
