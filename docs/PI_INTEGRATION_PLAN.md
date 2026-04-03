# Pi Integration Plan for GoClaw

## Overview

Integrate **Pi** (minimal terminal coding harness) with GoClaw to run all 9 agents in individual tmux panes with full interactivity and observability.

## Benefits

- ✅ **Full observability** - Watch each agent work in real-time
- ✅ **Interactive debugging** - Jump into any agent's session
- ✅ **Minimal overhead** - Pi is lightweight and fast
- ✅ **Native MiniMax support** - Pi already supports MiniMax provider
- ✅ **Extensible** - Add agent-specific skills and extensions
- ✅ **Session persistence** - All agent work saved as JSONL files
- ✅ **Branching** - Explore alternative agent decisions

## Architecture

```
tmux session: goclaw
├── pane 0: Orchestrator (coordinates all agents)
├── pane 1: Product Owner (requirements)
├── pane 2: Technical Lead (architecture)
├── pane 3: Backend (API implementation)
├── pane 4: Frontend (UI implementation)
├── pane 5: Database (schema management)
├── pane 6: QA (testing - waves 1,3 only)
├── pane 7: DevOps (infrastructure)
└── pane 8: Review (code review)
```

## Implementation Steps

### 1. Install Pi

**File:** `goclay-setup.sh` (add to setup function)

```bash
install_pi() {
    log_step "Installing Pi coding agent..."

    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        log_error "Node.js not found. Installing..."
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    # Install Pi globally
    if ! command -v pi &> /dev/null; then
        log_info "Installing Pi via npm..."
        npm install -g @mariozechner/pi-coding-agent
    else
        log_info "Pi already installed: $(pi --version)"
    fi
}
```

### 2. Create Agent Skills Directory Structure

**Directory:** `.pi/skills/`

```
.pi/
├── skills/
│   ├── po.md
│   ├── techlead.md
│   ├── orchestrator.md
│   ├── be.md
│   ├── fe.md
│   ├── db.md
│   ├── qa.md
│   ├── devops.md
│   └── review.md
├── extensions/
│   └── goclaw-orchestrator.ts
└── prompts/
    └── sprint-task.md
```

### 3. Create Agent-Specific Skills

**Example:** `.pi/skills/po.md`

```markdown
# Product Owner Agent

You are the Product Owner agent in the GoClaw pipeline. Your responsibilities:

- Gather and document requirements from user input
- Write Product Requirements Documents (PRDs)
- Create user stories with acceptance criteria
- Prioritize features based on business value
- Define success metrics

## Wave 1: Requirements Gathering

1. Analyze user requirements
2. Write comprehensive PRD
3. Break down into user stories
4. Define acceptance criteria

## Wave 2: Clarification

1. Answer technical lead questions
2. Clarify requirements ambiguities
3. Adjust scope based on constraints

## Wave 3: Validation

1. Review implementation against requirements
2. Accept/reject features based on criteria
3. Provide feedback for iterations

## Communication

- Use `/orchestrator` command to report status
- Tag technical lead for technical questions with `@techlead`
- Document all decisions in `docs/product/`
```

### 4. Create Tmux Integration Script

**File:** `scripts/start-goclaw-pi.sh`

```bash
#!/bin/bash
# Start GoClaw agents in Pi via tmux

set -euo pipefail

SESSION="goclaw"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Kill existing session
tmux has-session -t "$SESSION" 2>/dev/null && tmux kill-session -t "$SESSION"

# Create new session
tmux new-session -d -s "$SESSION" -n "orchestrator"

# Load agent configuration
source .env
source scripts/load-config.sh

# Start Orchestrator (pane 0)
tmux send-keys -t "$SESSION:0" "pi --model MiniMax-M2.7 --skill orchestrator" C-m
tmux send-keys -t "$SESSION:0" "Start GoClaw pipeline sprint. Initialize all agents and wait for tasks." C-m

# Function to start agent in new pane
start_agent() {
    local agent_id="$1"
    local agent_name="$2"
    local model="$3"

    local pane_num=$((agent_index + 1))

    # Create new window for agent
    tmux new-window -t "$SESSION" -n "$agent_id"

    # Start Pi with agent skill
    tmux send-keys -t "$SESSION:$pane_num" "pi --model $model --skill $agent_id" C-m
    tmux send-keys -t "$SESSION:$pane_num" "Ready for $agent_name tasks. Waiting for orchestrator assignment." C-m
}

# Start all agents
agents=$(jq -r '.agents | to_entries[] | "\(.key)|\(.value.name)|\(.value.model)"' .goclaw/agents-config.json)

agent_index=0
while IFS='|' read -r agent_id agent_name model; do
    if [[ "$agent_id" != "orchestrator" ]]; then
        start_agent "$agent_id" "$agent_name" "$model"
        ((agent_index++))
    fi
done <<< "$agents"

# Attach to orchestrator pane
tmux select-window -t "$SESSION:0"
tmux attach-session -t "$SESSION"
```

### 5. Create Orchestrator Extension

**File:** `.pi/extensions/goclaw-orchestrator.ts`

```typescript
import { ExtensionAPI } from '@mariozechner/pi-coding-agent';

interface TaskAssignment {
  agentId: string;
  task: string;
  wave: number;
  priority: 'high' | 'medium' | 'low';
}

export default function (pi: ExtensionAPI) {
  // Store active tasks
  const activeTasks = new Map<string, TaskAssignment>();

  // Register command to assign tasks
  pi.registerCommand('assign', {
    description: 'Assign task to an agent',
    handler: async (args, ctx) => {
      const [agentId, ...taskParts] = args;
      const task = taskParts.join(' ');

      if (!agentId || !task) {
        return 'Usage: /assign <agent> <task>';
      }

      // Send task to agent's tmux pane
      const paneIndex = getAgentPaneIndex(agentId);
      tmux.sendKeys(`goclaw:${paneIndex}`, task);

      activeTasks.set(agentId, {
        agentId,
        task,
        wave: getCurrentWave(),
        priority: 'medium'
      });

      return `Task assigned to ${agentId}: ${task}`;
    }
  });

  // Register command to check agent status
  pi.registerCommand('status', {
    description: 'Check status of all agents',
    handler: async () => {
      let status = 'Agent Status:\n\n';

      for (const [agentId, task] of activeTasks) {
        status += `- ${agentId}: ${task.task}\n`;
      }

      return status;
    }
  });

  // Register command to coordinate wave transitions
  pi.registerCommand('next-wave', {
    description: 'Move to next wave',
    handler: async () => {
      const currentWave = getCurrentWave();
      const nextWave = currentWave + 1;

      // Notify all agents
      for (const [agentId, task] of activeTasks) {
        if (shouldAgentBeActive(agentId, nextWave)) {
          const paneIndex = getAgentPaneIndex(agentId);
          tmux.sendKeys(`goclaw:${paneIndex}`, `Starting wave ${nextWave} tasks`);
        }
      }

      return `Moving to wave ${nextWave}`;
    }
  });
}

function getAgentPaneIndex(agentId: string): number {
  const agents = ['po', 'techlead', 'be', 'fe', 'db', 'qa', 'devops', 'review'];
  return agents.indexOf(agentId) + 1;
}

function getCurrentWave(): number {
  // Load from pipeline state
  return 1;
}

function shouldAgentBeActive(agentId: string, wave: number): boolean {
  // Check agent config for wave participation
  return true;
}
```

### 6. Create Sprint Task Prompt Template

**File:** `.pi/prompts/sprint-task.md`

```markdown
# Sprint Task: {{task_name}}

**Wave:** {{wave}}
**Agent:** {{agent_role}}
**Priority:** {{priority}}

## Context

{{context}}

## Task Description

{{task_description}}

## Acceptance Criteria

{{acceptance_criteria}}

## Dependencies

{{dependencies}}

## Output Format

Please:
1. Analyze the requirements
2. Implement the solution
3. Test your work
4. Document any changes
5. Report completion to orchestrator via `/orchestrator` command

## Notes

{{notes}}
```

### 7. Update Environment Configuration

**File:** `.env.example` (add to existing)

```bash
# === PI CONFIGURATION ===
PI_MODEL=MiniMax-M2.7              # Default model for Pi
PI_THINKING=medium                 # Thinking level (off, minimal, low, medium, high, xhigh)
PI_SESSION_DIR=~/.pi/agent/sessions/goclaw
```

### 8. Create Pi Integration Documentation

**File:** `docs/pi-integration.md`

```markdown
# Pi Integration Guide

## Overview

GoClaw now uses **Pi** (minimal terminal coding harness) to run all agents in individual tmux panes with full interactivity.

## Quick Start

### 1. Install Pi

```bash
# Run setup script
./goclay-setup.sh

# Or install manually
npm install -g @mariozechner/pi-coding-agent
```

### 2. Configure MiniMax for Pi

```bash
# Login to Pi
pi

# In Pi, type:
/login
# Select MiniMax and authenticate
```

### 3. Start GoClaw Pipeline

```bash
# Start all agents in tmux
./scripts/start-goclaw-pi.sh
```

## Usage

### Basic Workflow

1. **Orchestrator (pane 0)** - Main coordination pane
   - Assign tasks to agents
   - Monitor progress
   - Coordinate wave transitions

2. **Agent Panes (1-8)** - Individual agent sessions
   - Watch agents work in real-time
   - Jump in to provide guidance
   - Review outputs and decisions

### Tmux Commands

```bash
# List all panes
Ctrl+b w

# Switch to specific pane
Ctrl+b 0    # Orchestrator
Ctrl+b 1    # Product Owner
Ctrl+b 2    # Technical Lead
# ... etc

# Split pane vertically
Ctrl+b %

# Split pane horizontally
Ctrl+b "

# Detach from session
Ctrl+b d

# Reattach to session
tmux attach -t goclaw
```

### Assigning Tasks

In the orchestrator pane:

```
/assign po "Write PRD for user authentication feature"
/assign techlead "Design authentication architecture"
/assign be "Implement login endpoint"
```

### Monitoring Progress

```
/status              # Check all agent status
/next-wave          # Move to next wave
```

## Agent Skills

Each agent has a specific skill loaded:

- `po` - Product Owner requirements gathering
- `techlead` - Technical leadership and architecture
- `orchestrator` - Pipeline coordination
- `be` - Backend implementation
- `fe` - Frontend implementation
- `db` - Database schema management
- `qa` - Quality assurance testing
- `devops` - Infrastructure and CI/CD
- `review` - Code review

## Customization

### Adding New Skills

Create skill files in `.pi/skills/`:

```bash
.pi/skills/my-agent.md
```

### Modifying Agent Behavior

Edit agent skill files to change responsibilities, workflows, or communication patterns.

### Creating Custom Extensions

Add TypeScript extensions in `.pi/extensions/`:

```bash
.pi/extensions/my-extension.ts
```

## Troubleshooting

### Pi Not Found

```bash
# Reinstall Pi
npm install -g @mariozechner/pi-coding-agent

# Verify installation
pi --version
```

### Tmux Session Issues

```bash
# Kill existing session
tmux kill-session -t goclaw

# Start fresh
./scripts/start-goclaw-pi.sh
```

### Agent Not Responding

1. Switch to agent pane
2. Check for errors
3. Type `/status` in agent pane
4. If stuck, type `Ctrl+C` to clear and restart

### MiniMax Authentication

```bash
# In any Pi session:
/login
# Select MiniMax
# Follow OAuth flow
```

## Advanced Usage

### Manual Agent Start

```bash
# Start specific agent in new terminal
pi --model MiniMax-M2.7 --skill po
```

### Session Export

```bash
# In any Pi session:
/export po-session-2025-04-04.html
```

### Branching Exploration

```bash
# In any Pi session:
/tree    # Navigate session tree
/fork    # Create new branch
```

## Architecture Details

### Tmux Layout

```
Session: goclaw
├── Window 0: orchestrator
├── Window 1: po
├── Window 2: techlead
├── Window 3: be
├── Window 4: fe
├── Window 5: db
├── Window 6: qa
├── Window 7: devops
└── Window 8: review
```

### Communication Flow

1. User provides requirements to orchestrator
2. Orchestrator assigns tasks via `/assign`
3. Agents receive tasks in their panes
4. Agents work and report back via `/orchestrator`
5. Orchestrator coordinates wave transitions
6. Cycle repeats until sprint complete

## Benefits Over Direct API

- **Observability** - See every agent decision
- **Interactivity** - Guide agents in real-time
- **Debugging** - Jump in to fix issues
- **Flexibility** - Re-route tasks dynamically
- **Learning** - Understand agent reasoning
- **Transparency** - Full audit trail in sessions

## Migration from Direct API

The old direct API approach is still available. To switch back:

```bash
# Use old pipeline starter
./scripts/start-pipeline.sh

# Or run GoClaw directly
docker-compose -f /root/docker-compose.goclaw.yml up -d
```

## Support

- Pi Documentation: https://pi.dev
- Pi GitHub: https://github.com/badlogic/pi-mono
- GoClaw Docs: `docs/`
- Config Validation: `./scripts/load-config.sh validate`
```

## Migration Strategy

### Phase 1: Installation (Week 1)
1. Add Pi installation to goclay-setup.sh
2. Create skill directory structure
3. Test Pi installation on fresh system

### Phase 2: Agent Skills (Week 2)
1. Create all 9 agent skills
2. Test each skill individually
3. Refine agent responsibilities

### Phase 3: Tmux Integration (Week 3)
1. Build start-goclaw-pi.sh script
2. Test pane management
3. Verify agent communication

### Phase 4: Orchestrator Extension (Week 4)
1. Build orchestrator extension
2. Implement task assignment
3. Add wave coordination

### Phase 5: Testing & Documentation (Week 5)
1. End-to-end testing
2. Write comprehensive docs
3. Create troubleshooting guide

### Phase 6: Rollout (Week 6)
1. Beta testing with select users
2. Gather feedback
3. Refine and polish

## Success Criteria

- ✅ All 9 agents can run simultaneously in tmux
- ✅ Orchestrator can assign tasks to agents
- ✅ Agents can communicate back to orchestrator
- ✅ Wave transitions work smoothly
- ✅ Session persistence allows recovery
- ✅ Users can interact with any agent
- ✅ Full observability of agent work
- ✅ MiniMax authentication works
- ✅ Performance acceptable (< 2s per response)

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Pi installation fails | High | Add fallback to direct API |
| Tmux complexity | Medium | Provide simple starter script |
| Agent communication | High | Implement robust extension |
| Session management | Medium | Auto-save and recovery |
| Performance | Low | Monitor and optimize |

## Open Questions

1. Should we keep direct API as fallback?
2. How to handle long-running agent tasks?
3. Session cleanup strategy?
4. Multi-user support?
5. Remote collaboration?

## Next Steps

1. **Review this plan** - Get feedback
2. **Start Phase 1** - Install Pi in setup script
3. **Create agent skills** - Build 9 skill files
4. **Test tmux workflow** - Verify pane management
5. **Build extension** - Implement orchestrator
6. **Document everything** - User guide + troubleshooting

## Resources

- Pi Documentation: https://raw.githubusercontent.com/badlogic/pi-mono/refs/heads/main/packages/coding-agent/README.md
- Pi GitHub: https://github.com/badlogic/pi-mono
- Agent Skills Standard: https://agentskills.io
- Tmux Documentation: https://github.com/tmux/tmux/wiki
- Current GoClaw Config: `.goclaw/agents-config.json`
- MiniMax Token Plan: `docs/minimax-token-plan.md`
