// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

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
