#if DEBUG
import Foundation

// lets a simulator launch sign in and open a screen without typing, for screenshots:
//   SIMCTL_CHILD_SHARKORD_DEV_SERVER=http://localhost:4991 SIMCTL_CHILD_SHARKORD_DEV_IDENTITY=alice
//   SIMCTL_CHILD_SHARKORD_DEV_PASSWORD=... SIMCTL_CHILD_SHARKORD_DEV_CHANNEL=1 xcrun simctl launch <device> com.sharkord.ios
// SHARKORD_DEV_VOICE=<channel id> joins that voice channel once connected
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

    static var voiceChannelId: Int? {
        environment["SHARKORD_DEV_VOICE"].flatMap(Int.init)
    }
}
#endif
