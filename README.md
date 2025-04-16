# LearningCoreAudioWithSwift2.0

Every example from the Learning Core Audio book rewritten with Swift 2.0.




## Known issues


### CH08_AUGraphInput

The output can be silent when you use different devices for the input and output.
As a workaround, try to change the size of the ring buffer.


### CH11_MIDIWifiSource

The MIDIWifiSource crashes on iOS 9 + OS X 10.10. I was unable to test it with 
different OS's versions. 

In case you're interesting in debugging it, the crash happens when the connection 
is initialized:
```swift
let connection = MIDINetworkConnection(host: host)
```
