# App Store Release Notes

Current repo preparation status:

- `Release-MAS` archive builds successfully
- `Release-MAS` keeps the App Store bundle ID: `com.dev.kkuk.CommandReopen`
- `Release-Direct` now uses a separate bundle ID: `com.dev.kkuk.CommandReopen.direct`
- App Sandbox is enabled
- Outgoing network entitlement is disabled for `Release-MAS`
- User-selected file entitlement is disabled for `Release-MAS`
- Public privacy and support pages are available under `docs/`

What still requires Apple account access:

1. Create or confirm the final App Store Connect app record
2. Confirm the final app name and bundle ID
3. Provide an App Store Connect API key for metadata and submission automation
4. Upload the signed `MAS` build through Xcode Organizer

Recommended first App Store version:

- Marketing version: `1.0.0`
- First build number: `1`
- If review requires fixes before launch, keep `1.0.0` and upload build `2`, `3`, and so on

Suggested publish flow for this repo:

1. Enable GitHub Pages from the `docs/` folder
2. Use the resulting URLs for:
   - Privacy Policy URL: `.../privacy/`
   - Support URL: `.../support/`
3. Create the app record if it does not exist:

```bash
asc apps create \
  --name "Command Reopen" \
  --bundle-id "com.dev.kkuk.CommandReopen" \
  --sku "COMMANDREOPEN-MAC-001" \
  --primary-locale "en-US" \
  --platform MAC_OS
```

4. Create the App Store version:

```bash
asc versions create --app "APP_ID" --version "1.0.0" --platform MAC_OS
```

5. Fill metadata:

```bash
asc localizations update \
  --app "APP_ID" \
  --type app-info \
  --locale "en-US" \
  --name "Command Reopen" \
  --subtitle "Reopen windows with Command+Tab" \
  --privacy-policy-url "PRIVACY_URL"

asc app-info set \
  --app "APP_ID" \
  --version "1.0.0" \
  --platform MAC_OS \
  --locale "en-US" \
  --description "Reopen closed and minimized windows when switching apps with Command+Tab." \
  --keywords "command tab,window,reopen,menu bar,macos,productivity" \
  --support-url "SUPPORT_URL"
```

6. Add review notes from `appstore/review-notes.txt`
7. Upload screenshots for `APP_DESKTOP`
8. Validate before submission:

```bash
asc validate --app "APP_ID" --version "1.0.0" --platform MAC_OS --strict
```

Repo helpers:

- Copy `appstore/.env.example` to `appstore/.env`
- Fill the App Store Connect API credentials and public URLs
- Run `appstore/scripts/configure_appstore_metadata.sh`
- After Xcode upload finishes processing, run `appstore/scripts/check_uploaded_build.sh`
