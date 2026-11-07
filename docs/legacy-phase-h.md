# Phase H: reproducible developer builds and own-signing release gates

CI now compiles SwiftUI, the diagnostic clients, the audio DriverKit driver,
the independent passive service, USB AudioServerPlugin and VolumeProxy without
signing or installation. Existing USB shared-memory/clock contract tests run
alongside C++ sanitizers and Swift tests. libASPL is pinned to exact public
commit 633e0f70203edd87d320fc5a3cae901e1363aac5 rather than moving `main`.
The USB build's default signing path is unchanged; `--unsigned` exits before
accessing signing inputs. No CI step invokes the production installer script.

Artifacts contain executable compile products, source commit, build environment,
checksums, phase status documents and developer-only preflight output; separate
artifacts retain full test logs. These are NOT installable audio driver bundles,
an installer, a signed app or evidence of 64-channel hardware operation.

`Tools/legacy-release-check.py` is a read-only validator with four build classes:

- Developer: no signing/profile inputs required; never establishes hardware acceptance.
- Hardware-test: distinct own team/identifiers, explicit certificate and external
  profiles, exact signed artifact hashes and on-macOS profile/signature inspection.
- Release candidate: additionally requires matching hardware-tested source/artifact
  hashes, every acceptance report and explicit approval reference plus signed installer.
- Production: additionally validates stapled notarization with Apple's tool.

The validator never builds, signs, activates, installs, notarizes, publishes,
changes keychains or reads private keys. Profile certificate bytes are public
metadata; the explicit own signing certificate must match them. Upstream team
95CX6P84C4 and com.danielraffel.* identities are rejected. Profiles in the source
checkout are rejected. Negative tests verify that missing approval/evidence,
wrong team/ID/certificate, expired profiles or changed artifacts remain blocked.
An attestation file is not proof that its claims are true: reviewers must inspect
original physical test reports. The tool cannot grant release approval.

Example (copy the template outside Git and use only your own inputs):

```sh
python3 Tools/legacy-release-check.py --mode developer
python3 Tools/legacy-release-check.py --mode hardware-test --manifest /external/own-manifest.json --inspect-signed
```

No own profiles, certificates, hardware reports or approved signed artifacts are
available in this task. Hardware-test/RC/Production are therefore **BLOCKED**.
The manifest template intentionally fails until completed with actual own data.
Do not run Installer/build-installer.sh against its upstream IDs and assume a
new TEAM_ID is enough. A dedicated reviewed identifier/ownership migration and
upgrade/rollback plan is still required before assembling a fork installer.

## Own signing and activation plan

1. Register unique own identifiers for host app, diagnostic client, passive PCI
   service, audio DriverKit extension and relevant USB/helper components. Suggested
   namespace: com.kiwimartin.symphonymaestro.*, subject to actual Apple registration.
2. Request `com.apple.developer.driverkit` and
   `com.apple.developer.driverkit.transport.pci` for the passive service, constrained
   to ThunderBridge 19C2:2200. Audio extension also needs
   `com.apple.developer.driverkit.family.audio`. Inspect actual granted profile
   contents and matching requested entitlements; do not infer approval from a portal label.
3. Host app needs `com.apple.developer.system-extension.install`; authorized app
   and diagnostic client require approved `com.apple.developer.driverkit.userclient-access`
   for the own driver IDs. Validate IOServiceOpen on a signed test build; do not
   add broad allow-any access or reuse upstream permissions as a workaround.
4. Obtain own Developer ID Application/Installer certificates, external profiles
   and a private notarization configuration. Sign nested components explicitly,
   then the host app; verify installed/loaded team, ID, version and hashes.
5. Use a separate test package/update feed for upgrade, rollback and restart tests.
   The production Sparkle appcast/key/feed and release assets remain untouched.
6. Only after all physical gates pass: assemble the migrated installer, verify
   signatures, notarize/staple with own credentials, record exact PKG hash, request
   explicit publication approval. No tag/release/publication occurs in this work.

Physical signed installer/upgrade/notarization tests: **NOT RUN**. Long-term
signability is planned and checked structurally; an operational signed installer
has not been produced without the required Apple inputs and hardware evidence.
