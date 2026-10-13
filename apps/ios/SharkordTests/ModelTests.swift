import Foundation
import Testing
@testable import Sharkord

// what the app decodes from the server, against payloads shaped like the server's own
struct ModelTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func messageDecodesPinState() throws {
        let message = try decode(Message.self, """
        {"id":7,"content":"<p>hi</p>","userId":1,"pluginId":null,"channelId":2,"parentMessageId":null,
         "replyToMessageId":null,"createdAt":1700000000000,"editedAt":null,"files":[],"reactions":[],
         "pinned":true,"pinnedAt":1700000001000,"pinnedBy":1,"replyTo":null}
        """)

        #expect(message.pinned == true)
        #expect(message.pinnedBy == 1)
    }

    @Test func messageFromAnOlderServerStillDecodes() throws {
        let message = try decode(Message.self, """
        {"id":7,"content":null,"userId":null,"pluginId":null,"channelId":2,"parentMessageId":null,
         "replyToMessageId":null,"createdAt":1,"editedAt":null,"files":[],"reactions":[],"replyTo":null}
        """)

        #expect(message.pinned == nil)
        #expect(message.poll == nil)
        #expect(message.sticker == nil)
    }

    @Test func channelPermissionsDecodeFromTheJoinPayloadShape() throws {
        let map = try decode([String: ChannelPermissions].self, """
        {"5":{"channelId":5,"permissions":{"VIEW_CHANNEL":true,"SEND_MESSAGES":false}}}
        """)

        #expect(map["5"]?.channelId == 5)
        #expect(map["5"]?.permissions["SEND_MESSAGES"] == false)
    }

    @Test func typingEventDecodesWithAndWithoutAThread() throws {
        let channel = try decode(TypingEvent.self, #"{"channelId":1,"userId":3}"#)
        let thread = try decode(TypingEvent.self, #"{"channelId":1,"userId":3,"parentMessageId":9}"#)

        #expect(channel.parentMessageId == nil)
        #expect(thread.parentMessageId == 9)
    }

    @Test func voiceReactionEventDecodes() throws {
        let event = try decode(VoiceReactionEvent.self, #"{"channelId":2,"userId":4,"emoji":"tada"}"#)

        #expect(event.emoji == "tada")
    }

    @Test func adminUserInfoDecodesWithHiddenSensitiveData() throws {
        let info = try decode(AdminUserInfo.self, """
        {"user":{"id":3},"logins":[{"id":1,"userId":3,"userAgent":"Safari","os":"iOS","device":"iPhone",
         "ip":null,"hostname":null,"city":"Denver","region":"CO","country":"US","loc":null,"org":null,
         "postal":null,"timezone":null,"createdAt":1700000000000,"updatedAt":null}],
         "files":[],"messages":[{"id":4,"channelId":1,"userId":3,"content":"<p>x</p>","createdAt":5}],
         "storage":{"userId":3,"fileCount":2,"usedStorage":2048,"quota":0}}
        """)

        #expect(info.logins[0].ip == nil)
        #expect(info.logins[0].place == "Denver, CO, US")
        #expect(info.storage.usedStorage == 2048)
        #expect(info.messages.count == 1)
    }

    @Test func channelActivityDecodes() throws {
        let rows = try decode([ChannelActivity].self, #"[{"channelId":1,"lastMessageAt":1700000000000}]"#)

        #expect(rows[0].lastMessageAt == 1_700_000_000_000)
    }

    @Test func adminSettingsDecodeTheInviteOnlyLock() throws {
        let locked = try decode(AdminServerSettings.self, """
        {"name":"S","description":null,"password":null,"onlyAskForPasswordOnFirstJoin":false,
         "allowNewUsers":false,"inviteOnly":true,"directMessagesEnabled":true,"enablePlugins":false,
         "enableSearch":true,"showWelcomeDialog":true,"webRtcSimulcastEnabled":false}
        """)
        let older = try decode(AdminServerSettings.self, """
        {"name":"S","description":null,"password":null,"onlyAskForPasswordOnFirstJoin":false,
         "allowNewUsers":true,"directMessagesEnabled":true,"enablePlugins":false,
         "enableSearch":true,"showWelcomeDialog":true,"webRtcSimulcastEnabled":false}
        """)

        #expect(locked.inviteOnly == true)
        #expect(older.inviteOnly == nil)
    }

    @Test func storageSettingsDecodeTheSignedLinksLock() throws {
        let settings = """
        "storageSettings":{"storageUploadEnabled":true,"storageFileSharingInDirectMessages":true,
         "storageQuota":0,"storageUploadMaxFileSize":1,"storageMaxAvatarSize":1,"storageMaxBannerSize":1,
         "storageMaxFilesPerMessage":10,"storageSpaceQuotaByUser":0,"storageOverflowAction":"prevent",
         "storageSignedUrlsEnabled":true,"storageSignedUrlsTtlSeconds":3600,
         "storageImageOptimizationEnabled":false,"storageImageOptimizationQuality":80},
        "diskMetrics":{"totalSpace":1,"freeSpace":1,"usedSpace":0,"sharkordUsedSpace":0},"pluginStorage":[]
        """
        let locked = try decode(AdminStorage.self, "{\(settings),\"signedUrlsLocked\":true}")
        let older = try decode(AdminStorage.self, "{\(settings)}")

        #expect(locked.signedUrlsLocked == true)
        #expect(older.signedUrlsLocked == nil)
    }
}
