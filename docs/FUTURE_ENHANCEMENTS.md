# Future Enhancements - Medium Effort Ideas

This document tracks medium-effort enhancement ideas for future implementation.

---

## Transaction Categorization Enhancements

### 1. Integrate Ntropy API

**Effort:** Medium
**Value:** High accuracy transaction enrichment

[Ntropy](https://www.ntropy.com/) offers:
- 2,000 free transactions for testing
- Most accurate ML-based categorization
- Works globally with any data source
- Pay-per-use pricing after free tier

**Implementation Steps:**
1. Create `Provider::Ntropy` class implementing `LlmConcept`
2. Add `NTROPY_API_KEY` to settings
3. Implement `auto_categorize` and `auto_detect_merchants` methods
4. Add as fallback option in provider chain

**API Documentation:** [docs.ntropy.com](https://docs.ntropy.com/enrichment/introduction)

---

### 2. Learning from User Corrections

**Effort:** Medium
**Value:** Improves accuracy over time

When a user manually re-categorizes a transaction, the system should remember this for similar future transactions.

**Implementation Approach:**

```ruby
# New model: CategoryMapping
class CategoryMapping < ApplicationRecord
  belongs_to :family
  belongs_to :category

  # Store patterns that map to categories
  # pattern_type: 'merchant', 'keyword', 'mcc'
  # pattern_value: the actual pattern
end
```

**Logic:**
1. When user changes category on a transaction with a merchant → create mapping
2. On new transactions, check mappings before AI calls
3. Prioritize: User mappings > MCC codes > Keywords > AI

---

### 3. Merchant Logo Enrichment

**Effort:** Low-Medium
**Value:** Better visual experience

Currently uses `logo.synthfinance.com`. Could add fallbacks:

- [Clearbit Logo API](https://clearbit.com/logo) - Free tier available
- [Brandfetch](https://brandfetch.com/developers) - Brand assets API
- [Google Favicon Service](https://www.google.com/s2/favicons?domain=example.com) - Free

**Implementation:**
```ruby
def fetch_logo_url(domain)
  # Try multiple sources in order
  sources = [
    "https://logo.synthfinance.com/#{domain}",
    "https://logo.clearbit.com/#{domain}",
    "https://www.google.com/s2/favicons?sz=128&domain=#{domain}"
  ]
  # Return first working URL
end
```

---

### 4. Recurring Transaction Detection

**Effort:** Medium
**Value:** Better insights, subscription tracking

Automatically detect recurring transactions (subscriptions, bills, income).

**Detection Criteria:**
- Same merchant
- Similar amount (within 5% tolerance)
- Regular interval (weekly, monthly, yearly)
- Minimum 2-3 occurrences

**New Model:**
```ruby
class RecurringTransaction < ApplicationRecord
  belongs_to :family
  belongs_to :merchant, optional: true

  # frequency: 'weekly', 'monthly', 'yearly'
  # average_amount: decimal
  # next_expected_date: date
  # transaction_ids: array of related transaction IDs
end
```

---

### 5. Category Suggestions Based on Similar Users

**Effort:** Medium-High
**Value:** Better default categories

For managed deployments, aggregate anonymized categorization patterns:
- "80% of users categorize 'NETFLIX' as Entertainment"
- Suggest categories based on community patterns

**Privacy Considerations:**
- Only for managed mode (not self-hosted)
- Aggregate data only, no individual data shared
- Opt-in feature

---

### 6. Import Category Mappings from Other Apps

**Effort:** Medium
**Value:** Easier migration

Allow importing category mappings from:
- Mint (already has MintImport)
- YNAB
- Personal Capital
- Quicken

**Format:** CSV with columns `merchant_pattern, category_name`

---

## Implementation Priority

| Enhancement | Effort | Impact | Priority |
|-------------|--------|--------|----------|
| User correction learning | Medium | High | P1 |
| Recurring transaction detection | Medium | High | P1 |
| Ntropy API integration | Medium | Medium | P2 |
| Merchant logo fallbacks | Low | Medium | P2 |
| Import category mappings | Medium | Medium | P3 |
| Community suggestions | High | Medium | P4 |

---

*Last Updated: 2026-01-19*
