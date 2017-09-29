//
//  main.swift
//  CAToneFileGenerator
//
//  Created by Ales Tsurko on 25.08.15.
//  Edited by Dima Gimburg on 28.09.17.
//
import Foundation
import AudioToolbox

let SAMPLE_RATE: Float64 = 44100
let DURATION = 5.0
let FILENAME_FORMAT = "%0.3f-sine.aif"

func main() {
    let argc = CommandLine.argc
    let argv = CommandLine.arguments
    
    guard argc > 1 else {
        print("Usage: CAToneFileGenerator n\n(where n is tone in Hz)")
        return
    }
    
    let hz = Double(argv[1])
    
    assert(hz! > 0.0)
    
    print("generating \(hz!) hz tone")
    
    let fileName = String(format: FILENAME_FORMAT, hz!)
    let filePath = (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(fileName)
    let fileURL: CFURL = NSURL.fileURL(withPath: filePath) as CFURL
    
    // Prepare for format
    var asbd = AudioStreamBasicDescription()
    asbd.mSampleRate = SAMPLE_RATE;
    asbd.mFormatID = kAudioFormatLinearPCM
    asbd.mFormatFlags = kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked
    asbd.mBitsPerChannel = 16
    asbd.mChannelsPerFrame = 1
    asbd.mBytesPerFrame = asbd.mChannelsPerFrame * 2
    asbd.mFramesPerPacket = 1
    asbd.mBytesPerPacket = asbd.mFramesPerPacket * asbd.mBytesPerFrame
    
    // Set up the file
    var _audioFile: AudioFileID? = nil
    var audioErr = noErr
    
    audioErr = AudioFileCreateWithURL(fileURL, kAudioFileAIFFType, &asbd, AudioFileFlags.eraseFile, &_audioFile)
    
    guard let audioFile = _audioFile else { return }
    
    assert(audioErr == noErr)
    
    // Start writing samples
    let maxSampleCount = Int(SAMPLE_RATE * DURATION * Double(asbd.mChannelsPerFrame))
    var sampleCount = 0
    var bytesToWrite: UInt32 = 2
    let wavelengthInSamples = SAMPLE_RATE/hz!
    
    while sampleCount < maxSampleCount {
        for n in 0..<Int(wavelengthInSamples) {
            // Square wave
            //            var sample = n < Int(wavelengthInSamples) / 2 ? (Int16.max).bigEndian : (Int16.min).bigEndian
            
            // Saw wave
            //            var sample = Int16(((Double(n) / wavelengthInSamples) * Double(Int16.max) * 2) - Double(Int16.max)).bigEndian
            
            // Sine wave
            var sample = Int16(Double(Int16.max) * sin(2 * .pi * (Double(n) / wavelengthInSamples))).bigEndian
            
            audioErr = AudioFileWriteBytes(audioFile, false, Int64(sampleCount*2), &bytesToWrite, &sample)
            
            assert(audioErr == noErr)
            sampleCount += 1
        }
    }
    
    audioErr = AudioFileClose(audioFile)
    
    print("wrote \(sampleCount) samples")
}

main()
