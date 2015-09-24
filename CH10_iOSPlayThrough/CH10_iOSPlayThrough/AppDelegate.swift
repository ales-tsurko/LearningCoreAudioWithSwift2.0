//
//  AppDelegate.swift
//  CH10_iOSPlayThrough
//
//  Created by Ales Tsurko on 21.09.15.
//

import UIKit
import AudioToolbox
import AVFoundation

class EffectState {
    var rioUnit: AudioUnit = nil
    var asbd: AudioStreamBasicDescription!
    var sineFrequency = Float()
    var sinePhase = Float()
}

// MARK: helpers
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

// MARK: callbacks
let InputModulatingRenderCallback: AURenderCallback = {(inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
    let effectState = UnsafeMutablePointer<EffectState>(inRefCon).memory
    
    // Just copy samples
    var bus1: UInt32 = 1
    CheckError(AudioUnitRender(effectState.rioUnit, ioActionFlags, inTimeStamp, bus1, inNumberFrames, ioData),
        operation: "Couldn't render from RemoteIO unit")
    
    // Walk the samples
    var sample: Int16 = 0
    let bytesPerChannel = effectState.asbd.mBytesPerFrame / effectState.asbd.mChannelsPerFrame
    
    for buf in UnsafeMutableAudioBufferListPointer(ioData) {
        for currentFrame in 0..<Int(inNumberFrames) {
            // Copy sample to buffer, across all channels
            for currentChannel in 0..<Int(buf.mNumberChannels) {
                memcpy(&sample, buf.mData + (currentFrame * Int(effectState.asbd.mBytesPerFrame)) + (currentChannel * Int(bytesPerChannel)), sizeof(Int16))
                
                var theta = effectState.sinePhase * Float(M_PI) * 2
                sample = Int16(sinf(theta) * Float(sample))
                
                memcpy(buf.mData + (currentFrame * Int(effectState.asbd.mBytesPerFrame)) + (currentChannel * Int(bytesPerChannel)), &sample, sizeof(Int16))
                
                effectState.sinePhase += (1 / (Float(effectState.asbd.mSampleRate) / effectState.sineFrequency))
                
                if effectState.sinePhase > 1 {
                    effectState.sinePhase -= 1
                }
            }
        }
    }
    
    return noErr
}

// MARK: app lifecycle

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    var effectState = EffectState()
    var audioSession: AVAudioSession!
    
    func interruptionListener(notification: NSNotification) {
        guard notification.name == AVAudioSessionInterruptionNotification else {
            return
        }
        
        if let userInfo = notification.userInfo {
            if let typeKey = userInfo[AVAudioSessionInterruptionTypeKey] as? NSValue {
                var intValue = UInt()
                typeKey.getValue(&intValue)
                
                if let type = AVAudioSessionInterruptionType(rawValue: intValue) {
                    
                    print("Interrupted! Interruption state = \(intValue)\n")
                    
                    switch type {
                    case .Began:
                        break
                    case .Ended:
                        do {
                            try audioSession.setActive(true)
                        } catch {
                            print("Error: \(error)\n Couldn't set audio session active\n")
                        }
                        CheckError(AudioUnitInitialize(effectState.rioUnit), operation: "Couldn't initialize RIO unit")
                        CheckError(AudioOutputUnitStart(effectState.rioUnit), operation: "Couldn't start RIO unit")
                    }
                } else {
                    print("Couldn't get interruption type from raw value\n")
                    return
                }
            } else {
                print("User info type key is nil\n")
                return
            }
        } else {
            print("Notification's user info is nil\n")
            return
        }
    }
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Set up audio session
        // AudioSessionInitialize is deprecated. Here is AVAudioSession instead.
        audioSession = AVAudioSession.sharedInstance()
        
        // setting interruption listener
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "interruptionListener:", name: AVAudioSessionInterruptionNotification, object: nil)
        
        do {
            // setting session mode
            try audioSession.setMode(AVAudioSessionModeDefault)
            // setting session category
            try audioSession.setCategory(AVAudioSessionCategoryPlayAndRecord)
        } catch {
            print("Error: \(error)")
        }
        
        // Is audio input available?
        guard audioSession.inputAvailable else {
            let alert = UIAlertController(title: "No audio input", message: "No audio input device is currently attached", preferredStyle: UIAlertControllerStyle.Alert)
            alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.Cancel, handler: nil))
            window?.rootViewController?.presentViewController(alert, animated: true, completion: nil)
            
            return true
        }
        
        // Get hardware sample rate
        print("Hardware sample rate = \(audioSession.sampleRate)\n")
        
        // Describe the unit
        var audioCompDesc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_RemoteIO, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        
        // Get the Rio unit from the audio component manager
        let rioComponent = AudioComponentFindNext(nil, &audioCompDesc)
        CheckError(AudioComponentInstanceNew(rioComponent, &effectState.rioUnit),
            operation: "Couldn't get RIO unit instance")
        
        // Configure Rio unit
        // Set up the Rio unit for playback
        var oneFlag: UInt32 = 1
        let bus0: AudioUnitElement = 0
        CheckError(AudioUnitSetProperty(effectState.rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, bus0, &oneFlag, UInt32(sizeof(oneFlag.dynamicType))),
            operation: "Couldn't enable RIO output")
        
        // Enable RIO input
        let bus1: AudioUnitElement = 1
        CheckError(AudioUnitSetProperty(effectState.rioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, bus1, &oneFlag, UInt32(sizeof(oneFlag.dynamicType))),
            operation: "Couldn't enable RIO input")
        
        // Setup ASBD in the iPhone canonical format
        // (concept of canonical formats is deprecated also by default iOS 9 is 32-float instead of 16-int)
        var asbd = AudioStreamBasicDescription(mSampleRate: audioSession.sampleRate, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        
        // Set format for output (bus 0) on the RIO's input scope
        CheckError(AudioUnitSetProperty(effectState.rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, bus0, &asbd, UInt32(sizeof(asbd.dynamicType))),
            operation: "Couldn't set the ASBD for RIO on input scope/bus 0")
        
        // Set ASBD for mic input (bus 1) on RIO's output scope
        CheckError(AudioUnitSetProperty(effectState.rioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, bus1, &asbd, UInt32(sizeof(asbd.dynamicType))),
            operation: "Couldn't set the ASBD for RIO on output scope/bus 1")
        
        effectState.asbd = asbd
        effectState.sineFrequency = 30
        effectState.sinePhase = 0
        
        // Set callback method
        var callbackStruct = AURenderCallbackStruct(inputProc: InputModulatingRenderCallback, inputProcRefCon: &effectState)
        CheckError(AudioUnitSetProperty(effectState.rioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, bus0, &callbackStruct, UInt32(sizeof(callbackStruct.dynamicType))),
            operation: "Couldn't set RIO's render callback on bus 0")
        
        // Initialize and start the RIO unit
        CheckError(AudioUnitInitialize(effectState.rioUnit),
            operation: "Couldn't initialize the RIO unit")
        CheckError(AudioOutputUnitStart(effectState.rioUnit),
            operation: "Couldn't start the RIO unit")
        print("RIO started!\n")
        
        // Override point for customization after application launch
        window?.makeKeyAndVisible()
        return true
    }

    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }


}

