# MacroStack for iPhone

A native iOS camera prototype for the iPhone 13 Pro Max. It combines **focus stacking** and **multi-frame noise reduction**, with processing on the phone.

**Version 0.5.1:** fixes preview touch handling so a magnified camera preview cannot intercept taps on Flashlight or other surrounding controls. The camera screen, lens selection, continuous flashlight and project tools from 0.5 remain available. All 37 automated tests and the iPhone Release build passed. The IPA needs local signing through AltStore.

Start with [SETUP.md](SETUP.md) to build and install without owning a Mac.

Requires **iOS 16 or later**. Focus stacking requires a camera that exposes manual lens positioning. Photo and Noise modes can use fixed-focus cameras. The intended first test device is your iPhone 13 Pro Max.

## What is implemented

- Selection of available physical Ultra Wide, Main, Telephoto and Front cameras. Ultra Wide is preferred at startup. Focus-stack and manual-shutter capabilities are checked for each camera.
- Tap-to-focus and automatic focus setup before each capture. Focus sweeps start at the focused subject, with Shallow/Medium/Deep ranges. These are lens-position ranges, not measured subject depth.
- Optional manual near/far focus controls and live endpoint previews.
- Focus mode: one photo at each focus position.
- Noise mode: repeated photos at one focus position.
- Both mode: repeated photos at each position, followed by focus fusion.
- Single mode: one photo without stacking, useful for comparison.
- Still insect preset: 9 focus positions across a shallow sweep, one photo at each position, full resolution and a two-second timer. This is the startup preset.
- Moving insect preset: 5 individual burst photos, 1/500-second requested shutter, full resolution and no timer. Choose 3–8 photos and 1/250, 1/500 or 1/1000 second. ISO compensates from the metered exposure within camera limits; an ISO-limit message indicates insufficient light.
- Burst uses speed-prioritized photo capture to preserve manual shutter/ISO settings, plus continuous autofocus around the tapped area when Automatic focus is on. It is sequential still capture, not a guaranteed high-frame-rate burst or an insect-tracking system.
- A yellow subject box follows your tap and determines the area used for sharpness selection. Optional 2× preview magnification helps inspect focus without cropping the saved photo.
- Full-resolution output enabled by default, plus exposure adjustment, a 2/5-second timer, and an optional grid.
- Exposure and white-balance locking during the stack.
- Sequential still capture; camera completion callbacks and a short manual-focus settling delay precede each stacked photo. All camera originals are written to disk before registration or fusion begins, avoiding heavy processing between captures. Captured duration appears in the result.
- Perspective registration with Apple Vision to compensate for small rotation, translation, and focus breathing. If estimation fails, a constrained translation fallback is reported in the result.
- Linear-light averaging with reduced contribution from disagreeing pixels, and rejection/replacement of substantially softer repeated frames within a focus group.
- Two-band focus blending uses sharper masks for detail and smoother masks for low-frequency transitions.
- Streaming processing with rendered intermediates instead of retaining every full-size frame.
- Standard output up to 2048 pixels on the long edge; full output up to 4096 pixels. The camera's largest supported photo dimensions are requested. Alignment crops the output slightly.
- A single photo selected by edge-detail score in the subject box is aligned and cropped to match the stack. Pinch or double tap to inspect; switching comparison views preserves zoom.
- Burst never registers, averages, fuses or alignment-crops images. Review every original, override the suggested sharpest photo, and save/share the original camera file. Exposure and ISO from its EXIF metadata are shown when available.
- Save or share either the stack or comparison photo. Original HEIC/JPEG camera files are retained by default without recompression.
- Cancellation, background capture shutdown, permission handling, and capture/focus timeouts.

## Version 0.5.1: flashlight touch fix

The previous preview used a SwiftUI scale transform for 2× inspection. Its enlarged touch area could extend outside the visually clipped viewfinder. The preview now keeps its UIView bounds fixed and enlarges only the video layer inside it. Tap-to-focus converts through that layer's coordinates, and an explicit viewfinder hit shape prevents hits outside the viewport. Flashlight and Settings have full 48-point touch targets; the top controls stay above the preview.

Regression coverage includes UIKit hit-testing and coordinate conversion, plus UI tests that tap the real preview gesture recognizer and the flashlight button at 1× and 2× preview magnification. Tests also cover an unavailable flashlight and the padding around the button. Simulator tests substitute only hardware state/light actions; they do not establish physical LED behavior.

## Version 0.5: simpler camera and lighting

- The camera screen keeps the preview, lens selector, three modes, shutter, Projects and Focus range on one screen. Detailed options move to Capture settings; lower-level processing controls are under Advanced.
- Still selects the stationary-insect focus-stack preset; Moving selects individual burst photos; Photo takes a single photo. These controls replace the old long scrolling form.
- Lens buttons select physical cameras: **0.5×**, **1×**, **Tele**, and **Front** when present. Tele is the native telephoto lens, not digital zoom. Switching resets the focus range and tap location and turns the light off. Unsupported capture modes fall back to Photo; unavailable controls are disabled.
- The front preview and saved photos use the same unmirrored orientation. Front cameras without manual lens positioning cannot sweep focus, but can capture Photo or Noise; Moving requires custom exposure support.
- The top **Flashlight** button provides continuous illumination for composing and capture. Choose Low, Medium or High in Capture settings. Availability is checked at runtime; the front camera has no rear-facing torch. Light turns off after the capture sequence, on errors/cancellation, when changing cameras, opening Projects/results, or backgrounding the app. This is continuous torch illumination, not a per-photo flash or a simulated front screen flash.
- **Focus range** guides you through tapping and setting the nearest and farthest details, with endpoint previews. Closing the guide with × restores automatic range; Done preserves the manual range.
- The result screen prioritizes the photograph, comparison, Save and Share. Capture metadata is under Photo details. Projects retains its re-stacking and version tools.

Use 0.5× for very close insect work on iPhone 13 Pro Max. Main and Tele need more working distance; adding lens switching does not give every lens macro focusing. Choose Photo for an easy single-camera comparison.

Camera discovery follows [Apple's capture-device API](https://developer.apple.com/documentation/avfoundation/choosing-a-capture-device). Light controls check both hardware and current availability as described in [Apple's torch documentation](https://developer.apple.com/documentation/avfoundation/avcapturedevice/hastorch). Manual lens positions are reset on camera changes because they do not represent consistent distances across lenses.

## Version 0.4: capture and project tools

The workflow was informed by the published [Zeus Focus Stacking feature list](https://zeusfocusstacking.com/) and [App Store description](https://apps.apple.com/us/app/zeus-focus-stacking/id6471365204), reviewed October 11, 2026. This is an independent implementation; it does not use Zeus code, calibration profiles, assets or neural models. There is no measured evidence that MacroStack produces better photographs than Zeus.

| Workflow | MacroStack 0.4 |
| --- | --- |
| Live focus brackets | Tap the nearest detail, Set Near; tap the farthest detail, Set Far. Preview either endpoint before capture. |
| Frame spacing | 3–20 focus positions; Even or Near dense. Both are lens-position distributions, not a measured depth map. |
| Capture priority | Speed, Balanced or Quality at the same selected output resolution. Moving insect burst always uses Speed to respect its shutter setting. |
| Project gallery | Reopen saved results and retained originals, including compatible older captures and incomplete projects. |
| Selective re-stacking | Inspect originals, exclude frames, choose alignment/motion protection/resolution, and save a new stack with a processing recipe. Original capture groups are retained even when frames are excluded. |
| Separate detail versions | Adjustable conventional unsharp-mask detail, with source preserved and an edit recipe. Hold to compare with the original result. |
| Export | JPEG and HEIC for separate versions; HEIC requires an available device encoder. Save to Photos or share. |

Neural super resolution, depth-aware adaptive bracketing, model-specific lens calibration, automatic iCloud sync, landscape capture and 48 MP capture are not implemented. The iPhone 13 Pro Max has [12 MP cameras](https://support.apple.com/en-us/111870); upscaling would not turn that hardware into a 48 MP camera. Original files can still be shared to a destination of your choice through iOS.

### Set an exact subject range

1. Keep the phone supported. Tap the nearest insect detail and wait for focus to settle.
2. Open **Focus range**, press **Set near point**, then tap the farthest detail that should be sharp and press **Set far point**.
3. Check **Preview near** and **Preview far**, then Done. Advanced settings also include manual sliders.
4. Use 10–20 positions for closer spacing through a deep subject, with Quality capture. More frames take longer and cannot repair movement.

The original automatic Shallow/Medium/Deep ranges and insect presets remain available. Set Near/Far switches to manual endpoints so subsequent taps do not overwrite a bracket you already marked.

### Inspect and re-stack a saved project

Open the **Projects** button after closing the capture result. Select a project, inspect its original frames, deselect unwanted frames, and choose **Re-stack selected frames**. A new Restack result, a matching Reference photo and a JSON recipe are written alongside the initial result; the initial result and excluded source photos are preserved. A single remaining frame is allowed but cannot extend depth of field. Burst projects remain individual photos and are not offered focus re-stacking.

For a separate detail/export version, choose a version, set the detail amount and JPEG/HEIC format, then Create new version. Use 0% detail for conversion alone, and start from Original result for independent sharpening comparisons. The detail pass emphasizes existing edges; it does not reconstruct missing insect detail and can amplify halos or noise. Versions with different alignment crops may not match at the same zoom.

## First capture

1. Support the phone on a tripod or another stable surface. Choose a stationary subject with visible texture and soft, steady light.
2. Open the app, allow camera access, and start a few centimetres from the subject.
3. Leave **Automatic focus setup** enabled and tap the subject in the preview.
4. Select **Still**. This selects Focus, Shallow, 9 focus positions, one photo per position, Full resolution and the two-second timer. Try Both only if noise is the main problem and both phone and insect stay still.
5. Capture without moving the phone and keep the app open. After the timer, autofocus and metering settle, exposure/white balance lock, and the focus sweep begins at the subject's focus.
6. Pinch or double tap the result to inspect. Switch between Stack and Best single at the same zoom. Save whichever looks better. Try a deeper sweep only if details remain out of focus.

The startup Still insect preset captures 9 photos. Full-size processing can take tens of seconds after capture. For a moving insect, choose **Moving**, tap its eye, keep it inside the yellow box and use bright steady light. Review the burst originals rather than stacking them. The faster shutter may increase noise or underexpose in poor light and cannot guarantee sharp wings or fast flight.

## Quality limits

This prototype does not guarantee a better photo than Apple's Camera app. Normal HEIC/JPEG stills already include Apple's processing; they are not independent unprocessed sensor samples. Averaging can reduce remaining noise, but it does not create optical resolution that the lens and sensor did not capture.

Perspective registration can compensate for modest scale changes and camera movement when enough shared detail is visible. It cannot reliably reconstruct moving subjects, strong parallax, occlusion, or textureless/heavily defocused scenes. Focus fusion still uses an edge-based heuristic and may produce halos near overlapping surfaces. Narrow the focus range if registration fails or the stack is softer than the single photo.

The running average and fused image use 16-bit floating-point linear RGB intermediates to reduce repeated quantization. Stack processing and final JPEGs are 8-bit images; this is not a RAW/ProRAW pipeline. Best single means the highest edge-detail score inside a fixed subject box, which may not be the image you personally prefer. The box does not follow an insect that moves across the frame. Burst review lets you make your own selection from the originals.

Full resolution uses substantially more memory and processing time. If the app closes during a full-size stack, retry Standard resolution and fewer frames. No simulated benchmark can guarantee a better photograph than Apple's Camera; on-device memory/thermal behavior and image quality remain to be measured.

## Files and privacy

Images stay on the phone. Capture and processing do not use a server, API key, analytics service, or account.

Each result stores `MacroStack.jpg`, `Best-single.jpg`, `settings.json`, and `status.txt` in `Documents/Stacks/<unique-id>/`. Every captured HEIC/JPEG is staged there before processing. With Save original camera photos enabled, these exact originals remain after completion. Otherwise, this capture's temporary frame files are removed only after successful export. Burst always retains its originals. Filenames include capture order and the commanded focus position when focus is locked; continuous-autofocus burst files omit the focus position. A cancelled or failed capture can leave a partial folder with originals and an in-progress status. Files are accessible through **Files → On My iPhone → MacroStack → Stacks**; delete old folders there when no longer needed. Save to Photos is a separate action using add-only library permission. Source files can consume tens of megabytes per capture.

GitHub builds compile the source code. No captured photos or Apple ID credentials are needed by the build workflow.

## Project layout

| File | Purpose |
| --- | --- |
| `MacroStack/CameraService.swift` | Camera discovery/switching, torch, focus, exposure locks, still capture |
| `MacroStack/CameraChoice.swift` | Camera capability checks and simplified shooting modes |
| `MacroStack/CaptureSettingsView.swift` | Capture settings and advanced controls |
| `MacroStack/StackEngine.swift` | Alignment, denoising, focus fusion, cropping |
| `MacroStack/ImageAlignment.swift` | Perspective warp validation and conservative crop |
| `MacroStack/CaptureArchive.swift` | Original camera files, metadata, and JPEG results |
| `MacroStack/ZoomablePhoto.swift` | Zoomable matched comparison |
| `MacroStack/BurstResultView.swift` | Review, metadata, save/share for original burst frames |
| `MacroStack/ExposurePlan.swift` | Metering compensation and shutter/ISO limits |
| `MacroStack/ProjectFiles.swift` | Legacy project loading, grouping, separate versions and export |
| `MacroStack/ProjectModel.swift` | Selective re-stacking and version creation |
| `MacroStack/ProjectGalleryView.swift` | Project browser, original-frame inspection and comparison |
| `MacroStack/CameraModel.swift` | Capture sequence and JPEG output |
| `MacroStack/ContentView.swift` | Controls, instructions, comparison, saving |
| `MacroStackTests/StackEngineTests.swift` | Synthetic image tests |
| `project.yml` | XcodeGen project definition |
| `.github/workflows/ios.yml` | Cloud tests, device build, unsigned IPA artifact |

## Verification

Version 0.5.1 passed 32 unit/image tests and five UI tests with zero failures in [run 38143872062](https://github.com/cherifbmz/macrostack/actions/runs/38143872062), from source commit `b92589639265eaaa694b36ed7922ae3ae13e2906`. The new regression tests verify flashlight toggles do not reach the preview recognizer at normal or 2× magnification, including button padding and an unavailable flashlight. Preview taps and Settings navigation still work. The simulator screenshot was inspected. The iPhone Release build succeeded; downloaded IPA integrity, platform and metadata were verified (0.5.1, build 6). SHA-256: `3c2845a46c840346854ee4f0001257e8086d318c08558d97ee72d01abfca8963`. Physical camera focus and torch behavior still require on-device confirmation.


Version 0.5 passed 30 unit/image tests and three UI navigation tests with zero failures in [run 38142362284](https://github.com/cherifbmz/macrostack/actions/runs/38142362284), from source commit `2f75e242c9400a511784201b12064b76f11f3d73`. The iPhone Release build succeeded. The downloaded IPA was checked for archive integrity, an iPhoneOS executable, bundle `com.personal.macrostack`, version `0.5.0`, build `5`, and minimum iOS `16.0`. SHA-256: `5f6f67995d3f03083a5021fdade8255cb78d4105bdc34cc96a6219e81a9d98db`.

The new tests cover camera capabilities, reachable camera controls, settings navigation and Projects navigation. Screenshots of the camera, settings and empty Projects screens were inspected on the iPhone SE (3rd generation) simulator. Controls fit without scrolling on the camera screen; settings scroll separately. The camera screen screenshot has no live camera or lens selector because the simulator has no camera hardware. UI tests run without camera hardware; their screenshots verify layout and navigation, not lens operation. Physical switching, front-camera focus behavior, torch brightness/thermal availability, orientation and actual photograph quality must be verified on the iPhone.


Version 0.4 passed all 26 simulator tests with zero failures, including HEIC export, and the iPhone Release build in [run 38098160538](https://github.com/cherifbmz/macrostack/actions/runs/38098160538), from source commit `7807bcc043e9a87e764dac04c63d03f274c2fbf4`. The downloaded IPA was checked for archive integrity, an iPhoneOS executable, bundle identifier `com.personal.macrostack`, version `0.4.0`, build `4`, and minimum iOS `16.0`. Its SHA-256 is `50321470a82780d81053e2f66ec4596c4f2147fcee19b240beee0937519716a7`.

The seven new tests cover legacy settings, 20-position spacing, exclusions without regrouping focus planes, old/incomplete project discovery, preservation of sources and dimensions during version export, HEIC export, and detail adjustment on a flat field. The existing 19 tests cover stacking, registration, burst selection, focus presets and exposure planning. The legacy Core Image kernel initializer remains a future migration task. Real-camera behavior and UI interaction on a physical iPhone still need validation.

Local checks passed for project/workflow YAML parsing, simulator selection with available and unavailable devices, the empty-simulator error, asset JSON, and the icon's size/color format. These checks do not establish that the Swift code compiles or that camera/image processing works on iOS.

On the phone, verify:

- Camera permission denied and then enabled in Settings.
- Tap autofocus and automatic focus setup acquire the intended subject; manual endpoint previews also work.
- Single, Noise, Focus, and Both modes complete with expected photo counts.
- A supported-phone stack shows more in-focus detail than an individual exposure without obvious doubled edges.
- Cancellation and backgrounding return the camera to a usable state.
- Share, Save to Photos, denied Photos permission, and Files output behave correctly.
- Zoom/pan and comparison preserve the inspected region; originals retain camera metadata and full dimensions.
- The yellow subject box follows taps correctly with preview magnification on and off.
- Moving insect burst uses the requested shutter (check the per-photo EXIF readout), continuous autofocus is useful, and the original selected in review is the one saved/shared.
- A burst's actual capture cadence is acceptable, and bright/low-light examples establish how much detail the shutter/ISO tradeoff preserves.
- Use Focus range to mark and preview Near/Far on two parts of an insect; verify a later tap does not change an already marked manual endpoint.
- Switch 0.5×, 1×, Tele and Front; check preview orientation against the saved photo and verify unsupported modes are disabled.
- Try Low/Medium/High flashlight; verify off after capture, camera switching, opening Projects/results, and backgrounding. Verify unavailable/thermal states do not leave the UI claiming the light is on.
- Open old and new projects, inspect originals, exclude a frame, re-stack, and verify the first result remains available.
- Create detail versions at 0% and a moderate amount; compare, save and share JPEG/HEIC outputs at expected dimensions.
- Full-resolution output dimensions, capture time, memory behavior, and thermal behavior are acceptable.

## Reference documentation

- [Apple: macro photography on iPhone](https://support.apple.com/guide/iphone/take-macro-photos-and-videos-iphfaacf2eb0/ios)
- [Apple: manual lens positioning](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setfocusmodelocked(lensposition:completionhandler:))
- [Apple: image registration](https://developer.apple.com/documentation/vision/vntranslationalimageregistrationrequest)
- [Apple: perspective alignment observations](https://developer.apple.com/documentation/vision/vnimagehomographicalignmentobservation)
- [GitHub: hosted runners and public-repository availability](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [AltStore Classic: Windows installation](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [AltStore Classic: refresh and installation limits](https://faq.altstore.io/altstore-classic/your-altstore)

