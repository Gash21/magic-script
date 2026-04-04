# Dynamic Agent Configuration Implementation Plan for GoClaw Pipeline System

## Executive Summary

This plan outlines a comprehensive approach to add dynamic agent configuration to the GoClaw pipeline system, replacing static `.md` agent definitions with a flexible JSON/YAML-based configuration system. The design prioritizes:

1. **Multi-provider support** (Minimax, OpenAI, Anthropic, etc.)
2. **Per-agent LLM configuration** with provider switching
3. **Cost optimization** for users with limited provider access
4. **Backward compatibility** with existing pipeline-state.json
5. **Runtime configuration loading** without requiring full setup script reruns

---

## 1. Current State Analysis

### Existing Architecture (from `goclay-setup.sh`)

**Static Agent Definitions** (Lines 421-621):
- Agents defined as markdown files in `.goclaw/agents/*.md`
- 9 agents: po, techlead, orchestrator, be, fe, db, qa, devops, review
- Each agent has: Responsibilities, Wave Activities, Success Criteria

**Pipeline State** (Lines 626-763):
- `pipeline-state.json`: Tracks agent status (idle/running/error)
- `agent-responsibilities.json`: Maps agents to responsibilities and waves
- Static structure, hardcoded in setup script

**Environment Configuration** (Lines 772-804):
- `.env.example`: Only supports OPENAI_API_KEY and MINIMAX_API_KEY
- No per-agent provider selection
- No model configuration parameters

**Docker Compose** (Lines 290-314):
- Environment variables: GOCLAW_OPENAI_API_KEY, GOCLAW_MINIMAX_API_KEY
- No mechanism for per-agent provider routing

### Limitations

1. **Static configuration**: Requires running setup script to change agents
2. **No provider flexibility**: All agents use same provider (hardcoded)
3. **No cost optimization**: Cannot route specific agents to cheaper providers
4. **No model selection**: Cannot configure temperature, max_tokens per agent
5. **No failover**: No fallback providers if primary fails

---

## 2. New Configuration System Design

### 2.1 Configuration File Structure

The new system introduces two main configuration files:

#### A. Agent Configuration (`agents-config.json`)
Defines per-agent LLM settings including provider, model, temperature, max_tokens, and fallback configuration.

#### B. Provider Registry (`providers-config.json`)
Defines available LLM providers with their models, pricing, rate limits, and capabilities.

Both files use JSON format for easy parsing and validation.

---

## 3. Critical Files for Implementation

### Configuration Files

1. `/Users/galiharghubi/Work/personal/personal-script/.goclaw/agents-config.json`
   - Main agent configuration
   - Per-agent LLM settings
   - Provider assignments and fallbacks

2. `/Users/galiharghubi/Work/personal/personal-script/.goclaw/providers-config.json`
   - Provider registry
   - Model definitions and pricing
   - Rate limits and capabilities

3. `/Users/galiharghubi/Work/personal/personal-script/.env.example`
   - Updated environment template
   - Support for multiple provider API keys
   - Configuration reload options

### Script Files

4. `/Users/galiharghubi/Work/personal/personal-script/scripts/load-config.sh`
   - Configuration loader and validator
   - Provider resolution logic
   - Environment variable export

5. `/Users/galiharghubi/Work/personal/personal-script/scripts/switch-provider.sh`
   - Runtime provider switching
   - Configuration modification
   - Validation and reload

6. `/Users/galiharghubi/Work/personal/personal-script/scripts/migrate-to-dynamic-config.sh`
   - Migration from static .md files
   - Backup creation
   - Validation and rollback

### Setup Files

7. `/Users/galiharghubi/Work/personal/personal-script/goclay-setup.sh`
   - Lines 421-621: Update `create_agent_definitions()`
   - Lines 772-804: Update `create_env_template()`
   - Lines 809-1063: Add new config management scripts

### Docker Configuration

8. `/root/docker-compose.goclaw.yml`
   - Lines 290-314: Update environment variables
   - Add new provider env vars
   - Add configuration reload env vars

---

## 4. Implementation Phases

### Phase 1: Foundation (Week 1)

**Goals**: Create configuration file structure and basic loading mechanism

**Tasks**:
1. Create `agents-config.json` template with all 9 agents configured
2. Create `providers-config.json` with MiniMax and OpenAI definitions
3. Update `.env.example` with new variables (MINIMAX_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY)
4. Implement `scripts/load-config.sh` with validation logic
5. Update `goclay-setup.sh` to create JSON configs instead of .md files

**Deliverables**:
- Configuration templates
- Configuration loader script
- Updated setup script
- Validation tests

**Success Criteria**:
- Configuration files are valid JSON
- Loader script validates configuration
- Setup script creates new files without errors

### Phase 2: Provider Abstraction (Week 2)

**Goals**: Build provider management and switching capabilities

**Tasks**:
1. Define provider interface (Go or TypeScript)
2. Implement MiniMax provider adapter
3. Implement OpenAI provider adapter
4. Create provider factory for runtime selection
5. Implement `scripts/switch-provider.sh` for runtime changes
6. Add provider health checking

**Deliverables**:
- Provider abstraction layer
- Provider implementations
- Switch-provider script
- Health check system

**Success Criteria**:
- Can switch providers at runtime
- Fallback mechanism works
- Health checks detect provider failures

### Phase 3: Integration (Week 3)

**Goals**: Integrate new config system with GoClaw

**Tasks**:
1. Update GoClaw to read from agents-config.json
2. Implement `/api/config/reload` endpoint
3. Add configuration validation on startup
4. Update Docker Compose with new env vars
5. Test GoClaw with new configuration

**Deliverables**:
- Updated GoClaw (or configuration wrapper)
- API endpoints for config management
- Updated Docker configuration
- Integration tests

**Success Criteria**:
- GoClaw starts with new configuration
- Agents use configured providers
- Reload endpoint works without restart

### Phase 4: Migration & Testing (Week 4)

**Goals**: Migrate existing deployments and test thoroughly

**Tasks**:
1. Implement `scripts/migrate-to-dynamic-config.sh`
2. Implement `scripts/rollback-migration.sh`
3. Write unit tests for configuration loading
4. Write integration tests for GoClaw
5. Test fallback logic
6. Document migration process

**Deliverables**:
- Migration scripts
- Test suite
- Migration documentation
- Tested rollback procedure

**Success Criteria**:
- Migration completes without data loss
- All tests pass
- Rollback restores previous state

### Phase 5: Cost Optimization (Optional - Week 5+)

**Goals**: Add cost tracking and optimization features

**Tasks**:
1. Implement cost tracking (token usage logging)
2. Build cost reporting tools
3. Add cost optimization rules engine
4. Create cost analysis dashboard
5. Document cost optimization strategies

**Deliverables**:
- Cost tracking system
- Cost reports
- Optimization scripts
- Cost optimization guide

**Success Criteria**:
- Can track costs per provider and agent
- Cost reports provide actionable insights
- Optimization rules reduce costs without quality loss

---

## 5. Key Design Decisions

### 5.1 JSON vs YAML

**Decision**: Use JSON for configuration files

**Rationale**:
- Better parsing support in shell (jq)
- More strict validation
- Easier to generate programmatically
- Wider tooling support

### 5.2 Per-Agent Provider Selection

**Decision**: Each agent can have its own provider

**Rationale**:
- Allows cost optimization (cheap providers for simple tasks)
- Enables quality optimization (best providers for complex tasks)
- Provides flexibility for different use cases
- Supports gradual migration (some agents on new provider)

### 5.3 Fallback Mechanism

**Decision**: Each agent can have a fallback provider

**Rationale**:
- Increases reliability
- Prevents single point of failure
- Allows graceful degradation
- Supports cost-based routing (fallback to expensive provider if cheap fails)

### 5.4 Runtime Configuration Loading

**Decision**: Support hot-reload without container restart

**Rationale**:
- Faster configuration changes
- No downtime for config updates
- Better developer experience
- Supports A/B testing of configurations

### 5.5 Backward Compatibility

**Decision**: Maintain pipeline-state.json structure

**Rationale**:
- Existing scripts continue to work
- No breaking changes to monitoring
- Gradual migration path
- Easier rollback if needed

---

## 6. Configuration Examples

### Example 1: All Agents on MiniMax (Cheapest)

Use case: User only has MiniMax API key

```json
{
  "default_provider": "minimax",
  "agents": {
    "po": {"provider": "minimax", "model": "abab6.5s-chat"},
    "techlead": {"provider": "minimax", "model": "abab6.5s-chat"},
    "orchestrator": {"provider": "minimax", "model": "abab6.5s-chat"},
    "be": {"provider": "minimax", "model": "abab6.5s-chat"},
    "fe": {"provider": "minimax", "model": "abab6.5s-chat"},
    "db": {"provider": "minimax", "model": "abab6.5s-chat"},
    "qa": {"provider": "minimax", "model": "abab6.5s-chat"},
    "devops": {"provider": "minimax", "model": "abab6.5s-chat"},
    "review": {"provider": "minimax", "model": "abab6.5s-chat"}
  }
}
```

### Example 2: Mixed Providers (Balanced)

Use case: User has both MiniMax and OpenAI keys

```json
{
  "default_provider": "minimax",
  "agents": {
    "techlead": {"provider": "openai", "model": "gpt-4o", "fallback": "minimax"},
    "be": {"provider": "openai", "model": "gpt-4o", "fallback": "minimax"},
    "fe": {"provider": "openai", "model": "gpt-4o", "fallback": "minimax"},
    "db": {"provider": "openai", "model": "gpt-4o", "fallback": "minimax"},
    "po": {"provider": "minimax", "model": "abab6.5s-chat"},
    "orchestrator": {"provider": "minimax", "model": "abab6.5s-chat"},
    "qa": {"provider": "minimax", "model": "abab6.5s-chat"},
    "devops": {"provider": "minimax", "model": "abab6.5s-chat"},
    "review": {"provider": "minimax", "model": "abab6.5s-chat"}
  }
}
```

### Example 3: Cost Optimized

Use case: Minimize costs while maintaining quality

```json
{
  "default_provider": "minimax",
  "agents": {
    "techlead": {"provider": "openai", "model": "gpt-4o-mini", "fallback": "minimax"},
    "be": {"provider": "openai", "model": "gpt-4o-mini", "fallback": "minimax"},
    "fe": {"provider": "openai", "model": "gpt-4o-mini", "fallback": "minimax"},
    "po": {"provider": "minimax", "model": "abab6.5s-chat"},
    "orchestrator": {"provider": "minimax", "model": "abab6-chat"},
    "qa": {"provider": "minimax", "model": "abab6-chat"},
    "devops": {"provider": "minimax", "model": "abab6-chat"},
    "review": {"provider": "minimax", "model": "abab6-chat"},
    "db": {"provider": "minimax", "model": "abab6.5s-chat"}
  }
}
```

---

## 7. Testing Strategy

### 7.1 Unit Tests

**Configuration Validation**:
- Test JSON parsing
- Test schema validation
- Test default value handling
- Test provider resolution

**Provider Resolution**:
- Test primary provider selection
- Test fallback provider activation
- Test disabled provider handling
- Test missing provider handling

**Configuration Loading**:
- Test file reading
- Test environment variable export
- Test error handling
- Test configuration merging

### 7.2 Integration Tests

**GoClaw Integration**:
- Test GoClaw startup with new config
- Test agent execution with configured providers
- Test configuration reload API
- Test fallback provider activation

**Docker Integration**:
- Test container startup
- Test environment variable passing
- Test volume mounting
- Test hot-reload functionality

**Migration Testing**:
- Test migration from static files
- Test backup creation
- Test rollback procedure
- Test data integrity

### 7.3 End-to-End Tests

**Full Sprint Execution**:
- Trigger sprint with all agents on MiniMax
- Trigger sprint with mixed providers
- Trigger sprint with fallback activation
- Verify all agents complete successfully

**Cost Tracking**:
- Execute sprint
- Verify cost logging
- Generate cost report
- Verify cost calculations

---

## 8. Migration Process

### Step 1: Backup

```bash
# Automatic backup created by migration script
./scripts/migrate-to-dynamic-config.sh
```

### Step 2: Validate Prerequisites

```bash
# Check .env has required API keys
grep MINIMAX_API_KEY .env

# Validate new configuration
./scripts/load-config.sh validate
```

### Step 3: Migrate Configuration

```bash
# Run migration script
./scripts/migrate-to-dynamic-config.sh

# Review new configuration files
cat .goclaw/agents-config.json
cat .goclaw/providers-config.json
```

### Step 4: Test

```bash
# Validate configuration
./scripts/load-config.sh validate

# Test provider resolution
./scripts/load-config.sh get-provider po

# Restart GoClaw
docker-compose restart goclaw
```

### Step 5: Rollback (if needed)

```bash
# If migration fails, rollback
./scripts/rollback-migration.sh
```

---

## 9. Success Metrics

### Functional Requirements

- [ ] All 9 agents configurable independently
- [ ] Provider switching works at runtime
- [ ] Fallback mechanism activates on failure
- [ ] Configuration validates before use
- [ ] Migration completes without data loss

### Non-Functional Requirements

- [ ] No performance degradation vs static config
- [ ] Configuration changes don't require restart
- [ ] Backward compatibility maintained
- [ ] API keys protected (not in JSON files)

### User Experience

- [ ] Clear documentation for common tasks
- [ ] Easy to switch providers per agent
- [ ] Cost tracking provides actionable insights
- [ ] Migration is reversible

### Cost Optimization

- [ ] Can run all agents on MiniMax only
- [ ] Cost savings visible in reports
- [ ] Fallback to expensive providers only when needed

---

## 10. Future Enhancements

### A. Advanced Cost Optimization

- Dynamic provider selection based on task complexity
- Budget caps with automatic provider switching
- Time-based routing (cheaper providers during off-hours)

### B. Provider Health Monitoring

- Real-time health checks for all providers
- Automatic failover on degradation
- Performance metrics tracking

### C. Configuration Profiles

- Development profile (cheapest providers)
- Production profile (best providers)
- Cost-optimized profile (balanced)

### D. A/B Testing

- Provider experiments for same agent
- Statistical analysis of quality vs cost
- Automated optimization based on metrics

---

## Conclusion

This implementation plan provides a comprehensive approach to adding dynamic agent configuration to the GoClaw pipeline system. The design prioritizes flexibility, cost optimization, reliability, and ease of use while maintaining backward compatibility.

The phased implementation allows for incremental development and testing, with clear rollback options at each stage. The result is a production-ready configuration system that meets all user requirements while maintaining system stability.

---

## Appendix A: Quick Reference

### Common Commands

```bash
# Validate configuration
./scripts/load-config.sh validate

# Switch provider for agent
./scripts/switch-provider.sh techlead openai

# Get provider for agent
./scripts/load-config.sh get-provider po

# Reload configuration (hot-reload)
curl -X POST http://localhost:18789/api/config/reload

# View cost report
./scripts/cost-report.sh

# Migrate to new config
./scripts/migrate-to-dynamic-config.sh

# Rollback migration
./scripts/rollback-migration.sh
```

### File Locations

```bash
# Configuration files
.goclaw/agents-config.json
.goclaw/providers-config.json
.goclaw/pipeline-state.json (unchanged)
.goclaw/agent-responsibilities.json (unchanged)

# Scripts
scripts/load-config.sh
scripts/switch-provider.sh
scripts/migrate-to-dynamic-config.sh
scripts/rollback-migration.sh

# Environment
.env.example
.env (create from .env.example)
```

### Environment Variables

```bash
# Provider API keys
MINIMAX_API_KEY=sk-xxxxxxxxxxxxx
OPENAI_API_KEY=sk-xxxxxxxxxxxxx
ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxxx

# Configuration
DEFAULT_PROVIDER=minimax
DEFAULT_FALLBACK=openai
COST_OPTIMIZATION_ENABLED=true
COST_THRESHOLD_USD=0.50

# Hot-reload
CONFIG_HOT_RELOAD=true
CONFIG_WATCH_INTERVAL_SECONDS=5
```

