<!-- MASTER PR (Hotfix) -->

# Hotfix v1.2.1

## Description

This hotfix addresses a critical issue where the checkout process would fail when a user applied a discount code that had expired, instead of showing a validation error.

## How has this been tested?

- **Unit Test**: `discount.service.spec.ts` (added test case for expired codes).
- **Functional Test**: Attempted checkout with an expired code in the production-like sandbox environment.

- [x] I have added tests to cover my changes.
- [x] All new and existing tests passed.

## QA Review

Important: This fix only affects the discount validation logic. No changes were made to the payment gateway integration.

![Discount Test Result](https://via.placeholder.com/600x150.png?text=Expired+Discount+Validation+Test+Passed)
