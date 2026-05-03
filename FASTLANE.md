# Fastlane

Fastlane is configured to ship `LMPlayground` (Lunch Sync, bundle ID `com.littlebluebug.AppleCardSync`) to TestFlight and the App Store.

## Files

- `Gemfile` — pins fastlane via bundler
- `fastlane/Fastfile` — `beta`, `release`, and `bump_version` lanes
- `fastlane/Appfile` — bundle ID + team ID (`MF7QJ9TF5S`)
- `fastlane/.env.example` — template for App Store Connect API key vars

Both upload lanes pull the next build number from TestFlight, build `LMPlayground` in Release with automatic signing, and upload. `release` does **not** auto-submit for review unless you pass `submit:true`.

## One-time setup

1. **Create an App Store Connect API key** at https://appstoreconnect.apple.com/access/integrations/api with the **App Manager** role. Download the `AuthKey_XXXXXXXXXX.p8` file.
2. **Drop the `.p8` file** in `fastlane/` (it's gitignored).
3. **Copy the env template** and fill in your key ID, issuer ID, and the `.p8` path:
   ```sh
   cd fastlane && cp .env.example .env
   ```
4. **Make sure `Config.xcconfig` exists** at the project root (gitignored — copy from `Config.template.xcconfig` if missing).

## Usage

Run from this directory (`LunchSync/`):

```sh
bundle exec fastlane beta                          # TestFlight upload
bundle exec fastlane beta changelog:"Fixed sync"   # with custom changelog
bundle exec fastlane release                       # upload to ASC, you submit manually
bundle exec fastlane release submit:true           # upload + submit for review
bundle exec fastlane bump_version type:minor       # 1.8.2 → 1.9.0 (also: patch, major)
```

## Notes

- The Fastfile uses `signingStyle: "automatic"` to match the Xcode setup. The first archive may prompt Xcode to fetch the App Store distribution profile — if that fails in headless contexts, switch to `match`.
- `ensure_git_status_clean` blocks uploads when there are uncommitted changes; pass `allow_dirty:true` to override.
- For CI (GitHub Actions, etc.), the env-var-based API key auth works the same way — store the same vars as secrets and call the same lanes.
