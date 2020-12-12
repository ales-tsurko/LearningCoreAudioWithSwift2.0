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


---
I spend too much time for open source, but too little for commercial stuff. As
the result I always lack money. If you like some of my projects, or music, or
some of my contributions helped you, please consider donation.

- Bitcoin: **bc1q0p7tmxyyd0pn7qsfxwlm00ncazdzz24p8lagqp**
- Ethereum: **0x55B6805f462e19aaBdB304bc85F94099eac060CE**
