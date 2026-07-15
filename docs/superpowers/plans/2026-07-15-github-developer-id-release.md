# GitHub Developer ID Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make tag-triggered GitHub Releases produce a Developer ID signed, Apple-notarized, stapled, and independently verified MyFans installer package.

**Architecture:** The macOS runner imports a password-protected PKCS#12 containing only the Developer ID Application and Installer identities into an ephemeral keychain. The workflow stores a dedicated notarization credential in that keychain, invokes the existing strict packaging path, verifies the final package, and deletes all temporary key material even when a preceding step fails.

**Tech Stack:** GitHub Actions, macOS `security`, `codesign`, `productbuild`, `notarytool`, `stapler`, `spctl`, zsh contract tests.

---

### Task 1: Define the release workflow contract

**Files:**
- Create: `Tests/PackagingTests/ReleaseWorkflowTests.sh`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Write a failing shell contract test**

  Require the release workflow to import a PKCS#12 into a temporary keychain, configure notarization, enable strict release signing, verify the final installer, and always remove the keychain.

- [ ] **Step 2: Verify the new test fails for the missing workflow integration**

  Run: `zsh Tests/PackagingTests/ReleaseWorkflowTests.sh`

  Expected: failure naming the first missing workflow contract.

- [ ] **Step 3: Add the contract test to normal CI**

  Add `zsh Tests/PackagingTests/ReleaseWorkflowTests.sh` to the existing packaging verification step without removing the icon packaging check.

### Task 2: Support an explicit notarization keychain

**Files:**
- Modify: `Tests/PackagingTests/ReleaseSigningTests.sh`
- Modify: `scripts/build-pkg.sh`

- [ ] **Step 1: Extend the signing test first**

  Require `NOTARY_KEYCHAIN_PATH` support and conditional `--keychain` forwarding.

- [ ] **Step 2: Verify the test fails before implementation**

  Run: `zsh Tests/PackagingTests/ReleaseSigningTests.sh`

  Expected: failure for missing `NOTARY_KEYCHAIN_PATH`.

- [ ] **Step 3: Implement the smallest script change**

  Build a `notarytool` argument array from the profile plus the optional explicit keychain path and use it for submission.

- [ ] **Step 4: Verify the signing contract passes**

  Run: `zsh Tests/PackagingTests/ReleaseSigningTests.sh`

  Expected: `Release signing packaging checks passed.`

### Task 3: Implement the GitHub Actions signing job

**Files:**
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Import identities into an ephemeral keychain**

  Decode `DEVELOPER_ID_P12_BASE64`, create and unlock a random-password keychain, import with `DEVELOPER_ID_P12_PASSWORD`, configure Apple tool access, and assert that both expected Developer ID identities exist.

- [ ] **Step 2: Store dedicated notarization credentials**

  Use `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD` to create `myfans-notary` in the temporary keychain with validation enabled.

- [ ] **Step 3: Enable strict packaging and notarization**

  Pass the two signing identity names, `myfans-notary`, its keychain path, and `REQUIRE_RELEASE_SIGNING=1` to `scripts/package-pkg.sh`.

- [ ] **Step 4: Verify the release artifact independently**

  Run `pkgutil --check-signature`, `stapler validate`, and `spctl --type install` against the generated package.

- [ ] **Step 5: Always clean temporary signing files**

  Delete the temporary keychain and decoded PKCS#12 in an `if: always()` step.

- [ ] **Step 6: Verify workflow and packaging contracts pass**

  Run:

  ```sh
  zsh Tests/PackagingTests/ReleaseWorkflowTests.sh
  zsh Tests/PackagingTests/ReleaseSigningTests.sh
  swift test
  git diff --check
  ```

### Task 4: Configure GitHub repository secrets

**Files:**
- No repository files contain secret material.

- [ ] **Step 1: Export only the two Developer ID identities**

  Use an encrypted temporary keychain to filter out unrelated Apple Development identities, export a new password-protected PKCS#12, and verify it contains exactly the Application and Installer identities.

- [ ] **Step 2: Upload encrypted signing material**

  Set `DEVELOPER_ID_P12_BASE64` and `DEVELOPER_ID_P12_PASSWORD` with `gh secret set`, then securely delete temporary local exports.

- [ ] **Step 3: Create a dedicated CI app-specific password**

  After action-time confirmation in Apple Account, create `MyFans GitHub Actions` and set `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_ID`, and `APPLE_TEAM_ID` as Actions secrets.

- [ ] **Step 4: Verify only secret names and update times**

  Run `gh secret list --app actions`; never read secret values back or print them.

### Task 5: Final verification

**Files:**
- No additional production files.

- [ ] **Step 1: Confirm tests and workflow syntax checks pass**

  Re-run all packaging contracts, `swift test`, and `git diff --check`.

- [ ] **Step 2: Confirm no secret artifacts are tracked or left locally**

  Scan tracked and untracked project files for PKCS#12/private-key extensions and verify temporary export paths were deleted.

- [ ] **Step 3: Report the exact tag-driven release behavior**

  Document that a pushed `vX.Y[.Z]` tag builds, signs, notarizes, staples, verifies, uploads, and publishes `MyFans-X.Y[.Z].pkg`.
