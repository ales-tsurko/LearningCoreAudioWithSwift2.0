//
//  main.swift
//  AUGraphPlayThrough
//
//  Created by Ales Tsurko on 09.09.15.
//
// Instead of CARingBuffer here the RingBuffer which is an Objective-C wrapper for CARingBuffer.
// If you get silence on output try to change capacityFrames on RingBuffer allocation.

import Foundation
import AudioToolbox
import CoreAudio
import AudioUnit
import ApplicationServices

// To #define PART_II in your project, you need to add "-D PART_II" flag in "Other Swift Flags"
// of "Swift Compiler - Custom Flags" in project Build Settings. The one already defined in this project.

// MARK: User data struct
class AUGraphPlayer {
    var streamFormat = AudioStreamBasicDescription()
    
    var graph: AUGraph = nil
    var inputUnit: AudioUnit = nil
    var outputUnit: AudioUnit = nil
    #if PART_II
    var speechUnit: AudioUnit = nil
    #endif
    var inputBuffer = UnsafeMutableAudioBufferListPointer(nil)
    var ringBuffer = RingBuffer()
    
    var firstInputSampleTime: Float64 = 0
    var firstOutputSampleTime: Float64 = 0
    var inToOutSampleTimeOffset: Float64 = 0
}

// MARK: - render procs -
let InputRenderProc: AURenderCallback = {(inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData)  -> OSStatus in
    
    let player = UnsafeMutablePointer<AUGraphPlayer>(inRefCon).memory
    
    // Have we ever logged input timing? (for offset calculation)
    if player.firstInputSampleTime < 0 {
        player.firstInputSampleTime = inTimeStamp.memory.mSampleTime
        
        if player.firstOutputSampleTime > 0 && player.inToOutSampleTimeOffset < 0 {
            player.inToOutSampleTimeOffset = player.firstInputSampleTime - player.firstOutputSampleTime
        }
    }
    
    var inputProcErr = noErr
    inputProcErr = AudioUnitRender(player.inputUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, player.inputBuffer.unsafeMutablePointer)
    
    if inputProcErr == noErr {
        inputProcErr = player.ringBuffer.store(player.inputBuffer.unsafeMutablePointer, nFrames: inNumberFrames, frameNumber: Int64(inTimeStamp.memory.mSampleTime))
    }
    
    return inputProcErr
}

let GraphRenderProc: AURenderCallback = {(inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, var ioData)  -> OSStatus in
    
    let player = UnsafeMutablePointer<AUGraphPlayer>(inRefCon).memory
    
    // Have we ever logged input timing? (for offset calculation)
    if player.firstOutputSampleTime < 0 {
        player.firstOutputSampleTime = inTimeStamp.memory.mSampleTime
        
        if player.firstInputSampleTime > 0 && player.inToOutSampleTimeOffset < 0 {
            player.inToOutSampleTimeOffset = player.firstInputSampleTime - player.firstOutputSampleTime
        }
    }
    
    // Copy samples out of ring buffer
    var outputProcErr = noErr
    outputProcErr = player.ringBuffer.fetch(ioData, nFrame: inNumberFrames, frameNumnber: Int64(inTimeStamp.memory.mSampleTime + player.inToOutSampleTimeOffset))
    
    return outputProcErr
}

// MARK: - utility functions -
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

func CreateInputUnit(inout player: AUGraphPlayer) {
    
    // Generates a description that matches audio HAL
    var inputcd = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
    
    let comp = AudioComponentFindNext(nil, &inputcd)
    
    guard comp != nil else {
        print("Can't get output unit")
        exit(-1)
    }
    
    CheckError(AudioComponentInstanceNew(comp, &player.inputUnit),
        operation: "Couldn't open component for inputUnit")
    
    var disableFlag: UInt32 = 0
    var enableFlag: UInt32 = 1
    let outputBus: AudioUnitScope = 0
    let inputBus: AudioUnitScope = 1
    
    CheckError(AudioUnitSetProperty(player.inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, inputBus, &enableFlag, UInt32(sizeof(enableFlag.dynamicType))),
        operation: "Couldn't enable input on I/O unit")
    
    CheckError(AudioUnitSetProperty(player.inputUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, outputBus, &disableFlag, UInt32(sizeof(disableFlag.dynamicType))),
        operation: "Couldn't disable output on I/O unit")
    
    var defaultDevice: AudioObjectID = kAudioObjectUnknown
    var propertySize = UInt32(sizeof(defaultDevice.dynamicType))
    var defaultDeviceProperty = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMaster)
    
    CheckError(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultDeviceProperty, 0, nil, &propertySize, &defaultDevice),
        operation: "Couldn't get default input device")
    
    CheckError(AudioUnitSetProperty(player.inputUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, outputBus, &defaultDevice, UInt32(sizeof(defaultDevice.dynamicType))),
        operation: "Couldn't set default device on I/O unit")
    
    propertySize = UInt32(sizeof(AudioStreamBasicDescription))
    CheckError(AudioUnitGetProperty(player.inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputBus, &player.streamFormat, &propertySize),
        operation: "Couldn't get ASBD from input unit")
    
    var deviceFormat = AudioStreamBasicDescription()
    
    CheckError(AudioUnitGetProperty(player.inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, inputBus, &deviceFormat, &propertySize),
        operation: "Couldn't get ASBD from input unit")
    
    player.streamFormat.mSampleRate = deviceFormat.mSampleRate
    player.streamFormat.mChannelsPerFrame = 1 // set to mono
    
    propertySize = UInt32(sizeof(AudioStreamBasicDescription))
    
    CheckError(AudioUnitSetProperty(player.inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputBus, &player.streamFormat, propertySize),
        operation: "Couldn't set ASBD on input unit")
    
    var bufferSizeFrames: UInt32 = 0
    propertySize = UInt32(sizeof(UInt32))
    
    CheckError(AudioUnitGetProperty(player.inputUnit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &bufferSizeFrames, &propertySize),
        operation: "Couldn't get buffer frame size from input unit")
    
    let bufferSizeBytes = bufferSizeFrames * UInt32(sizeof(Float32))
    
    // Allocate AudioBufferList
    player.inputBuffer = AudioBufferList.allocate(maximumBuffers: Int(player.streamFormat.mChannelsPerFrame))
    
    // Pre-malloc buffers for AudioBuffersList
    for i in 0..<Int(player.inputBuffer.unsafeMutablePointer.memory.mNumberBuffers) {
        player.inputBuffer[i].mNumberChannels = 1
        player.inputBuffer[i].mDataByteSize = bufferSizeBytes
        player.inputBuffer[i].mData = malloc(Int(bufferSizeBytes))
    }
    
    // Alloc ring buffer that will hold data between the two audio devices
    player.ringBuffer.allocate(player.streamFormat.mChannelsPerFrame, bytesPerFrame: player.streamFormat.mBytesPerFrame, capacityFrames: bufferSizeFrames * 3)
    
    // Set render proc to supply samples from input unit
    var callbackStruct = AURenderCallbackStruct(inputProc: InputRenderProc, inputProcRefCon: &player)
    
    CheckError(AudioUnitSetProperty(player.inputUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callbackStruct, UInt32(sizeof(callbackStruct.dynamicType))),
        operation: "Couldn't set input callback")
    
    CheckError(AudioUnitInitialize(player.inputUnit),
        operation: "Couldn't initialize input unit")
    
    player.firstInputSampleTime = -1
    player.inToOutSampleTimeOffset = -1
    
    print("Bottom of CreateInputUnit\n")
}

func CreateAUGraph(inout player: AUGraphPlayer) {
    // Create a new AUGraph
    CheckError(NewAUGraph(&player.graph),
        operation: "NewAUGraph failed")
    
    // Generate a description that matches default output
    var outputcd = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_DefaultOutput, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
    
    let comp = AudioComponentFindNext(nil, &outputcd)
    
    guard comp != nil else {
        print("Can't get output unit")
        exit(-1)
    }
    
    // Adds a node with above description to the graph
    var outputNode = AUNode()
    CheckError(AUGraphAddNode(player.graph, &outputcd, &outputNode),
        operation: "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed")
    
    #if PART_II
        // Add a mixer to the graph
        var mixercd = AudioComponentDescription(componentType: kAudioUnitType_Mixer, componentSubType: kAudioUnitSubType_StereoMixer, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        var mixerNode = AUNode()
        
        CheckError(AUGraphAddNode(player.graph, &mixercd, &mixerNode),
            operation: "AUGraphAddNode[kAudioUnitSubType_StereoMixer] failed")
        
        // Add the speech synthesizer to the graph
        var speechcd = AudioComponentDescription(componentType: kAudioUnitType_Generator, componentSubType: kAudioUnitSubType_SpeechSynthesis, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        var speechNode = AUNode()
        
        CheckError(AUGraphAddNode(player.graph, &speechcd, &speechNode),
            operation: "AUGraphAddNode[kAudioUnitSubType_SpeechSynthesis] failed")
        
        // Opening the graph opens all contained audio units but does not allocate any resources yet
        CheckError(AUGraphOpen(player.graph), operation: "AUGraphOpen failed")
        
        // Get the reference to the AudioUnit objects for the various nodes
        CheckError(AUGraphNodeInfo(player.graph, outputNode, nil, &player.outputUnit),
            operation: "AUGraphNodeInfo failed")
        CheckError(AUGraphNodeInfo(player.graph, speechNode, nil, &player.speechUnit),
            operation: "AUGraphNodeInfo failed")
        
        var mixerUnit: AudioUnit = nil
        
        CheckError(AUGraphNodeInfo(player.graph, mixerNode, nil, &mixerUnit),
            operation: "AUGraphNodeInfo failed")
        
        // Set ASBDs here
        let propertySize = UInt32(sizeof(AudioStreamBasicDescription))
        
        CheckError(AudioUnitSetProperty(player.outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &player.streamFormat, propertySize),
            operation: "Couldn't set stream format on output unit")
        
        CheckError(AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &player.streamFormat, propertySize),
            operation: "Couldn't set stream format on mixer unit bus 0")
        CheckError(AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &player.streamFormat, propertySize),
            operation: "Couldn't set stream format on mixer unit bus 1")
        
        // Connections
        // Mixer output scope / bus 0 to outputUnit scope / bus 0
        // Mixer input scope / bus 0 to render callback
        // (from ringbuffer, which in turn is from inputUnit)
        // Mixer input scope / bus 1 to speech unit output scope / bus 0
        
        CheckError(AUGraphConnectNodeInput(player.graph, mixerNode, 0, outputNode, 0),
            operation: "Couldn't connect mixer output(0) to outputNode (0)")
        
        CheckError(AUGraphConnectNodeInput(player.graph, speechNode, 0, mixerNode, 1),
            operation: "Couldn't connect speech synth unit output (0) to mixer input (1)")
        
        var callbackStruct = AURenderCallbackStruct(inputProc: GraphRenderProc, inputProcRefCon: &player)
        
        CheckError(AudioUnitSetProperty(mixerUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &callbackStruct, UInt32(sizeof(callbackStruct.dynamicType))),
            operation: "Couldn't set render callback on mixer unit")
        
        #else
        // Opening the graph opens all contained audio units, but does not allocate any resources yet
        CheckError(AUGraphOpen(player.graph),
            operation: "AUGraphOpen failed")
        
        // Get the reference to the AudioUnit object for the output graph node
        CheckError(AUGraphNodeInfo(player.graph, outputNode, nil, &player.outputUnit),
            operation: "AUGraphNodeInfo failed")
        
        // Set the stream format on the output unit's input scope
        let propertySize = UInt32(sizeof(AudioStreamBasicDescription))
        CheckError(AudioUnitSetProperty(player.outputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &player.streamFormat, propertySize),
            operation: "Couldn't set stream format on output unit")
        
        var callbackStruct = AURenderCallbackStruct(inputProc: GraphRenderProc, inputProcRefCon: &player)
        
        CheckError(AudioUnitSetProperty(player.outputUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &callbackStruct, UInt32(sizeof(callbackStruct.dynamicType))),
            operation: "Couldn't set render callback on output unit")
    #endif
    
    // Now initialize the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(player.graph),
        operation: "AUGraphInitialize failed")
    
    player.firstOutputSampleTime = -1
}


#if PART_II
    func PrepareSpeechAU(inout player: AUGraphPlayer) {
        var chan: SpeechChannel = nil
        var propSize = UInt32(sizeof(SpeechChannel))
        
        CheckError(AudioUnitGetProperty(player.speechUnit, kAudioUnitProperty_SpeechChannel, kAudioUnitScope_Global, 0, &chan, &propSize),
            operation: "AudioUnitGetProperty[kAudioUnitProperty_SpeechChannel] failed")
        
        SpeakCFString(chan, "Please purchase as many copies of our Core Audio book as you possibly can" as CFString, nil)
    }
#endif

func main() {
    var player = AUGraphPlayer()
    
    // Create the input unit
    CreateInputUnit(&player)
    
    // Build a graph with output unit
    CreateAUGraph(&player)
    
    #if PART_II
        PrepareSpeechAU(&player)
    #endif
    
    // Start playing
    CheckError(AudioOutputUnitStart(player.inputUnit), operation: "AudioUnitOutputStart failed")
    CheckError(AUGraphStart(player.graph), operation: "AUGraphStart failed")
    
    // And wait
    print("Captured, press <return> to stop:\n")
    getchar()
    
    // Cleanup
    AUGraphStop(player.graph)
    AUGraphUninitialize(player.graph)
    AUGraphClose(player.graph)
}

main()