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

---
I spend too much time for open source, but too little for commercial stuff. As
the result I always lack money. If you like some of my projects, or music, or
some of my contributions helped you, please consider donation.

- Bitcoin: **bc1q0p7tmxyyd0pn7qsfxwlm00ncazdzz24p8lagqp**
- Ethereum: **0x55B6805f462e19aaBdB304bc85F94099eac060CE**
