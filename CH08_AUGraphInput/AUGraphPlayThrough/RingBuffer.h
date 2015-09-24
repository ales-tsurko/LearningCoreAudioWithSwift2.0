//
//  RingBuffer.h
//  AUGraphPlayThrough
//
//  Created by Ales Tsurko on 10.09.15.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

typedef SInt32 CARingBufferError;

@interface RingBuffer : NSObject
- (instancetype) init;
- (void) allocate:(UInt32) nChannels bytesPerFrame:(UInt32) bytesPerFrame capacityFrames:(UInt32) capacityFrames;
- (void) deallocate;
- (CARingBufferError) store:(const AudioBufferList *) abl nFrames:(UInt32) nFrames frameNumber:(SInt64) frameNumber;
- (CARingBufferError) fetch:(AudioBufferList *) abl nFrame:(UInt32) nFrames frameNumnber:(SInt64) frameNumber;
- (CARingBufferError) getTimeBounds:(SInt64 *) startTime :(SInt64 *) endTime;
@end