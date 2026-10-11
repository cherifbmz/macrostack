# Build and install without a Mac

The free route uses **your Windows PC + GitHub's cloud Mac + your iPhone**. A regular Apple ID is sufficient for the AltStore Classic installation route. No paid Apple Developer membership or TestFlight is required for this personal prototype.

This assumes you can connect your iPhone to the Windows PC. If you literally only have access to the iPhone and cannot use a computer, this particular installation route is not available.

The source is at [cherifbmz/macrostack](https://github.com/cherifbmz/macrostack). Version 0.5 simplifies the camera screen and adds available rear/front camera selection plus continuous flashlight controls. All 33 automated tests and the iPhone Release build passed in [run 38142362284](https://github.com/cherifbmz/macrostack/actions/runs/38142362284). The verified installer is `build/MacroStack-0.5.0-unsigned.ipa`. Steps 1 and 2 are retained for rebuilding or making your own copy.

## Updating your existing installation

1. Save any important existing results to Photos or Files.
2. Transfer the new `MacroStack-0.5.0-unsigned.ipa` to your iPhone's Files app.
3. Keep AltServer running on the Windows PC and connect the phone using your existing working setup.
4. In AltStore Classic, open **My Apps → +**, select the new IPA and use the same Apple ID as before. Keep the existing MacroStack app installed; the new build uses the same app identifier.
5. Choose **0.5×** for close insects, **1×** for Main, **Tele** for the telephoto lens, or **Front**. The buttons show only cameras available on your phone. Main and Tele require more distance from the subject.
6. Choose **Still** for a supported phone and motionless insect. Tap the subject and press the round shutter. **Moving** captures individual photos to review; **Photo** takes one image. Unsupported modes are disabled on lenses without the required focus/exposure controls.
7. Tap the top **flashlight icon** for continuous light. Open **Capture settings** using the sliders icon to set its strength, capture timer, quality and other options. The light switches off when capture finishes or you leave the camera.
8. For precise still-subject focus, tap **Focus range**, tap the closest detail, and **Set near point**. Tap the farthest detail and **Set far point**. Preview each end, then Done and capture.
9. Open **Projects** at the bottom left to inspect saved originals, exclude bad frames, re-stack and create separate detail/export versions. Keep originals enabled under **Capture settings → Advanced** if you want to re-stack later.

This remains a free personal installation with the same periodic refresh requirement. Rebuilding the app does not remove that requirement.

## 1. Put the source in your GitHub account

Create an empty repository named `macrostack` in your GitHub account.

- Standard GitHub-hosted runners are free for public repositories. Public means anyone can read the source.
- Private repositories use the account's included Actions allowance and can incur charges beyond it. If keeping the source private, check your allowance and spending settings before running macOS jobs.
- Do not add Apple ID passwords, certificates, or other secrets to the repository. This workflow does not need them.

Use your normal Git client to upload this folder, including `.github/workflows/ios.yml`. With Git in PowerShell, the following is one way, replacing `YOUR-USERNAME` first:

```powershell
Set-Location -LiteralPath 'C:\Users\k\Documents\ChatGPT\macro iphone'
git add .
git commit -m "Add MacroStack iPhone prototype"
git branch -M main
git remote add origin https://github.com/YOUR-USERNAME/macrostack.git
git push -u origin main
```

Sign into GitHub through your Git client's normal authentication flow. If Git asks for a commit name/email, configure the identity you want associated with the code, then repeat the commit. If a remote named `origin` already exists, inspect it with `git remote -v` instead of adding it again.

The current source has already been uploaded to `cherifbmz/macrostack` with your approval.

## 2. Build the app on GitHub's Mac

1. Open the repository's **Actions** tab.
2. Select **Build iPhone app**. A push to `main` starts it, or choose **Run workflow** manually.
3. Wait for all steps to pass. It generates the Xcode project, runs synthetic image tests in an iPhone simulator, compiles a Release build for a real iPhone, and packages it.
4. Download the artifact named **MacroStack-unsigned** from the completed run.
5. Extract the downloaded ZIP. Inside is `MacroStack-unsigned.ipa`.

The unsigned IPA cannot be installed just by tapping it. AltStore signs it for your Apple ID in the next step.

If a workflow fails, download `build-diagnostics` or copy the first compiler/test error and bring it back to this chat. Do not bypass failing image tests to assume the app works.

## 3. Install AltStore Classic from Windows

Follow the current [official Windows installation guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows). Use **AltStore Classic**, which works with AltServer on your PC.

In outline:

1. Install the Apple iTunes/iCloud components specified in the guide, then install AltServer for Windows.
2. Connect the iPhone by USB and trust the PC on the phone.
3. Enable the Wi-Fi sync option described in the guide.
4. Use the AltServer tray menu to install AltStore on the iPhone with your Apple ID.
5. Trust the developer profile in iPhone Settings when prompted and enable **Settings → Privacy & Security → Developer Mode**, including its restart/confirmation steps.

Enter credentials only into the relevant Apple/AltStore authentication flow. No credentials are needed in this chat or in GitHub Actions.

## 4. Install MacroStack

1. Transfer `MacroStack-unsigned.ipa` to the iPhone's Files app, for example using iCloud Drive.
2. Keep AltServer running on the PC, with the phone connected by USB or reachable using the supported Wi-Fi sync setup.
3. On the iPhone, open AltStore Classic → **My Apps** → **+** and select the IPA.
4. Wait for signing and installation, then open MacroStack and allow camera access.
5. Read the **Quick guide** in Capture settings. Leave Full resolution on for detail; Standard trades detail for lower memory use and faster processing.

## 5. Keep the free install working

With a free Apple ID, sideloaded apps expire after **7 days** unless refreshed. Open AltStore and use **Refresh All** while AltServer is reachable; background refresh may also handle it. Free-account limits also restrict the number of sideloaded apps and App IDs. See [AltStore's explanation](https://faq.altstore.io/altstore-classic/your-altstore).

Save important outputs to Photos or Files. Deleting the app removes its private data. Ordinary refreshes are not the same as deleting the app.

## What is free, and what remains to be validated

This route avoids buying a Mac and avoids the paid Apple Developer membership for personal testing. The hosted build policy and AltStore restrictions are external services' policies, so follow their current documentation if they change.

Simulator tests cannot verify your camera's focus behavior, insect detail, shutter behavior, capture cadence, memory limits, or how well a macro stack compares with Apple's Camera. Compare Stack/Best single at the same zoom on a stationary insect. For a burst, inspect fine details in each original and check the displayed shutter/ISO metadata. A sample of an unsatisfactory original is needed to distinguish optical magnification, missed focus, noise, motion blur and fusion artifacts.
