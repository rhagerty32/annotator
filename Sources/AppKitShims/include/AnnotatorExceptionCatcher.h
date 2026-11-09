#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns the NSException AppKit raised, or nil.
/// Swift cannot catch NSException, and an uncaught one skips the agent reply.
NSException *_Nullable AnnotatorCatchException(void(NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
