# MacroStack for iPhone

A native iOS camera prototype for the iPhone 13 Pro Max. It combines **focus stacking** and **multi-frame noise reduction**, with processing on the phone.

**Status:** source project prepared on Windows. It has not yet been compiled with Xcode or tested on a physical iPhone. The included GitHub Actions workflow runs the image-processing tests and builds an installable package for local signing. This is an experimental starting point, not a verified production camera app.

Start with [SETUP.md](SETUP.md) to build and install without owning a Mac.

Requires **iOS 16 or later** and an Ultra Wide camera that exposes manual focus. The intended first test device is your iPhone 13 Pro Max.

## What is implemented

- Direct selection of the physical Ultra Wide macro camera, with a manual-focus capability check.
- Near/far focus controls and live endpoint previews. Values are normalized lens positions, not distances in centimetres.
- Focus mode: one photo at each focus position.
- Noise mode: repeated photos at one focus position.
- Both mode: repeated photos at each position, followed by focus fusion.
- Exposure and white-balance locking during the stack.
- Sequential high-quality still capture; camera completion callbacks and a short focus-settling delay precede each photo.
- Translation registration with Apple Vision, with excessive motion rejected.
- Linear-light averaging within each focus group.
- Local edge-strength selection with feathered boundaries across focus groups.
- Streaming processing with rendered intermediates instead of retaining every full-size frame.
- Standard output up to 2048 pixels on the long edge; full output up to 4096 pixels. The camera's largest supported photo dimensions are requested. Alignment crops the output slightly.
- First-photo comparison, JPEG export, Save to Photos, and the share sheet.
- Cancellation, background capture shutdown, permission handling, and capture/focus timeouts.

## First capture

1. Support the phone on a tripod or another stable surface. Choose a stationary subject with visible texture and soft, steady light.
2. Open the app, allow camera access, and start a few centimetres from the subject.
3. Preview the Near endpoint and adjust until the nearest detail is sharp. Preview Far and adjust until the furthest detail is sharp. The initial values are starting guesses, not calibrated distances.
4. Select **Both**, **6 focus positions**, **3 photos per position**, and leave **Full resolution off** for the first test.
5. Let the preview exposure settle, then capture without moving the phone. Keep the app in the foreground.
6. Compare the stack with the first photo before saving. Increase resolution only after the basic capture works.

The app starts with 18 individual photos. The sequence can take tens of seconds because it captures and processes high-quality stills one at a time.

## Quality limits

This prototype does not guarantee a better photo than Apple's Camera app. Normal HEIC/JPEG stills already include Apple's processing; they are not independent unprocessed sensor samples. Averaging can reduce remaining noise, but it does not create optical resolution that the lens and sensor did not capture.

The current registration handles horizontal and vertical movement. It does **not** correct rotation, perspective, magnification changes from focus breathing, or subject motion. Focus fusion uses an edge-based heuristic and can produce halos or choose the wrong region near overlapping surfaces. A small focus range and a supported phone are important. Some heavily defocused or textureless frames may fail registration.

Internal intermediates are rendered to 8-bit sRGB to bound memory use, while blending runs in linear light. This version is not a RAW/ProRAW or 16-bit archival pipeline. The first comparison image is the first exposure, not an automatically selected best single exposure.

Full resolution uses substantially more memory and processing time. If the app closes during a full-size stack, retry Standard resolution. A production version should add memory-pressure handling, more robust registration, motion masking, and multiscale focus blending after measuring real-device results.

## Files and privacy

Images stay on the phone. Capture and processing do not use a server, API key, analytics service, or account.

Each completed result stores `MacroStack.jpg` and `First-photo.jpg` in `Documents/Stacks/<unique-id>/`. These are accessible through Files under **On My iPhone → MacroStack → Stacks**. Delete older folders there when no longer needed. Save to Photos is a separate, explicit action and requests add-only library permission. Individual source frames are discarded after processing; this version does not preserve a RAW stack.

GitHub builds compile the source code. No captured photos or Apple ID credentials are needed by the build workflow.

## Project layout

| File | Purpose |
| --- | --- |
| `MacroStack/CameraService.swift` | AVFoundation session, focus, exposure locks, still capture |
| `MacroStack/StackEngine.swift` | Alignment, denoising, focus fusion, cropping |
| `MacroStack/CameraModel.swift` | Capture sequence and JPEG output |
| `MacroStack/ContentView.swift` | Controls, instructions, comparison, saving |
| `MacroStackTests/StackEngineTests.swift` | Synthetic image tests |
| `project.yml` | XcodeGen project definition |
| `.github/workflows/ios.yml` | Cloud tests, device build, unsigned IPA artifact |

## Verification

The simulator tests cover linear-light averaging, noise reduction, recovery of sharp detail from different focus planes, the direction of a known registration shift, output sizing, and rejection of unfinished output. They are included in the cloud workflow and have not been run on Windows.

Local checks passed for project/workflow YAML parsing, simulator selection with available and unavailable devices, the empty-simulator error, asset JSON, and the icon's size/color format. These checks do not establish that the Swift code compiles or that camera/image processing works on iOS.

On the phone, verify:

- Camera permission denied and then enabled in Settings.
- Both endpoint previews actually change focus on your Ultra Wide camera.
- Noise-only, focus-only, and Both modes complete with the expected number of photos.
- A supported-phone stack shows more in-focus detail than an individual exposure without obvious doubled edges.
- Cancellation and backgrounding return the camera to a usable state.
- Share, Save to Photos, denied Photos permission, and Files output behave correctly.
- Full-resolution output dimensions, capture time, memory behavior, and thermal behavior are acceptable.

## Reference documentation

- [Apple: macro photography on iPhone](https://support.apple.com/guide/iphone/take-macro-photos-and-videos-iphfaacf2eb0/ios)
- [Apple: manual lens positioning](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setfocusmodelocked(lensposition:completionhandler:))
- [Apple: image registration](https://developer.apple.com/documentation/vision/vntranslationalimageregistrationrequest)
- [GitHub: hosted runners and public-repository availability](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [AltStore Classic: Windows installation](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [AltStore Classic: refresh and installation limits](https://faq.altstore.io/altstore-classic/your-altstore)

