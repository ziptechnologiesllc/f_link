//
//  ABLLinkWrapper.mm
//  f_link
//
//  Objective-C++ wrapper for ABLLink to expose to Swift
//

#import "ABLLinkWrapper.h"
#import "ABLLink.h"
#import <mach/mach_time.h>

@interface ABLLinkWrapper()
{
    ABLLinkRef _ablLink;
    double _quantum;
}
@end

@implementation ABLLinkWrapper

- (instancetype)initWithTempo:(double)tempo {
    self = [super init];
    if (self) {
        NSLog(@"[LinkKit] Initializing ABLLink with tempo: %f", tempo);
        _ablLink = ABLLinkNew(tempo);
        _quantum = 4.0;

        NSLog(@"[LinkKit] ABLLink instance created: %p", _ablLink);

        // Set up callbacks
        void *context = (__bridge void *)self;

        ABLLinkSetSessionTempoCallback(_ablLink, sessionTempoCallback, context);
        ABLLinkSetStartStopCallback(_ablLink, startStopCallback, context);
        ABLLinkSetIsConnectedCallback(_ablLink, isConnectedCallback, context);

        NSLog(@"[LinkKit] Callbacks registered");
        NSLog(@"[LinkKit] Link initialized but not yet enabled (call enableWithQuantum to activate)");
    }
    return self;
}

// C callback functions
static void sessionTempoCallback(double tempo, void *context) {
    ABLLinkWrapper *wrapper = (__bridge ABLLinkWrapper *)context;
    if (wrapper && [wrapper.delegate respondsToSelector:@selector(linkTempoChanged:)]) {
        [wrapper.delegate linkTempoChanged:tempo];
    }
}

static void startStopCallback(bool isPlaying, void *context) {
    ABLLinkWrapper *wrapper = (__bridge ABLLinkWrapper *)context;
    if (wrapper && [wrapper.delegate respondsToSelector:@selector(linkPlayingStateChanged:)]) {
        [wrapper.delegate linkPlayingStateChanged:isPlaying];
    }
}

static void isConnectedCallback(bool isConnected, void *context) {
    ABLLinkWrapper *wrapper = (__bridge ABLLinkWrapper *)context;
    NSLog(@"[LinkKit] isConnectedCallback fired: isConnected=%d", isConnected);
    if (wrapper && [wrapper.delegate respondsToSelector:@selector(linkNumPeersChanged:)]) {
        // ABLLink doesn't provide actual peer count, just connected/disconnected
        // Report 0 for disconnected, 1 for connected
        NSInteger peers = isConnected ? 1 : 0;
        NSLog(@"[LinkKit] Reporting peer count: %ld", (long)peers);
        [wrapper.delegate linkNumPeersChanged:peers];
    } else {
        NSLog(@"[LinkKit] WARNING: Delegate not set or doesn't respond to linkNumPeersChanged:");
    }
}

- (void)enableWithQuantum:(double)quantum {
    _quantum = quantum;
    NSLog(@"[LinkKit] Enabling Link with quantum: %f", quantum);
    NSLog(@"[LinkKit] Link instance: %p", _ablLink);

    ABLLinkSetActive(_ablLink, true);

    // Verify it's actually enabled and active
    BOOL enabled = ABLLinkIsEnabled(_ablLink);
    BOOL connected = ABLLinkIsConnected(_ablLink);
    NSLog(@"[LinkKit] After enable - isEnabled: %d, isConnected: %d", enabled, connected);
    NSLog(@"[LinkKit] Link should now be advertising on the network");
}

- (void)disable {
    ABLLinkSetActive(_ablLink, false);
}

- (BOOL)isEnabled {
    return ABLLinkIsEnabled(_ablLink);
}

- (NSInteger)numPeers {
    // ABLLink only provides isConnected, not actual peer count
    return ABLLinkIsConnected(_ablLink) ? 1 : 0;
}

- (void)setTempo:(double)tempo {
    const UInt64 hostTime = mach_absolute_time();
    ABLLinkSessionStateRef sessionState = ABLLinkCaptureAppSessionState(_ablLink);
    ABLLinkSetTempo(sessionState, tempo, hostTime);
    ABLLinkCommitAppSessionState(_ablLink, sessionState);
}

- (void)setIsPlaying:(BOOL)isPlaying {
    const UInt64 hostTime = mach_absolute_time();
    ABLLinkSessionStateRef sessionState = ABLLinkCaptureAppSessionState(_ablLink);
    ABLLinkSetIsPlaying(sessionState, isPlaying, hostTime);
    ABLLinkCommitAppSessionState(_ablLink, sessionState);
}

- (double)getTempo {
    ABLLinkSessionStateRef sessionState = ABLLinkCaptureAppSessionState(_ablLink);
    return ABLLinkGetTempo(sessionState);
}

- (BOOL)getIsPlaying {
    ABLLinkSessionStateRef sessionState = ABLLinkCaptureAppSessionState(_ablLink);
    return ABLLinkIsPlaying(sessionState);
}

- (double)getBeatAtTime:(uint64_t)hostTime quantum:(double)quantum {
    ABLLinkSessionStateRef sessionState = ABLLinkCaptureAppSessionState(_ablLink);
    return ABLLinkBeatAtTime(sessionState, hostTime, quantum);
}

- (double)getPhaseAtTime:(uint64_t)hostTime quantum:(double)quantum {
    ABLLinkSessionStateRef sessionState = ABLLinkCaptureAppSessionState(_ablLink);
    return ABLLinkPhaseAtTime(sessionState, hostTime, quantum);
}

- (uint64_t)getCurrentHostTime {
    return mach_absolute_time();
}

- (void)dealloc {
    if (_ablLink) {
        ABLLinkDelete(_ablLink);
        _ablLink = NULL;
    }
}

@end
