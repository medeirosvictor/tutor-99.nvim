# tutor-99.nvim Development Plan

## Overview

This fork of 99 adds a **Senior Dev Review Mode** for learning and architectural understanding.

## Priority 1: Senior Dev Review Mode

### User Flow

1. User selects code in visual mode
2. User presses `<leader>9r` (review keybinding)
3. Plugin prompts: "Which milestone is this for?"
4. User selects milestone from DEV-PLAN.md
5. AI receives:
   - Selected code
   - Current milestone context
   - Full DEV-PLAN.md
   - User preferences (preferences.md)
6. AI returns feedback in a floating window (chat style - does NOT replace code)
7. Response ends with discussion invite

### Implementation Tasks

#### 1. Create Review Skill
- Location: `scratch/custom_rules/review/SKILL.md`
- Content: Senior dev persona prompt explaining what review should cover

#### 2. Add Review Operation
- File: `lua/99/ops/review.lua` (new)
- Similar to `over-range.lua` but:
  - Does NOT replace code
  - Shows response in floating window
  - Uses review skill/system prompt

#### 3. Add Review Prompt Type
- File: `lua/99/prompt.lua`
- Add `Prompt.review(_99)` function similar to `Prompt.visual()`

#### 4. Add Review Prompt Template
- File: `lua/99/prompt-settings.lua`
- Add `prompts.review()` function

#### 5. Add Review to Main API
- File: `lua/99/init.lua`
- Add `_99.review(opts)` function

#### 6. Add Keybinding
- In setup example, add:
```lua
vim.keymap.set("v", "<leader>9r", function()
  _99.review()
end)
```

### Files to Create/Modify

| File | Action |
|------|--------|
| `scratch/custom_rules/review/SKILL.md` | Create |
| `lua/99/ops/review.lua` | Create |
| `lua/99/prompt.lua` | Modify - add `Prompt.review()` |
| `lua/99/prompt-settings.lua` | Modify - add `prompts.review()` |
| `lua/99/init.lua` | Modify - add `_99.review()` |

---

## Priority 2: DEV-PLAN.md Milestone Integration

### Changes

1. Extend `md_files` config to support multiple files:
```lua
md_files = {
  "AGENT.md",
  "DEV-PLAN.md",
  "preferences.md",
}
```

2. Modify milestone picker:
   - Extract milestones from DEV-PLAN.md
   - Show vim.ui.select() picker before sending request

### Implementation Tasks

#### 1. Add Milestone Extraction Utility
- File: `lua/99/extensions/milestones.lua` (new)
- Function to parse DEV-PLAN.md and extract milestone list

#### 2. Modify Operations to Support Milestone Selection
- Update `capture_prompt()` in `init.lua` to optionally ask for milestone first

---

## Priority 3: preferences.md Support

### Implementation Tasks

1. Add `preferences.md` to default `md_files` list
2. Create sample preferences file at repo root

---

## Architecture Notes

### How 99 Works (for reference)

1. **Prompt Creation**: `Prompt.visual()` / `Prompt.search()` / `Prompt.tutorial()`
2. **Operation**: `ops.visual()` / `ops.search()` - handles the request lifecycle
3. **Provider**: CLI wrapper (opencode, claude, etc.)
4. **UI**: Floating windows via `Window.capture_input()`

### Key Pattern

```lua
-- 1. Create context
local context = Prompt.review(_99)

-- 2. Add options
opts.additional_prompt = user_input

-- 3. Run operation
ops.review(context, opts)
```

### Skills/Rules System

- Skills live in `scratch/custom_rules/<skill_name>/SKILL.md`
- Referenced in prompts via `#skillname`
- Auto-complete available in prompt buffer

---

## Configuration Example

```lua
{
  "tutor-99.nvim",
  config = function()
    local _99 = require("99")
    
    _99.setup({
      provider = _99.Providers.OpenCodeProvider,
      md_files = {
        "AGENT.md",      -- 99's default context
        "DEV-PLAN.md",   -- Milestones and project goals
        "preferences.md", -- User-specific rules
      },
      completion = {
        custom_rules = {
          "scratch/custom_rules/",
        },
        source = "cmp",
      },
      tmp_dir = "./tmp",
    })
    
    -- Visual mode: replace selected code
    vim.keymap.set("v", "<leader>9v", function()
      _99.visual()
    end)
    
    -- Visual mode: review selected code (NEW)
    vim.keymap.set("v", "<leader>9r", function()
      _99.review()
    end)
    
    -- Normal mode: search project
    vim.keymap.set("n", "<leader>9s", function()
      _99.search()
    end)
    
    -- Cancel in-flight requests
    vim.keymap.set("n", "<leader>9x", function()
      _99.stop_all_requests()
    end)
  end,
}
```

---

## Future Considerations

- [ ] Direct API support (Anthropic, MiniMax) alongside CLI
- [ ] Streaming code preview before apply
- [ ] Conversation history browsing
- [ ] Model switching via Telescope
- [ ] Custom review personas as skills
