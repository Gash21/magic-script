# Dynamic Agent Configuration Guide

## Overview

The GoClaw pipeline now supports **dynamic agent configuration** using JSON files instead of static markdown files. This enables:

- ✅ **Per-agent LLM provider selection** - Different agents can use different providers
- ✅ **Multiple provider support** - MiniMax, OpenAI, Anthropic, and more
- ✅ **Runtime configuration changes** - Switch providers without restarting containers
- ✅ **Provider fallback mechanisms** - Automatic failover if primary provider fails
- ✅ **Cost optimization** - Use cheaper providers for simple tasks, premium for complex
- ✅ **Model-specific configuration** - Temperature, max tokens per agent

## Quick Start

### For New Installations

```bash
# 1. Run setup script (creates JSON configs automatically)
sudo ./goclay-setup.sh

# 2. Configure .env with your API keys
cp .env.example .env
vim .env  # Add MINIMAX_API_KEY (required), optionally OPENAI_API_KEY, ANTHROPIC_API_KEY

# 3. Validate configuration
./scripts/load-config.sh validate

# 4. Start pipeline
./scripts/start-pipeline.sh
```

### For Existing Installations

```bash
# 1. Run migration script
./scripts/migrate-to-dynamic-config.sh

# 2. Verify configuration
./scripts/load-config.sh validate

# 3. Restart GoClaw
docker-compose -f /root/docker-compose.goclaw.yml restart
```

## Configuration Files

### 1. Agent Configuration (`~/.goclaw/agents-config.json`)

Defines LLM settings for each agent:

```json
{
  "version": "1.0",
  "default_provider": "minimax",
  "agents": {
    "po": {
      "name": "Product Owner",
      "provider": "minimax",
      "model": "abab6.5s-chat",
      "temperature": 0.7,
      "max_tokens": 4000,
      "fallback": null,
      "waves": ["1", "2", "3"]
    },
    "techlead": {
      "name": "Technical Lead",
      "provider": "minimax",
      "model": "abab6.5s-chat",
      "temperature": 0.3,
      "max_tokens": 8000,
      "fallback": null,
      "waves": ["1", "2", "3"]
    }
  }
}
```

**Agent IDs:** `po`, `techlead`, `orchestrator`, `be`, `fe`, `db`, `qa`, `devops`, `review`

### 2. Provider Registry (`~/.goclaw/providers-config.json`)

Defines available LLM providers:

```json
{
  "version": "1.0",
  "providers": {
    "minimax": {
      "name": "MiniMax",
      "api_key_env": "MINIMAX_API_KEY",
      "base_url": "https://api.minimax.chat/v1",
      "models": {
        "abab6.5s-chat": {
          "name": "abab6.5s-chat",
          "max_tokens": 8192,
          "input_cost_per_1k": 0.00015,
          "output_cost_per_1k": 0.0006
        }
      },
      "rate_limit": {
        "requests_per_minute": 20,
        "tokens_per_minute": 30000
      },
      "enabled": true
    },
    "openai": {
      "name": "OpenAI",
      "api_key_env": "OPENAI_API_KEY",
      "base_url": "https://api.openai.com/v1",
      "models": { ... },
      "enabled": false
    }
  }
}
```

**Provider IDs:** `minimax`, `openai`, `anthropic`

## Using the Configuration System

### Validate Configuration

Check all configuration files for errors:

```bash
./scripts/load-config.sh validate
```

**Output:**
```
==========================================
Validating Configuration
==========================================

Validating agents configuration...
✓ agents-config.json is valid JSON
✓ Found 9 agents
✓   ✓ po: minimax/abab6.5s-chat
✓   ✓ techlead: minimax/abab6.5s-chat
...

Validating providers configuration...
✓ providers-config.json is valid JSON
✓ Found 3 providers
✓   ✓ MiniMax (minimax) - ENABLED
⚠   ⚠ OpenAI (openai) - DISABLED
⚠   ⚠ Anthropic (anthropic) - DISABLED

✓ All validation checks passed
```

### Get Provider for an Agent

Check which provider an agent is using:

```bash
./scripts/load-config.sh get-agent po
# Output: minimax/abab6.5s-chat
```

### List All Configurations

View all agent configurations:

```bash
./scripts/load-config.sh list-agents
```

View all available providers:

```bash
./scripts/load-config.sh list-providers
```

### Switch Provider at Runtime

Change an agent to use a different provider:

```bash
# Switch techlead to OpenAI
./scripts/switch-provider.sh techlead openai

# Switch po to MiniMax with OpenAI fallback
./scripts/switch-provider.sh po minimax --fallback openai

# Switch be to Anthropic without triggering reload
./scripts/switch-provider.sh be anthropic --no-reload
```

**The script will:**
1. Validate the agent exists
2. Validate the provider exists and is enabled
3. Update `agents-config.json`
4. Backup the old config to `agents-config.json.backup`
5. Trigger GoClaw configuration reload (unless `--no-reload` is specified)

### Export Environment Variables

Export configuration for GoClaw container:

```bash
./scripts/load-config.sh export-env > /tmp/goclaw-env.sh
source /tmp/goclaw-env.sh
```

## Docker Compose Configuration

### Required Environment Variables

Update your `/root/docker-compose.goclaw.yml`:

```yaml
version: '3.8'

services:
  goclaw-pipeline:
    image: your-goclaw-image
    container_name: goclaw-pipeline

    environment:
      # Existing variables
      - GOCLAW_OPENAI_API_KEY=${OPENAI_API_KEY:-}
      - GOCLAW_MINIMAX_API_KEY=${MINIMAX_API_KEY:-}
      - GOCLAW_TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN:-}
      - GOCLAW_TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID:-}

      # NEW: Additional providers
      - GOCLAW_ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}

      # NEW: Configuration settings
      - GOCLAW_DEFAULT_PROVIDER=${DEFAULT_PROVIDER:-minimax}
      - GOCLAW_CONFIG_HOT_RELOAD=${CONFIG_HOT_RELOAD:-true}

    # NEW: Mount configuration directory
    volumes:
      - /root/.goclaw:/root/.goclaw
      - ./.goclaw:/workspace/.goclaw:ro  # Read-only mount for config

    # ... other configuration
```

### Configuration Directory Mount

**Read-Only Mount:** `./.goclaw:/workspace/.goclaw:ro`

This allows GoClaw to read the JSON configuration files from the workspace while preventing the container from modifying them.

### Applying Docker Compose Changes

```bash
# 1. Edit docker-compose.goclaw.yml
vim /root/docker-compose.goclaw.yml

# 2. Restart container
docker-compose -f /root/docker-compose.goclaw.yml down
docker-compose -f /root/docker-compose.goclaw.yml up -d

# 3. Verify configuration is loaded
docker logs goclaw-pipeline | grep -i "provider\|config"
```

## Adding New Providers

### 1. Get API Key

Obtain an API key from your chosen provider:
- **OpenAI**: https://platform.openai.com/api-keys
- **Anthropic**: https://console.anthropic.com/settings/keys
- **MiniMax**: https://api.minimax.chat/

### 2. Add to `.env`

```bash
# Edit .env file
vim .env

# Add your API key
OPENAI_API_KEY=sk-...
# or
ANTHROPIC_API_KEY=sk-ant-...
```

### 3. Enable Provider in Config

Edit `~/.goclaw/providers-config.json`:

```json
{
  "providers": {
    "openai": {
      "name": "OpenAI",
      "api_key_env": "OPENAI_API_KEY",
      "base_url": "https://api.openai.com/v1",
      "models": { ... },
      "enabled": true  # <-- Change from false to true
    }
  }
}
```

### 4. Validate and Reload

```bash
# Validate configuration
./scripts/load-config.sh validate

# If GoClaw is running, reload configuration
./scripts/load-config.sh reload
```

## Cost Optimization Strategy

### Provider Selection Guide

| Task Type | Recommended Provider | Model | Cost (per 1K tokens) |
|-----------|---------------------|-------|---------------------|
| Simple tasks (PO, QA, DevOps) | MiniMax | abab6-chat | $0.00060 |
| Medium complexity (FE, DB, Review) | MiniMax | abab6.5s-chat | $0.00075 |
| Complex tasks (TechLead, BE) | OpenAI | gpt-4o-mini | $0.00060 |
| Critical tasks (Architecture) | OpenAI | gpt-4o | $0.01000 |
| Reasoning-heavy tasks | Anthropic | claude-3-5-sonnet | $0.01500 |

### Example: Cost-Optimized Configuration

```bash
# Simple agents on cheapest provider
./scripts/switch-provider.sh po minimax
./scripts/switch-provider.sh qa minimax
./scripts/switch-provider.sh devops minimax

# Medium complexity on MiniMax
./scripts/switch-provider.sh fe minimax
./scripts/switch-provider.sh db minimax
./scripts/switch-provider.sh review minimax

# Complex tasks on OpenAI (with fallback)
./scripts/switch-provider.sh techlead openai --fallback minimax
./scripts/switch-provider.sh be openai --fallback minimax

# Most critical on Anthropic (with double fallback)
./scripts/switch-provider.sh orchestrator anthropic --fallback openai
```

**Estimated savings:** 60-80% compared to all-OpenAI setup

## Migration Guide

### From Static .md Files to JSON Configuration

The migration script automatically:
1. Backs up existing `.goclaw/agents/` directory
2. Creates `agents-config.json` with MiniMax defaults
3. Creates `providers-config.json` with all providers
4. Validates new configuration
5. Preserves old `.md` files in backup

### Running Migration

```bash
# Run migration
./scripts/migrate-to-dynamic-config.sh

# Output:
# [STEP] Running pre-flight checks...
# [✓] Pre-flight checks passed
# [STEP] Creating backup...
# [✓] Backup created at: /root/.goclaw/.backup_20240101_120000
# [STEP] Creating dynamic configuration...
# [✓] Migration complete!
```

### Rollback (If Needed)

```bash
# Rollback to static .md files
./scripts/migrate-to-dynamic-config.sh rollback

# Output:
# [STEP] Rolling back migration...
# [✓] Restored agents directory from backup
# [✓] Rollback complete
```

### Backup Location

Backups are stored in: `~/.goclaw/.backup_YYYYMMDD_HHMMSS/`

## Troubleshooting

### Configuration Validation Failed

**Problem:** `./scripts/load-config.sh validate` fails

**Solution:**
```bash
# Check JSON syntax
cat ~/.goclaw/agents-config.json | jq .

# Check for missing providers
./scripts/load-config.sh list-agents

# Verify provider references
jq '.agents[].provider' ~/.goclaw/agents-config.json | sort -u
jq '.providers | keys[]' ~/.goclaw/providers-config.json
```

### Provider Not Enabled

**Problem:** `Provider is not enabled: openai`

**Solution:**
```bash
# 1. Add API key to .env
vim .env
# Add: OPENAI_API_KEY=sk-...

# 2. Enable provider in config
vim ~/.goclaw/providers-config.json
# Set: "enabled": true

# 3. Validate
./scripts/load-config.sh validate
```

### GoClaw Not Loading Configuration

**Problem:** GoClaw still uses old configuration after switching providers

**Solution:**
```bash
# Manual reload
./scripts/load-config.sh reload

# Or restart container
docker-compose -f /root/docker-compose.goclaw.yml restart

# Check logs
docker logs goclaw-pipeline | tail -50
```

### Agent Not Found

**Problem:** `Agent not found: xxx`

**Solution:**
```bash
# List all available agents
./scripts/load-config.sh list-agents

# Valid agent IDs: po, techlead, orchestrator, be, fe, db, qa, devops, review
```

### Missing API Key

**Problem:** Provider fails with authentication error

**Solution:**
```bash
# Check if API key is set
echo $MINIMAX_API_KEY
echo $OPENAI_API_KEY
echo $ANTHROPIC_API_KEY

# If empty, add to .env
vim .env
```

## Advanced Usage

### Per-Agent Temperature Tuning

Edit `~/.goclaw/agents-config.json`:

```json
{
  "agents": {
    "creative": {
      "temperature": 0.9  // More creative
    },
    "analytical": {
      "temperature": 0.1  // More focused
    }
  }
}
```

### Custom Max Tokens

```json
{
  "agents": {
    "long-form": {
      "max_tokens": 8000
    },
    "short-form": {
      "max_tokens": 2000
    }
  }
}
```

### Wave-Specific Configuration

```json
{
  "agents": {
    "qa": {
      "waves": ["1", "3"]  // Only active in waves 1 and 3
    }
  }
}
```

## Best Practices

1. **Start with MiniMax** - Cheapest, works well for most tasks
2. **Use fallback providers** - Prevents pipeline failures if primary provider is down
3. **Test after switching** - Validate configuration before running critical sprints
4. **Monitor costs** - Check provider dashboards for usage
5. **Keep backups** - Migration script creates automatic backups
6. **Document custom configs** - Note why you chose specific providers/models

## Support

For issues or questions:
- Check logs: `docker logs goclaw-pipeline`
- Validate config: `./scripts/load-config.sh validate`
- Check provider status: `./scripts/load-config.sh list-providers`

## Configuration File Reference

### agents-config.json Schema

```typescript
{
  "version": "1.0",                    // Configuration version
  "default_provider": "minimax",       // Default provider for agents
  "agents": {
    "<agent_id>": {
      "name": "Display Name",          // Human-readable name
      "provider": "minimax",           // Provider ID
      "model": "abab6.5s-chat",        // Model name
      "temperature": 0.7,              // 0.0 - 1.0 (creative)
      "max_tokens": 4000,              // Maximum response length
      "fallback": "openai",            // Optional fallback provider
      "waves": ["1", "2", "3"]        // Active wave numbers
    }
  }
}
```

### providers-config.json Schema

```typescript
{
  "version": "1.0",                    // Configuration version
  "providers": {
    "<provider_id>": {
      "name": "Provider Name",         // Display name
      "api_key_env": "API_KEY_ENV",    // Environment variable name
      "base_url": "https://...",       // API base URL
      "models": {
        "<model_id>": {
          "name": "model-name",        // Model identifier
          "max_tokens": 8192,          // Context window
          "input_cost_per_1k": 0.00015,
          "output_cost_per_1k": 0.0006
        }
      },
      "rate_limit": {
        "requests_per_minute": 20,
        "tokens_per_minute": 30000
      },
      "enabled": true                  // Is provider available?
    }
  }
}
```

## Changelog

### Version 1.0 (2024-01-01)
- Initial release of dynamic configuration system
- Support for MiniMax, OpenAI, Anthropic
- Runtime provider switching
- Provider fallback mechanism
- Configuration validation and migration tools
