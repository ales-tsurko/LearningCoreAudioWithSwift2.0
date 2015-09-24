//
//  main.swift
//  AudioQueueRecorder
//
//  Created by Ales Tsurko on 28.08.15.
//

import AudioToolbox

let kNumberRecordBuffers = 3

// MARK: User data struct (it's better to use reference type class in Swift version)
class Recorder {
    var recordFile: AudioFileID = nil
    var recordPacket: Int64 = 0
    var running: Bool = false
}

// MARK: Utility functions
func CheckError(error: OSStatus, operation: String) {
    guard error != noErr else {
        return
    }
    
    var result: String = ""
    var char = Int(error.bigEndian)
    
    for _ in 0..<4 {
        guard isprint(Int32(char&255)) == 1 else {
            result = "\(error)"
            break
        }
        result.append(UnicodeScalar(char&255))
        char = char/256
    }
    
    print("Error: \(operation) (\(result))")
    
    exit(1)
}

func GetDefaultInputDeviceSampleRate(inout outSampleRate: Double) -> OSStatus {
    var error: OSStatus
    var deviceID: AudioDeviceID = 0
    var propertyAddress = AudioObjectPropertyAddress()
    var propertySize: UInt32
    
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultInputDevice
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
    propertyAddress.mElement = 0
    propertySize = UInt32(sizeof(AudioDeviceID))
    error = AudioHardwareServiceGetPropertyData(UInt32(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
    
    if error != noErr {
        return error
    }
    
    propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate
    propertyAddress.mScope = kAudioObjectPropertyScopeGlobal
    propertyAddress.mElement = 0
    propertySize = UInt32(sizeof(Double))
    error = AudioHardwareServiceGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &outSampleRate)
    
    return error
}

func CopyEncoderCookieToFile(queue: AudioQueueRef, theFile: AudioFileID) {
    var error: OSStatus
    var propertySize = UInt32()
    
    error = AudioQueueGetPropertySize(queue, kAudioConverterCompressionMagicCookie, &propertySize)
    
    if error == noErr && propertySize > 0 {
        let magicCookie = UnsafeMutablePointer<UInt8>(malloc(Int(propertySize)))
        
        error = AudioQueueGetProperty(queue, kAudioQueueProperty_MagicCookie, magicCookie, &propertySize)
        
        CheckError(error, operation: "Couldn't get audio queue's magic cookie")
        
        error = AudioFileSetProperty(theFile, kAudioFilePropertyMagicCookieData, propertySize, magicCookie)
        
        CheckError(error, operation: "Couldn't set audio file's magic cookie")
        
        free(magicCookie)
    }
}

func ComputeRecordBufferSize(format: AudioStreamBasicDescription, queue: AudioQueueRef, seconds: Double) -> Int {
    var packets: Int, frames: Int, bytes: Int
    frames = Int(ceil(seconds * format.mSampleRate))
    
    
    if format.mBytesPerFrame > 0 {
        bytes = frames * Int(format.mBytesPerFrame)
    } else {
        var maxPacketSize = UInt32()
        
        if format.mBytesPerPacket > 0 {
            // Constant packet size
            maxPacketSize = format.mBytesPerPacket
        } else {
            // Get the largest single packet size possible
            var propertySize = UInt32(sizeof(maxPacketSize.dynamicType))
            
            CheckError(
                AudioQueueGetProperty(queue, kAudioConverterPropertyMaximumOutputPacketSize, &maxPacketSize, &propertySize),
                operation: "Couldn't get queue's maximum output packet size")
        }
        
        if format.mFramesPerPacket > 0 {
            packets = frames / Int(format.mFramesPerPacket)
        } else {
            // Worst-case scenario: 1 frame in a packet
            packets = frames
        }
        
        // Sanity check
        if packets == 0 {
            packets = 1
        }
        
        bytes = packets * Int(maxPacketSize)
    }
    
    return bytes
}

// MARK: Record callback function
let AQInputCallback: AudioQueueInputCallback = {(var inUserData, inQueue, inBuffer, inStartTime, var inNumPackets, inPacketDesc) -> () in
    let recorder = UnsafeMutablePointer<Recorder>(inUserData).memory
    
    if inNumPackets > 0 {
        // Write packets to a file
        CheckError(
            AudioFileWritePackets(recorder.recordFile, false, inBuffer.memory.mAudioDataByteSize, inPacketDesc, recorder.recordPacket, &inNumPackets, inBuffer.memory.mAudioData),
            operation: "AudioFileWritePackets failed")
        
        // Increment the packet index
        recorder.recordPacket += Int64(inNumPackets)
        
        if recorder.running {
            CheckError(AudioQueueEnqueueBuffer(inQueue, inBuffer, 0, nil), operation: "AudioQueueEnqueueBuffer failed")
            
            
            /*// Level metering
            var level: [Float32] = [0]
            var levelSize = UInt32(sizeof(level.dynamicType))
            CheckError(
                AudioQueueGetProperty(inQueue, kAudioQueueProperty_CurrentLevelMeterDB, &level, &levelSize),
                operation: "Couldn't get kAudioQueueProperty_CurrentLevelMeter")
            print(level)*/
        }
        
    }
}

// MARK: main function
func main() {
    // Set up format
    var recorder = Recorder()
    var recordFormat = AudioStreamBasicDescription()
    recordFormat.mFormatID = kAudioFormatMPEG4AAC
    recordFormat.mChannelsPerFrame = 2
    
    GetDefaultInputDeviceSampleRate(&recordFormat.mSampleRate)
    
    var propSize = UInt32(sizeof(recordFormat.dynamicType))
    
    var error: OSStatus
    
    error = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, nil, &propSize, &recordFormat)
    
    CheckError(error, operation: "AudioFormatGetProperty failed")
    
    // Set up queue
    var queue: AudioQueueRef = nil
    
    error = AudioQueueNewInput(&recordFormat, AQInputCallback, &recorder, nil, nil, 0, &queue)
    
    CheckError(error, operation: "AudioQueueNewInput failed")
    
    var size = UInt32(sizeof(recordFormat.dynamicType))
    error = AudioQueueGetProperty(queue, kAudioConverterCurrentOutputStreamDescription, &recordFormat, &size)
    
    CheckError(error, operation: "Couldn't get queue's format")
    
    /*// Uncomment to set level metering enabled
    var value: UInt32 = 1
    let valueSize = UInt32(sizeof(value.dynamicType))
    
    error = AudioQueueSetProperty(queue, kAudioQueueProperty_EnableLevelMetering, &value, valueSize)
    
    CheckError(error, operation: "AudioQueueSetProperty kAudioQueueProperty_EnableLevelMetering failed")*/
    
    // Set up file
    let fileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, "output.caf" as CFString, CFURLPathStyle.CFURLPOSIXPathStyle, false)
    
    error = AudioFileCreateWithURL(fileURL, kAudioFileCAFType, &recordFormat, AudioFileFlags.EraseFile, &recorder.recordFile)
    
    CheckError(error, operation: "AudioFileCreateWithURL failed")
    
    CopyEncoderCookieToFile(queue, theFile: recorder.recordFile)
    
    // Other set up as needed
    let bufferByteSize = ComputeRecordBufferSize(recordFormat, queue: queue, seconds: 0.5)
    
    for _ in 0..<kNumberRecordBuffers {
        var buffer = AudioQueueBufferRef()
        error = AudioQueueAllocateBuffer(queue, UInt32(bufferByteSize), &buffer)
        
        CheckError(error, operation: "AudioQueueAllocateBuffer failed")
        
        error = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        
        CheckError(error, operation: "AudioQueueEnqueueBuffer failed")
    }
    
    // Start queue
    recorder.running = true
    
    error = AudioQueueStart(queue, nil)
    
    CheckError(error, operation: "AudioQueueStart failed")
    
    print("Recording, press <return> to stop:\n")
    getchar()
    
    // Stop queue
    print("* recording done *\n")
    
    recorder.running = false
    
    error = AudioQueueStop(queue, true)
    
    CheckError(error, operation: "AudioQueueStop failed")
    
    CopyEncoderCookieToFile(queue, theFile: recorder.recordFile)
    
    AudioQueueDispose(queue, true)
    AudioFileClose(recorder.recordFile)
}

main()
