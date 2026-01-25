# Maybe Finance - Planned Features & Roadmap

This document catalogs unimplemented features, disabled functionality, and planned improvements discovered in the codebase. It serves as a Product Requirements Document (PRD) extension for future development.

---

## Table of Contents

1. [AI Assistant Features](#1-ai-assistant-features)
2. [Holdings Management](#2-holdings-management)
3. [Disabled UI Elements](#3-disabled-ui-elements)
4. [Temporarily Disabled Features](#4-temporarily-disabled-features)
5. [Internationalization (i18n)](#5-internationalization-i18n)
6. [Extension Points](#6-extension-points)

---

## 1. AI Assistant Features

### 1.1 Chat Input Actions (Coming Soon)

**Location:** `app/views/messages/_chat_form.html.erb` (lines 19-23)

Four disabled buttons in the chat input area indicate planned functionality:

| Icon | Intended Purpose | Priority | Complexity |
|------|------------------|----------|------------|
| **+** (Plus) | Add context, attachments, or file uploads | Medium | Medium |
| **/** (Slash) | Slash commands for quick AI actions | High | Medium |
| **@** (At-sign) | Mention accounts, categories, or financial data | High | Medium |
| **Cursor/Click** | Selection or interaction menu | Low | Low |

**Code Comment:**
```erb
<%# These are disabled for now, but in the future, will all open specific menus with their own context and search %>
```

#### Suggested Implementation: Slash Commands

Potential slash commands to implement:
- `/summary` - Get a financial summary for a period
- `/compare [period1] [period2]` - Compare spending between periods
- `/budget` - Check budget status
- `/export` - Export data to CSV/PDF
- `/help` - List available commands

#### Suggested Implementation: @ Mentions

Allow users to reference specific data:
- `@Checking` - Reference a specific account
- `@Groceries` - Reference a category
- `@Amazon` - Reference a merchant
- `@January` - Reference a time period

---

### 1.2 AI Model Selector

**Location:** `app/views/messages/_chat_form.html.erb` (line 10)

```erb
<%# In the future, this will be a dropdown with different AI models %>
<%= f.hidden_field :ai_model, value: ENV.fetch("OLLAMA_MODEL", Setting.ollama_model).presence || "gpt-4.1" %>
```

**Current State:** Hardcoded to use a single model from environment/settings.

**Planned Feature:** Dropdown to select between available AI models.

#### Suggested Implementation

```ruby
# Available models could include:
- OpenAI: gpt-4.1, gpt-4o, gpt-3.5-turbo
- Ollama: llama3.2, mistral, mixtral, codellama
- Future: Claude, Gemini, local models
```

**UI Considerations:**
- Show model capabilities (speed vs quality)
- Remember user's preferred model
- Indicate which models support function calling

---

### 1.3 Message Retry Functionality

**Location:** `test/controllers/api/v1/messages_controller_test.rb` (lines 61-79)

```ruby
skip "Retry functionality needs debugging"
```

**Current State:** Test disabled, feature exists but needs debugging.

**Intended Behavior:** Allow users to retry the last AI assistant message if it failed or produced unsatisfactory results.

---

### 1.4 Multi-Turn Function Calling

**Location:** `app/models/assistant/responder.rb` (line 42)

```ruby
# We do not currently support function executions for a follow-up response
# (avoid recursive LLM calls that could lead to high spend)
```

**Current State:** Only one level of tool calls supported.

**Potential Enhancement:** Allow chained function calls with safeguards:
- Maximum depth limit (e.g., 3 levels)
- Token/cost budget per conversation
- User confirmation for expensive operations

---

### 1.5 Additional AI Functions

**Location:** `app/models/assistant/function/`

**Currently Implemented:**
- `GetAccounts` - List accounts with balances
- `GetTransactions` - Search/filter transactions
- `GetBalanceSheet` - Net worth breakdown
- `GetIncomeStatement` - Income/expense by category

**Suggested New Functions:**

| Function | Description | Priority |
|----------|-------------|----------|
| `GetBudget` | Retrieve budget status and remaining amounts | High |
| `GetGoals` | Check savings goals progress | Medium |
| `GetRecurring` | List recurring transactions | Medium |
| `CompareAccounts` | Compare performance of accounts | Low |
| `GetTrends` | Identify spending trends over time | Medium |
| `SetReminder` | Create financial reminders | Low |

---

## 2. Holdings Management

### 2.1 New Holdings Page

**Location:** `app/views/holdings/new.html.erb` (line 1)

```erb
Coming soon...
```

**Current State:** Placeholder page, feature not implemented.

**Intended Feature:** Allow users to manually add holdings to investment accounts.

**Required Implementation:**
- Form to add new security holdings
- Security search/autocomplete
- Quantity and cost basis input
- Support for stocks, ETFs, mutual funds, crypto

---

## 3. Disabled UI Elements

### 3.1 Currency Selection (Read-Only)

**Location:** `app/views/settings/preferences/show.html.erb` (line 11)

**Current State:** Currency cannot be changed after account creation.

**Reason:** Changing currency would require recalculating all historical balances and exchange rates.

**Potential Enhancement:** Allow currency change with:
- Warning about recalculation
- Background job to update historical data
- Option to keep historical values in original currency

---

### 3.2 Transaction Account Reassignment

**Location:** `app/views/transactions/show.html.erb` (line 67)

**Current State:** Transactions cannot be moved between accounts.

**Potential Enhancement:** Allow reassignment with:
- Validation that accounts are compatible
- Update of related transfers
- Recalculation of account balances

---

### 3.3 Budget Uncategorized Spending

**Location:** `app/views/budget_categories/_uncategorized_budget_category_form.html.erb` (line 17)

**Current State:** Auto-calculated, not editable.

**Intended Behavior:** This is likely intentional - uncategorized spending is derived from actual transactions.

---

## 4. Temporarily Disabled Features

### 4.1 AutoSync on Login

**Location:** `test/controllers/concerns/auto_sync_test.rb` (lines 13, 20)

```ruby
skip "AutoSync functionality temporarily disabled"
```

**Intended Behavior:**
- Sync family data when user logs in
- Auto-sync if last sync was over 24 hours ago

**Status:** Feature exists but tests are disabled.

---

### 4.2 API OAuth2 Scope Checking

**Location:** `test/controllers/api/v1/accounts_controller_test.rb` (lines 27-46)

```ruby
skip "TODO: Re-enable this test after fixing scope checking"
# "Scope checking temporarily disabled - needs configuration fix"
```

**Intended Behavior:** Validate OAuth2 scopes for API access control.

**Status:** Needs configuration fix before re-enabling.

---

## 5. Internationalization (i18n)

**Location:** `test/i18n_test.rb`

**Reference:** GitHub Issue #1225

**Current State:** All i18n validation tests are skipped:
- Missing keys test
- Unused keys test
- File normalization test
- Inconsistent interpolations test

**Code Comment:**
```ruby
# We're currently skipping some i18n tests to speed up development.
# Eventually, we'll make a dedicated project for getting i18n working.
```

**Priority:** Low (deferred to dedicated project)

---

## 6. Extension Points

The codebase includes well-designed abstract base classes for extending functionality:

### 6.1 AI Assistant Functions

**Base Class:** `app/models/assistant/function.rb`

Create new functions by inheriting and implementing:
- `name` - Function identifier
- `description` - What the function does (for the LLM)
- `params_schema` - JSON Schema for parameters
- `call(params)` - Execute the function

### 6.2 LLM Providers

**Base Class:** `app/models/provider/llm_concept.rb`

Add new LLM providers by implementing:
- `auto_categorize` - Categorize transactions
- `auto_detect_merchants` - Detect merchant names
- `chat_response` - Generate chat responses

### 6.3 Data Providers

**Exchange Rates:** `app/models/provider/exchange_rate_concept.rb`
**Securities:** `app/models/provider/security_concept.rb`

### 6.4 Import Formats

**Base Class:** `app/models/import.rb`

Existing formats: TransactionImport, TradeImport, AccountImport, MintImport

---

## Implementation Priority Matrix

| Feature | Impact | Effort | Priority |
|---------|--------|--------|----------|
| Slash Commands | High | Medium | P1 |
| @ Mentions | High | Medium | P1 |
| AI Model Selector | Medium | Low | P2 |
| Holdings Management | High | High | P2 |
| Message Retry Fix | Low | Low | P3 |
| Additional AI Functions | Medium | Medium | P3 |
| Currency Change | Low | High | P4 |
| i18n Support | Medium | High | P4 |

---

## Contributing

When implementing these features:

1. Check existing patterns in the codebase
2. Add appropriate tests (see `test/` directory structure)
3. Follow the project conventions in `CLAUDE.md`
4. Update this document when features are completed

---

*Last Updated: 2026-01-19*
*Generated from codebase analysis*
