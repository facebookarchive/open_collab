#ifndef CollabCaptureDeviceConfigurator_h
#define CollabCaptureDeviceConfigurator_h

// Copyright (c) Meta Platforms, Inc. and affiliates.

// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.

#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

@class AVCaptureDevice;
@class AVCaptureDeviceFormat;

NS_ASSUME_NONNULL_BEGIN

void collabConfigureDevice(AVCaptureDevice *device,
                           AVCaptureDeviceFormat *format,
                           CMTime duration);

NS_ASSUME_NONNULL_END

#endif /* CollabCaptureDeviceConfigurator_h */
