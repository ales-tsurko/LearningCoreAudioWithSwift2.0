//
//  main.swift
//  ExtAudioFileConverter
//
//  Created by Ales Tsurko on 03.09.15.
//

import Foundation
import AudioToolbox

// Change paths to your
let kInputFileLocation = "/Users/alestsurko/Desktop/FBA1.mp3" as CFString
let kOutputFile = "/Users/alestsurko/Desktop/output.aif" as CFString

// MARK: User data struct
struct AudioConverterSettings {
    var outputFormat = AudioStreamBasicDescription()
    var inputFile: ExtAudioFileRef = nil
    var outputFile: AudioFileID = nil
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

func Convert(inout settings: AudioConverterSettings) {
    let outputBufferSize: UInt32 = 32 * 1024
    let sizePerPacket = settings.outputFormat.mBytesPerPacket
    let packetsPerBuffer = outputBufferSize / sizePerPacket
    let outputBuffer = malloc(sizeof(UInt8) * Int(outputBufferSize))
    var outputFilePacketPosition: UInt32 = 0
    
    while true {
        var convertedData = AudioBufferList()
        convertedData.mNumberBuffers = 1
        convertedData.mBuffers.mNumberChannels = settings.outputFormat.mChannelsPerFrame
        convertedData.mBuffers.mDataByteSize = outputBufferSize
        convertedData.mBuffers.mData = outputBuffer
        
        var frameCount = packetsPerBuffer
        
        CheckError(ExtAudioFileRead(settings.inputFile, &frameCount, &convertedData),
            operation: "Couldn't read from input file")
        
        if frameCount == 0 {
            print("Done reading from file.\n")
            return
        }
        
        CheckError(AudioFileWritePackets(settings.outputFile, false, frameCount, nil, Int64(outputFilePacketPosition/settings.outputFormat.mBytesPerPacket), &frameCount, convertedData.mBuffers.mData),
            operation: "Couldn't write packets to file")
        
        outputFilePacketPosition+=(frameCount * settings.outputFormat.mBytesPerPacket)
    }
}


// MARK: Main function
func main() {
    // Open input file
    var audioConverterSettings = AudioConverterSettings()
    
    // Open the input with ExtAudioFile
    let inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kInputFileLocation, CFURLPathStyle.CFURLPOSIXPathStyle, false)
    
    var error = ExtAudioFileOpenURL(inputFileURL, &audioConverterSettings.inputFile)
    
    CheckError(error, operation: "ExtAudioFileOpenURL failed")
    
    // Set up output file
    audioConverterSettings.outputFormat.mSampleRate = 44100
    audioConverterSettings.outputFormat.mFormatID = kAudioFormatLinearPCM
    audioConverterSettings.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
    audioConverterSettings.outputFormat.mBytesPerPacket = 4
    audioConverterSettings.outputFormat.mFramesPerPacket = 1
    audioConverterSettings.outputFormat.mBytesPerFrame = 4
    audioConverterSettings.outputFormat.mChannelsPerFrame = 2
    audioConverterSettings.outputFormat.mBitsPerChannel = 16
    
    let outputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kOutputFile, CFURLPathStyle.CFURLPOSIXPathStyle, false)
    
    error = AudioFileCreateWithURL(outputFileURL, kAudioFileAIFFType, &audioConverterSettings.outputFormat, AudioFileFlags.EraseFile, &audioConverterSettings.outputFile)
    
    CheckError(error, operation: "AudioFileCreateWithURL failed")
    
    error = ExtAudioFileSetProperty(audioConverterSettings.inputFile, kExtAudioFileProperty_ClientDataFormat, UInt32(sizeof(AudioStreamBasicDescription)), &audioConverterSettings.outputFormat)
    
    CheckError(error, operation: "Couldn't set client data format on input ext file")
    
    // Perform conversion
    print("Converting...\n")
    Convert(&audioConverterSettings)
    
    ExtAudioFileDispose(audioConverterSettings.inputFile)
    AudioFileClose(audioConverterSettings.outputFile)
}

main()