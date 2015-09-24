//
//  main.swift
//  CH11_MIDIToAUGraph
//
//  Created by Ales Tsurko on 22.09.15.
//

import Foundation
import CoreMIDI
import AudioToolbox

// MARK: - state struct
struct MIDIPlayer {
    var graph: AUGraph = nil
    var instrumentUnit: AudioUnit = nil
}

// MARK: utility functions
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

// MARK: - callbacks
let MIDINotifyCallback: MIDINotifyProc = {message, refCon in
    print("MIDI notify, messageID=\(message.memory.messageID.rawValue)")
}

let MIDIReadCallback: MIDIReadProc = {pktlist, refCon, connRefCon in
    var player = UnsafeMutablePointer<MIDIPlayer>(refCon)
    var packet = pktlist.memory.packet
    
    for i in 0..<Int(pktlist.memory.numPackets) {
        let midiStatus = packet.data.0
        let midiCommand = midiStatus>>4
        
        if midiCommand == 0x08 || midiCommand == 0x09 {
            let note = packet.data.1&0x7f
            let velocity = packet.data.2&0x7f
            
            CheckError(MusicDeviceMIDIEvent(player.memory.instrumentUnit, UInt32(midiStatus), UInt32(note), UInt32(velocity), 0),
                operation: "Couldn't send MIDI event")
            print("\(midiCommand) \(note) \(velocity)")
        }
        
        packet = MIDIPacketNext(&packet).memory
    }
}

// MARK: - augraph
func setupAUGraph(inout player: MIDIPlayer) {
    
    CheckError(NewAUGraph(&player.graph),
        operation: "Couldn't open AUGraph")
    
    // Generate description that will match our output device (speakers)
    var outputcd = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_DefaultOutput, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
    
    // Adds a node with above description to the graph
    var outputNode = AUNode()
    CheckError(AUGraphAddNode(player.graph, &outputcd, &outputNode),
        operation: "AUGraphAddNode[kAudioUnitSubType_DefaultOutput] failed")
    
    var instrumentcd = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice, componentSubType: kAudioUnitSubType_DLSSynth, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
    
    var instrumentNode = AUNode()
    
    CheckError(AUGraphAddNode(player.graph, &instrumentcd, &instrumentNode),
        operation: "AUGraphAddNode[kAudioUnitSubType_DLSSynth] failed")
    
    // Opening the graph opens all contained audio units but does not allocate any resources yet
    CheckError(AUGraphOpen(player.graph),
        operation: "AUGraphOpen failed")
    
    // Get the reference to the AudioUnit object for the instrument graph node
    CheckError(AUGraphNodeInfo(player.graph, instrumentNode, nil, &player.instrumentUnit),
        operation: "AUGraphNodeInfo failed")
    
    // Connect the output source of the speech synthesis AU to the input source of the output node
    CheckError(AUGraphConnectNodeInput(player.graph, instrumentNode, 0, outputNode, 0),
        operation: "AUGraphConnectNodeInput failed")
    
    // Now initialize the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(player.graph),
        operation: "AUGraphInitialize failed")
}

// MARK: - midi
func setupMIDI(inout player: MIDIPlayer) {
    
    var client = MIDIClientRef()
    CheckError(MIDIClientCreate("Core MIDI to System Sounds Demo", MIDINotifyCallback, &player, &client),
        operation: "Couldn't create MIDI client")
    
    var inPort = MIDIPortRef()
    CheckError(MIDIInputPortCreate(client, "Input port", MIDIReadCallback, &player, &inPort),
        operation: "Couldn't create MIDI input port")
    
    let sourceCount = MIDIGetNumberOfSources()
    print("\(sourceCount) sources\n")
    
    for i in 0..<sourceCount {
        let src = MIDIGetSource(i)
        var endpointName: Unmanaged<CFStringRef>?
        
        CheckError(MIDIObjectGetStringProperty(src, kMIDIPropertyName, &endpointName),
            operation: "Couldn't get endpoint name")
        
        print(" source \(i): \(endpointName!.takeRetainedValue() as String)\n")
        
        CheckError(MIDIPortConnectSource(inPort, src, nil),
            operation: "Couldn't connect MIDI port")
    }
}

// MARK: - main
func main() {
    var player = MIDIPlayer()
    
    setupAUGraph(&player)
    setupMIDI(&player)
    
    CheckError(AUGraphStart(player.graph),
        operation: "Couldn't start graph")
    
    CFRunLoopRun()
    // Run until aborted witgh Control-C
}

main()