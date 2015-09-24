//
//  main.swift
//  CAMetadata
//
//  Created by Ales Tsurko on 23.08.15.
//

import Foundation
import AudioToolbox

func main() {
    let argc = Process.argc
    let argv = Process.arguments
    
    guard argc > 1 else {
        print("Usage: CAMetaData /full/path/to/audiofile\n")
        return
    }
    
    if let audiofilePath = NSString(UTF8String: argv[1])?.stringByExpandingTildeInPath {
        let audioURL = NSURL(fileURLWithPath: audiofilePath)
        var audiofile: AudioFileID = nil
        var theErr = noErr
        
        theErr = AudioFileOpenURL(audioURL, AudioFilePermissions.ReadPermission, 0, &audiofile)
        
        assert(theErr == noErr)
        
        var dictionarySize: UInt32 = 0
        var isWritable: UInt32 = 0
        theErr = AudioFileGetPropertyInfo(audiofile, kAudioFilePropertyInfoDictionary, &dictionarySize, &isWritable)
        
        assert(theErr == noErr)
        
        var dictionary: UnsafePointer<CFDictionaryRef> = nil
        theErr = AudioFileGetProperty(audiofile, kAudioFilePropertyInfoDictionary, &dictionarySize, &dictionary)
        
        assert(theErr == noErr)
        
        NSLog("dictionary: %@", dictionary)
        
        theErr = AudioFileClose(audiofile)
        
        assert(theErr == noErr)
        
    } else {
        print("File not found\n")
    }
    
}

main()