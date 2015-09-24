# LearningCoreAudioWithSwift2.0
All the examples of the Learning Core Audio book rewritten in Swift 2.0

## Known issues

### CH08_AUGraphInput
If you use different devices for input and output the output can be silence. In such case try to increase or decrease size of ring buffer.

### CH11_MIDIWifiSource
The MIDIWifiSource is not working for me. The problem is in creating of connection (line #50):
```swift
let connection = MIDINetworkConnection(host: host)
```
I didn't found how to fix it yet.
