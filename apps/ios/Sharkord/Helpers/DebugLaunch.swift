#if DEBUG
import Foundation

// lets a simulator launch sign in and open a screen without typing, for screenshots:
//   SIMCTL_CHILD_SHARKORD_DEV_SERVER=http://localhost:4991 SIMCTL_CHILD_SHARKORD_DEV_IDENTITY=alice
//   SIMCTL_CHILD_SHARKORD_DEV_PASSWORD=... SIMCTL_CHILD_SHARKORD_DEV_CHANNEL=1 xcrun simctl launch <device> com.sharkord.ios
// SHARKORD_DEV_VOICE=<channel id> joins that voice channel once connected
// SHARKORD_DEV_SIGNED_OUT=1 forgets every saved server first, so a ui test starts at welcome
enum DebugLaunch {
    private static var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    static var credentials: (server: String, identity: String, password: String)? {
        guard
            let server = environment["SHARKORD_DEV_SERVER"],
            let identity = environment["SHARKORD_DEV_IDENTITY"],
            let password = environment["SHARKORD_DEV_PASSWORD"]
        else {
            return nil
        }

        return (server, identity, password)
    }

    static var channelId: Int? {
        environment["SHARKORD_DEV_CHANNEL"].flatMap(Int.init)
    }

    static var startsSignedOut: Bool {
        environment["SHARKORD_DEV_SIGNED_OUT"] == "1"
    }

    static var voiceChannelId: Int? {
        environment["SHARKORD_DEV_VOICE"].flatMap(Int.init)
    }

    // the simulator cannot be turned from the command line, so a run can ask for the ipad's
    // landscape layout at any size
    static var forcesSplit: Bool {
        environment["SHARKORD_DEV_SPLIT"] == "1"
    }

    // SHARKORD_DEV_VOICE_PLAYGROUND=1 opens a voice channel's sheet with no server behind it,
    // so its motion can be tried and recorded on a simulator
    static var opensVoicePlayground: Bool {
        environment["SHARKORD_DEV_VOICE_PLAYGROUND"] == "1"
    }
}
#endif
