// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

#import "CollabCaptureDeviceConfigurator.h"
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

void collabConfigureDevice(AVCaptureDevice *device,
                           AVCaptureDeviceFormat *format,
                           CMTime duration)
{
  @try {
    NSError *error = nil;
    if ([device lockForConfiguration:&error]) {
      [device setActiveFormat:format];
      [device setActiveVideoMinFrameDuration:duration];
      [device setActiveVideoMaxFrameDuration:duration];
      [device unlockForConfiguration];
    }
  } @catch (NSException *exception) {
    [device unlockForConfiguration];
  }
}
