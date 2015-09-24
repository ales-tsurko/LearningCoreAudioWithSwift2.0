//
//  ViewController.swift
//  CH11_MIDIWifiSource
//
//  Created by Ales Tsurko on 23.09.15.
//

import UIKit
import CoreMIDI

// Change to your address
let DESTINATION_ADDRESS = "192.168.1.11"

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

class ViewController: UIViewController {
    
    var midiSession: MIDINetworkSession!
    var destinationEndpoint: MIDIEndpointRef!
    var outputPort: MIDIPortRef!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.connectToHost()
    }
    
    func connectToHost() {
        let host = MIDINetworkHost(name: "MIDIWifi", address: DESTINATION_ADDRESS, port: 5004)
        let connection = MIDINetworkConnection(host: host)
        midiSession = MIDINetworkSession.defaultSession()
        if midiSession != nil {
            print("Got MIDI session\n")
            
            midiSession.addConnection(connection)
            midiSession.enabled = true
            destinationEndpoint = midiSession.destinationEndpoint()
            
            var client = MIDIClientRef()
            var outport = MIDIPortRef()
            
            CheckError(MIDIClientCreate("MIDIWifi Client", nil, nil, &client),
                operation: "Couldn't create MIDI client")
            CheckError(MIDIOutputPortCreate(client, "MIDIWifi Output port", &outport),
                operation: "Couldn't create output port")
            
            outputPort = outport
            print("Got output port\n")
        }
    }
    
    func sendStatus(status: UInt8, data1: UInt8, data2: UInt8) {
        var packet = MIDIPacket()
        var packetList = MIDIPacketList()
        let data = [status, data1, data2]
        MIDIPacketListAdd(&packetList, sizeof(packetList.dynamicType), &packet, 0, data.count, data)
        
        CheckError(MIDISend(outputPort, destinationEndpoint, &packetList),
            operation: "Couldn't send MIDI packet list")
    }
    
    func sendNoteOnEvent(key: UInt8, velocity: UInt8) {
        sendStatus(0x9, data1: key&0x7F, data2: velocity&0x7F)
    }
    
    func sendNoteOffEvent(key: UInt8, velocity: UInt8) {
        sendStatus(0x9, data1: key&0x7F, data2: velocity&0x7F)
    }
    
    @IBAction func handleKeyDown(sender: UIButton) {
        let note = UInt8(sender.tag)
        sendNoteOnEvent(note, velocity: 127)
    }
    
    @IBAction func handleKeyUp(sender: UIButton) {
        let note = UInt8(sender.tag)
        sendNoteOffEvent(note, velocity: 127)
    }
}

