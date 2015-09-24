//
//  main.swift
//  AUSpeechSynthesizer
//
//  Created by Ales Tsurko on 07.09.15.
//

import Foundation
import AudioToolbox
import AudioUnit
import ApplicationServices

// To #define PART_II in your project, you need to add "-D PART_II" flag in "Other Swift Flags" 
// of "Swift Compiler - Custom Flags" in project Build Settings. The one already defined in this project.

// MARK: User data struct
struct AUGraphPlayer {
    var graph: AUGraph = nil
    var speechAU: AudioUnit = nil
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
        operation: "NewAUGraph failde")
    
    // Generates a description that matches out output device (speakers)
    var outputcd = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_DefaultOutput, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
    
    // Adds a note with above description to the graph
    var outputNode = AUNode()
    
    CheckError(AUGraphAddNode(player.graph, &outputcd, &outputNode),
        operation: "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed")
    
    // Generates a description that will match a generator AU of type: speech synthesizer
    var speechcd = AudioComponentDescription(componentType: kAudioUnitType_Generator, componentSubType: kAudioUnitSubType_SpeechSynthesis, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
    
    // Adds a node
    var speechNode = AUNode()
    CheckError(AUGraphAddNode(player.graph, &speechcd, &speechNode),
        operation: "AUGraphAddNode[kAudioUnitSubType_SpeechSynthesis] failed")
    
    // Opening the graph opens all contained audio units, but does not allocated any resources yet
    CheckError(AUGraphOpen(player.graph),
        operation: "AUGraphOpen failed")
    
    // Gets the reference to the AudioUnit object for the speech synthesis graph node
    CheckError(AUGraphNodeInfo(player.graph, speechNode, nil, &player.speechAU),
        operation: "AUGraphNodeInfo failed")
    
    #if PART_II
        // Generate a description that matches the reverb effect
        var reverbcd = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_MatrixReverb, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        
        // Adds a node with above description to the graph
        var reverbNode = AUNode()
        
        CheckError(AUGraphAddNode(player.graph, &reverbcd, &reverbNode),
            operation: "AUGraphAddNode[kAudioUnitSubType_MatrixReverb] failed")
        
        // Connect the output source of the speech synthesizer AU to the input source of the reverb node
        CheckError(AUGraphConnectNodeInput(player.graph, speechNode, 0, reverbNode, 0),
            operation: "AUGraphConnectNodeInput (speech to reverb) failed")
        
        // Connect the output source of the reverb AU to the input source of the output node
        CheckError(AUGraphConnectNodeInput(player.graph, reverbNode, 0, outputNode, 0),
            operation: "AUGraphConnectNodeInput (reverb to output) failed")
        
        // Get the reference to the AudioUnit object for the reverb graph node
        var reverbUnit: AudioUnit = nil
        
        CheckError(AUGraphNodeInfo(player.graph, reverbNode, nil, &reverbUnit),
            operation: "AUGraphNodeInfo failed")
        
        // Now initialize the graph (this causes the resources to be allocated)
        CheckError(AUGraphInitialize(player.graph),
            operation: "AUGraphInitialize failed")
        
        // Set the reverb preset for room size
        var roomType = AUReverbRoomType.ReverbRoomType_LargeHall
        CheckError(AudioUnitSetProperty(reverbUnit, kAudioUnitProperty_ReverbRoomType, kAudioUnitScope_Global, 0, &roomType, UInt32(sizeof(roomType.dynamicType))),
            operation: "AudioUnitSetProperty[kAudioUnitProperty_ReverbRoomType] failed")
        
        #else
        // Connect the output source of the speech synthesis AU to the input source of the output node
        CheckError(AUGraphConnectNodeInput(player.graph, speechNode, 0, outputNode, 0),
            operation: "AUGraphConnectNodeInput failed")
        
        // Now initialize the graph (causes resources to be allocated)
        CheckError(AUGraphInitialize(player.graph),
            operation: "AUGraphInitialize failed")
    #endif
    
    CAShow(UnsafeMutablePointer<AUGraph>(player.graph))
}

func PrepareSpeechAU(inout player: AUGraphPlayer) {
    var chan: SpeechChannel = nil
    var propSize = UInt32(sizeof(SpeechChannel))
    
    CheckError(AudioUnitGetProperty(player.speechAU, kAudioUnitProperty_SpeechChannel, kAudioUnitScope_Global, 0, &chan, &propSize),
        operation: "AudioUnitGetProperty[kAudioUnitProperty_SpeechChannel] failed")
    
    SpeakCFString(chan, "hello world", nil)
}

// MARK: Main function
func main() {
    var player = AUGraphPlayer()
    
    // Build a basic speech->speakers graph
    CreateAUGraph(&player)
    
    // Configure the speech synthesizer
    PrepareSpeechAU(&player)
    
    // Start playing
    CheckError(AUGraphStart(player.graph), operation: "AUGraphStart failed")
    
    // Sleep a while so the speech can play out
    usleep(useconds_t(10 * 1000 * 1000))
    
    // Cleanup
    AUGraphStop(player.graph)
    AUGraphUninitialize(player.graph)
    AUGraphClose(player.graph)
}

main()