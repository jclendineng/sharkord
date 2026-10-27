import AVFoundation
#if os(macOS)
import CoreAudio
#endif

// which mic calls, the mic test and voice messages use: the one picked in voice settings, or
// else a headset's whenever one is plugged in, which matters most on a mac with no mic of its
// own. kept to on every route change, since webrtc's own audio device sets the session up where
// nothing here can reach it
enum AudioInputPreference {
    #if os(iOS)
    private static let headsets: Set<AVAudioSession.Port> = [.bluetoothHFP, .headsetMic, .usbAudio]
    private static var observer: NSObjectProtocol?
    #else
    // a mac's mic as voice settings lists it, by core audio's uid, which survives a replug
    nonisolated struct Input: Hashable {
        let uid: String
        let name: String
    }

    // posted when a mic is plugged in or out, or the system's default one changes
    static let inputsDidChange = Notification.Name("AudioInputPreference.inputsDidChange")

    private static var isListening = false
    #endif

    static func start() {
        #if os(iOS)
        guard observer == nil else {
            return
        }

        observer = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                apply()
            }
        }
        #else
        guard !isListening else {
            return
        }

        isListening = true

        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = Self.address(selector)

            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
                MainActor.assumeIsolated {
                    apply()
                    NotificationCenter.default.post(name: inputsDidChange, object: nil)
                }
            }
        }
        #endif
    }

    static func apply() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()

        guard session.category == .playAndRecord, let inputs = session.availableInputs else {
            return
        }

        // a device that takes a gain gets the one picked in voice settings
        if session.isInputGainSettable {
            try? session.setInputGain(Float(AppSettings.shared.inputGain))
        }

        let pickedId = AppSettings.shared.inputDeviceId
        let picked = inputs.first { $0.uid == pickedId }

        guard let target = picked ?? inputs.first(where: { headsets.contains($0.portType) }) else {
            return
        }

        // setting it is itself a route change, which would come straight back here
        let current = session.currentRoute.inputs.first

        if current?.uid != target.uid {
            try? session.setPreferredInput(target)
        }
        #else
        // the picked mic's own volume, the one the system's sound settings move too
        guard let device = currentDevice(), var address = gainAddress(of: device) else {
            return
        }

        var gain = Float32(AppSettings.shared.inputGain)

        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &gain)
        #endif
    }

    #if os(macOS)
    // every device with an input, in the order core audio lists them
    nonisolated static func inputs() -> [Input] {
        devices().compactMap { device in
            guard inputChannelCount(of: device) > 0, let uid = string(kAudioDevicePropertyDeviceUID, of: device) else {
                return nil
            }

            return Input(uid: uid, name: string(kAudioObjectPropertyName, of: device) ?? uid)
        }
    }

    static var canSetInputGain: Bool {
        guard let device = currentDevice() else {
            return false
        }

        return gainAddress(of: device) != nil
    }

    // a mac has no audio session to prefer an input on, each engine is pointed at the picked mic
    // itself. it has to happen before the engine's input format is read. automatic leaves the
    // system's default, which already moves to a headset when one is plugged in
    nonisolated static func apply(to engine: AVAudioEngine, inputDeviceId: String?) {
        guard
            let inputDeviceId,
            var device = device(withUID: inputDeviceId)
        else {
            return
        }

        engine.inputNode.withAudioUnit { unit in
            guard let unit else {
                return
            }

            AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &device,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }
    }

    // the picked mic while it is plugged in, the system's default otherwise
    private static func currentDevice() -> AudioDeviceID? {
        if let pickedId = AppSettings.shared.inputDeviceId, let device = device(withUID: pickedId) {
            return device
        }

        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = address(kAudioHardwarePropertyDefaultInputDevice)

        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr, device != 0 else {
            return nil
        }

        return device
    }

    nonisolated private static func device(withUID uid: String) -> AudioDeviceID? {
        devices().first { string(kAudioDevicePropertyDeviceUID, of: $0) == uid }
    }

    nonisolated private static func devices() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        let system = AudioObjectID(kAudioObjectSystemObject)

        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            return []
        }

        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else {
            return []
        }

        return devices
    }

    nonisolated private static func inputChannelCount(of device: AudioDeviceID) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput)
        var size = UInt32(0)

        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }

        let list = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)

        defer {
            list.deallocate()
        }

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else {
            return 0
        }

        let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))

        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    nonisolated private static func string(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else {
            return nil
        }

        return value.takeRetainedValue() as String
    }

    // the volume of the whole input where the device has one, else of its first channel, which
    // is all most usb mics give. nil when it cannot be set
    private static func gainAddress(of device: AudioDeviceID) -> AudioObjectPropertyAddress? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeInput, element: element)
            var isSettable = DarwinBoolean(false)

            if
                AudioObjectHasProperty(device, &address),
                AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr,
                isSettable.boolValue
            {
                return address
            }
        }

        return nil
    }

    nonisolated private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }
    #endif
}
