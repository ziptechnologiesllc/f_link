//
//  ABLLinkWrapper.h
//  f_link
//
//  Objective-C wrapper for ABLLink to expose to Swift
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ABLLinkWrapperDelegate <NSObject>
@optional
- (void)linkTempoChanged:(double)tempo;
- (void)linkNumPeersChanged:(NSInteger)numPeers;
- (void)linkPlayingStateChanged:(BOOL)isPlaying;
@end

@interface ABLLinkWrapper : NSObject

@property (nonatomic, weak, nullable) id<ABLLinkWrapperDelegate> delegate;
@property (nonatomic, readonly) BOOL isEnabled;
@property (nonatomic, readonly) NSInteger numPeers;

- (instancetype)initWithTempo:(double)tempo;
- (void)enableWithQuantum:(double)quantum;
- (void)disable;
- (void)setTempo:(double)tempo;
- (void)setIsPlaying:(BOOL)isPlaying;
- (double)getTempo;
- (BOOL)getIsPlaying;
- (double)getBeatAtTime:(uint64_t)hostTime quantum:(double)quantum;
- (double)getPhaseAtTime:(uint64_t)hostTime quantum:(double)quantum;
- (uint64_t)getCurrentHostTime;

@end

NS_ASSUME_NONNULL_END
