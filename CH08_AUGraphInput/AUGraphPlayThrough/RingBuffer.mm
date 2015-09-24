//
//  RingBuffer.mm
//  AUGraphPlayThrough
//
//  Created by Ales Tsurko on 10.09.15.
//

#import "RingBuffer.h"
#ifdef __cplusplus
#import "CARingBuffer.h"
#endif

@implementation RingBuffer
{
    CARingBuffer *buffer;
}

- (instancetype) init {
    self = [super init];
    self->buffer = new CARingBuffer();
    return self;
}

- (void) allocate:(UInt32)nChannels bytesPerFrame:(UInt32)bytesPerFrame capacityFrames:(UInt32)capacityFrames {
    buffer->Allocate(nChannels, bytesPerFrame, capacityFrames);
}

- (void) deallocate {
    buffer->Deallocate();
}

- (CARingBufferError) store:(const AudioBufferList *)abl nFrames:(UInt32)nFrames frameNumber:(SInt64)frameNumber {
    return buffer->Store(abl, nFrames, frameNumber);
}

- (CARingBufferError) fetch:(AudioBufferList *)abl nFrame:(UInt32)nFrames frameNumnber:(SInt64)frameNumber {
    AudioBufferList aubuflist = *abl;
    CARingBufferError result = buffer->Fetch(&aubuflist, nFrames, frameNumber);
    *abl = aubuflist;
    return result;
}

- (CARingBufferError) getTimeBounds:(SInt64 *) startTime :(SInt64 *) endTime {
    SInt64 startt, endt;
    
    CARingBufferError result = buffer->GetTimeBounds(startt, endt);
    *startTime = startt;
    *endTime = endt;
    
    return result;
}

@end
