//
//  main.swift
//  AudioUnitPlayer
//
//  Created by Ales Tsurko on 04.09.15.
//

import Foundation
import AudioToolbox
import AudioUnit

// Change to your path
let kInputFileLocation = "/Users/alestsurko/Desktop/FBA1.mp3" as CFString

// Adds an initializer to ScheduledAudioFileRegion
extension ScheduledAudioFileRegion {
    init(mTimeStamp: AudioTimeStamp, mCompletionProc: ScheduledAudioFileRegionCompletionProc?, mCompletionProcUserData: UnsafeMutablePointer<Void>, mAudioFile: COpaquePointer, mLoopCount: UInt32, mStartFrame: Int64, mFramesToPlay: UInt32) {
        self.mTimeStamp = mTimeStamp
        self.mCompletionProc = mCompletionProc
        self.mCompletionProcUserData = mCompletionProcUserData
        self.mAudioFile = mAudioFile
        self.mLoopCount = mLoopCount
        self.mStartFrame = mStartFrame
        self.mFramesToPlay = mFramesToPlay
    }
}

// MARK: User data struct
struct AUGraphPlayer {
    var inputFormat = AudioStreamBasicDescription()
    var inputFile: AudioFileID = nil
    var graph: AUGraph = nil
    var fileAU: AudioUnit = nil
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

func CreateAUGraph(inout player: AUGraphPlayer) {
    // Create a new AUGraph
    CheckError(NewAUGraph(&player.graph),
        operation: "NewAUGraph failed")
    
    // Generate description that matches output device (speakers)
    var outputcd = AudioComponentDescription()
    outputcd.componentType = kAudioUnitType_Output
    outputcd.componentSubType = kAudioUnitSubType_DefaultOutput
    outputcd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    // Adds a node with above description to the graph
    var outputNode = AUNode()
    CheckError(AUGraphAddNode(player.graph, &outputcd, &outputNode),
        operation: "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed")
    
    // Generate description that matches a generator AU of type:
    // audio file player
    var fileplayercd = AudioComponentDescription()
    fileplayercd.componentType = kAudioUnitType_Generator
    fileplayercd.componentSubType = kAudioUnitSubType_AudioFilePlayer
    fileplayercd.componentManufacturer = kAudioUnitManufacturer_Apple
    
    // Adds a node with above description to the graph
    var fileNode = AUNode()
    CheckError(AUGraphAddNode(player.graph, &fileplayercd, &fileNode),
        operation: "AUGraphAddNode[kAudioUnitSubType_AudioFilePlayer] failed")
    
    // Opening the graph opens all contained audio units but does not allocate any resources yet
    CheckError(AUGraphOpen(player.graph), operation: "AUGraphOpen failed")
    
    // Get the reference to the AudioUnit object for the file player graph node
    CheckError(AUGraphNodeInfo(player.graph, fileNode, nil, &player.fileAU),
        operation: "AUGraphNodeInfo failed")
    
    // Connect the output source of the file player AU to the input source of the output node
    CheckError(AUGraphConnectNodeInput(player.graph, fileNode, 0, outputNode, 0),
        operation: "AUGraphConnectNodeInput failed")
    
    // Now initialize the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(player.graph),
        operation: "AUGraphInitialize failed")
}

func PrepareFileAU(inout player: AUGraphPlayer) -> Double {
    // Tell the file player unit to load the file we want to play
    CheckError(AudioUnitSetProperty(player.fileAU, kAudioUnitProperty_ScheduledFileIDs, kAudioUnitScope_Global, 0, &player.inputFile, UInt32(sizeof(player.inputFile.dynamicType))),
        operation: "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFileIDs] failed")
    
    var nPackets = UInt64()
    var propSize = UInt32(sizeof(nPackets.dynamicType))
    CheckError(AudioFileGetProperty(player.inputFile, kAudioFilePropertyAudioDataPacketCount, &propSize, &nPackets),
        operation: "AudioFileGetProperty[kAudioFilePropertyAudioDataPacketCount] failed")
    
    // Tell the file player AU to play the entire file
    let smpteTime = SMPTETime(mSubframes: 0, mSubframeDivisor: 0, mCounter: 0, mType: SMPTETimeType.Type24, mFlags: SMPTETimeFlags.Running, mHours: 0, mMinutes: 0, mSeconds: 0, mFrames: 0)
    
    let timeStamp = AudioTimeStamp(mSampleTime: 0, mHostTime: 0, mRateScalar: 0, mWordClockTime: 0, mSMPTETime: smpteTime, mFlags: AudioTimeStampFlags.SampleTimeValid, mReserved: 0)
    
    var rgn = ScheduledAudioFileRegion(mTimeStamp: timeStamp, mCompletionProc: nil, mCompletionProcUserData: nil, mAudioFile: player.inputFile, mLoopCount: 1, mStartFrame: 0, mFramesToPlay: UInt32(nPackets) * player.inputFormat.mFramesPerPacket)
    
    CheckError(AudioUnitSetProperty(player.fileAU, kAudioUnitProperty_ScheduledFileRegion, kAudioUnitScope_Global, 0, &rgn, UInt32(sizeof(rgn.dynamicType))),
        operation: "AudioUnitSetProperty[kAudioUnitProperty_ScheduledFileRegion] failed")
    
    // Tell the file player AU when to start playing (-1 sample time means next render cycle)
    var startTime = AudioTimeStamp(mSampleTime: -1, mHostTime: 0, mRateScalar: 0, mWordClockTime: 0, mSMPTETime: smpteTime, mFlags: AudioTimeStampFlags.SampleTimeValid, mReserved: 0)
    
    CheckError(AudioUnitSetProperty(player.fileAU, kAudioUnitProperty_ScheduleStartTimeStamp, kAudioUnitScope_Global, 0, &startTime, UInt32(sizeof(startTime.dynamicType))),
        operation: "AudioUnitSetProperty[kAudioUnitProperty_ScheduleStartTimeStamp] failed")
    
    // File duration
    return Double(UInt32(nPackets) * player.inputFormat.mFramesPerPacket) / player.inputFormat.mSampleRate
}

// MARK: Main function
func main() {
    let inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kInputFileLocation, CFURLPathStyle.CFURLPOSIXPathStyle, false)
    
    var player = AUGraphPlayer()
    
    // Open the input audio file
    var error = AudioFileOpenURL(inputFileURL, AudioFilePermissions.ReadPermission, 0, &player.inputFile)
    CheckError(error, operation: "AudioFileOpenURL failed")
    
    // Get the audio data format from the file
    var propSize = UInt32(sizeof(player.inputFormat.dynamicType))
    
    error = AudioFileGetProperty(player.inputFile, kAudioFilePropertyDataFormat, &propSize, &player.inputFormat)
    CheckError(error, operation: "Couldn't get file's data format")
    
    // Build a basic fileplayer->speakers graph
    CreateAUGraph(&player)
    
    // Configure the file
    let fileDuration = PrepareFileAU(&player)
    
    // Start playing
    error = AUGraphStart(player.graph)
    CheckError(error, operation: "AUGraphStart failed")
    
    // Sleep until the file is finished
    usleep(useconds_t(fileDuration * 1000 * 1000))
    
    // Cleanup
    AUGraphStop(player.graph)
    AUGraphUninitialize(player.graph)
    AUGraphClose(player.graph)
    AudioFileClose(player.inputFile)
}

main()