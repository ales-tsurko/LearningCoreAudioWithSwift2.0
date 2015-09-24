//
//  main.swift
//  OpenALOrbitLoop
//
//  Created by Ales Tsurko on 14.09.15.
//

import AudioToolbox
import OpenAL

let LOOP_PATH = "/Library/Audio/Apple Loops/Apple/iLife Sound Effects/Transportation/Bicycle Coasting.caf" as CFString
let ORBIT_SPEED = 1.0
let RUN_TIME = 20.0

// MARK: user-data struct
class LoopPlayer {
    var dataFormat = AudioStreamBasicDescription()
    var sampleBuffer: UnsafeMutablePointer<Void> = nil
    var bufferSizeBytes: UInt32 = 0
    var sources: [ALuint] = [0]
}


// MARK: - utility functions -
// generic error handler - if err is nonzero, prints error message and exits program.
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


func CheckALError(operation: String) {
    let alErr = alGetError()
    guard alErr != AL_NO_ERROR else {
        return
    }
    
    var errMessage: String = ""
    
    switch alErr {
    case AL_INVALID_NAME:
        errMessage = "OpenAL Error: \(operation) (AL_INVALID_NAME)"
        break
    case AL_INVALID_VALUE:
        errMessage = "OpenAL Error: \(operation) (AL_INVALID_VALUE)"
        break
    case AL_INVALID_ENUM:
        errMessage = "OpenAL Error: \(operation) (AL_INVALID_ENUM)"
        break
    case AL_INVALID_OPERATION:
        errMessage = "OpenAL Error: \(operation) (AL_INVALID_OPERATION)"
        break
    case AL_OUT_OF_MEMORY:
        errMessage = "OpenAL Error: \(operation) (AL_OUT_OF_MEMORY)"
        break
    default:
        break
    }
    
    print("\(errMessage)")
    exit(-1)
}

func updateSourceLocation(player: LoopPlayer) {
    let theta = ALfloat(fmod(CFAbsoluteTimeGetCurrent() * ORBIT_SPEED, M_PI * 2))
    let x = 3 * cos(theta)
    let y = 0.5 * sin (theta)
    let z = 1.0 * sin (theta)
    print("x=\(x), y=\(y), z=\(z)")
    alSource3f(player.sources[0], AL_POSITION, x, y, z)
}

func loadLoopIntoBuffer(inout player: LoopPlayer) -> OSStatus {
    let loopFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, LOOP_PATH, CFURLPathStyle.CFURLPOSIXPathStyle, false)
    
    // describe the client format - AL needs mono
    player.dataFormat = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    
    var extAudioFile: ExtAudioFileRef = nil
    CheckError(ExtAudioFileOpenURL(loopFileURL, &extAudioFile),
        operation: "Couldn't open ExtAudioFile for reading")
    
    // tell extAudioFile about our format
    CheckError(ExtAudioFileSetProperty(extAudioFile, kExtAudioFileProperty_ClientDataFormat, UInt32(sizeof(AudioStreamBasicDescription)), &player.dataFormat),
        operation: "Couldn't set client format on ExtAudioFile")
    
    // figure out how big a buffer we need
    var fileLengthFrames: Int64 = 0
    var propSize = UInt32(sizeof(fileLengthFrames.dynamicType))
    ExtAudioFileGetProperty(extAudioFile, kExtAudioFileProperty_FileLengthFrames, &propSize, &fileLengthFrames)
    
    print("plan on reading \(fileLengthFrames) frames\n")
    player.bufferSizeBytes = UInt32(fileLengthFrames) * player.dataFormat.mBytesPerFrame
    
    let buffers = AudioBufferList.allocate(maximumBuffers: 1) // 1 channel
    
    // allocate sample buffer
    player.sampleBuffer = malloc(sizeof(UInt16) * Int(player.bufferSizeBytes))
    
    buffers[0].mNumberChannels = 1
    buffers[0].mDataByteSize = player.bufferSizeBytes
    buffers[0].mData = player.sampleBuffer
    
    print("created AudioBufferList\n")
    
    // loop reading into the ABL until buffer is full
    var totalFramesRead: UInt32 = 0
    repeat {
        var framesRead = UInt32(UInt32(fileLengthFrames) - totalFramesRead)
        buffers[0].mData = player.sampleBuffer + Int(totalFramesRead * UInt32(sizeof(UInt16)))
        CheckError(ExtAudioFileRead(extAudioFile, &framesRead, buffers.unsafeMutablePointer),
            operation: "ExtAudioFileRead failed")
        totalFramesRead += framesRead
        print("read \(framesRead) frames\n")
    } while totalFramesRead < UInt32(fileLengthFrames)
    
    // can free the ABL still have samples in sampleBuffer
    free(buffers.unsafeMutablePointer)
    return noErr
}

// MARK: main

func main() {
    var player = LoopPlayer()
    
    // convert to an OpenAL-friendly format and read into memory
    CheckError(loadLoopIntoBuffer(&player),
        operation: "Couldn't load loop into buffer")
    
    // set up OpenAL buffer
    let alDevice = alcOpenDevice(nil)
    CheckALError("Couldn't open AL device") // default device
    var attr = ALCint(0)
    let alContext = alcCreateContext(alDevice, &attr)
    CheckALError("Couldn't open AL context")
    alcMakeContextCurrent(alContext)
    CheckALError("Couldn't make AL context current")
    var buffers: [ALuint] = [0]
    alGenBuffers(1, &buffers)
    CheckALError("Couldn't generate buffers")
    alBufferData(buffers[0], AL_FORMAT_MONO16, player.sampleBuffer, ALsizei(player.bufferSizeBytes), ALsizei(player.dataFormat.mSampleRate))
    
    // AL copies the samples, so we can free them now
    free(player.sampleBuffer)
    
    // set up OpenAL source
    alGenSources(1, &player.sources)
    CheckALError ("Couldn't generate sources")
    alSourcei(player.sources[0], AL_LOOPING, AL_TRUE)
    CheckALError("Couldn't set source looping property")
    alSourcef(player.sources[0], AL_GAIN, ALfloat(AL_MAX_GAIN))
    CheckALError("Couldn't set source gain")
    updateSourceLocation(player)
    CheckALError("Couldn't set initial source position")
    
    // connect buffer to source
    alSourcei(player.sources[0], AL_BUFFER, ALint(buffers[0]))
    CheckALError ("Couldn't connect buffer to source")
    
    // set up listener
    alListener3f (AL_POSITION, 0.0, 0.0, 0.0)
    CheckALError("Couldn't set listner position")
    
    // start playing
    // alSourcePlayv (1, player.sources)
    alSourcePlay(player.sources[0])
    CheckALError("Couldn't play")
    
    // and wait
    print("Playing...\n")
    let startTime = time(nil)
    repeat {
        // get next theta
        updateSourceLocation(player)
        CheckALError("Couldn't set looping source position")
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false)
    } while (difftime(time(nil), startTime) < RUN_TIME)
    
    // cleanup:
    alSourceStop(player.sources[0])
    alDeleteSources(1, player.sources)
    alDeleteBuffers(1, buffers)
    alcDestroyContext(alContext)
    alcCloseDevice(alDevice)
    print("Bottom of main\n")
}

main()