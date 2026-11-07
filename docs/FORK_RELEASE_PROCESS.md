# Building and releasing the fork

The GitHub fork is **not yet production-ready for legacy 16X / 64-channel audio**.
See \`docs/legacy-first-release-readiness.md\` and the draft pull request.
This guide separates a build, a deployable macOS installer, and a GitHub Release.

## 1. Build in GitHub Actions (available now)

The feature branch has a Sequoia 15 / Tahoe 26 CI matrix:
\`.github/workflows/legacy-maestro-ci.yml\`. On pull requests it compiles
the SwiftUI app and hardware diagnostics, runs Swift unit tests, then builds
the two binaries in release configuration. Its downloadable Actions artifact
\`maestro-legacy-dev-binaries-<run number>\` contains only **unsigned diagnostic
executables**, a README and SHA-256 checksums. It is **not** an app bundle,
driver, installer, notarized package or GitHub Release.

Open the repository's **Actions** tab > **Legacy Maestro macOS Build and Tests**
> successful run > **Artifacts** and download the ZIP. For a manual
\`workflow_dispatch\` run, GitHub normally requires the workflow to be
available on the repository's default branch; until the draft PR is merged,
use its pull-request runs.

## 2. Local release-configuration compile (no installation)

On an Apple Silicon Mac with full Xcode and Swift 6 (Xcode 16.4 for the Sequoia SDK baseline, current Xcode for Tahoe):

\`\`\`sh
git clone https://github.com/kiwimartin/unofficial-symphony-maestro-mk1.git
cd unofficial-symphony-maestro-mk1
git checkout feature/legacy-symphony-topology
swift test --package-path Apps/Maestro --jobs 4
swift build --package-path Apps/Maestro -c release --jobs 4
\`\`\`

This does not sign or install the ThunderBridge DriverKit extension.
Do not confuse compiling \`MaestroApp\` with creating \`Maestro.app\`
or with releasing a functioning legacy audio driver.

## 3. Signed, notarized PKG (only after ALL production gates pass)

The existing packaging script is
\`Installer/build-installer.sh\`. Prerequisites:

- The **fork owner's own** Apple Developer team and approved DriverKit
  Audio/PCI/UserClient entitlements, with matching Developer ID provisioning
  profiles for both the app and the extension.
- Developer ID Application and Developer ID Installer certificates in an
  unlocked signing keychain.
- An Apple notarization keychain profile or a separate App Store Connect API key.
- Full Xcode including DriverKit SDK, Swift 6+, CMake and Python 3.
- Properly migrated fork bundle identifiers, driver identifiers,
  provisioning IDs, helper paths, updater public key and isolated Sparkle
  appcast. The checkout currently contains the upstream developer's identity
  and identifiers: setting only \`TEAM_ID\` is NOT sufficient.
- Completed hardware test evidence and explicit release sign-off.

Prepare the environment file OUTSIDE the repository:

\`\`\`sh
cp .env.example ~/maestro-release.env
chmod 600 ~/maestro-release.env
# Edit it locally with your own authorized certificates, profiles, paths,
# notarization credentials and TEAM_ID; NEVER commit it.
MAESTRO_ENV_FILE="$HOME/maestro-release.env" bash Installer/build-installer.sh
\`\`\`

The script builds, signs, notarizes and staples the PKG, but deliberately
**does not publish** a GitHub Release or update the Sparkle feed.
Output (after success):
\`Installer/build/output/UnofficialSymphonyMaestro-<version>-b<build>.pkg\`.

Before publication:

\`\`\`sh
pkgutil --check-signature Installer/build/output/*.pkg
xcrun stapler validate Installer/build/output/*.pkg
shasum -a 256 Installer/build/output/*.pkg
\`\`\`

Version sources are \`Tools/versions.json\` and
\`Apps/Maestro/MaestroCore/MaestroCore.swift\`. Update them consistently
under the project's documented sequence; don't derive build numbers from
Git history. Keep source, package, signing and update-feed operations separate.

## 4. GitHub Release (publish only after approved tests/signing)

Once a signed/notarized PKG has passed release verification, using the
GitHub CLI on the Mac (example version is a placeholder, NOT an instruction
to publish now):

\`\`\`sh
# Adjust the tag and filename to the new, verified fork release.
gh auth login
gh release create YOUR_NEW_VERSION_TAG \
  Installer/build/output/UnofficialSymphonyMaestro-YOUR_VERSION-bYOUR_BUILD.pkg \
  --repo kiwimartin/unofficial-symphony-maestro-mk1 \
  --target main \
  --title "Symphony Maestro YOUR_VERSION – verified build" \
  --notes-file RELEASE_NOTES.md \
  --draft
\`\`\`

Review the draft and its checksums, then publish via GitHub's Releases
interface only with explicit approval. Do not use the existing upstream
version or tag for a different binary, replace published assets or alter
the upstream Sparkle feed. The fork needs its own Sparkle signing key and
appcast, or in-app updates should be disabled until configured.

**Current policy:** Do not run step 3 or create a release tag under step 4
for legacy 64-channel operation until the explicit criteria in
\`docs/legacy-first-release-readiness.md\` have passed.
