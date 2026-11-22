# Opportunity Product Corrector

A Salesforce Lightning Web Component and Apex controller for **updating and correcting products on existing Opportunities**. Every correction is checked against business rules and logged with a reason, so Sales Operations can see who changed what and why.

![CI](https://github.com/ihydra-pk/salesforce-opportunity-product-ai/actions/workflows/ci.yml/badge.svg)

## The business problem

Sales reps and Sales Ops regularly need to fix Opportunity Products after a deal is created: a wrong quantity, a renegotiated price, or a discount entered in the wrong field. The standard "Edit Products" screen allows this, but it doesn't:

- require a reason for the change,
- keep an audit trail that can be reported on,
- stop discounts beyond the allowed limit before they reach forecasting.

## What it does

| Layer | Component | Purpose |
|---|---|---|
| UI | `opportunityProductCorrector` (LWC) | Inline-edit table of Quantity, Sales Price and Discount on the Opportunity record page. A reason is required before saving. |
| Logic | `OpportunityProductController` (Apex) | Loads line items with SOQL, saves only fields that really changed, and writes one audit row per changed field. Line items and audit rows are saved in one transaction: if either fails, both roll back. |
| Data model | `Product_Correction_Log__c` | Audit object: Opportunity, product, field changed, old/new value, reason. Reportable. |
| Data quality | Validation rules on `OpportunityLineItem` | Discount ≤ 50%, Quantity > 0. Rule errors are shown to the user as a toast. |
| Security | `Product_Correction_Access` permission set | Object, field, tab and Apex access. All SOQL and DML run in **user mode**, so field-level security and sharing are enforced. |

```
Opportunity record page
  └─ opportunityProductCorrector (LWC)
       ├─ @wire getLineItems ───────────► OpportunityProductController ── SOQL WITH USER_MODE
       └─ saveCorrections(drafts, reason) ► OpportunityProductController
                                              ├─ update as user OpportunityLineItem  ◄─ validation rules
                                              └─ insert as user Product_Correction_Log__c
```

## Testing

- **Apex**: `OpportunityProductControllerTest` covers loading, saving with audit rows, skipping unchanged values, required reason, and rollback when a validation rule fails.
- **LWC Jest**: 7 tests cover rendering, empty and error states, the reason check, converting edited cells to numbers, and success and error toasts.
- **CI**: GitHub Actions runs ESLint and Jest on every push.

## Setup

```bash
npm install

# Authorise a Developer Edition org
sf org login web --alias gd-portfolio --set-default

# Deploy and assign access
sf project deploy start --manifest manifest/package.xml
sf org assign permset --name Product_Correction_Access

# Demo data: one opportunity with three products
sf apex run --file scripts/apex/seed.apex
```

Then open the Opportunity, choose **Edit Page** in Lightning App Builder, drag **Opportunity Product Corrector** onto the page, and activate it.

## Commands

| Task | Command |
|---|---|
| Run all Apex tests with coverage | `sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 10` |
| Run one Apex test method | `sf apex run test --tests OpportunityProductControllerTest.saveCorrectionsRequiresReason --result-format human --wait 10` |
| Run LWC Jest tests | `npm run test:unit` |
| Lint LWC | `npm run lint` |
| Validate a deploy without saving | `sf project deploy validate --manifest manifest/package.xml --test-level RunLocalTests` |

## Next steps

- Record-triggered Flow: create a review Task for the Opportunity owner when a discount above 20% is saved.
- Report and dashboard on corrections by field and by user.
- AI review: an Agentforce Prompt Builder template that checks an Opportunity's products for unusual discounts, zero quantities and prices that differ from list price, and suggests corrections.
