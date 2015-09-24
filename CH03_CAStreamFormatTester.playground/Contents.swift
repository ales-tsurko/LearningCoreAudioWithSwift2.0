import Foundation
import AudioToolbox

var fileTypeAndFormat = AudioFileTypeAndFormatID()
fileTypeAndFormat.mFileType = kAudioFileAIFFType
fileTypeAndFormat.mFormatID = kAudioFormatLinearPCM

var audioErr = noErr

var infoSize: UInt32 = 0

audioErr = AudioFileGetGlobalInfoSize(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat, UInt32(sizeof(fileTypeAndFormat.dynamicType)), &fileTypeAndFormat, &infoSize)

assert(audioErr == noErr)

var asbds = UnsafeMutablePointer<AudioStreamBasicDescription>.alloc(Int(infoSize))

audioErr = AudioFileGetGlobalInfo(kAudioFileGlobalInfo_AvailableStreamDescriptionsForFormat, UInt32(sizeof(fileTypeAndFormat.dynamicType)), &fileTypeAndFormat, &infoSize, asbds)

assert(audioErr == noErr)

let asbdsCount = Int(infoSize) / sizeof(AudioStreamBasicDescription)

var formats = [String]()

for i in 0..<asbdsCount {
    var format4cc = asbds[i].mFormatID.bigEndian
    
    withUnsafePointer(&format4cc) {ptr in
        formats.append(String(format: "%d: mFormatID: %4.4s, mFormatFlags: %d, mBitsPerChannel: %d", arguments: [i, ptr, asbds[i].mFormatFlags, asbds[i].mBitsPerChannel]))
    }
    
    
}

formats
free(asbds)
