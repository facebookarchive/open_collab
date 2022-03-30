![iPhone_App_60_2x](https://user-images.githubusercontent.com/4399618/160677698-7e635301-1b14-4924-b056-380866e49b64.png)

# OpenCollab

A music creation and collaboration project that provides recording, trimming, and video & audio 
synchronization tools to simplify creating a multi-clip music video.

Based off of the original [Collab app by NPE](https://madewithcollab.com/).

**This repo will be maintained until July 1, 2022 at which point it will be made read-only**. Our hope is that developers interested in supporting this project over a longer term will fork the repo.

## Requirements
OpenCollab requires or works with
* iOS
* XCode

## Building OpenCollab
* Run ```pod install``` in the root project directory to install all package dependencies from the Podfile.
* Open the project (`OpenCollab.xcworkspace`) in XCode.
* Build & run the project in XCode
* To run on a device, you may need to manipulate code signing settings in the project's _Signing & Capabilities_ settings.

## How OpenCollab works
**TODO: demo video**
OpenCollab allows you to record a music video consisting of up to 6 videos stitched together. It provides several features that make recording music on your iPhone a snap:
* Support for external interfaces (e.g., Roland GoMixer Pro) and wireless headphones (e.g. Airpods)
* Record multiple takes and select your favorite one
* Advanced clip trimming for getting that perfect loop
* Nudge your clips to offset any delay from your recording interface
* Adjust volumes on a clip-by-clip basis
* Export your finished product and share it with your friends!

## Developer documentation
The original implementation of this app had server integration which allowed for features like creating accounts, a shared feed, and the ability to remix other people's collabs. This is a stripped down version of that app that only allows for creating your own videos from scratch, but a lot of code structures have been left behind as method stubs or comments for any developer that wishes to build server integration for this app.

1. TODOs for extension of this app are indicated by “## TODO :”; all other todos you may find are from the team’s development and have been left in as notes.
2. Right now there’s also no way to have a nil fragment (FragmentHost.AssetInfo.isEmpty) in any creation step, but we’ve left in some handling for nil fragments in case future extensions may introduce the concept.
3. We also built in the ability to upload a video from camera roll to create a collab from scratch using a pre-recorded clip. We never polished and released the feature, but we left it in this version in case someone is interested in completing it. The code is in `RecordActionViewController`. You can enable upload from camera roll for the app with the switch on the settings screen. See below for ideas on fixing.

### Suggested next contributions:
1. Add code to complete the AppMuteManager class (or rewrite it) so the app correctly understands and can respond to the actual mute state. It is missing pieces of logic at the moment, so inaccurate mute-related functionality or UI may show.
2. Fix the feature to upload the collab’s first video from camera roll. It does upload from Photos and appears just fine in the trim & remix stages, however progressing to the preview / share screen replaces it with a black video. Quick investigation shows the issue is in TakeGenerator.cropFragment (called from RemixViewController.properlyCropRecordedFragments), and the file at fileURL.path does not exist.
3. Add the ability to import clips into remix instead of creating one from scratch (see RemixViewController, PlaybackDataModel, and LocalAssetManager).
4. Create a feed! Many existing AV-related classes we built can be reused to display collabs in-sync (ex: LayoutEngineViewController, FragmentHost, AVPlayerView protocol, AVPlayerLayer, AVPlayerLooper, AVQueuePlayer, etc.)

*Considerations for adding the ability to remix with existing / imported fragments:*
* To be able to launch remix directly and bypass the initial record and trim steps, call `RemixViewController(model: PlaybackDataModel(from: [someFragmentRepresentation]), initialPlaybackTime: .zero)`. You’ll also need to build an `init` method on `PlaybackDataModel` to create an instance of it from a list of fragments. We left in there an example of how we did this when passed a collab itself and duplicated the clip assets.
* The initial state of the fragment pool in playbackDataModel can’t contain FragmentHosts with duplicate IDs
* Instructions in RemixViewController for what to do to load a pool of fragments into remix. First, call loadFragments() from viewDidLoad() (see more instructions in loadFragments() function header)


## Join the CollabOpenSource community
See the [CONTRIBUTING](CONTRIBUTING.md) file for how to help out.

## License
OpenCollab is MIT licensed, as found in the LICENSE file.

## Credits
Collab was built by a team of engineers at Meta consisting of:
* Product Management: Brit Menutti
* Design: Chris Melamed
* iOS Development: Cappie Regalado, Vardges Avetisyan, Natalie Muenster, Nick Confrey
* Server-side Development: Jake Shamash, Lilli Choung, Dobri Yordanov

With support from countless others on the New Product Experimentation team.
