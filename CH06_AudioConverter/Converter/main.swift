//
//  main.swift
//  Converter
//
//  Created by Ales Tsurko on 03.09.15.
//

import Foundation
import AudioToolbox

// Change to your path
let kInputFileLocation = "/Users/alestsurko/Desktop/FBA1.mp3" as CFString

// MARK: User data struct (it's better to use reference type class in Swift version)
class AudioConverterSettings {
    var inputFormat = AudioStreamBasicDescription()
    var outputFormat = AudioStreamBasicDescription()
    
    var inputFile: AudioFileID = nil
    var outputFile: AudioFileID = nil
    
    var inputFilePacketIndex = UInt64()
    var inputFilePacketCount = UInt64()
    var inputFilePacketMaxSize = UInt32()
    var inputFilePacketDescriptions: UnsafeMutablePointer<AudioStreamPacketDescription> = nil
    
    var sourceBuffer: UnsafeMutablePointer<Void> = nil
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

func Convert(var settings: AudioConverterSettings) {
    // Create the audioConverter object
    var audioConverter: AudioConverterRef = nil
    
    CheckError(AudioConverterNew(&settings.inputFormat, &settings.outputFormat, &audioConverter),
        operation: "AudioConverterNew failed")
    
    var packetsPerBuffer: UInt32 = 0
    var outputBufferSize: UInt32 = 32 * 1024
    var sizePerPacket: UInt32 = settings.inputFormat.mBytesPerPacket
    
    if sizePerPacket == 0 {
        var size = UInt32(sizeof(sizePerPacket.dynamicType))
        
        CheckError(AudioConverterGetProperty(audioConverter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &sizePerPacket),
            operation: "Couldn't get kAudioConverterPropertyMaximumOutputPacketSize")
        
        if sizePerPacket > outputBufferSize {
            outputBufferSize = sizePerPacket
        }
        
        packetsPerBuffer = outputBufferSize / sizePerPacket
        settings.inputFilePacketDescriptions = UnsafeMutablePointer<AudioStreamPacketDescription>(malloc(sizeof(AudioStreamPacketDescription) * Int(packetsPerBuffer)))
    } else {
        packetsPerBuffer = outputBufferSize / sizePerPacket
    }
    
    let outputBuffer = malloc(sizeof(UInt8) * Int(outputBufferSize))
    
    var outputFilePacketPosition: UInt32 = 0
    
    while true {
        var convertedData = AudioBufferList()
        convertedData.mNumberBuffers = 1
        convertedData.mBuffers.mNumberChannels = settings.inputFormat.mChannelsPerFrame
        convertedData.mBuffers.mDataByteSize = outputBufferSize
        convertedData.mBuffers.mData = outputBuffer
        
        var ioOutputDataPackets = packetsPerBuffer
        
        let error = AudioConverterFillComplexBuffer(audioConverter, AudioConverterCallback, &settings, &ioOutputDataPackets, &convertedData, settings.inputFilePacketDescriptions != nil ? settings.inputFilePacketDescriptions : nil)
        
        if error != noErr || ioOutputDataPackets < 1 {
            break // This is the termination condition
        }
        
        // Write the converted data to the output file
        CheckError(AudioFileWritePackets(settings.outputFile, false, ioOutputDataPackets, nil, Int64(outputFilePacketPosition/settings.outputFormat.mBytesPerPacket), &ioOutputDataPackets, convertedData.mBuffers.mData), operation: "Couldn't write packets to file")
        
        outputFilePacketPosition += (ioOutputDataPackets * settings.outputFormat.mBytesPerPacket)
    }
    
    AudioConverterDispose(audioConverter)
}

// MARK: Converter callback function
let AudioConverterCallback: AudioConverterComplexInputDataProc = {(inAudioConverter, ioDataPacketCount, ioData, outDataPacketDescription, inUserData) -> OSStatus in
    let audioConverterSettings = UnsafeMutablePointer<AudioConverterSettings>(inUserData).memory
    
    ioData.memory.mBuffers.mData = nil
    ioData.memory.mBuffers.mDataByteSize = 0
    
    // If there are not enough packets to satisfy request,
    // then read what's left
    if audioConverterSettings.inputFilePacketIndex + UInt64(ioDataPacketCount.memory) > audioConverterSettings.inputFilePacketCount {
        ioDataPacketCount.memory = UInt32(audioConverterSettings.inputFilePacketCount - audioConverterSettings.inputFilePacketIndex)
    }
    
    if ioDataPacketCount.memory == 0 {
        return noErr
    }
    
    if audioConverterSettings.sourceBuffer != nil {
        free(audioConverterSettings.sourceBuffer)
        audioConverterSettings.sourceBuffer = nil
    }
    
    audioConverterSettings.sourceBuffer = UnsafeMutablePointer<Void>(calloc(1, Int(ioDataPacketCount.memory * UInt32(audioConverterSettings.inputFilePacketMaxSize))))
    
    var outByteCount: UInt32 = 0
    // AudioFileReadPackets was deprecated in OS X 10.10 and iOS 8
    var result = AudioFileReadPackets(audioConverterSettings.inputFile, true, &outByteCount, audioConverterSettings.inputFilePacketDescriptions, Int64(audioConverterSettings.inputFilePacketIndex), ioDataPacketCount, audioConverterSettings.sourceBuffer)
    
    if result == kAudioFileEndOfFileError && ioDataPacketCount.memory > 0 {
        result = noErr
    } else if result != noErr {
        return result
    }
    
    audioConverterSettings.inputFilePacketIndex+=UInt64(ioDataPacketCount.memory)
    ioData.memory.mBuffers.mData = audioConverterSettings.sourceBuffer
    ioData.memory.mBuffers.mDataByteSize = outByteCount

    if outDataPacketDescription != nil {
        outDataPacketDescription.memory = audioConverterSettings.inputFilePacketDescriptions
    }
    
    return result
}

// MARK: Main function
func main() {
    // Open input file
    let audioConverterSettings = AudioConverterSettings()
    
    let inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, kInputFileLocation, CFURLPathStyle.CFURLPOSIXPathStyle, false)
    
    var error = AudioFileOpenURL(inputFileURL, AudioFilePermissions.ReadPermission, 0, &audioConverterSettings.inputFile)
    
    CheckError(error, operation: "AudioFileOpenURL failed")
    
    // Get input format
    var propSize = UInt32(sizeof(audioConverterSettings.inputFormat.dynamicType))
    
    error = AudioFileGetProperty(audioConverterSettings.inputFile, kAudioFilePropertyDataFormat, &propSize, &audioConverterSettings.inputFormat)
    
    CheckError(error, operation: "Couldn't get file's data format")
    
    // Set up output file
    // get the total number of packets in the file
    propSize = UInt32(sizeof(audioConverterSettings.inputFilePacketCount.dynamicType))
    
    error = AudioFileGetProperty(audioConverterSettings.inputFile, kAudioFilePropertyAudioDataPacketCount, &propSize, &audioConverterSettings.inputFilePacketCount)
    
    CheckError(error, operation: "Couldn't get file's packet count")
    
    // get size of the largest possible packet
    propSize = UInt32(sizeof(audioConverterSettings.inputFilePacketMaxSize.dynamicType))
    
    error = AudioFileGetProperty(audioConverterSettings.inputFile, kAudioFilePropertyMaximumPacketSize, &propSize, &audioConverterSettings.inputFilePacketMaxSize)
    
    CheckError(error, operation: "Couldn't get file's max packet size")
    
    audioConverterSettings.outputFormat.mSampleRate = 44100
    audioConverterSettings.outputFormat.mFormatID = kAudioFormatLinearPCM
    audioConverterSettings.outputFormat.mFormatFlags = kAudioFormatFlagIsBigEndian | kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
    audioConverterSettings.outputFormat.mBytesPerPacket = 4
    audioConverterSettings.outputFormat.mFramesPerPacket = 1
    audioConverterSettings.outputFormat.mBytesPerFrame = 4
    audioConverterSettings.outputFormat.mChannelsPerFrame = 2
    audioConverterSettings.outputFormat.mBitsPerChannel = 16
    
    let outputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, ("/Users/alestsurko/Desktop/output.aif" as CFString), CFURLPathStyle.CFURLPOSIXPathStyle, false)
    
    error = AudioFileCreateWithURL(outputFileURL, kAudioFileAIFFType, &audioConverterSettings.outputFormat, AudioFileFlags.EraseFile, &audioConverterSettings.outputFile)
    
    CheckError(error, operation: "AudioFileCreateWithURL failed")
    
    // Perform conversion
    print("Converting...\n")
    Convert(audioConverterSettings)
    
    AudioFileClose(audioConverterSettings.inputFile)
    AudioFileClose(audioConverterSettings.outputFile)
}

main()