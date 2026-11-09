# Releasing Annotator

Annotated screenshots ship as a notarized **Annotator.dmg** on [GitHub Releases](https://github.com/rhagerty32/annotator/releases). Sparkle reads `appcast.xml` from that same release, so **Check for Updates…** in the app installs the new version.

A release tag looks like `v1.2.3` (major.minor.patch, with the `v` prefix). The app's `CFBundleShortVersionString` and `CFBundleVersion` are both `1.2.3`. Sparkle compares `CFBundleVersion` to the appcast's `sparkle:version`.

Do not commit a certificate, an App Store Connect API key, or the Sparkle private key. Those stay in GitHub Actions secrets or in your login keychain.

## What you are publishing

The release workflow (`.github/workflows/release.yml`) runs on a tag push:

1. Builds a universal Annotator.app (arm64 and x86_64 when the toolchain supports it).
2. Puts `Annotator` and the `Capture` helper in `Contents/MacOS`, and Sparkle in `Contents/Frameworks`.
3. Sets the bundle id to `com.rhagerty32.annotator` and `LSUIElement` so the app stays out of the Dock.
4. Signs with a Developer ID Application certificate, notarizes, and staples.
5. Builds a drag-to-Applications `Annotator.dmg`, signs it, notarizes it, and staples it.
6. Signs that DMG with the Sparkle EdDSA private key and writes `appcast.xml`.
7. Attaches `Annotator.dmg` and `appcast.xml` to the GitHub Release for that tag.

If any signing secret is missing, the job stops before it creates a release. It will not upload an unsigned or ad-hoc app. Gatekeeper would block that download.

Pull-request CI still builds an ad-hoc app and DMG so packaging stays working. Those artifacts are not uploaded.

## One-time: Sparkle EdDSA key

Generate this key once, on a Mac. Sparkle 2.10.1 is the version linked from `Package.swift` (`packaging/sparkle-version`).

```bash
curl -fsSL -o /tmp/sparkle.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz
mkdir -p /tmp/sparkle && tar -xJf /tmp/sparkle.tar.xz -C /tmp/sparkle
/tmp/sparkle/bin/generate_keys --account annotator
```

The tool stores the private key in your login keychain under the account name `annotator` and prints the public key. That public key is safe to commit. The private key is not.

Print the public key again any time:

```bash
/tmp/sparkle/bin/generate_keys --account annotator -p
```

Put that single line in either place (they must match if you use both):

- GitHub secret `SPARKLE_EDDSA_PUBLIC_KEY`
- `packaging/SUPublicEDKey` in this repo (one line, no quotes)

Export the private key into a file only long enough to copy it into a secret, then delete the file:

```bash
/tmp/sparkle/bin/generate_keys --account annotator -x "$HOME/annotator-sparkle-private-key.txt"
```

The file contents are the `SPARKLE_EDDSA_PRIVATE_KEY` secret. The repo gitignore ignores `sparkle-private-key*`. Delete the file after the secret is saved. Do not paste the private key into a pull request, an issue, or a chat.

Losing the private key means already-shipped apps cannot verify a new update until you ship a Developer ID-signed disk image that rotates the key. Keep a backup in a password manager.

## One-time: Apple signing

You need a **Developer ID Application** certificate (not a Mac Development or Apple Distribution certificate) and an App Store Connect API key with access to notarization.

### Option A — GitHub Actions secrets

Create the API key in App Store Connect → Users and Access → Integrations → App Store Connect API. Download the `.p8` once. Note the Key ID and the Issuer ID.

Export the Developer ID certificate from Keychain Access as a `.p12` (include the private key) and pick a password for that file.

Repository secrets, exact names:

| Secret | Value |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | `base64 -i YourCert.p12` (macOS) and nothing else |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for that `.p12` |
| `APPLE_TEAM_ID` | 10-character Team ID inside the certificate name |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect Key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | App Store Connect Issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | `base64 -i AuthKey_XXXX.p8` |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Contents of the `generate_keys -x` file |
| `SPARKLE_EDDSA_PUBLIC_KEY` | Output of `generate_keys -p`, unless `packaging/SUPublicEDKey` is already committed |

The workflow generates its own temporary keychain password. You do not add one.

Delete the `.p12` and `.p8` from disk after the secrets are stored. They are gitignored, and they still should not sit in a checkout.

### Option B — sign on your Mac

Use this when the Developer ID belongs to a work team and should not be copied into GitHub secrets.

1. Install the Developer ID Application certificate in your login keychain.
2. Store notarization credentials in the keychain (the profile name `annotator-notary` is what `scripts/release-local.sh` looks for):

   ```bash
   xcrun notarytool store-credentials annotator-notary \
     --key /path/to/AuthKey_XXXX.p8 \
     --key-id "KEYID" \
     --issuer "ISSUER-UUID"
   ```

   You can use an Apple ID app-specific password instead of the API key. `notarytool store-credentials --help` lists the flags. The profile never goes in the repo.

3. Keep the Sparkle private key in the keychain (`generate_keys --account annotator`) or point `SPARKLE_EDDSA_PRIVATE_KEY_FILE` at a file outside the repo.
4. Make sure the public key is available as `SPARKLE_EDDSA_PUBLIC_KEY` or `packaging/SUPublicEDKey`.
5. Do **not** push the version tag until you have uploaded the notarized files yourself. A tag push starts GitHub Actions, and that job fails closed without the secrets above. It will not publish a DMG.

Build and notarize locally:

```bash
./scripts/release-local.sh 1.2.3
```

The script prints a `gh release create` command. Run that to attach `dist/Annotator.dmg` and `dist/appcast.xml` to `v1.2.3`. Create the git tag locally if you want the release version to match, but if the signing secrets are not in GitHub, do not `git push` the tag. Pushing it starts the workflow, which will fail and will not replace your upload with an unsigned build.

`APPLE_TEAM_ID` is optional on your Mac when the keychain has only one Developer ID Application identity. Set it when you have more than one team.

## Cut a release (GitHub Actions)

On `main`, with the secrets in place and the public key either committed or stored as `SPARKLE_EDDSA_PUBLIC_KEY`:

```bash
git tag v1.2.3
git push origin v1.2.3
```

Watch the **Release** workflow. When it is green, the Releases page has `Annotator.dmg` and `appcast.xml`.

The feed baked into the app is:

`https://github.com/rhagerty32/annotator/releases/latest/download/appcast.xml`

That URL always follows the latest release's `appcast.xml`. Each appcast item points at that version's `Annotator.dmg`.

## What a person does to update

1. Install the first version from the DMG (drag Annotator to Applications). Running the app from the disk image itself is read-only, and Sparkle will not replace it there.
2. Open Annotator.
3. Choose **Check for Updates…** from the Annotator menu or the Help menu.
4. Sparkle shows the new version. Confirm the install. The app relaunches from `/Applications`.

Automatic checks are off (`SUEnableAutomaticChecks` is false) so a screenshot session is not interrupted by an update prompt. Updates happen when someone asks.

A build produced by `npm run package:app` without the public key still has the menu item. Choosing it explains that updates are not configured. Only a release build, which has `SUPublicEDKey` in Info.plist, contacts the feed.

## Local packaging that is not a release

```bash
npm run package:app    # dist/Annotator.app, ad-hoc signature
npm run package:dmg    # dist/Annotator.dmg
```

Use this to click through the app bundle. Do not upload it. Gatekeeper blocks an ad-hoc app downloaded from the internet.

## If a release is bad

Sparkle will not downgrade. Ship a newer tag (`v1.2.4`) with the fix, or delete the bad GitHub Release so `releases/latest` points at the previous tag and ask people who already updated to install that previous DMG by hand.
