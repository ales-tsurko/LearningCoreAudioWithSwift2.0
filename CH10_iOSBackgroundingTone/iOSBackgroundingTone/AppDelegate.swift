//
//  AppDelegate.swift
//  iOSBackgroundingTone
//
//  Created by Ales Tsurko on 15.09.15.
//

import UIKit
import AudioToolbox
import AVFoundation

// MARK: #defines

let FOREGROUND_FREQUENCY = 880.0
let BACKGROUND_FREQUENCY = 523.25
let BUFFER_COUNT = 3
let BUFFER_DURATION = 0.5

// MARK: user data struct

class UserData {
    var audioQueue: AudioQueueRef = nil
    var streamFormat: AudioStreamBasicDescription!
    var bufferSize = UInt32()
    var currentFrequency = Double()
    var startingFrameCount = Double()
    
    func fillBuffer(buffer: AudioQueueBufferRef) -> OSStatus {
        var j = startingFrameCount
        let cycleLength = streamFormat.mSampleRate / currentFrequency
        let frameCount = bufferSize / streamFormat.mBytesPerFrame
        
        for frame in 0..<Int(frameCount) {
            let data = UnsafeMutablePointer<Int16>(buffer.memory.mAudioData)
            data[frame] = Int16(sin(2 * M_PI * (j / cycleLength)) * Double(Int16.max))
            
            j++
            if j > cycleLength {
                j-=cycleLength
            }
        }
        
        startingFrameCount = j
        buffer.memory.mAudioDataByteSize = bufferSize
        
        return noErr
    }
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

// MARK: callback

let AQOutputCallback: AudioQueueOutputCallback = {inUserData, inAQ, inBuffer in
    var userData = UnsafeMutablePointer<UserData>(inUserData)
    
    CheckError(userData.memory.fillBuffer(inBuffer),
        operation: "Can't refill buffer")
    
    CheckError(AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil),
        operation: "Couldn't enqueue the buffer (refill)")
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    var userData = UserData()
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
                        let smpte = SMPTETime(mSubframes: 0, mSubframeDivisor: 0, mCounter: 0, mType: SMPTETimeType.Type24, mFlags: SMPTETimeFlags.Running, mHours: 0, mMinutes: 0, mSeconds: 0, mFrames: 0)
                        var timeStamp = AudioTimeStamp(mSampleTime: 0, mHostTime: 0, mRateScalar: 0, mWordClockTime: 0, mSMPTETime: smpte, mFlags: AudioTimeStampFlags.SampleHostTimeValid, mReserved: 0)
                        
                        CheckError(AudioQueueStart(userData.audioQueue, &timeStamp),
                            operation: "Couldn't restart the audio queue")
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
        // Set up the audio session
        // AudioSessionInitialize is deprecated. Here is AVAudioSession instead.
        audioSession = AVAudioSession.sharedInstance()
        
        // setting interruption listener
        NSNotificationCenter.defaultCenter().addObserver(self, selector: "interruptionListener:", name: AVAudioSessionInterruptionNotification, object: nil)
        
        do {
            // setting session mode
            try audioSession.setMode(AVAudioSessionModeDefault)
            // setting session category
            try audioSession.setCategory(AVAudioSessionCategoryPlayback)
        } catch {
            print("Error: \(error)")
        }
        
        // Set the stream format
        userData.currentFrequency = FOREGROUND_FREQUENCY
        
        // kAudioFormatFlagsCanonical is deprecated
        userData.streamFormat = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        
        // Set up the audio queue
        CheckError(AudioQueueNewOutput(&userData.streamFormat!, AQOutputCallback, &userData, nil, kCFRunLoopCommonModes, 0, &userData.audioQueue),
            operation: "Couldn't create the output AudioQueue")
        
        // Create and enqueue buffers
        var buffers = [AudioQueueBufferRef](count: BUFFER_COUNT, repeatedValue: AudioQueueBufferRef())
        userData.bufferSize = UInt32(BUFFER_DURATION * Double(userData.streamFormat.mSampleRate) * Double(userData.streamFormat.mBytesPerFrame))
        
        print("bufferSize is \(userData.bufferSize)")
        
        for i in 0..<BUFFER_COUNT {
            CheckError(AudioQueueAllocateBuffer(userData.audioQueue, userData.bufferSize, &buffers[i]),
                operation: "Couldn't allocate the Audio Queue buffer")
            
            CheckError(userData.fillBuffer(buffers[i]),
                operation: "Couldn't fill buffer (priming)")
            
            CheckError(AudioQueueEnqueueBuffer(userData.audioQueue, buffers[i], 0, nil),
                operation: "Couldn't enqueue buffer (priming)")
        }
        
        // Start the audio queue
        CheckError(AudioQueueStart(userData.audioQueue, nil),
            operation: "Couldn't start the Audio Queue")
        
        // Override point for customization after the application launches.
        window?.makeKeyAndVisible()
        
        return true
    }
    
    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }
    
    func applicationDidEnterBackground(application: UIApplication) {
        userData.currentFrequency = BACKGROUND_FREQUENCY
    }
    
    func applicationWillEnterForeground(application: UIApplication) {
        do {
            try audioSession.setActive(true)
        } catch {
            print("Error: \(error)\n Couldn't re-set audio session active")
        }
        
        let smpte = SMPTETime(mSubframes: 0, mSubframeDivisor: 0, mCounter: 0, mType: SMPTETimeType.Type24, mFlags: SMPTETimeFlags.Running, mHours: 0, mMinutes: 0, mSeconds: 0, mFrames: 0)
        var timeStamp = AudioTimeStamp(mSampleTime: 0, mHostTime: 0, mRateScalar: 0, mWordClockTime: 0, mSMPTETime: smpte, mFlags: AudioTimeStampFlags.SampleHostTimeValid, mReserved: 0)
        
        CheckError(AudioQueueStart(userData.audioQueue, &timeStamp),
            operation: "Couldn't restart audio queue")
        
        userData.currentFrequency = FOREGROUND_FREQUENCY
    }
    
    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
    
}

