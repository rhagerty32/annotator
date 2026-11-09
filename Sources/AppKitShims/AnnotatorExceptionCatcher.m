#import "AnnotatorExceptionCatcher.h"

NSException *AnnotatorCatchException(void (^block)(void)) {
  @try {
    block();
  } @catch (NSException *exception) {
    return exception;
  }
  return nil;
}
