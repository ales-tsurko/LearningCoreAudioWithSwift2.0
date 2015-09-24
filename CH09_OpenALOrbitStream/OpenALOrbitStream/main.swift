//
//  main.swift
//  OpenALOrbitLoop
//
//  Created by Ales Tsurko on 14.09.15.
//

import AudioToolbox
import OpenAL

let STREAM_PATH = "/Library/Audio/Apple Loops/Apple/iLife Sound Effects/Jingles/Kickflip Long.caf" as CFString
let ORBIT_SPEED = 1.0
let BUFFER_DURATION_SECONDS	= 1.0
let BUFFER_COUNT = 3
let RUN_TIME = 20.0

// MARK: user-data struct
class StreamPlayer {
    var	dataFormat = AudioStreamBasicDescription()
    var bufferSizeBytes: UInt32 = 0
    var fileLengthFrames: Int64 = 0
    var totalFramesRead: Int64 = 0
    var sources: [ALuint] = [0]
    var extAudioFile: ExtAudioFileRef = nil
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

func updateSourceLocation(player: StreamPlayer) {
    let theta = fmod(CFAbsoluteTimeGetCurrent() * ORBIT_SPEED, M_PI * 2)
    let x = 3 * ALfloat(cos(theta))
    let y = 0.5 * ALfloat(sin(theta))
    let z = 1.0 * ALfloat(sin(theta))
    print("x=\(x), y=\(y), z=\(z)\n")
    alSource3f(player.sources[0], AL_POSITION, x, y, z)
}


func setUpExtAudioFile (inout player: StreamPlayer) -> OSStatus {
    let streamFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, STREAM_PATH, CFURLPathStyle.CFURLPOSIXPathStyle, false)
    
    // describe the client format - AL needs mono
    player.dataFormat = AudioStreamBasicDescription(mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    
    CheckError(ExtAudioFileOpenURL(streamFileURL, &player.extAudioFile),
        operation: "Couldn't open ExtAudioFile for reading")
    
    // tell extAudioFile about our format
    CheckError(ExtAudioFileSetProperty(player.extAudioFile, kExtAudioFileProperty_ClientDataFormat, UInt32(sizeof(AudioStreamBasicDescription)), &player.dataFormat),
        operation: "Couldn't set client format on ExtAudioFile")
    
    // figure out how big file is
    var propSize = UInt32(sizeof(player.fileLengthFrames.dynamicType))
    ExtAudioFileGetProperty(player.extAudioFile, kExtAudioFileProperty_FileLengthFrames, &propSize, &player.fileLengthFrames)
    
    print("fileLengthFrames = \(player.fileLengthFrames) frames\n")
    
    player.bufferSizeBytes = UInt32(BUFFER_DURATION_SECONDS) * UInt32(player.dataFormat.mSampleRate) * player.dataFormat.mBytesPerFrame
    
    print("bufferSizeBytes = \(player.bufferSizeBytes)\n")
    
    print("Bottom of setUpExtAudioFile\n")
    return noErr
}

func fillALBuffer(inout player: StreamPlayer, alBuffer: ALuint) {
    let bufferList = AudioBufferList.allocate(maximumBuffers: 1) // 1 channel
    
    // allocate sample buffer
    let sampleBuffer = malloc(sizeof(UInt16) * Int(player.bufferSizeBytes))
    
    bufferList[0].mNumberChannels = 1
    bufferList[0].mDataByteSize = player.bufferSizeBytes
    bufferList[0].mData = sampleBuffer
    print("allocated \(player.bufferSizeBytes) byte buffer for ABL\n")
    
    // read from ExtAudioFile into sampleBuffer
    var framesReadIntoBuffer: UInt32 = 0
    repeat {
        var framesRead = UInt32(player.fileLengthFrames) - framesReadIntoBuffer
        bufferList[0].mData = sampleBuffer + Int(framesReadIntoBuffer * UInt32(sizeof(UInt16)))
        CheckError(ExtAudioFileRead(player.extAudioFile, &framesRead, bufferList.unsafeMutablePointer),
            operation: "ExtAudioFileRead failed")
        framesReadIntoBuffer += framesRead
        player.totalFramesRead += Int64(framesRead)
        print("read \(framesRead) frames\n")
    } while framesReadIntoBuffer < (player.bufferSizeBytes / UInt32(sizeof(UInt16)))
    
    // copy from sampleBuffer to AL buffer
    alBufferData(alBuffer, AL_FORMAT_MONO16, sampleBuffer, ALsizei(player.bufferSizeBytes), ALsizei(player.dataFormat.mSampleRate))
    
    free(bufferList.unsafeMutablePointer)
    free(sampleBuffer)
}

func refillALBuffers(inout player: StreamPlayer) {
    var processed = ALint()
    alGetSourcei (player.sources[0], AL_BUFFERS_PROCESSED, &processed)
    CheckALError ("couldn't get al_buffers_processed")
    
    while (processed > 0) {
        var freeBuffer = ALuint()
        alSourceUnqueueBuffers(player.sources[0], 1, &freeBuffer)
        CheckALError("couldn't unqueue buffer")
        print("refilling buffer \(freeBuffer)\n")
        fillALBuffer(&player, alBuffer: freeBuffer)
        alSourceQueueBuffers(player.sources[0], 1, &freeBuffer)
        CheckALError ("couldn't queue refilled buffer")
        print("re-queued buffer \(freeBuffer)\n")
        processed--
    }
    
}

// MARK: main

func main() {
    var player = StreamPlayer()
    
    // prepare the ExtAudioFile for reading
    CheckError(setUpExtAudioFile(&player),
        operation: "Couldn't open ExtAudioFile")
    
    // set up OpenAL buffers
    let alDevice = alcOpenDevice(nil)
    CheckALError("Couldn't open AL device") // default device
    var attr = ALCint(0)
    let alContext = alcCreateContext(alDevice, &attr)
    CheckALError("Couldn't open AL context")
    alcMakeContextCurrent(alContext)
    CheckALError("Couldn't make AL context current")
    var buffers: [ALuint] = [ALuint](count: BUFFER_COUNT, repeatedValue: 0)
    alGenBuffers(ALsizei(BUFFER_COUNT), &buffers)
    CheckALError ("Couldn't generate buffers")
    
    for i in 0..<BUFFER_COUNT {
        fillALBuffer(&player, alBuffer: buffers[i])
    }
    
    // set up streaming source
    alGenSources(1, &player.sources)
    CheckALError ("Couldn't generate sources")
    alSourcef(player.sources[0], AL_GAIN, ALfloat(AL_MAX_GAIN))
    CheckALError("Couldn't set source gain")
    updateSourceLocation(player)
    CheckALError("Couldn't set initial source position")
    
    // queue up the buffers on the source
    alSourceQueueBuffers(player.sources[0], ALsizei(BUFFER_COUNT), buffers)
    CheckALError("Couldn't queue buffers on source")
    
    // set up listener
    alListener3f(AL_POSITION, 0.0, 0.0, 0.0)
    CheckALError("Couldn't set listener position")
    
    // start playing
    alSourcePlayv(1, &player.sources)
    CheckALError("Couldn't play")
    
    // and wait
    print("Playing...\n")
    let startTime = time(nil)
    repeat {
        // get next theta
        updateSourceLocation(player)
        CheckALError ("Couldn't set source position")
        
        // refill buffers if needed
        refillALBuffers(&player)
        
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false)
    } while difftime(time(nil), startTime) < RUN_TIME
    
    // cleanup:
    alSourceStop(player.sources[0])
    alDeleteSources(1, player.sources)
    alDeleteBuffers(ALsizei(BUFFER_COUNT), buffers)
    alcDestroyContext(alContext)
    alcCloseDevice(alDevice)
    print("Bottom of main\n")
}

main()