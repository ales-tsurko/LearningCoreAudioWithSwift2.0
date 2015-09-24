# LearningCoreAudioWithSwift2.0
All the examples of the Learning Core Audio book rewritten with Swift 2.0

## Known issues

### CH08_AUGraphInput
If you use different devices for input and output the output can be silence. In such case try to increase or decrease size of the ring buffer.

### CH11_MIDIWifiSource
The MIDIWifiSource is crashing with iOS 9 + OS X 10.10 (I've no possibility to test it with another configurations). The problem is in creating of connection (line #50):
```swift
let connection = MIDINetworkConnection(host: host)
```
I didn't found how to fix it yet.
