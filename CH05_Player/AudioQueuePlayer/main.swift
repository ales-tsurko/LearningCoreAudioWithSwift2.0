//
//  main.swift
//  AudioQueuePlayer
//
//  Created by Ales Tsurko on 01.09.15.

import Foundation
import AudioToolbox

let kNumberPlaybackBuffers = 3
// Change to your path
let kPlaybackFileLocation = "/Users/alestsurko/Desktop/FBA1.mp3" as CFString

// MARK: User data struct (it's better to use reference type class in Swift version)
class Player {
    var playbackFile: AudioFileID = nil
    var packetPosition: Int64 = 0
    var numPacketsToRead: UInt32 = 0
    var packetDescs: UnsafeMutablePointer<AudioStreamPacketDescription> = nil
    var isDone = false
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

func CopyEncoderCookieToQueue(theFile: AudioFileID, queue: AudioQueueRef) {
    var propertySize = UInt32()
    let result = AudioFileGetPropertyInfo(theFile, kAudioFilePropertyMagicCookieData, &propertySize, nil)
    
    if result == noErr && propertySize > 0 {
        let magicCookie = UnsafeMutablePointer<UInt8>(malloc(sizeof(UInt8) * Int(propertySize)))
        
        CheckError(AudioFileGetProperty(theFile, kAudioFilePropertyMagicCookieData, &propertySize, magicCookie), operation: "Get cookie from file failed")
        
        CheckError(AudioQueueSetProperty(queue, kAudioQueueProperty_MagicCookie, magicCookie, propertySize), operation: "Set cookie on queue failed")
        
        free(magicCookie)
    }
}

func CalculateBytesForTime(inAudioFile: AudioFileID, inDesc: AudioStreamBasicDescription, inSeconds: Double, inout outBufferSize: UInt32, inout outNumPackets: UInt32) {
    var maxPacketSize = UInt32()
    var propSize = UInt32(sizeof(maxPacketSize.dynamicType))
    
    CheckError(AudioFileGetProperty(inAudioFile, kAudioFilePropertyPacketSizeUpperBound, &propSize, &maxPacketSize), operation: "Couldn't get file's max packet size")
    
    let maxBufferSize: UInt32 = 0x10000
    let minBufferSize: UInt32 = 0x4000
    
    if inDesc.mFramesPerPacket > 0 {
        let numPacketsForTime = inDesc.mSampleRate / Double(inDesc.mFramesPerPacket) * inSeconds
        
        outBufferSize = UInt32(numPacketsForTime) * maxPacketSize
    } else {
        outBufferSize = maxBufferSize > maxPacketSize ? maxBufferSize : maxPacketSize
    }
    
    if outBufferSize > maxBufferSize && outBufferSize > maxPacketSize {
        outBufferSize = maxBufferSize
    } else {
        if outBufferSize < minBufferSize {
            outBufferSize = minBufferSize
        }
    }
    
    outNumPackets = outBufferSize / maxPacketSize
}

// MARK: Playback callback function
let AQOutputCallback: AudioQueueOutputCallback = {(inUserData, inAQ, inCompleteAQBuffer) -> () in
    let aqp = UnsafeMutablePointer<Player>(inUserData).memory
    
    guard !aqp.isDone else {
        return
    }
    
    var numBytes = UInt32()
    var nPackets = aqp.numPacketsToRead
    
    // AudioFileReadPackets was deprecated in OS X 10.10 and iOS 8
    CheckError(AudioFileReadPackets(aqp.playbackFile, false, &numBytes, aqp.packetDescs, aqp.packetPosition, &nPackets, inCompleteAQBuffer.memory.mAudioData), operation: "AudioFileReadPacketData failed")
    
    if nPackets > 0 {
        inCompleteAQBuffer.memory.mAudioDataByteSize = numBytes
        AudioQueueEnqueueBuffer(inAQ, inCompleteAQBuffer, (aqp.packetDescs != nil ? nPackets : 0), aqp.packetDescs)
        
        aqp.packetPosition+=Int64(nPackets)
    } else {
        CheckError(AudioQueueStop(inAQ, false), operation: "AudioQueueStop failed")
        aqp.isDone = true
    }
}

// MARK: Main function
func main() {
    var error = noErr
    
    // Open an audio file
    var player = Player()
    let fileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kPlaybackFileLocation, CFURLPathStyle.CFURLPOSIXPathStyle, false)
    
    error = AudioFileOpenURL(fileURL, AudioFilePermissions.ReadPermission, 0, &player.playbackFile)
    
    CheckError(error, operation: "AudioFileOpenURL failed")
    
    // Set up format
    var dataFormat = AudioStreamBasicDescription()
    var propSize = UInt32(sizeof(dataFormat.dynamicType))
    
    error = AudioFileGetProperty(player.playbackFile, kAudioFilePropertyDataFormat, &propSize, &dataFormat)
    
    CheckError(error, operation: "Couldn't get file's data format")
    
    // Set up queue
    var queue = AudioQueueRef()
    
    error = AudioQueueNewOutput(&dataFormat, AQOutputCallback, &player, nil, nil, 0, &queue)
    
    CheckError(error, operation: "AudioQueueNewOutput failed")
    
    var bufferByteSize = UInt32()
    CalculateBytesForTime(player.playbackFile, inDesc: dataFormat, inSeconds: 0.5, outBufferSize: &bufferByteSize, outNumPackets: &player.numPacketsToRead)
    
    let isFormatVBR = dataFormat.mBytesPerPacket == 0 || dataFormat.mFramesPerPacket == 0
    if isFormatVBR {
        player.packetDescs = UnsafeMutablePointer<AudioStreamPacketDescription>(malloc(sizeof(AudioStreamPacketDescription) * Int(player.numPacketsToRead)))
    } else {
        player.packetDescs = nil
    }
    
    CopyEncoderCookieToQueue(player.playbackFile, queue: queue)
    
    var buffers = [AudioQueueBufferRef](count: kNumberPlaybackBuffers, repeatedValue: AudioQueueBufferRef())
    
    player.isDone = false
    player.packetPosition = 0
    
    for i in 0..<kNumberPlaybackBuffers {
        error = AudioQueueAllocateBuffer(queue, bufferByteSize, &buffers[i])
        
        CheckError(error, operation: "AudioQueueAllocateBuffer failed")
        
        AQOutputCallback(&player, queue, buffers[i])
        
        if player.isDone {
            break
        }
    }
    
    // Start queue
    error = AudioQueueStart(queue, nil)
    CheckError(error, operation: "AudioQueueStart failed")
    
    print("Playing...\n")
    
    // http://stackoverflow.com/questions/14219315/why-call-to-cfrunloopruninmode-in-audio-queue-playback-code
    repeat {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.25, false)
    } while !player.isDone
    
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 2, false)
    
    // Clean up queue when finished
    player.isDone = true
    
    error = AudioQueueStop(queue, true)
    CheckError(error, operation: "AudioQueueStop failed")
    
    AudioQueueDispose(queue, true)
    AudioFileClose(player.playbackFile)
}

main()