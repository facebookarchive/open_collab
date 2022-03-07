#  Collab Open Source
<ADD LOGO HERE!!>

A music creation and collaboration project that provides recording, trimming, and video & audio 
synchronization tools to simplify creating a multi-clip music video.

## Examples
...

## Requirements
Collab Open Source requires or works with
* iOS

## Building CollabOpenSource
...

## Installing __________

run ```pod install``` in the root project directory to install all package dependencies from the Podfile:

BrightFutures
Kingfisher
FlexLayout

## How CollabOpenSource works
On app launch, a user can record a collab from scratch by selecting the center plus button.
This action will initiate a flow that starts with recording the first video. Recording cuts off 
at 90 seconds and the next screen will allow the user to trim the clip using awaveform trimmer
with additional precision "nudge" capabilities. The video must be trimmed down to <= 15 seconds
in order to proceed to the remix step. After proceeding the remix screen, the camera will open 
once again with the option to record a second video for the collab. The clips tray can be used
to exit and re-enter record, and select different clips that have already been recorded. The 
overall collab can be composed of 1-6 clips. Once happy with the collab, the user can select 
"preview" to review the collab in its final form, and they can then select "Save" which opens
the share sheet and allows the user to share or save the video to the camera roll.

## Full documentation

1. TODOs for extension of this app are indicated by “## TODO :”; all other todos you may find are from the team’s development and have been left in as notes
2. This project only contains client-side code for the Collab creation flow. We removed any code and structures that are no longer relevant for this open source version (for example, we don’t have a concept of a user). 
3. Since there is no backend in this project, it currently only supports creating a collab from scratch. If you want to initiate a remix session with your or other people’s existing clips (in code we call them fragments), you’ll need to build in a way to download these clips and access them when opening remix. More guidance on how to get started on that extension below.
4. Right now there’s also no way to have a nil fragment (FragmentHost.AssetInfo.isEmpty) in any of the creation step, but we’ve left in some handling for nil fragments in case future extensions may introduce the concept
5. We also built in the ability to upload a video from camera roll to create a collab from scratch using a pre-recorded clip. We never polished and released the feature, but we left it in this version in case someone is interested in completing it. (Code in RecordActionViewController). You can enable upload from camera roll for the app with the switch on the settings screen. See below for ideas on fixing.

## Suggested next contributions:
1. Add code to complete the AppMuteManager class (or rewrite it) so the app correctly understands and can respond to the actual mute state. It is missing pieces of logic at the moment, so inaccurate mute-related functionality or UI may show.
2. Fix the feature to upload the collab’s first video from camera roll. It does upload from Photos and appears just fine in the trim & remix stages, however progressing to the preview / share screen replaces it with a black video. Quick investigation shows the issue is in TakeGenerator.cropFragment (called from RemixViewController.properlyCropRecordedFragments), and the file at fileURL.path does not exist.
3. Add the ability to import clips into remix instead of creating one from scratch (see RemixViewController, PlaybackDataModel, and LocalAssetManager).(^)
Create a feed! Many existing AV-related classes we built can be reused to display collabs in-sync (ex: LayoutEngineViewController, FragmentHost, AVPlayerView protocol, AVPlayerLayer, AVPlayerLooper, AVQueuePlayer, etc.)

*(^) Considerations for adding the ability to remix with existing / imported fragments:*
To be able to launch remix directly and bypass the initial record and trim steps, call RemixViewController(model: PlaybackDataModel(from: [someFragmentRepresentation]), initialPlaybackTime: .zero). You’ll also need to build an init method on PlaybackDataModel to create an instance of it from a list of fragments. We left in there an example of how we did this when passed a collab itself and duplicated the clip assets.
The initial state of the fragment pool in playbackDataModel can’t contain FragmentHosts with duplicate IDs
You’ll need to calculate the starting duration for remix using the durations of the fragments in the pool you’re using. If you use the minimum duration, your collab won’t have any empty or ‘stuck’ content. If you use maximum duration, the clips you use with less duration will obviously not have content to fill the full time, so will either be empty (black) or frozen on the last frame.
Instructions in RemixViewController for what to do to load a pool of fragments into remix. First, call loadFragments() from viewDidLoad() (see more instructions in loadFragments() function header)


## Join the CollabOpenSource community
* Facebook page:

See the [CONTRIBUTING](CONTRIBUTING.md) file for how to help out.

## License
__________ is <YOUR LICENSE HERE> licensed, as found in the LICENSE file.
