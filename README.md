# MacroStack for iPhone

A native iOS camera prototype for the iPhone 13 Pro Max. It combines **focus stacking** and **multi-frame noise reduction**, with processing on the phone.

**Version 0.2:** focuses on easier autofocus and detail retention after the first version produced disappointing results on the user's iPhone. Cloud validation is in progress. The IPA needs local signing through AltStore. Simulator tests cannot establish real-camera quality; compare results on your iPhone before relying on a stack.

Start with [SETUP.md](SETUP.md) to build and install without owning a Mac.

Requires **iOS 16 or later** and an Ultra Wide camera that exposes manual focus. The intended first test device is your iPhone 13 Pro Max.

## What is implemented

- Direct selection of the physical Ultra Wide macro camera, with a manual-focus capability check.
- Tap-to-focus and automatic focus setup before each capture. Focus sweeps start at the focused subject, with Shallow/Medium/Deep ranges. These are lens-position ranges, not measured subject depth.
- Optional manual near/far focus controls and live endpoint previews.
- Focus mode: one photo at each focus position.
- Noise mode: repeated photos at one focus position.
- Both mode: repeated photos at each position, followed by focus fusion.
- Single mode: one photo without stacking, useful for moving subjects and comparison.
- Full-resolution output enabled by default, plus exposure adjustment, a 2/5-second timer, and an optional grid.
- Exposure and white-balance locking during the stack.
- Sequential high-quality still capture; camera completion callbacks and a short focus-settling delay precede each photo.
- Perspective registration with Apple Vision to compensate for small rotation, translation, and focus breathing. If estimation fails, a constrained translation fallback is reported in the result.
- Linear-light averaging with reduced contribution from disagreeing pixels, and rejection/replacement of substantially softer repeated frames within a focus group.
- Two-band focus blending uses sharper masks for detail and smoother masks for low-frequency transitions.
- Streaming processing with rendered intermediates instead of retaining every full-size frame.
- Standard output up to 2048 pixels on the long edge; full output up to 4096 pixels. The camera's largest supported photo dimensions are requested. Alignment crops the output slightly.
- A single photo selected by overall edge-detail score is aligned and cropped to match the stack. Pinch or double tap to inspect; switching comparison views preserves zoom.
- Save or share either the stack or comparison photo. Original HEIC/JPEG camera files are retained by default without recompression.
- Cancellation, background capture shutdown, permission handling, and capture/focus timeouts.

## First capture

1. Support the phone on a tripod or another stable surface. Choose a stationary subject with visible texture and soft, steady light.
2. Open the app, allow camera access, and start a few centimetres from the subject.
3. Leave **Automatic focus setup** enabled and tap the subject in the preview.
4. Select **Both**, **Shallow**, **7 focus positions**, and **2 photos per position**. Leave **Full resolution on** to preserve detail and use the **2-second timer**.
5. Capture without moving the phone and keep the app open. After the timer, autofocus and metering settle, exposure/white balance lock, and the focus sweep begins at the subject's focus.
6. Pinch or double tap the result to inspect. Switch between Stack and Best single at the same zoom. Save whichever looks better. Try a deeper sweep only if details remain out of focus.

The default Both mode captures 14 photos. Full-size processing can take tens of seconds. Use Single for moving subjects; stacking is intended for stationary scenes.

## Quality limits

This prototype does not guarantee a better photo than Apple's Camera app. Normal HEIC/JPEG stills already include Apple's processing; they are not independent unprocessed sensor samples. Averaging can reduce remaining noise, but it does not create optical resolution that the lens and sensor did not capture.

Perspective registration can compensate for modest scale changes and camera movement when enough shared detail is visible. It cannot reliably reconstruct moving subjects, strong parallax, occlusion, or textureless/heavily defocused scenes. Focus fusion still uses an edge-based heuristic and may produce halos near overlapping surfaces. Narrow the focus range if registration fails or the stack is softer than the single photo.

The running average and fused image use 16-bit floating-point linear RGB intermediates to reduce repeated quantization. Captures and final JPEGs are still processed 8-bit images; this is not a RAW/ProRAW pipeline. Best single means the highest overall edge-detail score, which may not be the image you personally prefer. Original files let you make your own selection.

Full resolution uses substantially more memory and processing time. If the app closes during a full-size stack, retry Standard resolution and fewer frames. No simulated benchmark can guarantee a better photograph than Apple's Camera; on-device memory/thermal behavior and image quality remain to be measured.

## Files and privacy

Images stay on the phone. Capture and processing do not use a server, API key, analytics service, or account.

Each result stores `MacroStack.jpg`, `Best-single.jpg`, `settings.json`, and `status.txt` in `Documents/Stacks/<unique-id>/`. With Save original camera photos enabled, the same folder contains the exact captured HEIC/JPEG files, named with capture order and focus position. A cancelled or failed capture can leave a partial folder with its originals and an in-progress status. Files are accessible through **Files → On My iPhone → MacroStack → Stacks**; delete old folders there when no longer needed. Save to Photos is a separate action using add-only library permission. Source files can consume tens of megabytes per stack.

GitHub builds compile the source code. No captured photos or Apple ID credentials are needed by the build workflow.

## Project layout

| File | Purpose |
| --- | --- |
| `MacroStack/CameraService.swift` | AVFoundation session, focus, exposure locks, still capture |
| `MacroStack/StackEngine.swift` | Alignment, denoising, focus fusion, cropping |
| `MacroStack/ImageAlignment.swift` | Perspective warp validation and conservative crop |
| `MacroStack/CaptureArchive.swift` | Original camera files, metadata, and JPEG results |
| `MacroStack/ZoomablePhoto.swift` | Zoomable matched comparison |
| `MacroStack/CameraModel.swift` | Capture sequence and JPEG output |
| `MacroStack/ContentView.swift` | Controls, instructions, comparison, saving |
| `MacroStackTests/StackEngineTests.swift` | Synthetic image tests |
| `project.yml` | XcodeGen project definition |
| `.github/workflows/ios.yml` | Cloud tests, device build, unsigned IPA artifact |

## Verification

The expanded simulator tests cover linear-light averaging, noise reduction, focus detail, translation direction, scale/rotation correction, invalid warp rejection, soft-repeat rejection, moving-patch protection, matched comparison size, output sizing, unfinished output, focus ranges, and Single mode defaults. Version 0.2 validation is pending. The legacy Core Image kernel initializer remains a future migration task.

Local checks passed for project/workflow YAML parsing, simulator selection with available and unavailable devices, the empty-simulator error, asset JSON, and the icon's size/color format. These checks do not establish that the Swift code compiles or that camera/image processing works on iOS.

On the phone, verify:

- Camera permission denied and then enabled in Settings.
- Tap autofocus and automatic focus setup acquire the intended subject; manual endpoint previews also work.
- Single, Noise, Focus, and Both modes complete with expected photo counts.
- A supported-phone stack shows more in-focus detail than an individual exposure without obvious doubled edges.
- Cancellation and backgrounding return the camera to a usable state.
- Share, Save to Photos, denied Photos permission, and Files output behave correctly.
- Zoom/pan and comparison preserve the inspected region; originals retain camera metadata and full dimensions.
- Full-resolution output dimensions, capture time, memory behavior, and thermal behavior are acceptable.

## Reference documentation

- [Apple: macro photography on iPhone](https://support.apple.com/guide/iphone/take-macro-photos-and-videos-iphfaacf2eb0/ios)
- [Apple: manual lens positioning](https://developer.apple.com/documentation/avfoundation/avcapturedevice/setfocusmodelocked(lensposition:completionhandler:))
- [Apple: image registration](https://developer.apple.com/documentation/vision/vntranslationalimageregistrationrequest)
- [GitHub: hosted runners and public-repository availability](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [AltStore Classic: Windows installation](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
- [AltStore Classic: refresh and installation limits](https://faq.altstore.io/altstore-classic/your-altstore)

