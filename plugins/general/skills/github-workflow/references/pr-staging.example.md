<!-- DEVELOP PR (Feature, Bugfix e Improvement) -->

# Add OAuth2 login support

## Description

This PR implements OAuth2 authentication using Google and GitHub providers. It includes the new authentication service, the updated login UI, and the necessary environment variable configurations.

[<img src="https://via.placeholder.com/250x150.png?text=Login+Screen" width="250"/>](https://via.placeholder.com/250x150.png?text=Login+Screen)

## How has this been tested?

- **Unit Tests**: `auth.service.spec.ts`, `login.component.spec.ts`
- **Integration Tests**: `auth.integration.spec.ts` (tested with mock OAuth servers)
- **Functional Test**: Manual login with Google and GitHub in the staging environment.

- [x] I have added tests to cover my changes.
- [x] All new and existing tests passed.

## QA Review

Total unit test coverage for the auth module: **94%**.

![Coverage Screenshot](https://via.placeholder.com/600x200.png?text=Unit+Test+Coverage+94%25)

## Types of changes

- [ ] Docs change / refactoring / dependency upgrade.
- [ ] Deployment change.
- [ ] Bug fix.
- [x] New feature.
- [ ] Improvement.
